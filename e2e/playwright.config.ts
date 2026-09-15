import { defineConfig, devices } from '@playwright/test';

/**
 * Playwright configuration for Lagestroemia web E2E tests.
 *
 * The `webServer` config below starts a static file server for the
 * Flutter web build automatically — no need to run it manually.
 */
export default defineConfig({
  testDir: './tests',
  fullyParallel: false,
  forbidOnly: !!process.env.CI,
  retries: process.env.CI ? 2 : 0,
  workers: 1,
  reporter: [['list'], ['html', { open: 'never' }]],
  timeout: 120_000,
  expect: { timeout: 30_000 },
  use: {
    baseURL: 'http://127.0.0.1:8080',
    trace: 'on-first-retry',
    screenshot: 'only-on-failure',
    video: 'retain-on-failure',
    launchOptions: {
      args: [
        '--disable-blink-features=AutomationControlled',
        // Disable CORS for testing. chat.z.ai returns 405 for OPTIONS
        // preflight requests, which blocks cross-origin POST requests
        // with custom headers (X-Signature, X-Device-ID, etc.) from
        // the browser. In production, users need to use a CORS proxy
        // or the desktop app. For E2E testing, we disable web security.
        '--disable-web-security',
        '--disable-features=IsolateOrigins,site-per-process',
      ],
    },
  },
  webServer: {
    command: 'python3 -m http.server 8080 --directory ../build/web --bind 127.0.0.1',
    url: 'http://127.0.0.1:8080/',
    reuseExistingServer: !process.env.CI,
    timeout: 30_000,
    cwd: __dirname,
  },
  projects: [
    {
      name: 'chromium',
      use: { ...devices['Desktop Chrome'] },
    },
  ],
});
