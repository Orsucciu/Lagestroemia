// content.js — Content script that runs inside the chat.z.ai tab.

// ---- Add a visible badge so the user can confirm the extension is loaded ----
(function addBadge() {
  // Remove any existing badge.
  var existing = document.getElementById('lagestroemia-badge');
  if (existing) existing.remove();

  var badge = document.createElement('div');
  badge.id = 'lagestroemia-badge';
  badge.innerHTML = '🌺 Lagestroemia Connected';
  badge.style.cssText = [
    'position:fixed',
    'bottom:12px',
    'right:12px',
    'z-index:9999999',
    'background:#7C4DFF',
    'color:white',
    'padding:6px 14px',
    'border-radius:20px',
    'font-family:-apple-system,BlinkMacSystemFont,"Segoe UI",Roboto,sans-serif',
    'font-size:12px',
    'font-weight:600',
    'box-shadow:0 2px 8px rgba(124,77,255,0.4)',
    'cursor:pointer',
    'transition:opacity 0.3s',
    'user-select:none',
  ].join(';');

  // Click to hide for 10 seconds.
  badge.onclick = function() {
    badge.style.opacity = '0.3';
    setTimeout(function() { badge.style.opacity = '1'; }, 10000);
  };

  // Wait for document.body to be available.
  if (document.body) {
    document.body.appendChild(badge);
  } else {
    document.addEventListener('DOMContentLoaded', function() {
      document.body.appendChild(badge);
    });
  }

  console.log('[content] 🌺 Lagestroemia badge added — extension is loaded and running');
})();

// ---- Native messaging status tracking ----
let nativeReady = false;

function updateBadge() {
  var badge = document.getElementById('lagestroemia-badge');
  if (badge) {
    badge.innerHTML = nativeReady
      ? '🌺 Lagestroemia — Server on :8081'
      : '🌺 Lagestroemia — No server (native host not registered)';
    badge.style.background = nativeReady ? '#27ae60' : '#e67e22';
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
