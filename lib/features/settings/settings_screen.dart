// Settings screen — account + appearance + language + about.
//
// Updated to support both guest mode and API-key mode (the auth state can
// be in either mode; this screen lets the user switch).

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/config/app_config.dart';
import '../../core/platform/platform_info.dart';
import '../../l10n/generated/app_localizations.dart';
import '../../state/auth_state.dart';
import '../../state/settings_state.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final settings = ref.watch(settingsStateProvider);
    final auth = ref.watch(authStateProvider);

    return Scaffold(
      appBar: AppBar(title: Text(l.navSettings)),
      body: ListView(
        children: <Widget>[
          _SectionHeader(l.settingsAccountSection),
          // Auth mode row
          ListTile(
            leading: Icon(auth.mode == AuthMode.guest
                ? Icons.person_outline
                : Icons.key),
            title: Text('Mode'),
            subtitle: Text(auth.mode == AuthMode.guest
                ? 'Guest (free, captcha per session)'
                : 'API key (paid, no captcha)'),
            trailing: auth.mode == AuthMode.guest
                ? FilledButton.tonal(
                    onPressed: () => context.go('/auth'),
                    child: const Text('Switch to API key'),
                  )
                : null,
          ),
          if (auth.mode == AuthMode.apiKey) ...<Widget>[
            ListTile(
              leading: const Icon(Icons.key),
              title: Text(l.settingsAccountKey),
              subtitle: Text(auth.signedIn
                  ? '${auth.apiKey!.substring(0, 8)}…${auth.apiKey!.substring(auth.apiKey!.length - 4)}'
                  : '—'),
              trailing: OutlinedButton(
                onPressed: () async {
                  final confirmed = await showDialog<bool>(
                    context: context,
                    builder: (_) => AlertDialog(
                      content: Text(l.authSignOut),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(context, false),
                          child: Text(l.commonCancel),
                        ),
                        FilledButton(
                          onPressed: () => Navigator.pop(context, true),
                          child: Text(l.commonOk),
                        ),
                      ],
                    ),
                  );
                  if (confirmed ?? false) {
                    await ref.read(authStateProvider.notifier).signOut();
                  }
                },
                child: Text(l.authSignOut),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.link),
              title: Text(l.authApiKeyCreate),
              subtitle: Text(AppConfig.apiKeyDashboardUrl),
              onTap: () => launchUrl(Uri.parse(AppConfig.apiKeyDashboardUrl)),
            ),
            ListTile(
              leading: const Icon(Icons.link),
              title: Text(l.settingsRateLimits),
              subtitle: Text(AppConfig.rateLimitsUrl),
              onTap: () => launchUrl(Uri.parse(AppConfig.rateLimitsUrl)),
            ),
            ListTile(
              leading: const Icon(Icons.dns),
              title: Text(l.settingsApiBaseUrl),
              subtitle: Text(settings.apiBaseUrl),
              trailing: OutlinedButton(
                onPressed: settings.apiBaseUrl == AppConfig.defaultApiBaseUrl
                    ? null
                    : () => ref
                        .read(settingsStateProvider.notifier)
                        .setApiBaseUrl(AppConfig.defaultApiBaseUrl),
                child: Text(l.settingsApiBaseUrlReset),
              ),
            ),
          ],
          if (auth.mode == AuthMode.guest) ...<Widget>[
            ListTile(
              leading: const Icon(Icons.refresh),
              title: const Text('Refresh guest session'),
              subtitle: Text(
                'Guest: ${auth.guestUserId ?? "—"}',
              ),
              onTap: () => ref.read(authStateProvider.notifier).refreshGuestToken(),
            ),
          ],
          if (PlatformInfo.isWeb)
            ListTile(
              leading: const Icon(Icons.warning_amber),
              title: const Text('Web storage notice'),
              subtitle: const Text(
                'On the Web target, your API key (if you switch to API-key '
                'mode) is stored in browser-local storage without at-rest '
                'encryption.',
              ),
            ),

          _SectionHeader(l.settingsAppearanceSection),
          ListTile(
            leading: const Icon(Icons.brightness_6),
            title: Text(l.settingsTheme),
            trailing: DropdownButton<ThemeMode>(
              value: settings.themeMode,
              items: <DropdownMenuItem<ThemeMode>>[
                DropdownMenuItem(
                  value: ThemeMode.system,
                  child: Text(l.settingsThemeSystem),
                ),
                DropdownMenuItem(
                  value: ThemeMode.light,
                  child: Text(l.settingsThemeLight),
                ),
                DropdownMenuItem(
                  value: ThemeMode.dark,
                  child: Text(l.settingsThemeDark),
                ),
              ],
              onChanged: (m) {
                if (m != null) {
                  ref.read(settingsStateProvider.notifier).setThemeMode(m);
                }
              },
            ),
          ),

          _SectionHeader(l.settingsLanguageSection),
          ListTile(
            leading: const Icon(Icons.language),
            title: Text(l.settingsLanguageEn),
            trailing: Radio<String?>(
              groupValue: settings.localeTag,
              value: 'en',
              onChanged: (v) =>
                  ref.read(settingsStateProvider.notifier).setLocale(v),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.language),
            title: Text(l.settingsLanguageZh),
            trailing: Radio<String?>(
              groupValue: settings.localeTag,
              value: 'zh',
              onChanged: (v) =>
                  ref.read(settingsStateProvider.notifier).setLocale(v),
            ),
          ),

          _SectionHeader(l.settingsAboutSection),
          ListTile(
            leading: const Icon(Icons.info_outline),
            title: Text(l.settingsVersion),
            subtitle: const Text(AppConfig.appVersion),
          ),
          ListTile(
            leading: const Icon(Icons.book),
            title: Text(l.settingsDocsLink),
            subtitle: const Text(AppConfig.docsUrl),
            onTap: () => launchUrl(Uri.parse(AppConfig.docsUrl)),
          ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.title);
  final String title;
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Text(
        title,
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: Theme.of(context).colorScheme.primary,
            ),
      ),
    );
  }
}
