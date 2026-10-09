# Security

- Never commit API keys, `auth.json`, cookies, local config, model catalogs, logs, app bundles, install state, or backups. `.gitignore` excludes these common paths; review the complete staged diff before every push.
- The DeepSeek integration expects a Bailian-specific `OPENAI_API_KEY` in the user's existing `~/.zshrc`. The launcher checks only presence and does not print or log the value. macOS `open --env OPENAI_API_KEY` receives the variable by name; the secret is not placed in a command argument.
- Sourcing `~/.zshrc` executes that user's shell startup code in the launcher child. Keep the file trusted and avoid interactive prompts in it.
- The provider configuration contains only the environment-variable name. It never embeds a key in TOML, scripts, applet plist, or logs.
- An older local installation may still contain `scripts/keychain-token.command` and historic copies in its backups. The current source does not ship or call that helper; leave the local legacy file and backups untouched unless the owner later requests cleanup.
- `auth.json` is not read, copied, deleted, or modified by the switcher. Both modes use the same official sign-in state.
- The switcher never force-quits ChatGPT.app. Unknown app state, missing credentials, invalid TOML, lock contention, and fingerprint mismatch stop before a route change.
- The install and uninstall commands do not use `sudo`, alter system files, or modify ACLs. Do not disable Gatekeeper, SIP, or other macOS security controls to work around a denied operation.
- Configuration backups may contain private user settings. Keep them local and do not attach them to bug reports.

If a key may have been committed or copied into a log, stop publication and rotate it at the provider before proceeding.
