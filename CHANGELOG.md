# Changelog

All notable changes to this project are documented in
[`PROGRESS.md`](./PROGRESS.md). This file mirrors the user-facing
release-oriented view.

## [Unreleased]

### Added — initial MVP

- Native cross-platform Flutter client for z.ai (Linux, Windows,
  Android, Web/WASM).
- Streaming chat completions against `https://api.z.ai/api/paas/v4`.
- Local SQLite cache of chats, messages, attachments, artifacts,
  system prompts and account metadata.
- System prompts library with 4 built-in prompts.
- Light / dark / system theme picker.
- English + Simplified Chinese localisations (i18n baked in from day
  one; additional locales can be added by dropping in an `.arb` file).
- API-key authentication stored in the OS keychain.
- GitHub Actions workflows for Linux, Windows, Android and Web (WASM)
  builds, plus CI checks for analyze + test.
- Web build auto-deploys to GitHub Pages on push to `main`.

### Known limitations

- Web target stores the API key in browser storage without at-rest
  encryption.
- Streaming cancel button only resets local state; the in-flight HTTP
  request continues until the next chunk lands.
- OAuth flow is not implemented — z.ai does not expose a public OAuth
  endpoint as of the MVP. Auth uses API keys only.
