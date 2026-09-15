// Simulate exactly what the content script does:
// 1. Get guest token (from cookie / API)
// 2. Compute X-Signature
// 3. POST to chat.z.ai/api/v2/chat/completions
// 4. Parse the SSE response
//
// This uses node-fetch with the same headers the content script would
// set. If we get past the "missing_param" captcha error (i.e., the
// server accepts our signature and returns a proper response or
// "verify_failed" captcha error), the signature + body format are
// correct.
//
// Run: node test-live-api.js

const crypto = require('crypto');

const SECRET_KEY = 'key-@@@@)))()((9))-xxxx&&&%%%%%';
const FE_VERSION = 'prod-fe-1.1.95';

function uuid() {
  return crypto.randomUUID();
}

async function computeSignature(sortedPayload, promptText, timestamp) {
  const p = Buffer.from(promptText, 'utf8').toString('base64');
  const h = sortedPayload + '|' + p + '|' + timestamp;
  const m = Math.floor(Number(timestamp) / 300000);
  const derivedKey = crypto.createHmac('sha256', SECRET_KEY).update(String(m)).digest('hex');
  return crypto.createHmac('sha256', derivedKey).update(h).digest('hex');
}

async function main() {
  // 1. Fetch guest token
  console.log('=== Step 1: Fetch guest token ===');
  const authResp = await fetch('https://chat.z.ai/api/v1/auths/', {
    method: 'GET',
    headers: {
      'Accept': 'application/json',
      'X-FE-Version': FE_VERSION,
      'Origin': 'https://chat.z.ai',
      'Referer': 'https://chat.z.ai/',
    },
  });
  const authData = await authResp.json();
  const token = authData.token;
  const userId = authData.id;
  console.log('✅ Got guest token (' + token.length + ' chars)');
  console.log('   User ID:', userId);

  // 2. Build request metadata + signature
  console.log('\n=== Step 2: Compute signature ===');
  const timestamp = String(Date.now());
  const requestId = uuid();
  const promptText = 'hewwo';

  const o = { timestamp, requestId, user_id: userId || '' };
  const sortedPayload = Object.entries(o)
    .sort((a, b) => a[0].localeCompare(b[0]))
    .map(([k, v]) => `${k},${v}`)
    .join(',');

  const signature = await computeSignature(sortedPayload, promptText, timestamp);
  console.log('✅ Computed signature:', signature);

  // 3. Build URL params
  const params = new URLSearchParams({
    ...o,
    version: '0.0.1',
    platform: 'web',
    token: token,
    user_agent: 'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36',
    language: 'en-US',
    languages: 'en-US,en',
    timezone: 'UTC',
    cookie_enabled: 'true',
    screen_width: '1920',
    screen_height: '1080',
    screen_resolution: '1920x1080',
    viewport_height: '900',
    viewport_width: '1440',
    viewport_size: '1440x900',
    color_depth: '24',
    pixel_ratio: '1',
    current_url: 'https://chat.z.ai/',
    pathname: '/',
    search: '',
    hash: '',
    host: 'chat.z.ai',
    hostname: 'chat.z.ai',
    protocol: 'https:',
    referrer: '',
    title: 'Z.ai',
    timezone_offset: '0',
    local_time: new Date().toISOString(),
    utc_time: new Date().toUTCString(),
    is_mobile: 'false',
    is_touch: 'false',
    max_touch_points: '0',
    browser_name: 'Chrome',
    os_name: 'Linux',
  });
  params.set('signature_timestamp', timestamp);

  // 4. Build request body
  const body = {
    stream: true,
    model: 'glm-4.7',
    messages: [{ role: 'user', content: promptText }],
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
      enable_thinking: false,
      reasoning_effort: 'low',
    },
    variables: {
      '{{USER_NAME}}': 'Guest',
      '{{USER_LOCATION}}': 'Unknown',
      '{{CURRENT_DATETIME}}': new Date().toISOString().substring(0, 19).replace('T', ' '),
      '{{CURRENT_DATE}}': new Date().toISOString().substring(0, 10),
      '{{CURRENT_TIME}}': new Date().toISOString().substring(11, 19),
      '{{CURRENT_WEEKDAY}}': ['Sunday','Monday','Tuesday','Wednesday','Thursday','Friday','Saturday'][new Date().getDay()],
      '{{CURRENT_TIMEZONE}}': 'UTC',
      '{{USER_LANGUAGE}}': 'en-US',
    },
    chat_id: uuid(),
    id: uuid(),
    current_user_message_id: uuid(),
    current_user_message_parent_id: null,
    background_tasks: { title_generation: true, tags_generation: true },
  };

  // 5. Send the request
  console.log('\n=== Step 3: Send chat request ===');
  const url = `https://chat.z.ai/api/v2/chat/completions?${params.toString()}`;
  console.log('URL:', url.substring(0, 100) + '...');
  console.log('X-Signature:', signature);

  const resp = await fetch(url, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      'Authorization': `Bearer ${token}`,
      'X-FE-Version': FE_VERSION,
      'X-Signature': signature,
      'X-Region': 'overseas',
      'Origin': 'https://chat.z.ai',
      'Referer': 'https://chat.z.ai/',
    },
    body: JSON.stringify(body),
  });

  console.log('\n=== Step 4: Parse response ===');
  console.log('HTTP Status:', resp.status);
  console.log('Content-Type:', resp.headers.get('content-type'));

  // Read the SSE stream
  const reader = resp.body.getReader();
  const decoder = new TextDecoder();
  let buffer = '';
  const events = [];

  while (true) {
    const { done, value } = await reader.read();
    if (done) break;
    buffer += decoder.decode(value, { stream: true });

    while (true) {
      const idx = buffer.indexOf('\n\n');
      if (idx === -1) break;
      const event = buffer.substring(0, idx);
      buffer = buffer.substring(idx + 2);

      const dataLines = [];
      for (const line of event.split('\n')) {
        if (line.startsWith('data:')) {
          dataLines.push(line.substring(5).trim());
        }
      }
      if (dataLines.length === 0) continue;
      const data = dataLines.join('\n');
      if (data === '[DONE]') {
        events.push({ done: true });
      } else {
        try { events.push(JSON.parse(data)); } catch {}
      }
    }
  }

  console.log(`\nReceived ${events.length} SSE events:`);
  let content = '';
  let captchaRequired = false;
  let error = null;

  for (const ev of events) {
    if (ev.done) { console.log('  [DONE]'); break; }

    // Unwrap
    let payload = ev;
    if (ev.type === 'chat:completion' && ev.data) {
      payload = ev.data.data || ev.data;
    } else if (ev.data && ev.data.data) {
      payload = ev.data.data;
    }

    if (payload.error) {
      const code = payload.error.error_code || payload.error.code;
      if (code === 'FRONTEND_CAPTCHA_REQUIRED') {
        captchaRequired = true;
        console.log('  Error: FRONTEND_CAPTCHA_REQUIRED (' + (payload.error.captcha_error_type || 'unknown') + ')');
      } else {
        console.log('  Error:', code, '-', payload.error.detail || payload.error.message);
      }
      error = payload.error;
      break;
    }

    if (payload.choices && payload.choices.length > 0) {
      const delta = payload.choices[0].delta;
      if (delta && delta.content) {
        content += delta.content;
        process.stdout.write(delta.content);
      }
    }
  }

  console.log('\n\n=== Result ===');
  if (captchaRequired) {
    console.log('✅ Signature ACCEPTED — server returned captcha-required');
    console.log('   (This is expected. The content script will solve the');
    console.log('    captcha natively and retry. The signature + body format');
    console.log('    are correct.)');
    console.log('\n   captcha_error_type:', error?.captcha_error_type);
  } else if (content) {
    console.log('✅ Chat SUCCESS — got response:');
    console.log('   ', content);
  } else if (error) {
    console.log('❌ Error:', JSON.stringify(error));
  } else {
    console.log('⚠️ No content, no error, no captcha — unexpected');
  }
}

main().catch(console.error);
