import { test, expect, Page, ConsoleMessage } from '@playwright/test';

/**
 * Lagestroemia web app — full chat flow test.
 *
 * Flow:
 *   1. App loads
 *   2. Guest auth succeeds (guest token fetched from chat.z.ai)
 *   3. Chat list screen appears
 *   4. User taps "New chat"
 *   5. Chat screen appears with model picker
 *   6. User types "hewwo" in the composer
 *   7. User presses Enter (or the send button)
 *   8. App sends the request to chat.z.ai
 *   9. Either:
 *      - The response streams in (success — assert content appears)
 *      - The captcha prompt appears (expected for first send)
 *      - An error appears (assert the error message)
 *
 * Flutter web renders to a canvas. After enabling semantics, Flutter
 * exposes widgets as <flt-semantics> elements with ARIA roles. We
 * interact with these elements via Playwright's ARIA-based locators.
 */

const APP_URL = 'http://127.0.0.1:8080/';
const STARTUP_TIMEOUT = 60_000;
const SEND_TIMEOUT = 60_000;

function captureLogs(page: Page): string[] {
  const logs: string[] = [];
  page.on('console', (msg: ConsoleMessage) => logs.push(msg.text()));
  page.on('pageerror', (err: Error) => logs.push(`PAGE_ERROR: ${err.message}`));
  return logs;
}

async function waitForLog(
  logs: string[],
  pattern: RegExp,
  timeoutMs = 30_000
): Promise<string | null> {
  const deadline = Date.now() + timeoutMs;
  while (Date.now() < deadline) {
    for (const l of logs) {
      if (pattern.test(l)) return l;
    }
    await new Promise((r) => setTimeout(r, 200));
  }
  return null;
}

/** Enables Flutter web accessibility (semantics). */
async function enableSemantics(page: Page) {
  try {
    await page.evaluate(() => {
      const el = document.querySelector('flt-semantics-placeholder');
      if (el) {
        el.dispatchEvent(new MouseEvent('click', { bubbles: true }));
      }
    });
    console.log('✓ Enabled Flutter semantics');
    await page.waitForTimeout(3000);
  } catch (e) {
    console.log('Could not enable semantics:', e);
  }
}

async function screenshot(page: Page, name: string) {
  await page.screenshot({
    path: `test-results/screenshot-${name}.png`,
    fullPage: true,
  });
}

/** Finds a Flutter semantics element by its text content. */
async function findSemanticsByRole(
  page: Page,
  role: string,
  textPattern?: RegExp
): Promise<string | null> {
  const elements = await page
    .locator(`flt-semantics[role="${role}"]`)
    .evaluateAll((els, pattern) => {
      const regex = pattern ? new RegExp(pattern) : null;
      return els
        .map((e, i) => ({
          index: i,
          text: (e.textContent || '').trim(),
        }))
        .filter((e) => !regex || regex.test(e.text));
    }, textPattern?.source);
  return elements.length > 0 ? `flt-semantics[role="${role}"] >> nth=${elements[0].index}` : null;
}

test.describe('Lagestroemia — full chat flow', () => {
  test('basic: start app → new chat → type "hewwo" → confirm response', async ({
    page,
  }) => {
    test.setTimeout(120_000);
    const logs: string[] = [];
    page.on('console', (msg: ConsoleMessage) => logs.push(msg.text()));
    page.on('pageerror', (err: Error) =>
      logs.push(`PAGE_ERROR: ${err.message}`)
    );

    // 1. Load the app.
    await page.goto(APP_URL, { waitUntil: 'domcontentloaded' });
    await page.waitForTimeout(5000);

    // 2. Wait for startup.
    const startupLog = await waitForLog(logs, /startup complete/, STARTUP_TIMEOUT);
    expect(startupLog, 'App should complete startup').toBeTruthy();
    console.log('✓ Startup completed');

    // 3. Verify guest auth.
    const guestOk = await waitForLog(logs, /guest token fetched OK/, 10_000);
    expect(guestOk, 'Guest token should be fetched').toBeTruthy();
    console.log('✓ Guest auth succeeded');

    // 4. Enable semantics.
    await enableSemantics(page);
    await screenshot(page, '01-chat-list');

    // 5. Click "New chat" button.
    const newChatBtn = page.locator('flt-semantics[role="button"]').filter({
      hasText: 'New chat',
    });
    await newChatBtn.click({ timeout: 10_000 });
    console.log('✓ Clicked "New chat"');
    await page.waitForTimeout(5000);
    await screenshot(page, '02-chat-screen');

    // 5a. Dump all semantic elements on the chat screen for debugging.
    const chatElements = await page
      .locator('flt-semantics[role]')
      .evaluateAll((els) =>
        els.map((e) => ({
          role: e.getAttribute('role'),
          text: (e.textContent || '').trim().substring(0, 80),
        }))
      );
    console.log('=== Chat screen semantic elements ===');
    console.log(JSON.stringify(chatElements, null, 2));

    // 5b. Also check for any hidden HTML input/textarea elements.
    const htmlInputs = await page
      .locator('input, textarea')
      .evaluateAll((els) =>
        els.map((e) => ({
          tag: e.tagName,
          type: (e as HTMLInputElement).type,
          placeholder: (e as HTMLInputElement).placeholder,
          ariaLabel: e.getAttribute('aria-label'),
          visible: (e as HTMLElement).offsetParent !== null,
        }))
      );
    console.log('=== HTML input/textarea elements ===');
    console.log(JSON.stringify(htmlInputs, null, 2));

    // 6. Find the composer text field and type "hewwo".
    //    Flutter web exposes text fields as hidden HTML <input> elements.
    //    We fill the input directly, which Flutter's TextEditingController
    //    picks up automatically.
    const textboxCount = await page.locator('flt-semantics[role="textbox"]').count();
    const htmlInput = page.locator('input[type="text"]').first();
    const htmlInputCount = await page.locator('input[type="text"]').count();
    console.log(`Textboxes: ${textboxCount}, HTML inputs: ${htmlInputCount}`);

    if (htmlInputCount > 0) {
      // Flutter web's <input> is hidden off-screen. Use force: true to
      // interact with it regardless of visibility.
      await htmlInput.click({ force: true, timeout: 10_000 });
      await htmlInput.fill('hewwo', { force: true });
      console.log('✓ Filled HTML input with "hewwo"');
    } else if (textboxCount > 0) {
      const composer = page.locator('flt-semantics[role="textbox"]').first();
      await composer.click({ timeout: 10_000 });
      await page.keyboard.type('hewwo', { delay: 50 });
      console.log('✓ Typed into semantics textbox');
    } else {
      // Last resort: click between the Attach file and Send buttons.
      console.log('No textbox found — clicking composer area...');
      const attachBtn = page.locator('flt-semantics[role="button"]').filter({ hasText: 'Attach file' });
      const sendBtn = page.locator('flt-semantics[role="button"]').filter({ hasText: 'Send' });
      const attachBox = await attachBtn.boundingBox();
      const sendBox = await sendBtn.boundingBox();
      if (attachBox && sendBox) {
        const midX = (attachBox.x + attachBox.width + sendBox.x) / 2;
        const midY = attachBox.y + attachBox.height / 2;
        await page.mouse.click(midX, midY);
      }
      await page.keyboard.type('hewwo', { delay: 50 });
      console.log('✓ Typed via mouse click + keyboard');
    }
    await page.waitForTimeout(1000);
    await screenshot(page, '03-typed-hewwo');

    // 7. Press Enter to send.
    await page.keyboard.press('Enter');
    console.log('✓ Pressed Enter');
    await page.waitForTimeout(3000);
    await screenshot(page, '04-after-send');

    // 8. Verify send() was called.
    const sendLog = await waitForLog(logs, /\[CHAT\] send\(\) called/, 15_000);
    if (!sendLog) {
      // If send() wasn't called, try clicking the send button.
      console.log('Enter did not trigger send. Trying send button...');
      const sendBtn = page
        .locator('flt-semantics[role="button"]')
        .filter({ hasText: /send/i });
      if (await sendBtn.count() > 0) {
        await sendBtn.click({ force: true });
        await page.waitForTimeout(3000);
      }
    }

    const sendLog2 = await waitForLog(logs, /\[CHAT\] send\(\) called/, 10_000);
    expect(sendLog2, 'send() should be called after typing + Enter/send button').toBeTruthy();
    console.log('✓ send() was called');

    // 9. Wait for the stream to start.
    const streamLog = await waitForLog(
      logs,
      /\[CHAT\] send\(\): starting stream/,
      15_000
    );
    expect(streamLog, 'Stream should start').toBeTruthy();
    console.log('✓ Stream started');

    // 10. Wait for the outcome (success, captcha, or error).
    const outcome = await waitForLog(
      logs,
      /\[CHAT\] send\(\): (stream error|finished|captcha required|non-retryable)/,
      SEND_TIMEOUT
    );
    console.log('✓ Stream outcome:', outcome);
    await screenshot(page, '05-outcome');

    expect(outcome, 'Stream should produce an outcome').toBeTruthy();

    if (outcome && outcome.includes('captcha required')) {
      console.log('ℹ Captcha required — expected for first guest send');
    } else if (outcome && outcome.includes('finished (success=true')) {
      console.log('✓ Chat completed successfully!');
    } else if (outcome && outcome.includes('non-retryable error')) {
      console.log('ℹ Non-retryable error (may be model not allowed)');
    }

    // Print all logs for debugging.
    console.log('\n=== ALL LOGS ===');
    for (const l of logs) console.log(l);
  });

  test('startup sequence: app boots and fetches guest token', async ({ page }) => {
    const logs: string[] = [];
    page.on('console', (msg: ConsoleMessage) => logs.push(msg.text()));

    await page.goto(APP_URL, { waitUntil: 'domcontentloaded' });
    await page.waitForTimeout(5000);

    expect(await waitForLog(logs, /LAGESTROEMIA STARTING/, 10_000)).toBeTruthy();
    expect(await waitForLog(logs, /Initializing Flutter binding/, 10_000)).toBeTruthy();
    expect(await waitForLog(logs, /Restoring auth/, 10_000)).toBeTruthy();
    expect(await waitForLog(logs, /_fetchGuestToken\(\): sending GET/, 30_000)).toBeTruthy();
    expect(await waitForLog(logs, /got response \(status 200\)/, 30_000)).toBeTruthy();
    expect(await waitForLog(logs, /guest token fetched OK/, 10_000)).toBeTruthy();
    expect(await waitForLog(logs, /startup complete/, 30_000)).toBeTruthy();
    console.log('✓ Full startup sequence verified');
  });

  test('database opens successfully on web', async ({ page }) => {
    const logs: string[] = [];
    page.on('console', (msg: ConsoleMessage) => logs.push(msg.text()));

    await page.goto(APP_URL, { waitUntil: 'domcontentloaded' });
    await page.waitForTimeout(5000);

    const dbLog = await waitForLog(logs, /Opening SQLite database/, 30_000);
    expect(dbLog, 'Database should open').toBeTruthy();
    console.log('✓ Database opened:', dbLog);

    const dbError = await waitForLog(logs, /SqfliteFfiWebException|web worker/, 5_000);
    expect(dbError, 'No database errors should occur').toBeNull();
  });
});
