// Integration test: full app startup flow.
//
// These tests verify the exact startup sequence that caused the
// infinite-loop bug:
//   1. App starts at /splash
//   2. Splash calls restore() (async)
//   3. Router must NOT dispose the splash while restore() is running
//   4. After restore(), splash navigates to / or /auth
//   5. No infinite loop (splash → dispose → splash → dispose)
//
// The test environment has no platform channels (no flutter_secure_storage,
// no network), so restore() will fail. But the app should still reach a
// stable state (auth screen) without looping.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:lagestroemia/main.dart';
import 'package:lagestroemia/state/providers.dart';
import 'package:lagestroemia/state/settings_state.dart';

void main() {
  testWidgets('App boots and renders the splash screen', (tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final prefs = await SharedPreferences.getInstance();
    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          settingsStateProvider.overrideWith(
            (ref) => SettingsNotifier(prefs),
          ),
          sharedPrefsProvider.overrideWithValue(prefs),
        ],
        child: const LagestroemiaApp(),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byIcon(Icons.local_florist), findsOneWidget);
  });

  testWidgets('App reaches a stable state within 8 seconds (no infinite loop)',
      (tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final prefs = await SharedPreferences.getInstance();
    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          settingsStateProvider.overrideWith(
            (ref) => SettingsNotifier(prefs),
          ),
          sharedPrefsProvider.overrideWithValue(prefs),
        ],
        child: const LagestroemiaApp(),
      ),
    );

    // Pump for 8 seconds (past the 5-second fallback timer + 3-second
    // timeouts). Pump in small increments so all timers/microtasks fire.
    for (var i = 0; i < 80; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    // After 8 seconds, the app should have reached a stable state.
    // In the test environment (no network, no secure storage),
    // restore() fails, and the app should end up on the auth screen.
    //
    // The key assertion: the "Continue as guest" button should be
    // visible (it's on the auth screen, not the splash screen).
    // If it's NOT visible, the app is stuck on the splash.
    //
    // We allow up to 5 seconds of Flutter error accumulation (the
    // secure storage plugin throws in tests) but the app should
    // still navigate.
    final guestButton = find.text('Continue as guest (free)');
    expect(
      guestButton,
      findsOneWidget,
      reason: 'The app should have navigated to the auth screen by now. '
          'If the "Continue as guest" button is not visible, the app is '
          'stuck on the splash screen (infinite loop bug).',
    );
  });
}
