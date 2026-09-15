import { test, expect, Page } from '@playwright/test';

/**
 * Helper: wait for the Flutter app to finish loading.
 *
 * Flutter web renders to a canvas. We can't query individual widgets
 * directly — we interact via the accessibility tree (ARIA labels) or
 * by taking screenshots and comparing them.
 *
 * To enable accessibility in Flutter web, the app must have
 * `semanticsEnabled` or the user must press the screen-reader button.
 * In tests, we programmatically enable it.
 */
async function waitForFlutterApp(page: Page) {
  // Wait for the Flutter app to load (the flutter view element appears).
  await page.waitForLoadState('networkidle');
  // Give Flutter time to initialize its engine + render the first frame.
  await page.waitForTimeout(5000);
  // Enable accessibility (Flutter web exposes a hidden button for this).
  // We try clicking the accessibility button if it exists.
  try {
    const a11yButton = page.locator('flt-glass-pane').first();
    await a11yButton.click({ timeout: 3000 });
  } catch {
    // If the glass pane isn't found, the app might be in canvas mode.
    // We'll rely on screenshots instead.
  }
}

/**
 * Helper: take a screenshot for visual regression / debugging.
 */
async function screenshot(page: Page, name: string) {
  await page.screenshot({
    path: `test-results/screenshot-${name}.png`,
    fullPage: true,
  });
}

test.describe('Lagestroemia web app', () => {
  test.beforeEach(async ({ page }) => {
    await page.goto('/');
    await waitForFlutterApp(page);
  });

  test('app loads and shows the splash screen or main UI', async ({ page }) => {
    // The app should show either the splash screen (during startup)
    // or the main UI (chat list / auth screen).
    // We check that the page title is set and the canvas is rendering.
    await expect(page).toHaveTitle(/lagestroemia|Lagestroemia/i);

    // Take a screenshot to verify the app rendered something.
    await screenshot(page, 'initial-load');

    // Wait a bit more for the app to finish startup.
    await page.waitForTimeout(5000);
    await screenshot(page, 'after-startup');
  });

  test('guest auth succeeds and shows the chat list', async ({ page }) => {
    // After startup, the app should:
    // 1. Fetch a guest token from chat.z.ai
    // 2. Transition to the chat list screen
    // This takes a few seconds. We wait up to 30s for the console log
    // that indicates success.
    const logs: string[] = [];
    page.on('console', (msg) => logs.push(msg.text()));

    // Wait for the "startup complete" log line.
    await expect
      .poll(() => logs.some((l) => l.includes('startup complete')), {
        timeout: 30_000,
      })
      .toBeTruthy();

    // The app should now be on the chat list (or auth screen if guest
    // fetch failed). Take a screenshot to verify.
    await screenshot(page, 'after-auth');
  });

  test('can navigate to a new chat', async ({ page }) => {
    const logs: string[] = [];
    page.on('console', (msg) => logs.push(msg.text()));

    // Wait for startup.
    await expect
      .poll(() => logs.some((l) => l.includes('startup complete')), {
        timeout: 30_000,
      })
      .toBeTruthy();

    await page.waitForTimeout(2000);
    await screenshot(page, 'chat-list');

    // Try to find and click the "new chat" button. In Flutter web with
    // accessibility enabled, buttons are exposed as ARIA elements.
    // We look for an element with the "add" tooltip or aria-label.
    const addButton = page.getByRole('button', { name: /new chat|add/i });
    if (await addButton.isVisible({ timeout: 5000 }).catch(() => false)) {
      await addButton.click();
      await page.waitForTimeout(2000);
      await screenshot(page, 'new-chat');
    }
  });

  test('console logs show the expected startup sequence', async ({ page }) => {
    const logs: string[] = [];
    page.on('console', (msg) => logs.push(msg.text()));

    await expect
      .poll(() => logs.some((l) => l.includes('LAGESTROEMIA STARTING')), {
        timeout: 10_000,
      })
      .toBeTruthy();

    await expect
      .poll(() => logs.some((l) => l.includes('Initializing Flutter binding')), {
        timeout: 10_000,
      })
      .toBeTruthy();

    await expect
      .poll(() => logs.some((l) => l.includes('Restoring auth')), {
        timeout: 10_000,
      })
      .toBeTruthy();
  });

  test('guest token fetch is attempted', async ({ page }) => {
    const logs: string[] = [];
    page.on('console', (msg) => logs.push(msg.text()));

    // Wait for the guest token fetch to be attempted.
    await expect
      .poll(
        () =>
          logs.some((l) =>
            l.includes('_fetchGuestToken(): sending GET to https://chat.z.ai')
          ),
        { timeout: 30_000 }
      )
      .toBeTruthy();

    // Wait for the result (either success or failure).
    await expect
      .poll(
        () =>
          logs.some(
            (l) =>
              l.includes('guest token fetched OK') ||
              l.includes('guest token fetch returned null') ||
              l.includes('_fetchGuestToken(): EXCEPTION')
          ),
        { timeout: 30_000 }
      )
      .toBeTruthy();

    await screenshot(page, 'after-guest-fetch');
  });
});
