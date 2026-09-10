// App entry. Boots logging, prefs, secure storage, opens the database and
// hands the Riverpod container over to [LagestroemiaApp].
//
// The app uses a simple state machine for startup instead of routing the
// splash screen through go_router. The splash is shown directly by the
// root widget while the startup sequence runs. Once it's done, the root
// widget switches to the go_router. This eliminates the race condition
// where the router disposes the splash while restore() is running.

import 'dart:async';
import 'dart:io' show Platform, File, stdout, stderr, FileMode;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_web_plugins/url_strategy.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'l10n/generated/app_localizations.dart';
import 'router/app_router.dart';
import 'state/auth_state.dart';
import 'state/anon_profiles_state.dart';
import 'state/openai_server_state.dart';
import 'state/providers.dart';
import 'state/settings_state.dart';
import 'theme/app_theme.dart';

String get _logPath {
  try {
    final dir = Platform.environment['TEMP'] ?? '/tmp';
    return '$dir/lagestroemia_debug.log';
  } catch (_) {
    return '/tmp/lagestroemia_debug.log';
  }
}

/// Writes a debug log line. On native platforms: writes to stdout, stderr,
/// and appends to the log file at `$TEMP/lagestroemia_debug.log`. On web:
/// only writes to the browser console via `print()` (the file system
/// doesn't exist there, and `stdout`/`stderr`/`File` all throw).
void debugLog(String msg) {
  final line = '[${DateTime.now().toIso8601String()}] $msg';
  // Browser console — works on every platform.
  print(line);
  if (kIsWeb) return;
  // File + stdout/stderr — native only.
  try { stdout.writeln(line); stdout.flush(); } catch (_) {}
  try { stderr.writeln(line); } catch (_) {}
  try {
    final f = File(_logPath);
    f.writeAsStringSync('$line\n', mode: FileMode.append);
  } catch (_) {}
}

Future<void> main() async {
  // Use path-based URLs on web (e.g. /auth instead of /#/auth).
  // This prevents the "Could not navigate to initial route" warning
  // that appears when the browser URL hash is out of sync with the
  // go_router's initial location.
  if (kIsWeb) {
    usePathUrlStrategy();
  }

  if (!kIsWeb) {
    try { File(_logPath).writeAsStringSync(''); } catch (_) {}
  }

  debugLog('=== LAGESTROEMIA STARTING ===');
  debugLog('Platform: ${_platformInfo()}');

  debugLog('1/4: Initializing Flutter binding...');
  WidgetsFlutterBinding.ensureInitialized();

  debugLog('2/4: Loading SharedPreferences...');
  final prefs = await SharedPreferences.getInstance();

  debugLog('3/4: Initializing logger...');
  initAppLogger();

  debugLog('4/4: Starting app...');
  runApp(ProviderScope(
    overrides: <Override>[
      settingsStateProvider.overrideWith((ref) => SettingsNotifier(prefs)),
      sharedPrefsProvider.overrideWithValue(prefs),
    ],
    child: const LagestroemiaApp(),
  ));
}

String _platformInfo() {
  if (kIsWeb) return 'web';
  try {
    return '${Platform.operatingSystem} ${Platform.operatingSystemVersion}';
  } catch (_) {
    return 'unknown';
  }
}

/// A simple enum for the app's startup phase.
enum StartupPhase { loading, done }

/// The root widget. Shows the splash screen during startup, then
/// switches to the go_router-based app once startup is done.
///
/// This is NOT a routed page — it's the direct child of MaterialApp.
/// The splash screen is shown as a simple widget, not a go_router route.
/// This eliminates the race condition where the router disposes the
/// splash while restore() is still running.
class LagestroemiaApp extends ConsumerStatefulWidget {
  const LagestroemiaApp({super.key});
  @override
  ConsumerState<LagestroemiaApp> createState() => _LagestroemiaAppState();
}

class _LagestroemiaAppState extends ConsumerState<LagestroemiaApp> {
  StartupPhase _phase = StartupPhase.loading;
  String _statusText = 'Starting...';

  @override
  void initState() {
    super.initState();
    debugLog('[APP] initState — starting startup sequence');
    _runStartup();
  }

  Future<void> _runStartup() async {
    final container = ProviderScope.containerOf(context, listen: false);

    // Step 1: restore auth
    _setStatus('Restoring auth...');
    try {
      await container
          .read(authStateProvider.notifier)
          .restore()
          .timeout(const Duration(seconds: 10));
      debugLog('[APP] restore() completed');
    } on TimeoutException {
      debugLog('[APP] restore() TIMED OUT');
    } catch (e) {
      debugLog('[APP] restore() threw: $e');
    }

    // Step 2: anon profiles
    _setStatus('Restoring profiles...');
    try {
      await container
          .read(anonProfilesProvider.notifier)
          .restore()
          .timeout(const Duration(seconds: 3));
    } catch (e) {
      debugLog('[APP] anonProfiles threw: $e');
    }

    // Step 3: OpenAI server
    _setStatus('Restoring server...');
    try {
      await container
          .read(openAiServerProvider.notifier)
          .restoreIfEnabled()
          .timeout(const Duration(seconds: 3));
    } catch (e) {
      debugLog('[APP] openAiServer threw: $e');
    }

    _setStatus('Done');
    debugLog('[APP] startup complete, switching to router');

    if (mounted) {
      setState(() => _phase = StartupPhase.done);
    }
  }

  void _setStatus(String s) {
    _statusText = s;
    debugLog('[APP] $s');
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsStateProvider);
    final locale =
        settings.localeTag == null ? null : Locale(settings.localeTag!);

    if (_phase == StartupPhase.loading) {
      // Show the splash screen directly — NOT through the router.
      return MaterialApp(
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
        home: _SplashContent(statusText: _statusText),
      );
    }

    // Startup is done — switch to the go_router-based app.
    final router = ref.watch(routerProvider);
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

/// Simple splash content — just the logo, spinner, and status text.
/// Not a routed page, so the router can't dispose it.
class _SplashContent extends StatelessWidget {
  const _SplashContent({required this.statusText});
  final String statusText;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 40),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              const Icon(Icons.local_florist,
                  size: 80, color: Color(0xFF7C4DFF)),
              const SizedBox(height: 16),
              Text(
                'Lagestroemia',
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              const SizedBox(height: 24),
              const CircularProgressIndicator(),
              const SizedBox(height: 16),
              Text(
                statusText,
                style: Theme.of(context).textTheme.bodySmall,
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
