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

## Outstanding work for future sessions

### High priority

1. **Run the unit tests** under `flutter test` and fix any failures
   (current smoke test should pass — it just pumps the splash screen).
2. **Wire the file_picker** into the chat composer's attach button.
   The state plumbing (`ChatComposerNotifier.attachFile`) is already
   there; only the UI call to `FilePicker.platform.pickFiles()` is
   missing.
3. **Render image attachments** inline in the chat list when the user
   message has `content_json` set.
4. **Stop button** actually cancels the in-flight HTTP request — pass
   a `CancelToken` into `ZaiApiClient.chatCompletionStream`.
5. **Implement the Files view** at `/library/files` (list attachments
   from the SQLite `attachments` table).

### Medium priority

6. **JWT auth mode** — for keys in form `<id>.<secret>`, sign a
   short-lived JWT (HS256, ms timestamps, `sign_type: SIGN` header)
   and use it as the Bearer token. UI: a toggle in Settings.
7. **Model picker** — currently the chat screen's app bar shows a
   dropdown of all known models; we should also persist the per-chat
   selection (already wired in the model — just need to seed it from
   `settings.model` on chat creation, which we do).
8. **Search** in the chat list and the artifacts library.
9. **Export chat** to Markdown / JSON.
10. **Tool calls** rendering in the chat view (today tool_calls are
    stored but not rendered).

### Low priority / nice-to-have

11. **Multi-account** — the `accounts` table is designed for this; we
    just need a UI for switching accounts.
12. **Drag-and-drop** file attachments in the chat composer on desktop.
13. **System tray icon** for desktop targets.
14. **Notification** when a long-running stream finishes in the
    background.

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
