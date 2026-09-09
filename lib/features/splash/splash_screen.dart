// Splash screen — shows the app name while the database is opening and
// the auth state is being restored. Routes to either the chat list (if
// signed in via guest or API key) or the auth screen (if guest fetch
// failed).
//
// DEBUG: prints every step to the console so the user can see exactly
// where the app is hanging. Run the app from a terminal to see the
// output.

import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../state/auth_state.dart';
import '../../state/openai_server_state.dart';
import '../../state/anon_profiles_state.dart';
import '../../core/config/app_config.dart';

void _debug(String msg) {
  // ignore: avoid_print
  print('[SPLASH] $msg');
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
    _debug(s);
    if (mounted) setState(() {});
  }

  @override
  void initState() {
    super.initState();
    _debug('Splash screen initState');
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      _debug('Post-frame callback started');

      // 5-second fallback timer
      _fallbackTimer = Timer(const Duration(seconds: 5), () {
        _debug('FALLBACK TIMER FIRED (5s elapsed without completion)');
        if (!_navigated && mounted) {
          _setStatus('Fallback: navigating to auth screen');
          _navigateToAuth();
        }
      });

      // Step 1: restore auth state
      _setStatus('1/4: Restoring auth state...');
      try {
        await ref
            .read(authStateProvider.notifier)
            .restore()
            .timeout(const Duration(seconds: 5));
        _debug('  restore() completed');
      } on TimeoutException {
        _debug('  restore() timed out');
      } catch (e) {
        _debug('  restore() threw: $e');
      }

      // Step 2: restore anon profiles
      _setStatus('2/4: Restoring anonymous profiles...');
      try {
        await ref
            .read(anonProfilesProvider.notifier)
            .restore()
            .timeout(const Duration(seconds: 3));
        _debug('  anonProfiles.restore() completed');
      } catch (e) {
        _debug('  anonProfiles.restore() threw: $e');
      }

      // Step 3: restore OpenAI server
      _setStatus('3/4: Restoring OpenAI server...');
      try {
        await ref
            .read(openAiServerProvider.notifier)
            .restoreIfEnabled()
            .timeout(const Duration(seconds: 3));
        _debug('  openAiServer.restoreIfEnabled() completed');
      } on TimeoutException {
        _debug('  openAiServer.restoreIfEnabled() TIMEOUT');
      } catch (e) {
        _debug('  openAiServer.restoreIfEnabled() threw: $e');
      }

      _fallbackTimer?.cancel();
      if (!mounted || _navigated) return;

      // Step 4: navigate
      _setStatus('4/4: Navigating...');
      final auth = ref.read(authStateProvider);
      _debug('  auth.signedIn=${auth.signedIn}, mode=${auth.mode}, '
          'status=${auth.status}');
      if (auth.signedIn) {
        _debug('  -> navigating to / (chat list)');
        _navigated = true;
        context.go('/');
      } else {
        _debug('  -> navigating to /auth (auth screen)');
        _navigateToAuth();
      }
    });
  }

  void _navigateToAuth() {
    _navigated = true;
    if (mounted) context.go('/auth');
  }

  @override
  void dispose() {
    _debug('Splash screen disposed');
    _fallbackTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
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
    );
  }
}
