# Codex macOS Dual Launcher

Two native macOS desktop launchers for one ChatGPT/Codex installation:

- **Codex - GO** selects the official OpenAI provider and restores the model and catalog state captured at install time.
- **Codex - DeepSeek** selects `deepseek-v4.1-flash` through Aliyun Bailian's Responses-compatible endpoint.

The switcher edits only the root routing fields and its owned `Model_Studio` provider table in `~/.codex/config.toml`. Other settings remain in place. It requires ChatGPT.app to be normally quit before changing the route, creates a full pre-install backup, uses an exclusive lock and atomic replacement, and restores the previous file if a committed write or app launch fails safely.

## Requirements

- macOS with `/Applications/ChatGPT.app` installed.
- Codex config at `~/.codex/config.toml`.
- Model catalog at `~/.codex/model-catalog.local.json`, containing the `deepseek-v4.1-flash` slug.
- Python 3.11 or newer; the installer does not install Python or dependencies.
- Xcode Command Line Tools for compiling the small AppKit application-state helper.
- A dedicated Aliyun Bailian API key available as `OPENAI_API_KEY` in the user's `~/.zshrc`.

## Install

In Terminal, from a checked-out copy of this repository:

```sh
./install.command
```

Review the summary and type `INSTALL` to continue. The installer refuses to overwrite an existing `~/.codex-switcher` or either target desktop app. It snapshots the current config and route, but does not switch modes, launch or quit ChatGPT.app, read `auth.json`, or access the network.

The model catalog is deliberately not shipped as a template: its schema and contents are app/user-managed. The installer checks that the existing file contains the required model slug and never overwrites it.

The generated apps are unsigned local AppleScript/JXA applets. The installer checks compilation, bundle metadata, and signature integrity; it does not claim a LaunchServices GUI self-test. macOS may show its normal first-open confirmation. Do not weaken Gatekeeper or change Desktop ACLs. If the Desktop folder prevents publishing an app, stop and follow the troubleshooting guide; the installer will retain its staged files and backups.

## Daily use

1. Save work and normally quit ChatGPT.app.
2. Double-click **Codex - GO.app** or **Codex - DeepSeek.app**.
3. The launcher checks application state, changes the route, and opens `/Applications/ChatGPT.app`.

The switcher never force-quits ChatGPT.app. If it cannot determine whether the app is running, it stops without changing the config.

For DeepSeek, the launcher sources the existing `~/.zshrc` in its private child shell, checks that `OPENAI_API_KEY` is present without printing it, and runs `open --env OPENAI_API_KEY`. The variable name—not its value—is passed as an argument. The key is not copied into TOML, a plist, a script, or a log. Use a Bailian-specific key; do not point this at an unrelated OpenAI key.

## Restore and uninstall

- To return to GO, double-click **Codex - GO.app**.
- To uninstall, run `~/.codex-switcher/scripts/uninstall.command` in Terminal and confirm in its dialog. It restores the install-time route while preserving later non-routing config changes, removes the two applets only after confirmation, and archives the switcher and backups instead of deleting them.
- The install-time full config backup and every transaction backup are retained under `~/.codex-switcher/backups/`.

Do not manually replace the complete `config.toml` with an old backup to uninstall; that would discard later MCP, plugin, marketplace, and other settings. The transaction tool's `restore` operation restores only the captured routing semantics.

If a Desktop ACL prevents removing an applet, uninstall reports the failure and preserves the switcher archive. Do not change the ACL as a workaround; handle the remaining icon through Finder's normal permissions UI or keep it in place.

## Verification record

The user's reported integration run on ChatGPT.app `26.1002.52244` and Codex CLI `0.162.0-alpha.2` confirmed successful GUI startup for both entries and a successful in-app call to `deepseek-v4.1-flash` (Aliyun DashScope Custom Model). These are user-reported integration results, not CI tests. This repository's local tests cover configuration transactions only; they do not claim to verify GUI startup or network/API behavior.

See [Architecture](docs/ARCHITECTURE.md), [Security](docs/SECURITY.md), [Troubleshooting](docs/TROUBLESHOOTING.md), and [Changelog](docs/CHANGELOG.md).
