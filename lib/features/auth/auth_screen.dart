// Auth screen — first-run API key entry OR "continue as guest" button.
//
// In guest mode the app automatically fetches a guest JWT from
// chat.z.ai/api/v1/auths/ — no user interaction needed. The auth screen
// is only shown if:
//   - the guest fetch fails (network error, chat.z.ai down),
//   - the user explicitly signs out of API-key mode,
//   - the user opens Settings → Account → Switch to API-key mode.
//
// The auth screen offers two paths:
//   1. "Continue as guest" — re-attempts the guest fetch.
//   2. "Paste API key" — switches to API-key mode.

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/config/app_config.dart';
import '../../core/platform/platform_info.dart';
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
  bool _showKeyEntry = false;

  @override
  void dispose() {
    _key.dispose();
    super.dispose();
  }

  Future<void> _continueAsGuest() async {
    await ref.read(authStateProvider.notifier).continueAsGuest();
    if (!mounted) return;
    if (ref.read(authStateProvider).signedIn) {
      context.go('/');
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            ref.read(authStateProvider).lastError ??
                'Could not reach chat.z.ai for guest signup. Check your network.',
          ),
        ),
      );
    }
  }

  Future<void> _signInWithKey() async {
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
        SnackBar(
          content: Text(ref.read(authStateProvider).lastError ?? 'Error'),
        ),
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
                  child: Icon(Icons.local_florist,
                      size: 56, color: Color(0xFF7C4DFF)),
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
                if (PlatformInfo.isWeb)
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.errorContainer,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: <Widget>[
                        const Icon(Icons.warning_amber),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'On the Web target, your API key is stored in '
                            'browser-local storage without at-rest encryption. '
                            'Use guest mode on shared devices.',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ),
                      ],
                    ),
                  ),
                if (PlatformInfo.isWeb) const SizedBox(height: 16),

                // Primary action: "Continue as guest" — the same path the
                // website itself uses.
                FilledButton.icon(
                  onPressed: auth.status == AuthStatus.loading
                      ? null
                      : _continueAsGuest,
                  icon: const Icon(Icons.person_outline),
                  label: auth.status == AuthStatus.loading
                      ? Row(
                          mainAxisSize: MainAxisSize.min,
                          children: <Widget>[
                            const SizedBox(
                              width: 16,
                              height: 16,
                              child:
                                  CircularProgressIndicator(strokeWidth: 2),
                            ),
                            const SizedBox(width: 8),
                            Text(l.authTesting),
                          ],
                        )
                      : const Text('Continue as guest (free)'),
                ),
                const SizedBox(height: 12),

                // Toggle for the API key entry section.
                TextButton(
                  onPressed: () =>
                      setState(() => _showKeyEntry = !_showKeyEntry),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Icon(_showKeyEntry
                          ? Icons.expand_less
                          : Icons.expand_more),
                      const SizedBox(width: 4),
                      Text(_showKeyEntry
                          ? 'Hide API key entry'
                          : 'I have a z.ai API key'),
                    ],
                  ),
                ),
                if (_showKeyEntry) ...<Widget>[
                  const SizedBox(height: 8),
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
                        onPressed: () =>
                            setState(() => _obscure = !_obscure),
                      ),
                    ),
                    onSubmitted: (_) => _signInWithKey(),
                  ),
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: auth.status == AuthStatus.loading
                        ? null
                        : _signInWithKey,
                    child: Text(l.authSignIn),
                  ),
                ],

                const SizedBox(height: 24),
                Center(
                  child: RichText(
                    text: TextSpan(
                      style: Theme.of(context).textTheme.bodySmall,
                      children: <InlineSpan>[
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
