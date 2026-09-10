// Splash screen with debug output.
//
// CRITICAL FIX: the previous version had a race condition where the
// router redirect would fire while restore() was still running, causing
// the splash widget to be disposed mid-restore, which threw
// "Cannot use ref after the widget was disposed" and caused an infinite
// loop of splash init → dispose → init → dispose.
//
// The fix: the splash screen captures all the provider notifiers it
// needs BEFORE starting any async work. It then uses those captured
// references instead of ref.read() — so even if the widget is disposed,
// the notifiers still work (they're owned by the ProviderScope, not
// the widget).

import 'dart:async';
import 'dart:io' show Platform, File, stdout, stderr, FileMode;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../state/auth_state.dart';
import '../../state/openai_server_state.dart';
import '../../state/anon_profiles_state.dart';
import '../../core/config/app_config.dart';

void _debugLog(String msg) {
  final line = '[${DateTime.now().toIso8601String()}] $msg';
  try { stdout.writeln(line); stdout.flush(); } catch (_) {}
  try { stderr.writeln(line); } catch (_) {}
  try {
    final dir = Platform.environment['TEMP'] ?? '/tmp';
    File('${dir}/lagestroemia_debug.log')
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
  String _statusText = 'Initializing...';
  bool _done = false;

  // Capture provider containers so we can use them even after the
  // widget is disposed (the ProviderScope outlives the widget).
  late final AuthNotifier _authNotifier;
  late final AnonProfilesNotifier _anonNotifier;
  late final OpenAiServerNotifier _serverNotifier;

  void _setStatus(String s) {
    _statusText = s;
    _debugLog('[SPLASH] $s');
    if (mounted) setState(() {});
  }

  @override
  void initState() {
    super.initState();
    _debugLog('[SPLASH] initState');

    // Capture the notifiers NOW while we know ref is valid.
    _authNotifier = ref.read(authStateProvider.notifier);
    _anonNotifier = ref.read(anonProfilesProvider.notifier);
    _serverNotifier = ref.read(openAiServerProvider.notifier);

    // Start the startup sequence directly (no addPostFrameCallback).
    _runStartup();
  }

  Future<void> _runStartup() async {
    _debugLog('[SPLASH] startup sequence beginning');

    // 5-second fallback timer
    _fallbackTimer = Timer(const Duration(seconds: 5), () {
      _debugLog('[SPLASH] FALLBACK TIMER FIRED');
      _navigate();
    });

    // Step 1: restore auth
    _setStatus('1/4: Restoring auth...');
    try {
      await _authNotifier.restore().timeout(const Duration(seconds: 5));
      _debugLog('[SPLASH] restore() completed');
    } on TimeoutException {
      _debugLog('[SPLASH] restore() TIMED OUT');
    } catch (e) {
      _debugLog('[SPLASH] restore() threw: $e');
    }

    // Step 2: anon profiles
    _setStatus('2/4: Restoring profiles...');
    try {
      await _anonNotifier.restore().timeout(const Duration(seconds: 3));
    } catch (e) {
      _debugLog('[SPLASH] anonProfiles threw: $e');
    }

    // Step 3: OpenAI server
    _setStatus('3/4: Restoring server...');
    try {
      await _serverNotifier.restoreIfEnabled().timeout(
          const Duration(seconds: 3));
    } catch (e) {
      _debugLog('[SPLASH] openAiServer threw: $e');
    }

    _setStatus('4/4: Done');
    _navigate();
  }

  void _navigate() {
    if (_done) return;
    _done = true;
    _fallbackTimer?.cancel();

    // Read the current auth state. We use the captured notifier's state
    // instead of ref.read() to avoid "Cannot use ref after disposed".
    final auth = _authNotifier.state;
    _debugLog('[SPLASH] navigating: signedIn=${auth.signedIn} '
        'mode=${auth.mode} status=${auth.status}');

    if (!mounted) {
      _debugLog('[SPLASH] widget disposed, cannot navigate');
      return;
    }

    if (auth.signedIn) {
      _debugLog('[SPLASH] -> / (chat list)');
      context.go('/');
    } else {
      _debugLog('[SPLASH] -> /auth');
      context.go('/auth');
    }
  }

  @override
  void dispose() {
    _debugLog('[SPLASH] dispose()');
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
            ],
          ),
        ),
      ),
    );
  }
}
