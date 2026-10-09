#!/usr/bin/env python3
"""Conservative root-route edits for the Codex profile switcher.

This module edits only root model routing keys and the owned Model_Studio
provider section. It keeps all other TOML text byte-for-byte intact.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import tempfile
import tomllib

ROOT_KEYS = ("model_provider", "model", "model_catalog_json")
PROVIDER_HEADER = "[model_providers.Model_Studio]"
DEEPSEEK_URL = "https://llm-ekqova7mnia3tsqn.cn-beijing.maas.aliyuncs.com/compatible-mode/v1"


def sha(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def parse(data: bytes) -> dict:
    return tomllib.loads(data.decode("utf-8"))


def capture_route(data: bytes) -> dict:
    parsed = parse(data)
    root = {}
    for key in ROOT_KEYS:
        root[key] = {"present": key in parsed, "value": parsed.get(key)}
    text = data.decode("utf-8")
    root["model_studio_section"] = section_text(text)
    return root


def section_text(text: str) -> str | None:
    matches = list(re.finditer(r"(?m)^\[model_providers\.Model_Studio\]\s*$", text))
    if not matches:
        return None
    if len(matches) != 1:
        raise ValueError("duplicate Model_Studio provider tables")
    start = matches[0].start()
    nxt = re.search(r"(?m)^\[", text[matches[0].end():])
    end = matches[0].end() + nxt.start() if nxt else len(text)
    # Preserve the preceding newline boundary of the next table.
    return text[start:end].rstrip("\r\n")


def toml_string(value: str) -> str:
    return json.dumps(value, ensure_ascii=False)


def remove_owned_section(text: str) -> str:
    match = re.search(r"(?m)^\[model_providers\.Model_Studio\]\s*$", text)
    if not match:
        return text
    nxt = re.search(r"(?m)^\[", text[match.end():])
    end = match.end() + nxt.start() if nxt else len(text)
    # Remove only the table and its adjacent blank lines, retaining next header.
    before = text[:match.start()].rstrip("\r\n")
    after = text[end:].lstrip("\r\n")
    return (before + "\n\n" + after).lstrip("\n") if after else before + "\n"


def set_root(text: str, key: str, value: str | None) -> str:
    # Routing keys are root-level assignments before the first table.
    first = re.search(r"(?m)^\s*\[", text)
    boundary = first.start() if first else len(text)
    head, tail = text[:boundary], text[boundary:]
    pattern = re.compile(rf"(?m)^{re.escape(key)}\s*=.*(?:\r?\n|$)")
    found = list(pattern.finditer(head))
    if len(found) > 1:
        raise ValueError(f"duplicate root key: {key}")
    line = f"{key} = {toml_string(value)}\n" if value is not None else ""
    if found:
        head = head[:found[0].start()] + line + head[found[0].end():]
    elif value is not None:
        head = head.rstrip("\r\n") + ("\n" if head.strip() else "") + line
    return head + tail


def apply_route(data: bytes, mode: str, catalog: Path, original_route: dict | None = None) -> bytes:
    parsed = parse(data)
    text = data.decode("utf-8")
    if mode in ("go", "restore") and original_route is None:
        raise ValueError("original route manifest required")
    # Validate there is at most one provider section before changing anything.
    current_section = section_text(text)
    if mode == "deepseek":
        if not catalog.is_absolute() or not catalog.is_file():
            raise ValueError("absolute model catalog path is missing")
        try:
            catalog_data = json.loads(catalog.read_text(encoding="utf-8"))
        except Exception as exc:
            raise ValueError("model catalog is invalid JSON") from exc
        models = catalog_data.get("models", []) if isinstance(catalog_data, dict) else []
        if not any(isinstance(m, dict) and m.get("slug") == "deepseek-v4.1-flash" for m in models):
            raise ValueError("model catalog lacks deepseek-v4.1-flash")
        text = remove_owned_section(text)
        for key, value in (("model_catalog_json", str(catalog)), ("model_provider", "Model_Studio"), ("model", "deepseek-v4.1-flash")):
            text = set_root(text, key, value)
        provider = (
            f"{PROVIDER_HEADER}\n"
            'name = "Model_Studio"\n'
            f"base_url = {toml_string(DEEPSEEK_URL)}\n"
            'wire_api = "responses"\n'
            'env_key = "OPENAI_API_KEY"\n'
        )
        text = text.rstrip() + "\n\n" + provider
    elif mode in ("go", "restore"):
        # Explicit OpenAI route. Restore original model/catalog presence/value;
        # never invent a model identifier.
        text = remove_owned_section(text)
        if mode == "go":
            # Runtime GO is always an explicit official route. Restore the
            # install-time model/catalog state where available, never invent a model.
            if original_route is not None:
                for key in ("model", "model_catalog_json"):
                    item = original_route.get(key, {"present": False})
                    text = set_root(text, key, item.get("value") if item.get("present") else None)
            text = set_root(text, "model_provider", "openai")
            saved = (original_route or {}).get("model_studio_section")
            if saved:
                text = text.rstrip() + "\n\n" + saved.rstrip() + "\n"
        else:
            for key in ("model", "model_catalog_json"):
                item = original_route.get(key, {"present": False})
                text = set_root(text, key, item.get("value") if item.get("present") else None)
            provider_item = original_route.get("model_provider", {"present": False})
            text = set_root(text, "model_provider", provider_item.get("value") if provider_item.get("present") else None)
            saved = original_route.get("model_studio_section")
            if saved:
                text = text.rstrip() + "\n\n" + saved.rstrip() + "\n"
    else:
        raise ValueError("mode must be go or deepseek")
    candidate = text.encode("utf-8")
    result = parse(candidate)
    if mode == "deepseek":
        provider = result.get("model_providers", {}).get("Model_Studio", {})
        if (result.get("model_provider"), result.get("model"), result.get("model_catalog_json")) != ("Model_Studio", "deepseek-v4.1-flash", str(catalog)):
            raise ValueError("DeepSeek route validation failed")
        if provider.get("wire_api") != "responses" or provider.get("env_key") != "OPENAI_API_KEY" or "auth" in provider:
            raise ValueError("DeepSeek provider validation failed")
    elif mode == "go":
        if result.get("model_provider") != "openai":
            raise ValueError("GO provider validation failed")
    elif mode == "restore":
        if original_route is None:
            raise ValueError("original route manifest required")
        for key in ROOT_KEYS:
            saved = original_route.get(key, {"present": False})
            if (key in result) != bool(saved.get("present")) or (key in result and result.get(key) != saved.get("value")):
                raise ValueError(f"restore validation failed for {key}")
        if section_text(text) != original_route.get("model_studio_section"):
            raise ValueError("restore validation failed for Model_Studio section")
    # Keep the current parsed object referenced to make malformed source fail early.
    del parsed, current_section
    return candidate


def atomic_replace(path: Path, expected_sha: str, payload: bytes, backup_dir: Path) -> Path:
    original = path.read_bytes()
    if sha(original) != expected_sha:
        raise RuntimeError("concurrent modification detected; refusing to write")
    backup_dir.mkdir(mode=0o700, parents=True, exist_ok=True)
    # Backups can be created several times within one second (for example GO
    # -> DeepSeek). Let the OS allocate a unique name; never overwrite an old
    # backup just because its timestamp and input fingerprint happen to match.
    stamp = __import__('time').strftime('%Y%m%d-%H%M%S')
    fd, backup_name = tempfile.mkstemp(
        prefix=f"config-{stamp}-{os.getpid()}-{sha(original)[:10]}-",
        suffix=".bak",
        dir=backup_dir,
    )
    backup = Path(backup_name)
    os.fchmod(fd, 0o600)
    try:
        with os.fdopen(fd, "wb") as f:
            f.write(original); f.flush(); os.fsync(f.fileno())
    except Exception:
        backup.unlink(missing_ok=True)
        raise
    if sha(backup.read_bytes()) != sha(original):
        raise RuntimeError(f"backup verification failed: {backup}")
    tmp_fd, tmp_name = tempfile.mkstemp(prefix=f".{path.name}.switch-", dir=path.parent)
    tmp = Path(tmp_name)
    committed = False
    try:
        with os.fdopen(tmp_fd, "wb") as f:
            f.write(payload); f.flush(); os.fsync(f.fileno())
        shutil.copystat(path, tmp, follow_symlinks=True)
        parse(tmp.read_bytes())
        if sha(path.read_bytes()) != expected_sha:
            raise RuntimeError("concurrent modification detected before atomic replace")
        os.replace(tmp, path)
        # The destination has changed even if opening or syncing its directory
        # fails. Mark it committed before any operation that can raise so the
        # exception path can safely restore the original bytes.
        committed = True
        dirfd = os.open(path.parent, os.O_RDONLY)
        try: os.fsync(dirfd)
        finally: os.close(dirfd)
        if sha(path.read_bytes()) != sha(payload):
            raise RuntimeError("post-write fingerprint mismatch")
        return backup
    except Exception:
        tmp.unlink(missing_ok=True)
        if committed:
            # Roll back only if nobody else changed the just-written file.
            if sha(path.read_bytes()) == sha(payload):
                restore_fd, restore_name = tempfile.mkstemp(prefix=f".{path.name}.rollback-", dir=path.parent)
                with os.fdopen(restore_fd, "wb") as f:
                    f.write(original); f.flush(); os.fsync(f.fileno())
                os.chmod(restore_name, path.stat().st_mode & 0o777)
                os.replace(restore_name, path)
            else:
                raise RuntimeError(f"write failed and external change prevents safe rollback; backup: {backup}")
        raise


def cli() -> int:
    p = argparse.ArgumentParser()
    p.add_argument("mode", choices=("go", "deepseek", "capture", "rollback", "restore"))
    p.add_argument("--config", type=Path, required=True)
    p.add_argument("--catalog", type=Path)
    p.add_argument("--manifest", type=Path)
    p.add_argument("--backup-dir", type=Path)
    p.add_argument("--expected-sha")
    p.add_argument("--backup", type=Path)
    a = p.parse_args()
    raw = a.config.read_bytes(); before = sha(raw)
    if a.expected_sha and before != a.expected_sha:
        raise SystemExit("concurrent modification detected; refusing to write")
    if a.mode == "capture":
        if not a.manifest: raise SystemExit("--manifest required")
        a.manifest.write_text(json.dumps({"sha256": before, "route": capture_route(raw)}, ensure_ascii=False, indent=2) + "\n")
        return 0
    if a.mode == "rollback":
        if not a.backup or not a.expected_sha or not a.backup_dir:
            raise SystemExit("rollback requires --backup, --expected-sha and --backup-dir")
        payload = a.backup.read_bytes()
        parse(payload)
        atomic_replace(a.config, a.expected_sha, payload, a.backup_dir)
        return 0
    if not a.manifest or not a.backup_dir: raise SystemExit("--manifest and --backup-dir required")
    manifest = json.loads(a.manifest.read_text(encoding="utf-8"))
    payload = apply_route(raw, a.mode, a.catalog or Path("/invalid"), manifest["route"] if a.mode in ("go", "restore") else None)
    backup = atomic_replace(a.config, before, payload, a.backup_dir)
    print(str(backup))
    return 0


if __name__ == "__main__":
    raise SystemExit(cli())
