# Lagestroemia — Progress Log

This file is the authoritative narrative changelog for the project.
Future AI sessions should read this first, then check `git log` and
the open GitHub Issues to figure out where to pick up.

Each entry is dated and prefixed with a stage tag:

- `[setup]`    — environment / project scaffolding
- `[feature]`  — user-visible functionality
- `[fix]`      — bug fix
- `[build]`    — build pipeline / CI
- `[docs]`     — documentation
- `[chore]`    — refactor / deps / cleanup

---

## 2026-09-08 — Initial MVP

### `[setup]` Environment

- Installed Flutter 3.27.4 (stable) to `~/.local/opt/flutter`.
- Installed clang 18.1.8 (minimal extract — `clang-18`, headers, libs) to
  `~/.local/opt/clang`. Worked around the missing `libtinfo.so.5` on the
  host by downloading `libtinfo5_6.3-2_amd64.deb` and dropping the
  `libtinfo.so.5.9` into `~/.local/opt/clang/lib`.
- Installed CMake 4.4.3 + Ninja 1.13.2 via `pip install --user --break-system-packages`.
- Built a GTK3 + deps dev-sysroot at `~/.local/opt/sysroot` by extracting
  `.deb` files for: `libgtk-3-dev`, `libglib2.0-dev`, `libpango1.0-dev`,
  `libcairo2-dev`, `libatk1.0-dev`, `libatk-bridge2.0-dev`,
  `libgdk-pixbuf-2.0-dev`, `libharfbuzz-dev`, `libfribidi-dev`,
  `libwayland-dev`, `libxkbcommon-dev`, `libepoxy-dev`, plus the X11 dev
  packages (`libxi-dev`, `libxrandr-dev`, `libxcursor-dev`,
  `libxfixes-dev`, `libxcomposite-dev`, `libxdamage-dev`,
  `libxinerama-dev`) and Mesa dev packages (`libgl-dev`, `libegl-dev`).
- Patched every `.pc` file under the sysroot to point at the sysroot's
  prefix (was `/usr`, now `$HOME/.local/opt/sysroot/usr`).
- Stubbed missing packages (`cloudproviders`, `atspi-2`, `dbus-1`) in
  `~/.local/opt/pkgconfig-overrides` so pkg-config resolves cleanly.
- Created `.so` symlinks for `libgtk-3`, `libgdk-3`, `libatk-1.0` inside
  the sysroot, pointing at the system's `.so.0` shared libraries.
- Installed the `libsecret-1-0` runtime package into the sysroot so
  `flutter_secure_storage` can link.
- `flutter doctor` reports Linux toolchain green.

Environment variables (set in `~/.bashrc`):

```sh
export LD_LIBRARY_PATH="$HOME/.local/opt/clang/lib:$LD_LIBRARY_PATH"
export PATH="$HOME/.local/opt/clang/bin:$HOME/.local/bin:$HOME/.local/opt/flutter/bin:$PATH"
export PKG_CONFIG_PATH="$HOME/.local/opt/pkgconfig-overrides:/usr/lib/x86_64-linux-gnu/pkgconfig:/usr/share/pkgconfig:$HOME/.local/opt/sysroot/usr/lib/x86_64-linux-gnu/pkgconfig:$HOME/.local/opt/sysroot/usr/share/pkgconfig"
```

Important: **do not** set `C_INCLUDE_PATH` / `CPLUS_INCLUDE_PATH` /
`LIBRARY_PATH` — when set, clang stops adding its default system include
search paths, and `cstdlib:79: #include_next <stdlib.h>` fails because
`/usr/include/stdlib.h` is no longer in the search list. CMake's
`-isystem` flags + pkg-config are enough.

### `[setup]` Project

- Cloned the empty GitHub repo.
- `flutter create --platforms=linux,android,web,windows --org com.lagestroemia --project-name lagestroemia .`
- Added dependencies: `flutter_riverpod`, `go_router`, `sqflite_common_ffi`
  + `sqflite_common_ffi_web`, `flutter_secure_storage`, `dio`,
  `flutter_markdown`, `file_picker`, `intl`, `uuid`, `shared_preferences`,
  `url_launcher`, `logging`, `crypto`, `json_annotation`.
- Configured `flutter config --jdk-dir=/usr/lib/jvm/java-21-openjdk-amd64`
  for Android builds (Gradle needs Java 17–21).
- Set up `l10n.yaml` + `lib/l10n/app_en.arb` + `lib/l10n/app_zh.arb`.
  Generated via `flutter gen-l10n`.

### `[feature]` z.ai API research

Researched the z.ai API (sub-agent task). Key findings:

- z.ai = international brand of Zhipu AI.
- API base URL: `https://api.z.ai/api/paas/v4`.
- Auth: API key (Bearer). Keys look like `<id>.<secret>`. **No OAuth flow
  is publicly documented.** An optional JWT signing flow exists for
  high-security keys (HS256, `sign_type: SIGN` header, ms timestamps).
- Chat completions: `POST /chat/completions`, OpenAI-shaped. Streaming
  via SSE `data: <json>\n\n`, terminated by `data: [DONE]`.
- Models: `glm-5.3`, `glm-5.2`, `glm-5.1`, `glm-5`, `glm-4.7`, `glm-4.6`,
  `glm-4.5` + variants (`-flash`, `-air`, `-x`, `v` for vision). Default
  picked for the app: `glm-4.6`.
- File upload: `POST /files` (multipart, `purpose=user_data|agent`).
- Errors: `{"error":{"code":"1214","message":"..."}}` for non-streaming;
  during SSE, errors surface as `finish_reason: 'error'`.
- No Dart SDK exists. Built a thin `ZaiApiClient` ourselves.

### `[feature]` Core architecture

Wrote the following layers:

1. **`core/config/app_config.dart`** — all constants (URLs, storage keys,
   default model, known model list, prefs keys).
2. **`core/platform/platform_info.dart`** — runtime detection helpers
   (isWeb, isLinux, isAndroid, etc.). Used everywhere instead of raw
   `dart:io` so the WASM build works.
3. **`core/logging/logging.dart`** — `initLogging(Level)` + `logger(name)`.
4. **`core/result/result.dart`** — `sealed class Result<T,E>` with
   `Ok<T,E>` / `Err<T,E>` subclasses and `unwrap`, `unwrapOr`, `map`,
   `mapErr` helpers.
5. **`core/storage/secure_storage_service.dart`** — wraps
   `flutter_secure_storage` for the API key + optional JWT secret.
6. **`data/models/`** — plain Dart models for `Chat`, `ChatMessage`
   (with `MessageRole` enum), `Attachment`, `Artifact`
   (with `ArtifactKind` enum), `SystemPrompt`, `Account`, `ApiError`
   (with `ApiErrorKind` enum). Each has `fromMap`/`toMap` for SQLite and
   `toWirePayload` where useful for the API.
7. **`data/database/database_helper.dart`** — singleton SQLite open +
   migration helper. Picks the right `DatabaseFactory` per platform
   (`databaseFactoryFfi` on Linux/Windows/macOS, `databaseFactoryFfiWeb`
   on Web, default on Android). Schema v1 includes `chats`, `messages`,
   `attachments`, `artifacts`, `system_prompts`, `accounts`, `kv`. Seeds
   four built-in system prompts on first creation.
8. **`data/repositories/`** — one repository per table: `ChatRepository`,
   `MessageRepository`, `AttachmentRepository`, `ArtifactRepository`,
   `SystemPromptRepository`, `AccountRepository`, `KvRepository`.
9. **`data/api/zai_api_client.dart`** — HTTP + SSE client. Methods:
   `chatCompletion` (non-streaming, returns `Result<AssistantResponse,
   ApiError>`), `chatCompletionStream` (streaming, yields
   `ChatStreamChunk`), `uploadFile`. SSE parser splits on `\n\n` and
   extracts `data:` lines; `[DONE]` sentinel ends the stream.
10. **`state/providers.dart`** — Riverpod providers for: database,
    secure storage, dio, all repositories, the `ZaiApiClient`
    (returns `null` if signed out), and `initAppLogger()`.
11. **`state/settings_state.dart`** — `SettingsNotifier` persists theme
    mode, locale, model id, API base URL to `SharedPreferences`.
12. **`state/auth_state.dart`** — `AuthNotifier` with `restore()`,
    `signInWithKey()`, `signOut()`. Coordinated with `SecureStorageService`.
13. **`state/chat_state.dart`** — `ChatListNotifier` (CRUD on chats),
    `currentChatIdProvider`, `currentChatMessagesProvider`,
    `ChatComposerNotifier` (input + send + streaming).

### `[feature]` UI

Wrote the following screens:

1. **`features/splash/splash_screen.dart`** — boot screen. Reads the
   saved API key and routes to either `/auth` or `/`.
2. **`features/auth/auth_screen.dart`** — first-run API key entry. Has
   a link to the z.ai dashboard to create a key.
3. **`features/chat/chat_list_screen.dart`** — home screen. Lists chats
   with rename / archive / delete via popup menu.
4. **`features/chat/chat_screen.dart`** — the conversation view.
   Messages rendered with `flutter_markdown`. Composer with attach +
   send/stop buttons. Streams live and persists every chunk. Model
   picker in the app bar.
5. **`features/library/library_screen.dart`** — entry to the library
   (artifacts list today; files view stubbed).
6. **`features/library/artifacts_library_screen.dart`** — flat list of
   all artifacts across all chats. Click to open in a modal dialog.
7. **`features/prompts/prompts_screen.dart`** — list of system prompts
   with builtin badges.
8. **`features/prompts/prompt_editor_screen.dart`** — create / edit a
   prompt.
9. **`features/settings/settings_screen.dart`** — account (sign out,
   link to dashboard + rate limits + API base URL reset), appearance
   (theme dropdown), language (radio), about (version + docs link).
10. **`router/app_router.dart`** — `go_router` with a `ShellRoute` that
    wraps the four main destinations in a `NavigationRail`.
11. **`theme/app_theme.dart`** — Material 3 light + dark themes. Brand
    accent is purple/violet (#7C4DFF) — Lagerstroemia is the crape
    myrtle genus, which has pink-purple blossoms.

### `[feature]` i18n

- `lib/l10n/app_en.arb` — English strings.
- `lib/l10n/app_zh.arb` — Chinese (Simplified) strings.
- Generated files in `lib/l10n/generated/`.
- Every screen pulls strings via `AppLocalizations.of(context)`.

### `[build]` GitHub Actions

- `.github/workflows/ci.yml` — analyze + test on every push/PR.
- `.github/workflows/build-linux.yml` — Linux desktop build.
- `.github/workflows/build-windows.yml` — Windows desktop build.
- `.github/workflows/build-android.yml` — Android APK build
  (split per ABI).
- `.github/workflows/build-web.yml` — Web WASM build, deploys to
  GitHub Pages on `main`.

### `[build]` Local build verification

Successfully built the Linux target locally:

```
$ flutter build linux --release
✓ Built build/linux/x64/release/bundle/lagestroemia
```

The binary runs headlessly (`(com.lagestroemia.lagestroemia:11458):
Gtk-WARNING **: cannot open display:`) — expected in this sandbox.

---

## 2026-09-09 — Guest mode + 9 issues fixed

### `[feature]` Two-mode auth (guest + API-key)

Reverse-engineered the chat.z.ai web app to figure out how the
website itself does unauthenticated chat:

- `GET https://chat.z.ai/api/v1/auths/` returns a **guest JWT** with
  no captcha required — this is the same anonymous flow the website
  uses when a user opens chat.z.ai without logging in.
- The chat endpoint is `POST /api/v2/chat/completions` (NOT
  `/api/chat/completions` or `/openai/chat/completions` as we initially
  probed — those return 404). It accepts the guest JWT as `Bearer`
  + `X-FE-Version: prod-fe-1.1.93` header.
- The endpoint requires an Aliyun captcha per session, provided as
  `captcha_verify_param` in the request body. Without it, the SSE
  stream yields an inline error with `error_code: "FRONTEND_CAPTCHA_REQUIRED"`.
- The Aliyun captcha SDK lives at
  `https://o.alicdn.com/captcha-frontend/aliyunCaptcha/AliyunCaptcha.js`
  and uses scene id `didk33e0`, prefix `no8xfe`, region `sgp`.
- chat.z.ai wraps the SSE payload in a
  `{"type": "chat:completion", "data": {...}}` envelope (which itself
  has a nested `data` field with the OpenAI-shaped content).
- The actual model ids on chat.z.ai are different from api.z.ai's:
  `glm-4.7`, `glm-4.6v`, `glm-5.3`, `glm-5.2`, `GLM-5-Turbo`,
  `GLM-5v-Turbo`, `0727-106B-API` (=GLM-4.5-Air), `0727-360B-API`
  (=GLM-4.5), `x-preview-l` (=GLM-5.3-Flash), `deep-research`
  (=Z1-Rumination), `zero` (=Z1-32B).

### `[feature]` Two backends in `ZaiApiClient`

Refactored the API client to support both backends via an
`ApiBackend` enum:

- `ApiBackend.apiZai` — `https://api.z.ai/api/paas/v4` (OpenAI-compat,
  requires API key, no captcha).
- `ApiBackend.chatZai` — `https://chat.z.ai/api` (open-webui-style,
  accepts guest JWT, requires captcha per session).

Both share the same `chatCompletion` / `chatCompletionStream` /
`uploadFile` / `listModels` API. The SSE parser was extended to
unwrap the chat.z.ai envelope. `chatCompletionStream` now accepts
an optional `CancelToken` so the Stop button can actually cancel
the in-flight HTTP request (issue #6).

### `[feature]` Captcha widget

Added `lib/widgets/aliyun_captcha_widget.dart` — an in-app webview
(via `flutter_inappwebview`) that loads AliyunCaptcha.js and forwards
the `captcha_verify_param` string back to Dart via JS interop. This
is the **only** piece of the app that uses a webview; it renders
*only* the captcha (not the chat.z.ai UI), as required by the user's
"no webview to cheat" rule.

### `[feature]` Auth flow redesign

`AuthState` now has a `mode` field (none/guest/apiKey). The splash
screen automatically fetches a guest JWT on first launch — no auth
UI is shown by default. The auth screen only appears if the guest
fetch fails (network error, chat.z.ai down) or when the user
explicitly chooses "Switch to API key" from Settings.

The auth screen now offers:

- **"Continue as guest (free)"** as the primary action.
- **"I have a z.ai API key"** as a collapsible secondary path.

### `[feature]` Settings redesign

The Settings screen shows the current auth mode and lets the user
switch. In guest mode it shows a "Refresh guest session" button.
On the Web target it shows a warning about the lack of at-rest
encryption for the API key (issue #3).

### `[feature]` Chat screen upgrades

- App bar shows the current chat title.
- Model picker uses the right list for the current auth mode.
- Per-chat system prompt picker (issue #4).
- Export chat menu (issue #10) — Markdown or JSON via FilePicker.saveFile.
- Composer file picker (issue #1) — multiple files, with chips above
  the text field and per-chip remove.
- Inline image attachments render in the message bubble (issue #5).
- Tool calls render in a collapsible panel under the assistant
  message (issue #11).
- Captcha prompt bar appears when the chat backend returns
  `FRONTEND_CAPTCHA_REQUIRED`.
- Stop button cancels the in-flight HTTP request (issue #6).

### `[feature]` Files library (issue #7)

`AttachmentRepository.listAll()` joins `attachments` ↔ `messages`
↔ `chats` and returns `AttachmentWithChat` with the parent chat's
title. New `/library/files` route renders an ExpansionTile per
chat with thumbnails for images and a download button.

### `[feature]` Search (issue #9)

`chatListSearchProvider` and `artifactsSearchProvider` StateProviders
power a search bar at the top of the chat list and the artifacts
library. Filtering is case-insensitive substring match on title
(chats) or name+language+body (artifacts).

### `[build]` Scripts to recreate the environment

Two scripts in `/home/z/my-project/scripts/`:

- `build-sysroot.sh` — idempotent bash that re-downloads all the
  `.deb` files needed for the GTK3 dev sysroot, patches `.pc` files
  to point at the sysroot, stubs missing packages (cloudproviders,
  atspi-2, dbus-1), and creates `.so` symlinks for system-provided
  runtime libs. Re-run after a workspace wipe.
- `env.sh` — sourceable file that sets `PATH`, `LD_LIBRARY_PATH`,
  and `PKG_CONFIG_PATH` correctly. Use as
  `/home/z/my-project/scripts/env.sh flutter build linux --release`.

### `[test]` Live integration tests

`test/zai_api_live_test.dart` is tagged `live` and runs against the
real chat.z.ai backend. Three tests:

1. Guest signup returns a JWT (>40 chars).
2. Chat completion endpoint returns `FRONTEND_CAPTCHA_REQUIRED`
   when called without a captcha — proves the endpoint is reachable
   and our auth + error parsing is correct.
3. `listModels()` returns a non-empty list including `glm-4.7`.

All 3 tests pass.

### `[build]` Linux build still works

`flutter build linux --release` produces
`build/linux/x64/release/bundle/lagestroemia` (Linux x64 binary).
The binary runs cleanly (only fails on display in the headless
sandbox).

### `[docs]` Updated PROGRESS.md (this section).

---

## Outstanding work for future sessions

The following tasks are tracked as GitHub Issues under the
**MVP polish** milestone. Each issue number is in parentheses.

### High priority — DONE in this session

1. ~~**Run the unit tests** under `flutter test` and fix any failures~~ ✅
2. ~~**Wire the file_picker** into the chat composer's attach button.~~ ✅ (#1)
3. ~~**Render image attachments** inline in the chat list.~~ ✅ (#5)
4. ~~**Stop button** actually cancels the in-flight HTTP request.~~ ✅ (#6)
5. ~~**Implement the Files view** at `/library/files`.~~ ✅ (#7)

### Medium priority — DONE in this session

6. **JWT auth mode** — for keys in form `<id>.<secret>`, sign a
   short-lived JWT (HS256, ms timestamps, `sign_type: SIGN` header)
   and use it as the Bearer token. UI: a toggle in Settings. (#8)
   — **DEFERRED.** Needs `dart_jsonwebtoken` dep + UI. Next session.
7. ~~**Per-chat system prompt picker** in the chat screen's app bar.~~ ✅ (#4)
8. ~~**Search** in the chat list and the artifacts library.~~ ✅ (#9)
9. ~~**Export chat** to Markdown / JSON.~~ ✅ (#10)
10. ~~**Tool calls** rendering in the chat view.~~ ✅ (#11)

### Low priority / nice-to-have

11. **Multi-account** — the `accounts` table is designed for this; we
    just need a UI for switching accounts. (#12)
12. **Drag-and-drop** file attachments in the chat composer on desktop.
13. **System tray icon** for desktop targets.
14. **Notification** when a long-running stream finishes in the
    background.

### Build / release

15. **Re-install .github/workflows once a workflow-scoped PAT is
    available.** Workflows are in `docs/workflows/` until then. (#2)
16. **Document Web target's lack of at-rest encryption for the API
    key** in the auth screen + Settings (the README already mentions
    it). (#3)

### Known limitations

- **Web target**: secure storage on the Web uses browser-local storage
  with no encryption at rest. We should document this prominently
  before publishing the WASM build.
- **Web target**: file uploads via the file_picker package work on Web
  but require the user to explicitly opt-in via the file dialog.
- **Linux target**: the app expects `libsecret-1` to be installed
  (the GNOME keyring is typically running). On minimal systems you
  may need to install it.
- **z.ai OAuth**: not available in the public API. If z.ai ever exposes
  it, we should switch the auth flow to that for better UX.
- **Streaming cancel**: the in-flight HTTP request is not actually
  cancelled yet — only the local `streaming` flag is reset. The stream
  continues until the next chunk arrives. Fixing this requires passing
  a `CancelToken` into `chatCompletionStream`.
