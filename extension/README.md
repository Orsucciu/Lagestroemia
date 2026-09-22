# Lagestroemia Browser Extension

A browser extension that provides a powerful chat client for chat.z.ai,
running directly inside the chat.z.ai tab. This solves the captcha +
CORS + origin-binding issues that the Flutter app faces.

It also exposes a local OpenAI-compatible HTTP server so external tools
(opencode, Cline, Continue, curl, the OpenAI SDKs, etc.) can use
chat.z.ai through Lagestroemia — with **full support for tools
(function calling), reasoning content, and multi-turn conversations**.

## How it works

```
┌─────────────────────────────────────────────┐
│  Browser Tab: https://chat.z.ai             │
│  ┌───────────────────────────────────────┐  │
│  │  content.js (content script)         │  │
│  │  - Runs in chat.z.ai's origin        │  │
│  │  - Sends fetch() to /api/v2/chat/... │  │
│  │  - No CORS issues (same-origin)      │  │
│  │  - Captcha SDK works natively        │  │
│  │  - Computes X-Signature              │  │
│  │  - Forwards tools / temperature /    │  │
│  │    reasoning_effort from the caller  │  │
│  └──────────────┬────────────────────────┘  │
│                 │ chrome.runtime             │
│  ┌──────────────▼────────────────────────┐  │
│  │  background.js (service worker)       │  │
│  │  - Relays messages                   │  │
│  │  - Manages guest token cache         │  │
│  └──────────────┬────────────────────────┘  │
│  ┌──────────────▼────────────────────────┐  │
│  │  sidepanel.html/js (side panel UI)   │  │
│  │  - Chat interface                    │  │
│  │  - Model picker                      │  │
│  │  - Streams responses in real time    │  │
│  └──────────────┬────────────────────────┘  │
└─────────────────┼───────────────────────────┘
                  │ HTTP (loopback / LAN)
┌─────────────────▼───────────────────────────┐
│  native_host.py (Python, OpenAI-compat)    │
│  - POST /v1/chat/completions               │
│  - GET  /v1/models                         │
│  - Forwards tools / temp / etc to ext      │
│  - Translates SSE → OpenAI shape           │
│  - Emits tool_calls + reasoning_content    │
└─────────────────┬───────────────────────────┘
                  │ HTTP
                  ▼
        opencode / Cline / curl / etc.
```

### Why this works (and the Flutter app doesn't)

| Problem | Flutter app | Browser extension |
|---------|-------------|-------------------|
| **CORS** | ❌ chat.z.ai blocks cross-origin POST | ✅ Same-origin (content script runs in chat.z.ai) |
| **Captcha origin** | ❌ Aliyun rejects tokens from localhost | ✅ Token solved from chat.z.ai's origin |
| **X-Signature** | ❌ Browser strips custom headers on cross-origin | ✅ Same-origin, no header restrictions |
| **Cookies** | ❌ Can't access chat.z.ai cookies | ✅ `credentials: 'include'` works natively |
| **Tools (function calling)** | ❌ Not implemented | ✅ Forwarded to chat.z.ai, results emitted in OpenAI shape |
| **Reasoning content** | ❌ DOM scrape discards it | ✅ Surfaced as `delta.reasoning_content` |
| **Multi-turn** | ❌ Only last message sent | ✅ Full `messages` array forwarded |

## Features

- **OpenAI-compatible server**: full chat.z.ai API client with signature computation
- **Function calling**: `tools` parameter forwarded, `tool_calls` emitted with backfilled IDs
- **Reasoning**: `reasoning_content` forwarded; `reasoning_effort: 'medium'|'high'` enables thinking
- **Streaming**: real-time SSE streaming with content + reasoning + tool_calls deltas
- **Auto-retry**: exponential backoff on server errors (5xx, rate limit, network)
- **Captcha solving**: uses chat.z.ai's own Aliyun captcha SDK (works natively)
- **Model picker**: live model list from chat.z.ai
- **Enter to send**: Shift+Enter for newline
- **Clean UI**: side panel with chat bubbles
- **LAN access**: bind to `0.0.0.0` with API key for opencode-on-another-machine workflows

## Installation

### Chrome / Edge

1. Run `scripts/build-extension.sh chrome` (or just load `extension/` directly)
2. Open `chrome://extensions` (or `edge://extensions` in Edge)
3. Enable **Developer mode** (toggle in the top-right)
4. Click **Load unpacked**
5. Select the `extension/` directory (or `scripts/extension-chrome/`)
6. Open https://chat.z.ai in a tab (sign in as guest — it's automatic)
7. Click the Lagestroemia toolbar icon to open the side panel
8. Type a message and press Enter

### Firefox

Firefox 121+ is required (for Manifest V3 + `sidebar_action` support).

1. Run `scripts/build-extension.sh firefox` (creates `scripts/extension-firefox/`)
2. Open `about:debugging` in Firefox
3. Click **This Firefox** → **Load Temporary Add-on**
4. Select `scripts/extension-firefox/manifest.json`
5. Open https://chat.z.ai in a tab (sign in as guest — it's automatic)
6. Press `Ctrl+Shift+B` to toggle the sidebar (or use the toolbar button)
7. Type a message and press Enter

### Build script

```sh
# Build for a specific browser:
scripts/build-extension.sh chrome
scripts/build-extension.sh firefox

# Build for both:
scripts/build-extension.sh all
```

The build script copies the shared files (background.js, content.js,
sidepanel.html/js, icons) and swaps the appropriate manifest:
- `manifest.json` — Chrome/Edge (uses `side_panel` + `service_worker`)
- `manifest.firefox.json` — Firefox (uses `sidebar_action` + `background.scripts`)

## Using with opencode / Cline / Continue

The native host exposes an OpenAI-compatible HTTP server. By default it
listens on `http://127.0.0.1:8081` (loopback only).

**Full setup guide (same-machine, WSL2, LAN, troubleshooting, reinstall):
see [docs/opencode-setup.md](../docs/opencode-setup.md).**

### Same-machine setup

1. Install the native host: `scripts/install-native.sh firefox` (or `chrome`/`edge`)
2. Reload the extension so the native host starts
3. Point your OpenAI-compatible client at `http://127.0.0.1:8081/v1`

For opencode (`~/.config/opencode/opencode.json`):
```json
{
  "provider": {
    "lagestroemia": {
      "npm": "@ai-sdk/openai-compatible",
      "name": "Lagestroemia (z.ai)",
      "options": { "baseURL": "http://127.0.0.1:8081/v1" },
      "models": {
        "glm-4.7": { "name": "GLM-4.7" }
      }
    }
  }
}
```

### LAN setup (opencode on a different machine)

1. Edit `extension/native_host_wrapper.sh` (regenerate it via `scripts/install-native.sh` if missing)
2. Uncomment two lines:
   ```bash
   export LAGESTROEMIA_HOST=0.0.0.0
   export LAGESTROEMIA_API_KEY=change-me-to-a-secret
   ```
3. Reload the extension. The native host logs every reachable URL to stderr.
4. On the remote machine, point opencode at `http://<desktop-ip>:8081/v1`
   with `apiKey: "change-me-to-a-secret"`.

**Security model:**
- Loopback binds (`127.0.0.1`) require no API key.
- Non-loopback binds (`0.0.0.0` or a specific IP) **require** an API key.
  The server refuses to start otherwise.
- Internal endpoints (`/_pending`, `/_response`, `/_debug`) are
  loopback-only — they can't be reached from the LAN even when the
  server is bound to `0.0.0.0`. This prevents remote callers from
  reading pending user messages or injecting fake responses.

### Verifying it works

```bash
# Health (no auth needed):
curl http://127.0.0.1:8081/health

# Models (auth if API key set):
curl http://127.0.0.1:8081/v1/models \
  -H "Authorization: Bearer change-me-to-a-secret"

# Chat (non-streaming):
curl http://127.0.0.1:8081/v1/chat/completions \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer change-me-to-a-secret" \
  -d '{
    "model": "glm-4.7",
    "messages": [{"role": "user", "content": "Say hi"}],
    "stream": false
  }'

# Chat with tools:
curl http://127.0.0.1:8081/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "glm-4.7",
    "messages": [{"role": "user", "content": "What is 2+2?"}],
    "tools": [{
      "type": "function",
      "function": {
        "name": "calculator",
        "description": "Perform arithmetic",
        "parameters": {
          "type": "object",
          "properties": {
            "expression": {"type": "string"}
          },
          "required": ["expression"]
        }
      }
    }],
    "stream": true
  }'
```

## Architecture

### `manifest.json`
Manifest V3 extension. Requests permissions for `chat.z.ai` + the
Aliyun CDN (for the captcha SDK). Uses the `sidePanel` API (Chrome 114+).

### `background.js` (service worker)
- Opens the side panel on toolbar click
- Manages the guest token (fetch + cache for 30 minutes)
- Relays messages between the side panel and the content script

### `content.js` (content script)
Runs inside the chat.z.ai tab. This is the core of the extension:
- Computes the X-Signature header (HMAC-SHA256 with the secret key)
- Sends chat completion requests to `/api/v2/chat/completions` via `fetch()`
- Forwards `tools`, `tool_choice`, `temperature`, `max_tokens`, `top_p`,
  `presence_penalty`, `frequency_penalty`, `stop`, `seed` from the caller
- Parses SSE streams and extracts content + reasoning + tool_calls deltas
- Solves the Aliyun captcha using chat.z.ai's own SDK
- Auto-retries on server errors with exponential backoff
- Falls back to DOM-scrape path if the SSE parser fails

### `native_host.py` (Python)
The OpenAI-compatible HTTP server. Bridges external clients to the
extension via HTTP polling (`/_pending` and `/_response`).
- Translates OpenAI-shaped requests to the extension's internal format
- Translates the extension's streamChunks back to OpenAI SSE chunks
- Backfills `tool_call.id` if chat.z.ai omits it (required by opencode)
- Accumulates tool_call argument fragments across chunks (non-streaming)
- Enforces auth + loopback-only internal endpoints

### `sidepanel.html/js` (side panel UI)
- Chat interface with message bubbles
- Model picker (fetched live from chat.z.ai)
- Streaming response display
- Enter to send, Shift+Enter for newline

## Key files

- `extension/manifest.json` — extension manifest (V3)
- `extension/background.js` — service worker (token management + relay)
- `extension/content.js` — content script (API client + captcha + retry)
- `extension/native_host.py` — OpenAI-compat HTTP server (Python)
- `extension/sidepanel.html` — side panel UI
- `extension/sidepanel.js` — side panel logic
- `extension/tests/test-tools.py` — unit tests for tool_calls + reasoning

## Tests

```sh
# Signature tests (offline):
node extension/tests/test-signature.js

# OpenAI-compat translation tests (offline, no chat.z.ai needed):
python3 extension/tests/test-tools.py

# Live API test (needs network + captcha solved):
node extension/tests/test-live-api.js
```

## Comparison with the Flutter app

The Flutter app is a standalone cross-platform desktop/mobile/web app
that works without a browser. The browser extension is lighter and
solves the captcha/CORS issues by running inside chat.z.ai's tab, but
requires the user to have a chat.z.ai tab open.

Both share the same:
- X-Signature algorithm (HMAC-SHA256 with secret key)
- Request body format (signature_prompt, features, variables, etc.)
- SSE parsing logic
- Auto-retry strategy

## Browser compatibility

| Browser | Support | Sidebar API | Notes |
|---------|---------|-------------|-------|
| Chrome 114+ | ✅ | `chrome.sidePanel` | Full support |
| Edge 114+ | ✅ | `chrome.sidePanel` | Full support |
| Firefox 121+ | ✅ | `browser.sidebarAction` | Uses `background.scripts` instead of `service_worker` |
| Safari | ⚠️ Not tested | `browser.sidebarAction` | Should work with minor adjustments |

The extension auto-detects the browser at runtime:
- If `browser.sidebarAction` exists → Firefox mode
- Otherwise → Chrome/Edge mode (uses `chrome.sidePanel`)
