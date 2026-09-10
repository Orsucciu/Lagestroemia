// App entry. Boots logging, prefs, secure storage, opens the database and
// hands the Riverpod container over to [LagestroemiaApp].
//
// DEBUG: writes a step-by-step log to BOTH stdout (with flush) and a
// file (lagestroemia_debug.log) so the user can see exactly what's
// happening even if the console doesn't show output.

import 'dart:async';
import 'dart:io' show Platform, File, stdout, stderr, FileMode;

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

/// Debug log file path. On Windows: %TEMP%\lagestroemia_debug.log
/// On Linux: /tmp/lagestroemia_debug.log
String get _logPath {
  try {
    final dir = Platform.environment['TEMP'] ?? '/tmp';
    return '$dir/lagestroemia_debug.log';
  } catch (_) {
    return '/tmp/lagestroemia_debug.log';
  }
}

/// Writes a debug message to stdout (with flush) AND to a log file.
/// On Windows, Flutter's print() doesn't flush stdout immediately,
/// so we use stdout.write() + stdout.flush() to force it.
void debugLog(String msg) {
  final line = '[${DateTime.now().toIso8601String()}] $msg';
  try {
    stdout.writeln(line);
    stdout.flush();
  } catch (_) {}
  try {
    stderr.writeln(line);
  } catch (_) {}
  try {
    final f = File(_logPath);
    f.writeAsStringSync('$line\n', mode: FileMode.append);
  } catch (_) {}
}

Future<void> main() async {
  // Clear the debug log file at start
  try { File(_logPath).writeAsStringSync(''); } catch (_) {}

  debugLog('=== LAGESTROEMIA STARTING ===');
  debugLog('Platform: ${_platformInfo()}');
  debugLog('Log file: $_logPath');

  debugLog('1/6: Initializing Flutter binding...');
  WidgetsFlutterBinding.ensureInitialized();

  debugLog('2/6: Loading SharedPreferences...');
  final prefs = await SharedPreferences.getInstance();
  debugLog('  SharedPreferences loaded OK');

  debugLog('3/6: Initializing logger...');
  initAppLogger();

  debugLog('4/6: Creating ProviderScope...');
  runApp(ProviderScope(
    overrides: <Override>[
      settingsStateProvider.overrideWith(
        (ref) => SettingsNotifier(prefs),
      ),
      sharedPrefsProvider.overrideWithValue(prefs),
    ],
    child: const LagestroemiaApp(),
  ));

  debugLog('5/6: App started. Waiting for splash screen...');
}

String _platformInfo() {
  try {
    return '${Platform.operatingSystem} ${Platform.operatingSystemVersion}';
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
