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

const NATIVE_HOST_NAME = 'lagestroemia';
let nativePort = null;
let nativeReady = false;
let keepAliveInterval = null;

function connectNative() {
  try {
    console.log('[bg] Attempting to connect to native host:', NATIVE_HOST_NAME);
    nativePort = api.runtime.connectNative(NATIVE_HOST_NAME);
    console.log('[bg] connectNative() returned:', nativePort);

    nativePort.onMessage.addListener((msg) => {
      console.log('[bg] Native message:', msg.type);

      if (msg.type === 'nativeReady') {
        nativeReady = true;
        console.log('[bg] Native host ready on port', msg.port);
        broadcastNativeStatus(true);
        startKeepAlive();
        return;
      }

      if (msg.type === 'sendChat') {
        const requestId = msg.requestId;
        const messages = msg.messages;
        const model = msg.model;
        const options = msg.options || {};

        api.tabs.query({ url: 'https://chat.z.ai/*' }, (tabs) => {
          if (tabs.length === 0) {
            sendToNative({ type: 'error', requestId, error: 'No chat.z.ai tab open.' });
            return;
          }
          api.tabs.sendMessage(tabs[0].id, {
            type: 'sendChat', requestId, messages, model, options,
          }, (response) => {
            if (api.runtime.lastError) {
              sendToNative({ type: 'error', requestId, error: api.runtime.lastError.message });
            }
          });
        });
      }
    });

    nativePort.onDisconnect.addListener(() => {
      const err = api.runtime.lastError;
      console.log('[bg] Native host DISCONNECTED:', err ? err.message : '(no error)');
      nativePort = null;
      nativeReady = false;
      stopKeepAlive();
      broadcastNativeStatus(false);
      setTimeout(connectNative, 3000);
    });

    console.log('[bg] Connected to native host, waiting for nativeReady...');
  } catch (e) {
    console.log('[bg] Failed to connect to native host:', e);
    broadcastNativeStatus(false);
    setTimeout(connectNative, 5000);
  }
}

// ---- Keep the service worker alive ----
// MV3 service workers are killed after 30s of inactivity. We send a
// ping every 25s to keep the port alive. The native host ignores it.
function startKeepAlive() {
  if (keepAliveInterval) clearInterval(keepAliveInterval);
  keepAliveInterval = setInterval(() => {
    if (nativePort) {
      try {
        nativePort.postMessage({ type: 'ping' });
        console.log('[bg] keepalive ping sent');
      } catch (e) {
        console.log('[bg] keepalive failed, reconnecting...');
        stopKeepAlive();
        connectNative();
      }
    }
  }, 25000);
}

function stopKeepAlive() {
  if (keepAliveInterval) {
    clearInterval(keepAliveInterval);
    keepAliveInterval = null;
  }
}

function broadcastNativeStatus(connected) {
  api.tabs.query({ url: 'https://chat.z.ai/*' }, (tabs) => {
    for (const tab of tabs) {
      api.tabs.sendMessage(tab.id, { type: 'nativeStatus', connected }).catch(() => {});
    }
  });
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

// Connect on startup.
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
