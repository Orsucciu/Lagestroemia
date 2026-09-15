# End-to-End Tests (Playwright)

Playwright tests for the Lagestroemia web app. These tests run a real
browser, load the Flutter web app, and verify that it boots correctly.

## Prerequisites

1. **Flutter** — must be on your PATH
2. **Node.js** — v18+ (for Playwright)
3. **Playwright browsers** — install with `npx playwright install chromium`

## Running the tests

### 1. Start the Flutter web app

In one terminal:

```sh
cd /home/z/my-project/lagestroemia
flutter run -d web-server --web-port 8080 --web-hostname 0.0.0.0
```

Wait for "This app is linked to the debug service" to appear.

### 2. Run the tests

In another terminal:

```sh
cd /home/z/my-project/lagestroemia/e2e
npm install
npx playwright install chromium
npx playwright test
```

### 3. View the report

```sh
npx playwright show-report
```

## What the tests cover

- **app loads and shows the splash screen or main UI** — verifies the
  Flutter engine boots and renders a canvas
- **guest auth succeeds and shows the chat list** — waits for the
  "startup complete" console log
- **can navigate to a new chat** — tries to click the "new chat" button
- **console logs show the expected startup sequence** — verifies the
  `[APP]`, `[AUTH]` debug log lines appear in the browser console
- **guest token fetch is attempted** — verifies the app tries to fetch
  a guest token from chat.z.ai

## Limitations

Flutter web renders to a canvas by default, which means Playwright
can't interact with individual widgets (buttons, text fields, etc.)
the way it can with standard HTML. The tests primarily use:

1. **Console log monitoring** — the app prints `[APP]`, `[AUTH]`,
   `[CHAT]` debug lines that we can assert on.
2. **Screenshots** — saved to `test-results/` for visual inspection.
3. **ARIA labels** — when accessibility is enabled, Flutter exposes
   buttons as ARIA elements that Playwright can interact with.

For full widget-level testing, use Flutter's `integration_test` package
instead (see `integration_test/` directory in the project root).

## CI integration

To run in CI:

```yaml
- name: Start Flutter web app
  run: flutter run -d web-server --web-port 8080 --web-hostname 0.0.0.0 &
- name: Wait for app to start
  run: sleep 30
- name: Run Playwright tests
  run: |
    cd e2e
    npm install
    npx playwright install chromium
    npx playwright test
```
