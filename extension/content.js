// content.js — Content script that runs inside the chat.z.ai tab.

// ---- Add a visible badge + control panel ----
(function addControlPanel() {
  // Remove existing.
  var existing = document.getElementById('lagestroemia-panel');
  if (existing) existing.remove();

  // Create the panel container.
  var panel = document.createElement('div');
  panel.id = 'lagestroemia-panel';
  panel.style.cssText = [
    'position:fixed',
    'bottom:12px',
    'right:12px',
    'z-index:9999999',
    'background:#1a1a2e',
    'color:white',
    'padding:0',
    'border-radius:12px',
    'font-family:-apple-system,BlinkMacSystemFont,"Segoe UI",Roboto,sans-serif',
    'font-size:12px',
    'box-shadow:0 4px 20px rgba(0,0,0,0.5)',
    'width:340px',
    'max-height:500px',
    'overflow-y:auto',
    'user-select:none',
  ].join(';');

  // Header.
  var header = document.createElement('div');
  header.style.cssText = 'background:#7C4DFF;padding:8px 12px;border-radius:12px 12px 0 0;font-weight:600;display:flex;align-items:center;gap:8px;cursor:pointer;';
  header.innerHTML = '<span>🌺 Lagestroemia <span id="lz-version" style="font-size:10px;opacity:0.7">v0.4.0</span></span><span id="lz-status-dot" style="margin-left:auto;width:8px;height:8px;border-radius:50%;background:#e74c3c;"></span>';
  panel.appendChild(header);

  // Body.
  var body = document.createElement('div');
  body.id = 'lz-panel-body';
  body.style.cssText = 'padding:12px;display:flex;flex-direction:column;gap:8px;';
  panel.appendChild(body);

  // Status line.
  var statusLine = document.createElement('div');
  statusLine.id = 'lz-status-line';
  statusLine.style.cssText = 'color:#888;font-size:11px;';
  statusLine.textContent = 'Checking...';
  body.appendChild(statusLine);

  // Divider.
  body.appendChild(makeDivider());

  // Section: Chats
  body.appendChild(makeLabel('📋 Chats'));
  var chatList = document.createElement('div');
  chatList.id = 'lz-chat-list';
  chatList.style.cssText = 'color:#aaa;font-size:11px;max-height:150px;overflow-y:auto;';
  chatList.textContent = 'Not loaded yet';
  body.appendChild(chatList);

  // Buttons row.
  var btnRow1 = document.createElement('div');
  btnRow1.style.cssText = 'display:flex;gap:6px;';
  btnRow1.appendChild(makeButton('Refresh chats', '#3498db', function() {
    log('[content] Refresh chats button clicked');
    refreshChatList();
  }));
  btnRow1.appendChild(makeButton('Open new chat', '#27ae60', function() {
    log('[content] Open new chat button clicked');
    openNewChat();
  }));
  body.appendChild(btnRow1);

  body.appendChild(makeDivider());

  // Section: Current chat
  body.appendChild(makeLabel('💬 Current chat'));
  var currentChatInfo = document.createElement('div');
  currentChatInfo.id = 'lz-current-chat';
  currentChatInfo.style.cssText = 'color:#aaa;font-size:11px;';
  currentChatInfo.textContent = 'No chat selected';
  body.appendChild(currentChatInfo);

  body.appendChild(makeButton('Read current chat', '#e67e22', function() {
    log('[content] Read current chat button clicked');
    readCurrentChat();
  }));

  body.appendChild(makeDivider());

  // Section: Test
  body.appendChild(makeLabel('🧪 Test'));
  body.appendChild(makeButton('Send test message', '#9b59b6', function() {
    log('[content] Test send button clicked');
    sendTestMessage();
  }));

  body.appendChild(makeDivider());

  // Log
  body.appendChild(makeLabel('📜 Log'));
  var logBox = document.createElement('div');
  logBox.id = 'lz-log';
  logBox.style.cssText = 'background:#0d0d1a;color:#0f0;font-family:monospace;font-size:10px;padding:6px;border-radius:4px;max-height:120px;overflow-y:auto;line-height:1.4;';
  logBox.textContent = 'Ready.';
  body.appendChild(logBox);

  // Toggle body on header click.
  var expanded = true;
  header.onclick = function() {
    body.style.display = expanded ? 'none' : 'flex';
    expanded = !expanded;
  };

  // Wait for body.
  if (document.body) {
    document.body.appendChild(panel);
  } else {
    document.addEventListener('DOMContentLoaded', function() {
      document.body.appendChild(panel);
    });
  }

  console.log('[content] 🌺 Lagestroemia control panel added');

  // ---- Helper functions for the panel ----

  function makeDivider() {
    var d = document.createElement('hr');
    d.style.cssText = 'border:none;border-top:1px solid #333;margin:4px 0;';
    return d;
  }

  function makeLabel(text) {
    var l = document.createElement('div');
    l.style.cssText = 'font-weight:600;font-size:11px;color:#ccc;';
    l.textContent = text;
    return l;
  }

  function makeButton(text, color, onClick) {
    var b = document.createElement('button');
    b.textContent = text;
    b.style.cssText = 'flex:1;padding:6px 8px;border:none;border-radius:6px;background:' + color + ';color:white;font-size:11px;cursor:pointer;font-family:inherit;';
    b.onmouseover = function() { b.style.opacity = '0.85'; };
    b.onmouseout = function() { b.style.opacity = '1'; };
    b.onclick = onClick;
    return b;
  }

  window.lzLog = function(msg) {
    var box = document.getElementById('lz-log');
    if (!box) return;
    var time = new Date().toLocaleTimeString();
    var line = document.createElement('div');
    line.textContent = time + ' ' + msg;
    box.appendChild(line);
    box.scrollTop = box.scrollHeight;
    while (box.children.length > 50) box.removeChild(box.firstChild);
  };

  function log(msg) {
    console.log(msg);
    window.lzLog(msg.replace('[content] ', ''));
  }

  // ---- Chat list: read from chat.z.ai's DOM ----
  window.lzRefreshChatList = function refreshChatList() {
    log('[content] Refreshing chat list...');
    var chatListEl = document.getElementById('lz-chat-list');
    if (chatListEl) chatListEl.innerHTML = '<div style="color:#888">Loading...</div>';

    // Try to read the chat list from chat.z.ai's sidebar.
    // chat.z.ai uses React with a sidebar that contains chat links.
    var chats = [];

    // Method 1: look for anchor tags with /c/ in the href (chat URLs).
    var links = document.querySelectorAll('a[href*="/c/"]');
    log('[content] Found ' + links.length + ' chat links');
    for (var i = 0; i < links.length; i++) {
      var href = links[i].getAttribute('href') || '';
      var title = links[i].textContent.trim().substring(0, 50);
      var chatId = href.split('/c/')[1];
      if (chatId && title) {
        chats.push({ id: chatId, title: title, url: href });
      }
    }

    // Method 2: look for elements with chat-like content.
    if (chats.length === 0) {
      var items = document.querySelectorAll('[class*="chat"], [class*="conversation"], [class*="history"]');
      log('[content] Found ' + items.length + ' chat-like elements');
    }

    // Display.
    if (chatListEl) {
      if (chats.length === 0) {
        chatListEl.innerHTML = '<div style="color:#888">No chats found in DOM. The sidebar may be collapsed.</div>';
      } else {
        chatListEl.innerHTML = '';
        for (var j = 0; j < chats.length; j++) {
          var div = document.createElement('div');
          div.style.cssText = 'padding:4px 0;border-bottom:1px solid #222;';
          div.innerHTML = '<div style="color:#fff">' + escapeHtml(chats[j].title) + '</div>' +
                          '<div style="color:#666;font-size:10px">ID: ' + chats[j].id.substring(0, 12) + '...</div>';
          chatListEl.appendChild(div);
        }
      }
    }
    log('[content] Chat list: ' + chats.length + ' chats found');
  };

  // ---- Open new chat ----
  window.lzOpenNewChat = function openNewChat() {
    log('[content] Opening new chat...');
    // Navigate to chat.z.ai's root (creates a new chat).
    window.location.href = 'https://chat.z.ai/';
    log('[content] Navigated to new chat');
  };

  // ---- Read current chat ----
  window.lzReadCurrentChat = function readCurrentChat() {
    log('[content] Reading current chat...');
    var infoEl = document.getElementById('lz-current-chat');
    if (infoEl) infoEl.innerHTML = '<div style="color:#888">Reading...</div>';

    // Get the current URL to extract the chat ID.
    var url = window.location.href;
    var chatId = '';
    var match = url.match(/\/c\/([a-f0-9-]+)/);
    if (match) chatId = match[1];

    // Try to read messages from the DOM.
    var messages = [];
    var msgElements = document.querySelectorAll('[class*="message"], [class*="chat-content"], [class*="prose"]');
    log('[content] Found ' + msgElements.length + ' message-like elements');

    // Try to read the page title.
    var title = document.title || 'Unknown';

    // Try to find the model selector value.
    var model = 'Unknown';
    var modelSelect = document.querySelector('select, [class*="model"], [class*="ModelSelect"]');
    if (modelSelect) {
      model = modelSelect.textContent || modelSelect.value || 'Unknown';
    }

    var info = 'URL: ' + url + '\n' +
               'Chat ID: ' + (chatId || 'none') + '\n' +
               'Title: ' + title + '\n' +
               'Model: ' + model + '\n' +
               'Message elements: ' + msgElements.length;
    log('[content] Current chat info:\n' + info);

    if (infoEl) {
      infoEl.innerHTML = '<pre style="white-space:pre-wrap;color:#ccc;">' + escapeHtml(info) + '</pre>';
    }
  };

  // ---- Send test message ----
  window.lzSendTestMessage = function sendTestMessage() {
    log('[content] Sending test message via background...');
    chrome.runtime.sendMessage({
      type: 'sendChat',
      messages: [{ role: 'user', content: 'Hello! This is a test from Lagestroemia.' }],
      model: 'glm-4.7',
      options: {},
    }, function(response) {
      if (chrome.runtime.lastError) {
        log('[content] ❌ Error: ' + chrome.runtime.lastError.message);
      } else if (response && response.ok) {
        var content = response.chunks.map(function(c) { return c.content || ''; }).join('');
        log('[content] ✅ Response: ' + content.substring(0, 100));
      } else {
        log('[content] ❌ ' + (response ? response.error : 'No response'));
      }
    });
  };

  function escapeHtml(text) {
    var div = document.createElement('div');
    div.textContent = text;
    return div.innerHTML;
  }

  // Auto-refresh on load.
  setTimeout(function() {
    window.lzRefreshChatList();
    window.lzReadCurrentChat();
  }, 2000);
})();

// ---- Native messaging status tracking ----
let nativeReady = false;

function updateBadge() {
  var dot = document.getElementById('lz-status-dot');
  var line = document.getElementById('lz-status-line');
  if (dot) {
    dot.style.background = nativeReady ? '#27ae60' : '#e74c3c';
  }
  if (line) {
    line.textContent = nativeReady ? 'Server on :8081 — connected' : 'No server — native host not connected';
  }
}

// ---- Constants ----

const SECRET_KEY = 'key-@@@@)))()((9))-xxxx&&&%%%%%';
const CHAT_COMPLETIONS_URL = 'https://chat.z.ai/api/v2/chat/completions';
const MODELS_URL = 'https://chat.z.ai/api/models';
const FE_VERSION = 'prod-fe-1.1.95';

// ---- Utility: UUID v4 ----
function uuid() {
  return crypto.randomUUID();
}

// ---- Signature computation (ported from chat.z.ai's JS bundle) ----
async function computeSignature(sortedPayload, promptText, timestamp) {
  // 1. base64-encode the UTF-8 bytes of the prompt.
  const encoder = new TextEncoder();
  const promptBytes = encoder.encode(promptText);
  const p = btoa(String.fromCharCode(...promptBytes));

  // 2. canonical string: sortedPayload | base64(prompt) | timestamp
  const h = sortedPayload + '|' + p + '|' + timestamp;

  // 3. 5-minute time window index
  const m = Math.floor(Number(timestamp) / 300000);

  // 4. derived key = HMAC_SHA256(SECRET_KEY, str(m))
  const keyBytes = encoder.encode(SECRET_KEY);
  const cryptoKey = await crypto.subtle.importKey(
    'raw', keyBytes, { name: 'HMAC', hash: 'SHA-256' }, false, ['sign']
  );
  const derivedBuf = await crypto.subtle.sign('HMAC', cryptoKey, encoder.encode(String(m)));
  const derivedKey = Array.from(new Uint8Array(derivedBuf))
    .map(b => b.toString(16).padStart(2, '0')).join('');

  // 5. signature = HMAC_SHA256(derivedKey, canonicalString)
  const sigKey = encoder.encode(derivedKey);
  const sigCryptoKey = await crypto.subtle.importKey(
    'raw', sigKey, { name: 'HMAC', hash: 'SHA-256' }, false, ['sign']
  );
  const sigBuf = await crypto.subtle.sign('HMAC', sigCryptoKey, encoder.encode(h));
  return Array.from(new Uint8Array(sigBuf))
    .map(b => b.toString(16).padStart(2, '0')).join('');
}

// ---- Build request metadata (sortedPayload + URL params) ----
function buildRequestMeta(userId, token) {
  const timestamp = String(Date.now());
  const requestId = uuid();
  const o = { timestamp, requestId, user_id: userId || '' };

  // sortedPayload: entries sorted by key, joined by ","
  const sortedPayload = Object.entries(o)
    .sort((a, b) => a[0].localeCompare(b[0]))
    .map(([k, v]) => `${k},${v}`)
    .join(',');

  // URL params (browser fingerprint — values can be faked)
  const params = new URLSearchParams({
    ...o,
    version: '0.0.1',
    platform: 'web',
    token: token || '',
    user_agent: navigator.userAgent,
    language: navigator.language || 'en-US',
    languages: (navigator.languages || ['en-US']).join(','),
    timezone: Intl.DateTimeFormat().resolvedOptions().timeZone || 'UTC',
    cookie_enabled: String(navigator.cookieEnabled),
    screen_width: String(screen.width),
    screen_height: String(screen.height),
    screen_resolution: `${screen.width}x${screen.height}`,
    viewport_height: String(window.innerHeight),
    viewport_width: String(window.innerWidth),
    viewport_size: `${window.innerWidth}x${window.innerHeight}`,
    color_depth: String(screen.colorDepth),
    pixel_ratio: String(window.devicePixelRatio),
    current_url: window.location.href,
    pathname: window.location.pathname,
    search: window.location.search,
    hash: window.location.hash,
    host: window.location.host,
    hostname: window.location.hostname,
    protocol: window.location.protocol,
    referrer: document.referrer,
    title: document.title,
    timezone_offset: String(new Date().getTimezoneOffset()),
    local_time: new Date().toISOString(),
    utc_time: new Date().toUTCString(),
    is_mobile: 'false',
    is_touch: String('ontouchstart' in window),
    max_touch_points: String(navigator.maxTouchPoints || 0),
    browser_name: 'Chrome',
    os_name: 'Unknown',
  });

  return { timestamp, requestId, sortedPayload, params };
}

// ---- Extract the guest token ----
// Tries cookie first, falls back to fetching from the API.
let cachedToken = null;
let cachedTokenTime = 0;

async function getGuestToken() {
  // Check cache (valid for 30 minutes).
  if (cachedToken && (Date.now() - cachedTokenTime) < 30 * 60 * 1000) {
    return cachedToken;
  }

  // Try cookie first (fastest).
  try {
    const match = document.cookie.match(/(?:^|;\s*)token=([^;]+)/);
    if (match && match[1]) {
      cachedToken = match[1];
      cachedTokenTime = Date.now();
      console.log('[content] Got token from cookie');
      return cachedToken;
    }
  } catch (e) {
    console.log('[content] Cookie access failed:', e);
  }

  // Fallback: fetch from the API (same-origin, no CORS issues).
  console.log('[content] No cookie token, fetching from API...');
  const resp = await fetch('https://chat.z.ai/api/v1/auths/', {
    method: 'GET',
    headers: {
      'Accept': 'application/json',
      'X-FE-Version': FE_VERSION,
    },
    credentials: 'include',
  });
  if (!resp.ok) {
    throw new Error(`Guest token fetch failed: HTTP ${resp.status}`);
  }
  const data = await resp.json();
  if (!data.token) {
    throw new Error('No token in API response');
  }
  cachedToken = data.token;
  cachedTokenTime = Date.now();
  console.log('[content] Got token from API');
  return cachedToken;
}

// ---- Extract user ID from JWT ----
function getUserIdFromToken(token) {
  try {
    const payload = JSON.parse(atob(token.split('.')[1]));
    return payload.id || '';
  } catch {
    return '';
  }
}

// ---- Send a chat completion request (with auto-retry) ----
async function sendChatCompletion(messages, model, options = {}) {
  const token = await getGuestToken();
  if (!token) {
    throw new Error('Could not get guest token. Make sure you are signed in on chat.z.ai.');
  }
  const userId = getUserIdFromToken(token);
  const promptText = extractPromptText(messages);

  // Build request metadata + signature.
  const meta = buildRequestMeta(userId, token);
  const signature = await computeSignature(meta.sortedPayload, promptText, meta.timestamp);
  meta.params.set('signature_timestamp', meta.timestamp);

  // Build the request body (matching chat.z.ai's format).
  const body = {
    stream: true,
    model: model || 'glm-4.7',
    messages: messages,
    signature_prompt: promptText,
    params: {},
    extra: {},
    features: {
      image_generation: false,
      web_search: false,
      auto_web_search: false,
      preview_mode: true,
      flags: [],
      vlm_tools_enable: false,
      vlm_web_search_enable: false,
      vlm_website_mode: false,
      enable_thinking: options.thinking || false,
      reasoning_effort: options.thinking ? 'max' : 'low',
    },
    variables: {
      '{{USER_NAME}}': 'Guest',
      '{{USER_LOCATION}}': 'Unknown',
      '{{CURRENT_DATETIME}}': new Date().toISOString().substring(0, 19).replace('T', ' '),
      '{{CURRENT_DATE}}': new Date().toISOString().substring(0, 10),
      '{{CURRENT_TIME}}': new Date().toISOString().substring(11, 19),
      '{{CURRENT_WEEKDAY}}:': ['Sunday','Monday','Tuesday','Wednesday','Thursday','Friday','Saturday'][new Date().getDay()],
      '{{CURRENT_TIMEZONE}}': Intl.DateTimeFormat().resolvedOptions().timeZone || 'UTC',
      '{{USER_LANGUAGE}}': navigator.language || 'en-US',
    },
    chat_id: options.chatId || uuid(),
    id: uuid(),
    current_user_message_id: uuid(),
    current_user_message_parent_id: null,
    background_tasks: { title_generation: true, tags_generation: true },
  };

  // If we have a captcha param, include it.
  if (options.captchaVerifyParam) {
    body.captcha_verify_param = options.captchaVerifyParam;
  }

  const url = `${CHAT_COMPLETIONS_URL}?${meta.params.toString()}`;
  console.log('[content] Sending chat request to', url);

  const resp = await fetch(url, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      'Authorization': `Bearer ${token}`,
      'X-FE-Version': FE_VERSION,
      'X-Signature': signature,
      'X-Region': 'overseas',
    },
    body: JSON.stringify(body),
    credentials: 'include',
  });

  if (!resp.ok) {
    const text = await resp.text();
    throw new Error(`HTTP ${resp.status}: ${text}`);
  }

  return resp;
}

// ---- Extract prompt text from messages ----
function extractPromptText(messages) {
  for (let i = messages.length - 1; i >= 0; i--) {
    if (messages[i].role === 'user') {
      const c = messages[i].content;
      if (typeof c === 'string') return c;
      if (Array.isArray(c)) {
        for (const part of c) {
          if (part.type === 'text') return part.text || '';
        }
      }
      return '';
    }
  }
  return '';
}

// ---- Parse SSE stream ----
async function* parseSSE(resp) {
  const reader = resp.body.getReader();
  const decoder = new TextDecoder();
  let buffer = '';

  while (true) {
    const { done, value } = await reader.read();
    if (done) break;
    buffer += decoder.decode(value, { stream: true });

    // Split on double newlines (SSE event boundaries).
    while (true) {
      const idx = buffer.indexOf('\n\n');
      if (idx === -1) break;
      const event = buffer.substring(0, idx);
      buffer = buffer.substring(idx + 2);

      // Parse data: lines.
      const dataLines = [];
      for (const line of event.split('\n')) {
        if (line.startsWith('data:')) {
          dataLines.push(line.substring(5).trim());
        }
      }
      if (dataLines.length === 0) continue;
      const data = dataLines.join('\n');
      if (data === '[DONE]') return;
      yield JSON.parse(data);
    }
  }
}

// ---- Solve captcha using chat.z.ai's own SDK ----
async function solveCaptcha() {
  return new Promise((resolve, reject) => {
    // Check if the Aliyun captcha SDK is loaded.
    if (!window.initAliyunCaptcha) {
      // Load it ourselves.
      const s = document.createElement('script');
      s.src = 'https://o.alicdn.com/captcha-frontend/aliyunCaptcha/AliyunCaptcha.js';
      s.onload = () => doInitCaptcha(resolve, reject);
      s.onerror = () => reject(new Error('Failed to load captcha SDK'));
      document.head.appendChild(s);
    } else {
      doInitCaptcha(resolve, reject);
    }
  });
}

function doInitCaptcha(resolve, reject) {
  if (!window.initAliyunCaptcha) {
    reject(new Error('initAliyunCaptcha not found'));
    return;
  }

  // Create a container for the captcha.
  let container = document.getElementById('lz-captcha-overlay');
  if (!container) {
    container = document.createElement('div');
    container.id = 'lz-captcha-overlay';
    container.style.cssText = 'position:fixed;top:0;left:0;width:100%;height:100%;background:rgba(0,0,0,0.5);z-index:999999;display:flex;align-items:center;justify-content:center;';
    const inner = document.createElement('div');
    inner.style.cssText = 'background:white;padding:24px;border-radius:12px;max-width:400px;';
    const title = document.createElement('div');
    title.textContent = 'Solve the captcha to continue';
    title.style.cssText = 'font-size:16px;font-weight:600;margin-bottom:16px;color:#333;';
    inner.appendChild(title);
    const captchaEl = document.createElement('div');
    captchaEl.id = 'lz-captcha-element';
    captchaEl.style.cssText = 'min-height:200px;';
    inner.appendChild(captchaEl);
    const btn = document.createElement('button');
    btn.id = 'lz-captcha-button';
    btn.style.cssText = 'position:absolute;left:-9999px;';
    inner.appendChild(btn);
    container.appendChild(inner);
    document.body.appendChild(container);
  }

  window.initAliyunCaptcha({
    SceneId: 'didk33e0',
    mode: 'embed',
    element: '#lz-captcha-element',
    button: '#lz-captcha-button',
    prefix: 'no8xfe',
    region: 'sgp',
    language: 'en',
    timeout: 60000,
    delayBeforeSuccess: false,
    success: function(v) {
      const param = (typeof v === 'string') ? v : JSON.stringify(v);
      // Remove the overlay.
      const overlay = document.getElementById('lz-captcha-overlay');
      if (overlay) overlay.remove();
      resolve(param || '');
    },
    fail: function(e) {
      const overlay = document.getElementById('lz-captcha-overlay');
      if (overlay) overlay.remove();
      reject(new Error(String(e || 'captcha fail')));
    },
    onError: function(e) {
      const overlay = document.getElementById('lz-captcha-overlay');
      if (overlay) overlay.remove();
      reject(new Error(String(e || 'captcha error')));
    }
  });
}

// ---- Auto-retry wrapper ----
const MAX_RETRIES = 5;
const RETRYABLE_ERRORS = ['server overload', 'rate limit', 'network', '502', '503', '504'];

async function sendChatWithRetry(messages, model, options, onChunk, onStatus) {
  let captchaParam = options.captchaVerifyParam || null;
  let lastError = null;

  for (let attempt = 0; attempt <= MAX_RETRIES; attempt++) {
    try {
      if (onStatus) onStatus(attempt === 0 ? 'Sending…' : `Retry ${attempt}/${MAX_RETRIES}…`);

      const opts = { ...options };
      if (captchaParam) {
        opts.captchaVerifyParam = captchaParam;
      }

      const resp = await sendChatCompletion(messages, model, opts);

      // Check for inline SSE error.
      let streamError = null;
      let captchaRequired = false;

      for await (const chunk of parseSSE(resp)) {
        // Unwrap chat.z.ai's envelope. Error events have a different
        // structure: {data: {data: {done:true, error:{}}}} (no type field).
        // Content events have: {type:"chat:completion", data:{data:{choices:[]}}}
        let payload = chunk;
        if (chunk.type === 'chat:completion' && chunk.data) {
          if (chunk.data.data) {
            payload = chunk.data.data;
          } else {
            payload = chunk.data;
          }
        } else if (chunk.data && chunk.data.data) {
          // Error event: {data: {data: {done:true, error:{}}}}
          payload = chunk.data.data;
        }

        // Check for error FIRST (before extracting content).
        if (payload.error) {
          const err = payload.error;
          const errorCode = err.error_code || err.code;
          if (errorCode === 'FRONTEND_CAPTCHA_REQUIRED') {
            captchaRequired = true;
            streamError = new Error('Captcha required');
            break;
          }
          streamError = new Error(err.detail || err.message || 'Unknown error');
          break;
        }

        // Skip done-only events (no choices, no error).
        if (payload.done && !payload.choices) continue;

        // Extract content delta.
        if (payload.choices && payload.choices.length > 0) {
          const delta = payload.choices[0].delta;
          if (delta) {
            if (onChunk) onChunk({
              content: delta.content || '',
              reasoning: delta.reasoning_content || '',
            });
          }
        }
      }

      if (captchaRequired) {
        if (onStatus) onStatus('Captcha required — solving…');
        captchaParam = await solveCaptcha();
        if (onStatus) onStatus('Captcha solved — retrying…');
        continue; // retry with the captcha param
      }

      if (streamError) {
        // Check if retryable.
        const msg = streamError.message.toLowerCase();
        const isRetryable = RETRYABLE_ERRORS.some(e => msg.includes(e));
        if (isRetryable && attempt < MAX_RETRIES) {
          const delay = Math.pow(2, attempt) * 1000; // 1s, 2s, 4s, 8s, 16s
          if (onStatus) onStatus(`Server error — retrying in ${delay/1000}s…`);
          await new Promise(r => setTimeout(r, delay));
          continue;
        }
        throw streamError;
      }

      // Success!
      if (onStatus) onStatus('Done');
      return { ok: true };

    } catch (err) {
      lastError = err;
      const msg = err.message.toLowerCase();
      const isRetryable = RETRYABLE_ERRORS.some(e => msg.includes(e)) ||
                         msg.includes('fetch') || msg.includes('network');
      if (isRetryable && attempt < MAX_RETRIES) {
        const delay = Math.pow(2, attempt) * 1000;
        if (onStatus) onStatus(`Error — retrying in ${delay/1000}s…`);
        await new Promise(r => setTimeout(r, delay));
        continue;
      }
      throw err;
    }
  }

  throw lastError || new Error('Max retries exceeded');
}

// ---- Message handler ----
chrome.runtime.onMessage.addListener((message, sender, sendResponse) => {
  console.log('[content] Message:', message.type);

  // Handle native host status updates.
  if (message.type === 'nativeStatus') {
    nativeReady = message.connected;
    console.log('[content] Native host:', message.connected ? 'CONNECTED' : 'DISCONNECTED');
    updateBadge();
    return false;
  }

  if (message.type === 'sendChat') {
    // Flash the badge to show we received the message.
    var badge = document.getElementById('lagestroemia-badge');
    if (badge) {
      badge.style.transform = 'scale(1.3)';
      badge.style.background = '#e74c3c';
      badge.innerHTML = '🌺 Sending...';
      setTimeout(function() {
        badge.style.transform = '';
        updateBadge();
      }, 2000);
    }
    console.log('[content] sendChat received! requestId:', message.requestId, 'model:', message.model);

    const { messages, model, options, requestId } = message;
    const chunks = [];

    sendChatWithRetry(
      messages, model, options || {},
      // onChunk — collect chunks AND forward to side panel + native host.
      (chunk) => {
        chunks.push(chunk);
        // Forward to the side panel for live streaming + native host.
        chrome.runtime.sendMessage({
          type: 'chatChunk',
          requestId: requestId,
          chunk: chunk,
        }).catch(() => {});
      },
      // onStatus
      (status) => {
        chrome.runtime.sendMessage({
          type: 'chatStatus',
          requestId: requestId,
          status: status,
        }).catch(() => {});
      }
    ).then((result) => {
      // Stream complete — notify the background script.
      chrome.runtime.sendMessage({
        type: 'chatComplete',
        requestId: requestId,
      }).catch(() => {});
      sendResponse({ ok: true, chunks: chunks });
    }).catch((err) => {
      chrome.runtime.sendMessage({
        type: 'chatError',
        requestId: requestId,
        error: err.message,
      }).catch(() => {});
      sendResponse({ ok: false, error: err.message });
    });
    return true; // async response
  }

  if (message.type === 'solveCaptcha') {
    solveCaptcha()
      .then((param) => sendResponse({ ok: true, captchaVerifyParam: param }))
      .catch((err) => sendResponse({ ok: false, error: err.message }));
    return true;
  }

  if (message.type === 'getModels') {
    getGuestToken().then(token =>
      fetch(MODELS_URL, {
        headers: {
          'Authorization': `Bearer ${token}`,
          'X-FE-Version': FE_VERSION,
        },
        credentials: 'include',
      })
    )
      .then(r => r.json())
      .then(data => sendResponse({ ok: true, models: data.data || [] }))
      .catch(err => sendResponse({ ok: false, error: err.message }));
    return true;
  }
});
