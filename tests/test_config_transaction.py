import importlib.util
import json
import tempfile
import tomllib
import unittest
from pathlib import Path
from unittest import mock


SCRIPT = Path(__file__).resolve().parents[1] / "scripts" / "config_transaction.py"
spec = importlib.util.spec_from_file_location("config_transaction", SCRIPT)
tx = importlib.util.module_from_spec(spec)
spec.loader.exec_module(tx)


CONFIG = b'''notify = ["notify-command", "turn-ended"]
model = "original-model"
model_catalog_json = "original-catalog.json"
model_provider = "legacy-provider"

[desktop]
followUpQueueMode = "queue"

[marketplaces.example]
source_type = "local"
source = "./marketplace"

[plugins."browser@example"]
enabled = true

[mcp_servers.local]
command = "mcp-command"
args = ["--safe"]

[model_providers.Model_Studio]
name = "old-model-studio"
base_url = "https://old.invalid/v1"
wire_api = "responses"
'''


class ConfigTransactionTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="codex-switcher-test-")
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.catalog = self.root / "catalog.json"
        self.catalog.write_text(json.dumps({"models": [{"slug": "deepseek-v4.1-flash"}]}))
        self.route = tx.capture_route(CONFIG)

    def parsed(self, data):
        return tomllib.loads(data.decode("utf-8"))

    def test_deepseek_sets_responses_env_key_and_model_catalog(self):
        out = tx.apply_route(CONFIG, "deepseek", self.catalog)
        parsed = self.parsed(out)
        provider = parsed["model_providers"]["Model_Studio"]
        self.assertEqual(parsed["model_provider"], "Model_Studio")
        self.assertEqual(parsed["model"], "deepseek-v4.1-flash")
        self.assertEqual(parsed["model_catalog_json"], str(self.catalog))
        self.assertEqual(provider["wire_api"], "responses")
        self.assertEqual(provider["env_key"], "OPENAI_API_KEY")
        self.assertNotIn("auth", provider)

    def test_go_route_preserves_install_time_model_catalog_and_restores_provider_section(self):
        out = tx.apply_route(CONFIG, "go", self.catalog, self.route)
        parsed = self.parsed(out)
        self.assertEqual(parsed["model_provider"], "openai")
        self.assertEqual(parsed["model"], "original-model")
        self.assertEqual(parsed["model_catalog_json"], "original-catalog.json")
        self.assertEqual(parsed["model_providers"]["Model_Studio"]["name"], "old-model-studio")

    def test_go_does_not_invent_model_when_original_was_absent(self):
        base = b"model_provider = \"other\"\n[mcp_servers.local]\ncommand=\"x\"\n"
        route = tx.capture_route(base)
        parsed = self.parsed(tx.apply_route(base, "go", self.catalog, route))
        self.assertEqual(parsed["model_provider"], "openai")
        self.assertNotIn("model", parsed)
        self.assertNotIn("model_catalog_json", parsed)

    def test_mcp_plugins_marketplace_notify_and_desktop_are_preserved(self):
        parsed = self.parsed(tx.apply_route(CONFIG, "deepseek", self.catalog))
        self.assertEqual(parsed["notify"], ["notify-command", "turn-ended"])
        self.assertEqual(parsed["desktop"]["followUpQueueMode"], "queue")
        self.assertEqual(parsed["marketplaces"]["example"]["source"], "./marketplace")
        self.assertTrue(parsed["plugins"]["browser@example"]["enabled"])
        self.assertEqual(parsed["mcp_servers"]["local"]["args"], ["--safe"])

    def test_invalid_toml_is_rejected_before_write(self):
        with self.assertRaises(Exception):
            tx.apply_route(b"model = [broken\n", "deepseek", self.catalog)

    def test_concurrent_change_is_not_overwritten(self):
        target = self.root / "config.toml"
        target.write_bytes(CONFIG)
        expected = tx.sha(CONFIG)
        external = CONFIG + b"\n# external edit\n"
        target.write_bytes(external)
        with self.assertRaisesRegex(RuntimeError, "concurrent modification"):
            tx.atomic_replace(target, expected, b"model_provider = \"openai\"\n", self.root / "backups")
        self.assertEqual(target.read_bytes(), external)

    def test_atomic_replace_failure_keeps_original_config(self):
        target = self.root / "config.toml"
        target.write_bytes(CONFIG)
        with mock.patch.object(tx.os, "replace", side_effect=OSError("simulated replace failure")):
            with self.assertRaises(OSError):
                tx.atomic_replace(target, tx.sha(CONFIG), b"model_provider = \"openai\"\n", self.root / "backups")
        self.assertEqual(target.read_bytes(), CONFIG)

    def test_directory_sync_failure_after_replace_rolls_back(self):
        target = self.root / "config.toml"
        target.write_bytes(CONFIG)
        real_fsync = tx.os.fsync
        calls = 0

        def fail_second_fsync(fd):
            nonlocal calls
            calls += 1
            if calls == 2:
                raise OSError("simulated directory fsync failure")
            return real_fsync(fd)

        with mock.patch.object(tx.os, "fsync", side_effect=fail_second_fsync):
            with self.assertRaisesRegex(OSError, "directory fsync"):
                tx.atomic_replace(target, tx.sha(CONFIG), b"model_provider = \"openai\"\n", self.root / "backups")
        self.assertEqual(target.read_bytes(), CONFIG)

    def test_repeated_switches_remain_parseable_and_route_correct(self):
        deepseek = tx.apply_route(CONFIG, "deepseek", self.catalog)
        deepseek_again = tx.apply_route(deepseek, "deepseek", self.catalog)
        go = tx.apply_route(deepseek_again, "go", self.catalog, self.route)
        go_again = tx.apply_route(go, "go", self.catalog, self.route)
        self.assertEqual(self.parsed(deepseek_again)["model_provider"], "Model_Studio")
        self.assertEqual(self.parsed(go_again)["model_provider"], "openai")
        self.assertEqual(self.parsed(go_again)["model"], "original-model")

    def test_restore_returns_to_captured_route_semantics(self):
        deepseek = tx.apply_route(CONFIG, "deepseek", self.catalog)
        restored = tx.apply_route(deepseek, "restore", self.catalog, self.route)
        parsed = self.parsed(restored)
        self.assertEqual(parsed["model_provider"], "legacy-provider")
        self.assertEqual(parsed["model"], "original-model")
        self.assertEqual(parsed["model_providers"]["Model_Studio"]["base_url"], "https://old.invalid/v1")

    def test_auth_file_fixture_is_untouched(self):
        auth = self.root / "auth.json"
        fake = b'{"fixture":"not a credential"}\n'
        auth.write_bytes(fake)
        tx.apply_route(CONFIG, "deepseek", self.catalog)
        self.assertEqual(auth.read_bytes(), fake)

    def test_missing_model_slug_is_rejected(self):
        self.catalog.write_text(json.dumps({"models": [{"slug": "other-model"}]}))
        with self.assertRaisesRegex(ValueError, "lacks deepseek-v4.1-flash"):
            tx.apply_route(CONFIG, "deepseek", self.catalog)


if __name__ == "__main__":
    unittest.main()
