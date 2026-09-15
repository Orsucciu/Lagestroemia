// Test the extension's signature computation against a known-good
// reference value. Run with: node test-signature.js

const crypto = require('crypto');

const SECRET_KEY = 'key-@@@@)))()((9))-xxxx&&&%%%%%';

// Reference implementation (from the reverse-engineered chat.z.ai bundle)
function computeSignatureRef(sortedPayload, promptText, timestamp) {
  const p = Buffer.from(promptText, 'utf8').toString('base64');
  const h = sortedPayload + '|' + p + '|' + timestamp;
  const m = Math.floor(Number(timestamp) / 300000);
  const derivedKey = crypto.createHmac('sha256', SECRET_KEY).update(String(m)).digest('hex');
  const signature = crypto.createHmac('sha256', derivedKey).update(h).digest('hex');
  return signature;
}

// The extension's implementation (using Web Crypto API)
async function computeSignatureExt(sortedPayload, promptText, timestamp) {
  const encoder = new TextEncoder();
  const promptBytes = encoder.encode(promptText);
  const p = Buffer.from(promptBytes).toString('base64');
  const h = sortedPayload + '|' + p + '|' + timestamp;
  const m = Math.floor(Number(timestamp) / 300000);

  const keyBytes = encoder.encode(SECRET_KEY);
  const cryptoKey = await crypto.subtle.importKey(
    'raw', keyBytes, { name: 'HMAC', hash: 'SHA-256' }, false, ['sign']
  );
  const derivedBuf = await crypto.subtle.sign('HMAC', cryptoKey, encoder.encode(String(m)));
  const derivedKey = Buffer.from(derivedBuf).toString('hex');

  const sigKey = encoder.encode(derivedKey);
  const sigCryptoKey = await crypto.subtle.importKey(
    'raw', sigKey, { name: 'HMAC', hash: 'SHA-256' }, false, ['sign']
  );
  const sigBuf = await crypto.subtle.sign('HMAC', sigCryptoKey, encoder.encode(h));
  return Buffer.from(sigBuf).toString('hex');
}

async function main() {
  const testCases = [
    {
      sortedPayload: 'requestId,abc-123,timestamp,1700000000000,user_id,user-xyz',
      promptText: 'hewwo',
      timestamp: '1700000000000',
    },
    {
      sortedPayload: 'requestId,def-456,timestamp,1789471677228,user_id,a6b201f5-b488-4081-9e7a-b5a8b8387a27',
      promptText: 'joe',
      timestamp: '1789471677228',
    },
    {
      sortedPayload: 'requestId,ghi-789,timestamp,1789461460826,user_id,a0d01e28-7e2f-495c-84bd-5810347595d4',
      promptText: 'hewwoooo',
      timestamp: '1789461460826',
    },
  ];

  let allPassed = true;
  for (const tc of testCases) {
    const ref = computeSignatureRef(tc.sortedPayload, tc.promptText, tc.timestamp);
    const ext = await computeSignatureExt(tc.sortedPayload, tc.promptText, tc.timestamp);
    const match = ref === ext;
    console.log(`Test: prompt="${tc.promptText}" ts=${tc.timestamp}`);
    console.log(`  Reference: ${ref}`);
    console.log(`  Extension: ${ext}`);
    console.log(`  Match: ${match ? '✅' : '❌'}`);
    if (!match) allPassed = false;
  }

  console.log(allPassed ? '\n✅ All signature tests passed!' : '\n❌ Some tests failed!');
  process.exit(allPassed ? 0 : 1);
}

main();
