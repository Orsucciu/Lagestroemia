// Splash screen — shows the app name while the database is opening and
// the auth state is being restored. Routes to either the chat list (if
// signed in via guest or API key) or the auth screen (if guest fetch
// failed).
//
// BUG FIX: if restore() hangs (e.g. flutter_secure_storage blocks on
// Windows Credential Manager, or the network call is slow), the splash
// screen would stay on "loading" forever. This version adds a 5-second
// fallback: if restore() hasn't completed in 5 seconds, we route to
// /auth so the user can retry manually or switch to API-key mode.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../state/auth_state.dart';
import '../../state/openai_server_state.dart';
import '../../state/anon_profiles_state.dart';
import '../../core/config/app_config.dart';

class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});
  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen> {
  Timer? _fallbackTimer;
  bool _navigated = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      // 5-second fallback. If restore() hasn't completed, go to /auth.
      _fallbackTimer = Timer(const Duration(seconds: 5), () {
        if (!_navigated && mounted) {
          _navigateToAuth();
        }
      });

      try {
        // Run restore() with a 5-second timeout. If it doesn't complete
        // in time, we catch the timeout and navigate to /auth.
        await ref
            .read(authStateProvider.notifier)
            .restore()
            .timeout(const Duration(seconds: 5));
      } on TimeoutException {
        // restore() took too long — go to auth screen.
      } catch (e) {
        // Any error during restore — go to auth.
      }

      try {
        await ref
            .read(anonProfilesProvider.notifier)
            .restore()
            .timeout(const Duration(seconds: 3));
      } catch (_) {}

      try {
        await ref
            .read(openAiServerProvider.notifier)
            .restoreIfEnabled()
            .timeout(const Duration(seconds: 3));
      } catch (_) {}

      _fallbackTimer?.cancel();
      if (!mounted || _navigated) return;
      final auth = ref.read(authStateProvider);
      if (auth.signedIn) {
        _navigated = true;
        context.go('/');
      } else {
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
    _fallbackTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authStateProvider);
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
              auth.status == AuthStatus.loading
                  ? 'Starting up…'
                  : auth.status == AuthStatus.error
                      ? (auth.lastError ?? 'Could not reach z.ai')
                      : '',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}
