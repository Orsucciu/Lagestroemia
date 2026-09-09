# Changelog

All notable changes to this project are documented in
[`PROGRESS.md`](./PROGRESS.md). This file mirrors the user-facing
release-oriented view.

## [Unreleased]

### Added — guest mode (2026-09-09)

- **Anonymous guest mode** — the app now boots directly into the chat
  list without prompting for an API key. It uses the same anonymous
  signup path as the chat.z.ai website (`GET /api/v1/auths/`).
- **Two-mode auth** — users can switch between guest mode (free,
  captcha per session) and API-key mode (paid, no captcha) from
  Settings.
- **In-app Aliyun captcha widget** — when the chat backend returns
  `FRONTEND_CAPTCHA_REQUIRED`, an in-app webview renders the Aliyun
  captcha SDK and forwards the `captcha_verify_param` to Dart via
  JS interop.
- **Files library** (`/library/files`) — flat list of all attachments
  across all chats, grouped by chat, with image thumbnails and a
  download button.
- **Search** in the chat list (by title) and the artifacts library
  (by name, language, body).
- **Per-chat system prompt picker** in the chat screen's app bar.
- **Export chat** to Markdown or JSON via FilePicker.saveFile.
- **Inline image rendering** for image attachments in chat messages.
- **Tool calls rendering** in a collapsible panel under assistant
  messages.
- **Real Stop button** — actually cancels the in-flight HTTP request
  via Dio's CancelToken.
- **Live integration tests** against chat.z.ai — verified guest
  signup, chat endpoint reachability, and model list.

### Changed

- The auth screen now shows "Continue as guest" as the primary action
  and "I have a z.ai API key" as a collapsible secondary path.
- The Settings screen now shows the current auth mode and lets the
  user switch between guest and API-key modes.

### Initial MVP (2026-09-08)

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
  encryption (a warning is now shown on the auth screen and in Settings
  for Web builds).
- The Aliyun captcha widget uses `flutter_inappwebview`, which requires
  a webview runtime on Linux (libwebkit2gtk) and Android. On Linux it
  may need an additional system package; on iOS it is supported natively.
- OAuth flow is not implemented — z.ai does not expose a public OAuth
  endpoint. Auth uses either guest mode or API keys.
