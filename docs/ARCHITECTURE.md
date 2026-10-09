# Architecture

## Runtime flow

The two applets call the same `scripts/applet-dispatch.command` with a fixed mode and the install directory. The dispatcher validates the arguments, then invokes `launch-go.command` or `launch-deepseek.command`. Both reach `switch.command`.

The switcher checks its lock and queries `NSRunningApplication` through the AppKit helper. Finder must be visible to that helper before an empty Codex result can mean stopped; otherwise the answer is `unknown` and the switcher fails closed. The switcher checks again before committing the route.

`config_transaction.py` parses TOML, changes only `model_provider`, `model`, `model_catalog_json`, and `[model_providers.Model_Studio]`, preserves unrelated TOML text, backs up the original bytes, validates the candidate, checks the source fingerprint, and uses same-directory atomic replacement. It restores the just-written file only if its fingerprint still matches the transaction's expected output.

GO explicitly sets `model_provider = "openai"` and restores install-time model/catalog presence and values. DeepSeek selects `Model_Studio`, the required model and catalog, Responses wire protocol, and `env_key = "OPENAI_API_KEY"`.

## Launch and credentials

The DeepSeek shell wrapper sources the user's existing `~/.zshrc` because a Finder-launched applet does not inherit interactive shell startup. It then checks presence only. `open --env OPENAI_API_KEY` forwards that existing process variable to the newly launched GUI app. GO does not source this file or pass the variable.

The desktop applet contains only dispatch logic and a home-relative install path; mode switching remains in shared scripts so script fixes do not require replacing a working applet bundle.

## Persistence

- Full install-time config snapshot: `~/.codex-switcher/backups/config.install-time.bak`.
- Per-transition byte backups: `~/.codex-switcher/backups/config-*.bak`.
- Install route metadata and app fingerprints: `~/.codex-switcher/install-state.json`.
- Logs contain timestamp, mode, stage, and safe error text only.

The installer does not copy the user's model catalog, `auth.json`, plugins, MCP state, or complete config into the repository. It validates the existing catalog in place.
