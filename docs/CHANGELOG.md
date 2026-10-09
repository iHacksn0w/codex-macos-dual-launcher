# Changelog

## 1.0.0 — 2026-10-09

- Added native GO and DeepSeek launcher source for macOS.
- Added route-only transactional config editing with backups, locking, validation, and rollback.
- Restored the established `OPENAI_API_KEY` / `env_key` path for Bailian and controlled GUI environment forwarding.
- Documented the reported successful GO and DeepSeek GUI/model-call validation separately from automated tests.

## Known limits

- LaunchServices behavior can vary by macOS session and folder ACL. The installer validates the applet bundle but leaves GUI startup confirmation to an actual desktop session.
- The current maintainer's GUI and model-call results were confirmed on one ChatGPT.app/Codex version and are not a compatibility guarantee for future releases.
