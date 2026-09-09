// Splash screen — shows the app name while the database is opening and
// the auth state is being restored. Routes to either the chat list (if
// signed in via guest or API key) or the auth screen (if guest fetch
// failed).
//
// The default flow is: app launches → splash → restore() → guest signup →
// chat list. The auth screen is only shown if the guest fetch fails.
//
// BUG FIX: if restore() hangs (e.g. network is slow on mobile, or the
// guest token fetch blocks), the splash screen would stay on "loading"
// forever. This version adds a 10-second fallback: if restore() hasn't
// completed in 10 seconds, we route to /auth so the user can retry
// manually or switch to API-key mode.

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
      // Start a 10-second fallback. If restore() hasn't completed in
      // 10 seconds, navigate to /auth so the user isn't stuck.
      _fallbackTimer = Timer(const Duration(seconds: 10), () {
        if (!_navigated && mounted) {
          _navigateToAuth();
        }
      });

      try {
        await ref.read(authStateProvider.notifier).restore();
        // Restore anonymous profiles from SharedPreferences.
        await ref.read(anonProfilesProvider.notifier).restore();
        // Restore the OpenAI server if it was running before the last
        // quit. (Native targets only — on Web this is a no-op.)
        try {
          await ref
              .read(openAiServerProvider.notifier)
              .restoreIfEnabled()
              .timeout(const Duration(seconds: 5));
        } catch (_) {
          // OpenAI server restore failed — not critical, just skip.
        }
      } catch (e) {
        // Any error during restore — go to auth.
      }

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
