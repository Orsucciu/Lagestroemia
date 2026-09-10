// Splash screen with debug output to stdout+file+UI.
//
// Every step is logged via debugLog() so it appears in:
// 1. The console (stdout with flush)
// 2. A log file (lagestroemia_debug.log)
// 3. The UI (status text below the spinner)

import 'dart:async';
import 'dart:io' show Platform, File, stdout, stderr, FileMode;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../state/auth_state.dart';
import '../../state/openai_server_state.dart';
import '../../state/anon_profiles_state.dart';
import '../../core/config/app_config.dart';

/// Same debugLog as in main.dart — writes to stdout+flush and a log file.
void debugLog(String msg) {
  final line = '[${DateTime.now().toIso8601String()}] $msg';
  try { stdout.writeln(line); stdout.flush(); } catch (_) {}
  try { stderr.writeln(line); } catch (_) {}
  try {
    final dir = Platform.environment['TEMP'] ?? '/tmp';
    File('$dir/lagestroemia_debug.log')
        .writeAsStringSync('$line\n', mode: FileMode.append);
  } catch (_) {}
}

class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});
  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen> {
  Timer? _fallbackTimer;
  bool _navigated = false;
  String _statusText = 'Initializing...';

  void _setStatus(String s) {
    _statusText = s;
    debugLog('[SPLASH] $s');
    if (mounted) setState(() {});
  }

  @override
  void initState() {
    super.initState();
    debugLog('[SPLASH] initState called');
    WidgetsBinding.instance.addPostFrameCallback((_) {
      debugLog('[SPLASH] post-frame callback FIRED');

      // 5-second fallback timer
      _fallbackTimer = Timer(const Duration(seconds: 5), () {
        debugLog('[SPLASH] FALLBACK TIMER FIRED (5s elapsed)');
        if (!_navigated && mounted) {
          _setStatus('Fallback: navigating to auth');
          _navigateToAuth();
        }
      });

      _runStartup();
    });
  }

  Future<void> _runStartup() async {
    // Step 1: restore auth
    _setStatus('1/4: Restoring auth...');
    try {
      await ref
          .read(authStateProvider.notifier)
          .restore()
          .timeout(const Duration(seconds: 5));
      debugLog('[SPLASH] restore() completed');
    } on TimeoutException {
      debugLog('[SPLASH] restore() TIMED OUT');
    } catch (e) {
      debugLog('[SPLASH] restore() threw: $e');
    }

    // Step 2: anon profiles
    _setStatus('2/4: Restoring profiles...');
    try {
      await ref
          .read(anonProfilesProvider.notifier)
          .restore()
          .timeout(const Duration(seconds: 3));
    } catch (e) {
      debugLog('[SPLASH] anonProfiles threw: $e');
    }

    // Step 3: OpenAI server
    _setStatus('3/4: Restoring server...');
    try {
      await ref
          .read(openAiServerProvider.notifier)
          .restoreIfEnabled()
          .timeout(const Duration(seconds: 3));
    } catch (e) {
      debugLog('[SPLASH] openAiServer threw: $e');
    }

    _fallbackTimer?.cancel();
    if (!mounted || _navigated) return;

    // Step 4: navigate
    _setStatus('4/4: Navigating...');
    final auth = ref.read(authStateProvider);
    debugLog('[SPLASH] auth.signedIn=${auth.signedIn} mode=${auth.mode} '
        'status=${auth.status}');
    if (auth.signedIn) {
      debugLog('[SPLASH] -> going to / (chat list)');
      _navigated = true;
      context.go('/');
    } else {
      debugLog('[SPLASH] -> going to /auth');
      _navigateToAuth();
    }
  }

  void _navigateToAuth() {
    _navigated = true;
    if (mounted) context.go('/auth');
  }

  @override
  void dispose() {
    debugLog('[SPLASH] dispose()');
    _fallbackTimer?.cancel();
    super.dispose();
  }

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
                AppConfig.appName,
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              const SizedBox(height: 24),
              const CircularProgressIndicator(),
              const SizedBox(height: 16),
              Text(
                _statusText,
                style: Theme.of(context).textTheme.bodySmall,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                'Check log: ${Platform.environment['TEMP'] ?? '/tmp'}/lagestroemia_debug.log',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: Theme.of(context).colorScheme.outline,
                    ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
