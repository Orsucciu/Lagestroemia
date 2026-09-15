// Test the extension's SSE parsing + auto-retry logic.
// Run with: node test-retry.js

// Simulate the SSE parsing from content.js
function parseSSEStream(text) {
  const events = [];
  let buffer = '';
  const lines = text.split('\n');

  for (const line of lines) {
    buffer += line + '\n';
    if (line === '') {
      // End of event.
      const dataLines = [];
      for (const l of buffer.split('\n')) {
        if (l.startsWith('data:')) {
          dataLines.push(l.substring(5).trim());
        }
      }
      if (dataLines.length > 0) {
        const data = dataLines.join('\n');
        if (data === '[DONE]') {
          events.push({ done: true });
        } else {
          try {
            events.push(JSON.parse(data));
          } catch {
            // skip invalid JSON
          }
        }
      }
      buffer = '';
    }
  }
  return events;
}

// Test SSE parsing.
function testSSEParsing() {
  const sseData = [
    'data: {"type":"chat:completion","data":{"data":{"choices":[{"delta":{"content":"Hello"}}]}}}',
    '',
    'data: {"type":"chat:completion","data":{"data":{"choices":[{"delta":{"content":" world"}}]}}}',
    '',
    'data: {"type":"chat:completion","data":{"data":{"choices":[{"delta":{"content":"!"}}]}}}',
    '',
    'data: {"data":{"data":{"done":true,"error":{"captcha_error_type":"missing_param","code":"FRONTEND_CAPTCHA_REQUIRED"}}}}',
    '',
    'data: [DONE]',
    '',
  ].join('\n');

  const events = parseSSEStream(sseData);
  console.log(`SSE events parsed: ${events.length}`);

  // Verify content extraction.
  let content = '';
  let captchaRequired = false;
  for (const ev of events) {
    // Only the string "[DONE]" marks the end — not objects with
    // done: true (chat.z.ai's error events have done: true too).
    if (ev === '[DONE]' || (typeof ev === 'object' && ev.done === true && !ev.data)) {
      break;
    }
    // Unwrap chat.z.ai envelope. Error events have a different
    // structure: {data: {data: {done:true, error:{}}}} (no type field).
    let payload = ev;
    if (ev.type === 'chat:completion' && ev.data) {
      if (ev.data.data) {
        payload = ev.data.data;
      } else {
        payload = ev.data;
      }
    } else if (ev.data && ev.data.data) {
      // Error event: {data: {data: {done:true, error:{}}}}
      payload = ev.data.data;
    }

    // Check for error FIRST (before extracting content).
    if (payload.error) {
      const errorCode = payload.error.error_code || payload.error.code;
      if (errorCode === 'FRONTEND_CAPTCHA_REQUIRED') {
        captchaRequired = true;
      }
      console.log(`  Error: ${errorCode}`);
      continue;
    }

    // Then extract content.
    if (payload.choices && payload.choices.length > 0) {
      const delta = payload.choices[0].delta;
      if (delta && delta.content) {
        content += delta.content;
      }
    }
  }

  // Note: the captcha error comes AFTER the content chunks in the SSE
  // stream, and before [DONE]. Both content AND captchaRequired should
  // be true (content was streamed, then the error arrived).
  console.log(`  Content: "${content}"`);
  console.log(`  Captcha required: ${captchaRequired}`);

  const passed = content === 'Hello world!' && captchaRequired;
  console.log(passed ? '  ✅ SSE parsing test passed' : '  ❌ SSE parsing test failed');
  return passed;
}

// Test auto-retry logic.
function testAutoRetry() {
  const RETRYABLE_ERRORS = ['server overload', 'rate limit', 'network', '502', '503', '504'];
  const MAX_RETRIES = 5;

  function isRetryable(errorMsg) {
    const msg = errorMsg.toLowerCase();
    return RETRYABLE_ERRORS.some(e => msg.includes(e));
  }

  const testCases = [
    { error: 'Server overload', expectedRetry: true },
    { error: 'Rate limit exceeded', expectedRetry: true },
    { error: 'Network error', expectedRetry: true },
    { error: 'HTTP 502: Bad Gateway', expectedRetry: true },
    { error: 'HTTP 503: Service Unavailable', expectedRetry: true },
    { error: 'HTTP 504: Gateway Timeout', expectedRetry: true },
    { error: 'Captcha required', expectedRetry: false },
    { error: 'Model not available for current user level', expectedRetry: false },
    { error: 'Oops, something went wrong', expectedRetry: false },
  ];

  let allPassed = true;
  for (const tc of testCases) {
    const result = isRetryable(tc.error);
    const passed = result === tc.expectedRetry;
    console.log(`  "${tc.error}" → retry=${result} (expected ${tc.expectedRetry}) ${passed ? '✅' : '❌'}`);
    if (!passed) allPassed = false;
  }

  console.log(allPassed ? '  ✅ Auto-retry test passed' : '  ❌ Auto-retry test failed');
  return allPassed;
}

// Run tests.
console.log('=== SSE Parsing Test ===');
const ssePassed = testSSEParsing();

console.log('\n=== Auto-Retry Test ===');
const retryPassed = testAutoRetry();

console.log(`\n${ssePassed && retryPassed ? '✅ All tests passed!' : '❌ Some tests failed!'}`);
process.exit(ssePassed && retryPassed ? 0 : 1);
