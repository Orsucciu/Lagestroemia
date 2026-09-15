# Lagestroemia Browser Extension

A browser extension that provides a powerful chat client for chat.z.ai,
running directly inside the chat.z.ai tab. This solves the captcha +
CORS + origin-binding issues that the Flutter app faces.

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
│  └──────────────┬────────────────────────┘  │
│                 │ chrome.runtime             │
│  ┌──────────────▼────────────────────────┐  │
│  │  background.js (service worker)       │  │
│  │  - Relays messages                   │  │
│  │  - Manages guest token cache         │  │
│  └──────────────┬────────────────────────┘  │
│                 │ chrome.runtime             │
│  ┌──────────────▼────────────────────────┐  │
│  │  sidepanel.html/js (side panel UI)   │  │
│  │  - Chat interface                    │  │
│  │  - Model picker                      │  │
│  │  - Streams responses in real time    │  │
│  └───────────────────────────────────────┘  │
└─────────────────────────────────────────────┘
```

### Why this works (and the Flutter app doesn't)

| Problem | Flutter app | Browser extension |
|---------|-------------|-------------------|
| **CORS** | ❌ chat.z.ai blocks cross-origin POST | ✅ Same-origin (content script runs in chat.z.ai) |
| **Captcha origin** | ❌ Aliyun rejects tokens from localhost | ✅ Token solved from chat.z.ai's origin |
| **X-Signature** | ❌ Browser strips custom headers on cross-origin | ✅ Same-origin, no header restrictions |
| **Cookies** | ❌ Can't access chat.z.ai cookies | ✅ `credentials: 'include'` works natively |

## Features

- **Server API**: full chat.z.ai API client with signature computation
- **Auto-retry**: exponential backoff on server errors (5xx, rate limit, network)
- **Captcha solving**: uses chat.z.ai's own Aliyun captcha SDK (works natively)
- **Model picker**: live model list from chat.z.ai
- **Streaming**: real-time SSE streaming with content + reasoning
- **Enter to send**: Shift+Enter for newline
- **Clean UI**: side panel with chat bubbles

## Installation (development)

1. Open `chrome://extensions` (or `edge://extensions` in Edge)
2. Enable **Developer mode** (toggle in the top-right)
3. Click **Load unpacked**
4. Select the `extension/` directory
5. Open https://chat.z.ai in a tab (sign in as guest — it's automatic)
6. Click the Lagestroemia toolbar icon to open the side panel
7. Type a message and press Enter

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
- Sends chat completion requests to `/api/v2/chat/completions`
- Parses SSE streams and extracts content + reasoning deltas
- Solves the Aliyun captcha using chat.z.ai's own SDK
- Auto-retries on server errors with exponential backoff

### `sidepanel.html/js` (side panel UI)
- Chat interface with message bubbles
- Model picker (fetched live from chat.z.ai)
- Streaming response display
- Enter to send, Shift+Enter for newline

## Key files

- `extension/manifest.json` — extension manifest (V3)
- `extension/background.js` — service worker (token management + relay)
- `extension/content.js` — content script (API client + captcha + retry)
- `extension/sidepanel.html` — side panel UI
- `extension/sidepanel.js` — side panel logic

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
