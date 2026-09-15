// background.js — Service worker / background script for the Lagestroemia extension.
//
// Works in both Chrome/Edge (sidePanel API) and Firefox (sidebarAction API).
// Responsibilities:
//   1. Open the side panel when the toolbar icon is clicked
//   2. Relay messages between the side panel and the content script
//   3. Manage the guest token (fetch + cache)

const GUEST_TOKEN_URL = 'https://chat.z.ai/api/v1/auths/';
const TOKEN_CACHE_KEY = 'lagestroemia_guest_token';
const TOKEN_CACHE_TS_KEY = 'lagestroemia_guest_token_ts';
const TOKEN_TTL_MS = 30 * 60 * 1000; // 30 minutes

// Detect browser API differences.
// Chrome/Edge: chrome.sidePanel.open()
// Firefox: browser.sidebarAction.open() (or browser.sidebarAction.toggle())
const isFirefox = typeof browser !== 'undefined' && typeof browser.sidebarAction !== 'undefined';
const api = isFirefox ? browser : chrome;

// Open the side panel / sidebar on action click.
if (isFirefox) {
  // Firefox: sidebarAction.toggle() opens/closes the sidebar.
  browser.action.onClicked.addListener(() => {
    browser.sidebarAction.toggle().catch(() => {
      // If toggle isn't available, try open().
      browser.sidebarAction.open().catch(() => {});
    });
  });
} else {
  // Chrome/Edge: sidePanel.open() requires a tabId.
  chrome.action.onClicked.addListener((tab) => {
    chrome.sidePanel.open({ tabId: tab.id });
  });
  // Enable the side panel on chat.z.ai tabs.
  chrome.sidePanel.setPanelBehavior({ openPanelOnActionClick: true });
}

// ---- Guest token management ----

async function getGuestToken() {
  // Check cache first.
  const cached = await chrome.storage.local.get([TOKEN_CACHE_KEY, TOKEN_CACHE_TS_KEY]);
  const now = Date.now();
  if (cached[TOKEN_CACHE_KEY] && cached[TOKEN_CACHE_TS_KEY] &&
      (now - cached[TOKEN_CACHE_TS_KEY]) < TOKEN_TTL_MS) {
    console.log('[bg] Using cached guest token');
    return cached[TOKEN_CACHE_KEY];
  }

  // Fetch a new token.
  console.log('[bg] Fetching new guest token from', GUEST_TOKEN_URL);
  const resp = await fetch(GUEST_TOKEN_URL, {
    method: 'GET',
    headers: {
      'Accept': 'application/json',
      'X-FE-Version': 'prod-fe-1.1.95',
    },
    credentials: 'include',
  });
  if (!resp.ok) {
    throw new Error(`Guest token fetch failed: HTTP ${resp.status}`);
  }
  const data = await resp.json();
  const token = data.token;
  if (!token) throw new Error('No token in response');

  // Cache it.
  await chrome.storage.local.set({
    [TOKEN_CACHE_KEY]: token,
    [TOKEN_CACHE_TS_KEY]: now,
  });
  console.log('[bg] Guest token cached');
  return token;
}

// ---- Native Messaging (local HTTP server bridge) ----
//
// The native_host.py script runs a local HTTP server on localhost:8081
// that exposes an OpenAI-compatible API. External apps (opencode, curl)
// connect to it. The native script relays requests to us via Native
// Messaging (stdin/stdout), and we forward them to the content script.

const NATIVE_HOST_NAME = 'lagestroemia';
let nativePort = null;
let nativeReady = false;

function connectNative() {
  try {
    nativePort = api.runtime.connectNative(NATIVE_HOST_NAME);

    nativePort.onMessage.addListener((msg) => {
      console.log('[bg] Native message:', msg.type);

      if (msg.type === 'nativeReady') {
        nativeReady = true;
        console.log('[bg] Native host ready on port', msg.port);
        return;
      }

      if (msg.type === 'sendChat') {
        // A request from the local HTTP server. Forward to the content script.
        const requestId = msg.requestId;
        const messages = msg.messages;
        const model = msg.model;
        const stream = msg.stream !== false;
        const options = msg.options || {};

        // Find the chat.z.ai tab.
        api.tabs.query({ url: 'https://chat.z.ai/*' }, (tabs) => {
          if (tabs.length === 0) {
            // No chat.z.ai tab — send error back.
            sendToNative({
              type: 'error',
              requestId: requestId,
              error: 'No chat.z.ai tab open. Open https://chat.z.ai in a tab first.',
            });
            return;
          }

          // Forward to the content script.
          api.tabs.sendMessage(tabs[0].id, {
            type: 'sendChat',
            requestId: requestId,
            messages: messages,
            model: model,
            options: options,
          }, (response) => {
            if (api.runtime.lastError) {
              sendToNative({
                type: 'error',
                requestId: requestId,
                error: api.runtime.lastError.message,
              });
            }
            // The content script will send streaming chunks via
            // chrome.runtime.sendMessage — we relay those to the native host.
          });
        });
      }
    });

    nativePort.onDisconnect.addListener(() => {
      console.log('[bg] Native host disconnected');
      nativePort = null;
      nativeReady = false;
      // Try to reconnect after 5 seconds.
      setTimeout(connectNative, 5000);
    });

    console.log('[bg] Connected to native host');
  } catch (e) {
    console.log('[bg] Failed to connect to native host:', e);
    // Retry after 10 seconds.
    setTimeout(connectNative, 10000);
  }
}

function sendToNative(msg) {
  if (nativePort) {
    try {
      nativePort.postMessage(msg);
    } catch (e) {
      console.log('[bg] Failed to send to native:', e);
    }
  }
}

// Connect to the native host on startup.
connectNative();

// ---- Message relay (side panel + content script + native host) ----

api.runtime.onMessage.addListener((message, sender, sendResponse) => {
  console.log('[bg] Message:', message.type);

  if (message.type === 'getGuestToken') {
    getGuestToken()
      .then((token) => sendResponse({ ok: true, token }))
      .catch((err) => sendResponse({ ok: false, error: err.message }));
    return true;
  }

  if (message.type === 'sendChat') {
    // From the side panel — forward to content script.
    api.tabs.query({ url: 'https://chat.z.ai/*' }, (tabs) => {
      if (tabs.length === 0) {
        sendResponse({ ok: false, error: 'No chat.z.ai tab open. Open https://chat.z.ai in a tab first.' });
        return;
      }
      api.tabs.sendMessage(tabs[0].id, message, (response) => {
        if (api.runtime.lastError) {
          sendResponse({ ok: false, error: api.runtime.lastError.message });
        } else {
          sendResponse(response);
        }
      });
    });
    return true;
  }

  if (message.type === 'solveCaptcha') {
    api.tabs.query({ url: 'https://chat.z.ai/*' }, (tabs) => {
      if (tabs.length === 0) {
        sendResponse({ ok: false, error: 'No chat.z.ai tab open' });
        return;
      }
      api.tabs.sendMessage(tabs[0].id, message, (response) => {
        if (api.runtime.lastError) {
          sendResponse({ ok: false, error: api.runtime.lastError.message });
        } else {
          sendResponse(response);
        }
      });
    });
    return true;
  }

  // ---- Streaming messages from the content script ----
  // When the content script sends chatChunk/chatStatus/streamEnd,
  // relay them to BOTH the side panel AND the native host (for
  // external apps connected via the local HTTP server).

  if (message.type === 'chatChunk') {
    // Forward to side panel (sidepanel.js listens for this).
    // Also forward to native host if a requestId is present.
    if (message.requestId) {
      sendToNative({
        type: 'streamChunk',
        requestId: message.requestId,
        chunk: message.chunk,
      });
    }
    // Don't send a response — this is a fire-and-forget relay.
    return false;
  }

  if (message.type === 'chatStatus') {
    if (message.requestId) {
      sendToNative({
        type: 'streamChunk',
        requestId: message.requestId,
        chunk: { content: '', status: message.status },
      });
    }
    return false;
  }

  if (message.type === 'chatComplete') {
    if (message.requestId) {
      sendToNative({
        type: 'streamEnd',
        requestId: message.requestId,
      });
    }
    return false;
  }

  if (message.type === 'chatError') {
    if (message.requestId) {
      sendToNative({
        type: 'error',
        requestId: message.requestId,
        error: message.error,
      });
    }
    return false;
  }
});
