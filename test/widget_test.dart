// Integration test: full app startup flow.
//
// The app now uses a two-phase approach:
//   Phase 1 (loading): shows splash directly (not through go_router)
//   Phase 2 (done): switches to go_router
//
// This test verifies:
//   1. The splash renders
//   2. After enough pumping, the app switches to the router phase
//   3. The "Continue as guest" button appears (proving auth screen shows)

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

  testWidgets('App reaches a stable state within 15 seconds (no infinite loop)',
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

    // Pump for 15 seconds (past all timeouts: 10s restore + 3s profiles + 3s server)
    for (var i = 0; i < 150; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    // After 15 seconds, the app should have switched from splash to router.
    // In the test environment (no secure storage, limited network), the auth
    // screen should be visible with the "Continue as guest" button.
    final guestButton = find.text('Continue as guest (free)');
    expect(
      guestButton,
      findsOneWidget,
      reason: 'The app should have navigated to the auth screen by now. '
          'If the "Continue as guest" button is not visible, the app is '
          'still stuck on the splash screen.',
    );
  });
}
