# Lagestroemia

A native cross-platform client for [z.ai](https://z.ai), built with Flutter.

Targets:

| Platform | Status |
|----------|--------|
| Linux (x64) | ✅ Builds locally & via GitHub Actions |
| Windows (x64) | ✅ Builds via GitHub Actions |
| Android (arm64 / arm / x86_64) | ✅ Builds via GitHub Actions |
| Web (WebAssembly + JS fallback) | ✅ Builds via GitHub Actions |

The app is **native** on every target — no webview. On Web it compiles to
WebAssembly; on Linux/Windows/Android it uses Flutter's native rendering
engine (Skia/Impeller).

## Features (MVP)

- **Chat** with streaming responses from z.ai (OpenAI-compatible
  `/paas/v4/chat/completions` endpoint).
- **Local storage** of every chat, message, attachment and artifact in a
  SQLite database under your app-data directory. One file, easy to back up
  or transfer to another machine.
- **Library** view to browse all artifacts the assistant has produced
  across all chats.
- **System prompts** library with built-in prompts (default, coder,
  explainer, translator) and the ability to add your own.
- **Settings**: account (API key), theme (light/dark/system), language
  (English / 中文), model picker.
- **i18n** from day one — English and Chinese localisations are bundled,
  more can be added by dropping in an `.arb` file.
- **Optional night mode** that follows the system preference by default.

## Authentication

z.ai does not currently expose a public OAuth flow, so we use **API-key
authentication**: paste your z.ai API key (create one at
<https://z.ai/manage-apikey/apikey-list>) into the first-run screen, and
Lagestroemia stores it in the OS keychain (Windows Credential Manager /
libsecret on Linux / Android Keystore / browser storage on Web).

## Build locally

You need [Flutter](https://flutter.dev) 3.27+ and the per-platform build
deps.

### Linux

```bash
sudo apt-get install -y clang cmake ninja-build pkg-config \
  libgtk-3-dev libglib2.0-dev libsecret-1-dev libgcrypt20-dev \
  libgpg-error-dev libepoxy-dev libwayland-dev libxkbcommon-dev \
  libatk1.0-dev libatk-bridge2.0-dev libgdk-pixbuf2.0-dev \
  libpango1.0-dev libcairo2-dev libharfbuzz-dev libfribidi-dev \
  libxi-dev libxrandr-dev libxcursor-dev libxfixes-dev \
  libxcomposite-dev libxdamage-dev libxinerama-dev \
  libgl1-mesa-dev libegl1-mesa-dev libgles2-mesa-dev
flutter pub get
flutter build linux --release
# Output: build/linux/x64/release/bundle/lagestroemia
```

### Windows

```bash
flutter pub get
flutter build windows --release
# Output: build\windows\x64\runner\Release\lagestroemia.exe
```

### Android

```bash
flutter pub get
flutter build apk --release --split-per-abi
# Output: build/app/outputs/flutter-apk/app-*-release.apk
```

### Web (WASM)

```bash
flutter pub get
flutter build web --release --wasm
# Output: build/web/  (open index.html in a browser)
```

## Architecture

```
lib/
├── core/                 Cross-cutting concerns
│   ├── config/           AppConfig — URLs, storage keys, model list
│   ├── logging/          Logger setup
│   ├── platform/         PlatformInfo — runtime detection helpers
│   ├── result/           Result<T,E> sealed-union
│   └── storage/          SecureStorageService — wraps keychain
├── data/                 Data layer
│   ├── api/              ZaiApiClient — HTTP + SSE for z.ai
│   ├── database/         DatabaseHelper — SQLite open + migrations
│   ├── models/           Plain Dart models (Chat, Message, Artifact, ...)
│   └── repositories/     CRUD per table
├── features/             UI features
│   ├── auth/             First-run API key entry
│   ├── chat/             Chat list + chat screen + composer
│   ├── library/          Artifacts library
│   ├── prompts/          System prompts library + editor
│   ├── settings/         Account / appearance / language / about
│   └── splash/          Boot screen
├── l10n/                 AppLocalizations (.arb source + generated)
├── router/               go_router config
├── state/                Riverpod providers + state notifiers
├── theme/                Light/dark Material 3 themes
└── widgets/              Shared widgets (ErrorBanner, ...)
```

State management: [Riverpod](https://pub.dev/packages/flutter_riverpod).
Routing: [go_router](https://pub.dev/packages/go_router).
Database: SQLite via `sqflite_common_ffi` (native) and
`sqflite_common_ffi_web` (Web/WASM).

## Repository

- **Source**: <https://github.com/Orsucciu/Lagestroemia>
- **Issues**: see `PROGRESS.md` for the live roadmap, and the GitHub
  Issues tab for per-task tracking.
- **Progress**: `PROGRESS.md` is the authoritative narrative changelog
  that future AI sessions can read to pick up where the last session left
  off.

## License

MIT — see `LICENSE`.
