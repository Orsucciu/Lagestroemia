import { defineConfig, devices } from '@playwright/test';

/**
 * Playwright configuration for Lagestroemia web E2E tests.
 *
 * The app must be running at http://localhost:8080 before running tests.
 * Start it with: cd e2e && npm run serve:dev
 * (or build + serve: npm run serve)
 *
 * Then run tests: npx playwright test
 */
export default defineConfig({
  testDir: './tests',
  fullyParallel: false, // Flutter web is single-threaded; run serially
  forbidOnly: !!process.env.CI,
  retries: process.env.CI ? 2 : 0,
  workers: 1,
  reporter: 'html',
  timeout: 60_000,
  expect: { timeout: 30_000 },
  use: {
    baseURL: 'http://localhost:8080',
    trace: 'on-first-retry',
    screenshot: 'only-on-failure',
    video: 'retain-on-failure',
    // Flutter web renders to a canvas by default. We need to enable
    // accessibility for Playwright to interact with elements.
    launchOptions: {
      args: ['--disable-blink-features=AutomationControlled'],
    },
  },
  projects: [
    {
      name: 'chromium',
      use: { ...devices['Desktop Chrome'] },
    },
  ],
});
