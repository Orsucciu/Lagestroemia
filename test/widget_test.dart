// Smoke test — verifies the splash screen renders without throwing.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:lagestroemia/main.dart';
import 'package:lagestroemia/state/settings_state.dart';

void main() {
  testWidgets('App boots to the splash screen', (tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final prefs = await SharedPreferences.getInstance();
    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          settingsStateProvider.overrideWith(
            (ref) => SettingsNotifier(prefs),
          ),
        ],
        child: const LagestroemiaApp(),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byIcon(Icons.local_florist), findsOneWidget);
  });
}
