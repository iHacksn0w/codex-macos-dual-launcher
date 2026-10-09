# Troubleshooting

## ChatGPT.app is running or state is unknown

Save work and quit the app normally, then double-click the desired launcher again. `unknown` is not treated as stopped. Do not force-quit the app or edit `config.toml` manually during a switch.

## DeepSeek says `OPENAI_API_KEY` is missing

Confirm the existing export is available in `~/.zshrc`. The launcher sources that file in a child zsh and checks variable presence only. It does not display the value. Ensure the key belongs to Aliyun Bailian. No Keychain item is required by this version.

If `~/.zshrc` prompts for input or errors when sourced noninteractively, move environment initialization that is safe for noninteractive shells into `~/.zshenv`, or make the `.zshrc` section noninteractive-safe. Do not put the key in a project script, plist, TOML file, or log.

## Desktop app cannot be replaced or published

The installer refuses to overwrite existing applets and does not change Desktop ACLs. macOS may deny renaming an existing `.app` due to folder ACLs. Keep the old app and all backups, inspect the permission error in Finder's Get Info, and do not remove ACL entries as a workaround. A working applet dispatches to shared scripts, so updating those scripts may not require replacing the app bundle.

## Config transaction failed

Check `~/.codex-switcher/logs/switch.log` for the stage only. The log does not contain a full config or key. Keep all backups. A concurrent edit, malformed TOML, missing model slug, or uncertain app status intentionally stops the switch.

## App opened but DeepSeek model call failed

App startup is not proof of provider routing or API compatibility. Confirm the model shown in the GUI and inspect a safe, redacted error message. This project does not automatically send a test API request.
