// Splash screen — shows the app name while the database is opening and
// the auth state is being restored. Routes to either the chat list (if
// signed in via guest or API key) or the auth screen (if guest fetch
// failed).
//
// The default flow is: app launches → splash → restore() → guest signup →
// chat list. The auth screen is only shown if the guest fetch fails.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../state/auth_state.dart';
import '../../state/openai_server_state.dart';
import '../../core/config/app_config.dart';

class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});
  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await ref.read(authStateProvider.notifier).restore();
      // Restore the OpenAI server if it was running before the last quit.
      // (Native targets only — on Web this is a no-op.)
      await ref.read(openAiServerProvider.notifier).restoreIfEnabled();
      if (!mounted) return;
      final auth = ref.read(authStateProvider);
      if (auth.signedIn) {
        context.go('/');
      } else {
        context.go('/auth');
      }
    });
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
