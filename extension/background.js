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

// ---- Message relay ----

api.runtime.onMessage.addListener((message, sender, sendResponse) => {
  console.log('[bg] Message:', message.type);

  if (message.type === 'getGuestToken') {
    getGuestToken()
      .then((token) => sendResponse({ ok: true, token }))
      .catch((err) => sendResponse({ ok: false, error: err.message }));
    return true; // async response
  }

  if (message.type === 'sendChat') {
    // Forward the chat request to the content script (which runs in
    // the chat.z.ai tab and can solve captchas + has the right origin).
    api.tabs.query({ url: 'https://chat.z.ai/*' }, (tabs) => {
      if (tabs.length === 0) {
        sendResponse({ ok: false, error: 'No chat.z.ai tab open. Open https://chat.z.ai in a tab first.' });
        return;
      }
      // Use the first chat.z.ai tab.
      api.tabs.sendMessage(tabs[0].id, message, (response) => {
        if (api.runtime.lastError) {
          sendResponse({ ok: false, error: api.runtime.lastError.message });
        } else {
          sendResponse(response);
        }
      });
    });
    return true; // async response
  }

  if (message.type === 'solveCaptcha') {
    // Ask the content script to solve the captcha.
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
});
