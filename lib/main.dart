// App entry. Boots logging, prefs, secure storage, opens the database and
// hands the Riverpod container over to [LagestroemiaApp].
//
// When the app starts, it prints a step-by-step log to the console
// (stdout) so the user can see exactly what's happening and where it
// might hang. This is critical for debugging the "stuck on loading"
// issue on Windows/Android.

import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/material.dart' show WidgetsFlutterBinding, MaterialApp;
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'l10n/generated/app_localizations.dart';
import 'router/app_router.dart';
import 'state/providers.dart';
import 'state/settings_state.dart';
import 'theme/app_theme.dart';

/// Debug print that flushes immediately. On Windows, stdout is
/// line-buffered by default so prints might not appear until the app
/// exits. This forces a flush after each line.
void debugPrint(String msg) {
  // ignore: avoid_print
  print('[LAGESTROEMIA] $msg');
}

Future<void> main() async {
  debugPrint('=== STARTING ===');
  debugPrint('Platform: ${_platformInfo()}');

  debugPrint('1/6: Initializing Flutter binding...');
  WidgetsFlutterBinding.ensureInitialized();

  debugPrint('2/6: Loading SharedPreferences...');
  final prefs = await SharedPreferences.getInstance();
  debugPrint('  SharedPreferences loaded OK');

  debugPrint('3/6: Initializing logger...');
  initAppLogger();

  debugPrint('4/6: Creating ProviderScope...');
  runApp(ProviderScope(
    overrides: <Override>[
      settingsStateProvider.overrideWith(
        (ref) => SettingsNotifier(prefs),
      ),
      sharedPrefsProvider.overrideWithValue(prefs),
    ],
    child: const LagestroemiaApp(),
  ));

  debugPrint('5/6: App started. Waiting for splash screen...');
}

String _platformInfo() {
  // Use dart:io if available (native), otherwise web
  try {
    // ignore: avoid_dynamic_calls
    final platform = Platform.operatingSystem;
    return '$platform ${Platform.operatingSystemVersion}';
  } catch (_) {
    return 'web';
  }
}

class LagestroemiaApp extends ConsumerWidget {
  const LagestroemiaApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsStateProvider);
    final router = ref.watch(routerProvider);
    final locale =
        settings.localeTag == null ? null : Locale(settings.localeTag!);
    return MaterialApp.router(
      title: 'Lagestroemia',
      debugShowCheckedModeBanner: false,
      theme: lightTheme,
      darkTheme: darkTheme,
      themeMode: settings.themeMode,
      locale: locale,
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: const <LocalizationsDelegate>[
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      routerConfig: router,
    );
  }
}
