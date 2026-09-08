// Auth screen — first-run API key entry.
//
// The user pastes their z.ai API key here. We don't validate it via an API
// call (z.ai does not expose a `GET /me` endpoint); instead we just do a
// minimal format check and store it. The first real chat call will
// validate it.

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/config/app_config.dart';
import '../../l10n/generated/app_localizations.dart';
import '../../state/auth_state.dart';

class AuthScreen extends ConsumerStatefulWidget {
  const AuthScreen({super.key});

  @override
  ConsumerState<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends ConsumerState<AuthScreen> {
  final TextEditingController _key = TextEditingController();
  bool _obscure = true;

  @override
  void dispose() {
    _key.dispose();
    super.dispose();
  }

  Future<void> _signIn() async {
    final raw = _key.text.trim();
    final l = AppLocalizations.of(context);
    if (raw.isEmpty) return;
    // Minimal sanity check: z.ai API keys are 30+ characters and don't
    // contain spaces. (Real keys look like `<32hex>.<secret>`.)
    if (raw.contains(' ') || raw.length < 20) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l.authInvalidKey)),
      );
      return;
    }
    await ref.read(authStateProvider.notifier).signInWithKey(raw);
    if (!mounted) return;
    if (ref.read(authStateProvider).signedIn) {
      context.go('/');
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(ref.read(authStateProvider).lastError ?? 'Error')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final auth = ref.watch(authStateProvider);
    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                const Center(
                  child: Icon(Icons.local_florist, size: 56,
                      color: Color(0xFF7C4DFF)),
                ),
                const SizedBox(height: 16),
                Center(
                  child: Text(
                    l.authWelcomeTitle(AppConfig.appName),
                    style: Theme.of(context).textTheme.headlineSmall,
                    textAlign: TextAlign.center,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  l.authWelcomeBody(AppConfig.apiKeyDashboardUrl),
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 24),
                Text(l.authApiKeyLabel),
                const SizedBox(height: 8),
                TextField(
                  controller: _key,
                  obscureText: _obscure,
                  decoration: InputDecoration(
                    hintText: l.authApiKeyHint,
                    suffixIcon: IconButton(
                      icon: Icon(_obscure
                          ? Icons.visibility_outlined
                          : Icons.visibility_off_outlined),
                      onPressed: () => setState(() => _obscure = !_obscure),
                    ),
                  ),
                  onSubmitted: (_) => _signIn(),
                ),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: auth.status == AuthStatus.loading ? null : _signIn,
                  child: auth.status == AuthStatus.loading
                      ? Row(
                          mainAxisSize: MainAxisSize.min,
                          children: <Widget>[
                            const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                            const SizedBox(width: 8),
                            Text(l.authTesting),
                          ],
                        )
                      : Text(l.authSignIn),
                ),
                const SizedBox(height: 24),
                Center(
                  child: RichText(
                    text: TextSpan(
                      style: Theme.of(context).textTheme.bodySmall,
                      children: [
                        TextSpan(text: '${l.authApiKeyCreate}: '),
                        TextSpan(
                          text: AppConfig.apiKeyDashboardUrl,
                          style: const TextStyle(color: Color(0xFF7C4DFF)),
                          recognizer: TapGestureRecognizer()
                            ..onTap = () => launchUrl(
                                Uri.parse(AppConfig.apiKeyDashboardUrl)),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
