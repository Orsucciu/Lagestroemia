// Settings screen — account + appearance + language + about.
//
// Supports both guest mode and API-key mode (the auth state can be in
// either mode; this screen lets the user switch).
//
// In API-key mode, additional sections appear:
//   - JWT auth mode toggle (issue #8): for keys in <id>.<secret> form,
//     lets the user switch from raw-key Bearer to short-lived signed
//     JWT Bearer.
//   - Multi-account switcher (issue #12): list all accounts, add / switch
//     / delete.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/config/app_config.dart';
import '../../core/platform/platform_info.dart';
import '../../data/models/models.dart';
import '../../l10n/generated/app_localizations.dart';
import '../../state/auth_state.dart';
import '../../state/providers.dart';
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
            title: const Text('Mode'),
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
            // JWT auth mode toggle (issue #8). Only shown when the API
            // key is in <id>.<secret> form.
            if (auth.apiKeyParts != null) ...<Widget>[
              const Divider(),
              SwitchListTile(
                secondary: const Icon(Icons.verified_user_outlined),
                title: const Text('JWT auth mode'),
                subtitle: const Text(
                    'Sign a short-lived JWT (1h) using the secret '
                    'half of your API key, instead of sending the raw '
                    'key as Bearer. Matches z.ai\'s recommended flow '
                    'for higher security.'),
                value: auth.useJwtAuth,
                onChanged: (value) => ref
                    .read(authStateProvider.notifier)
                    .setUseJwtAuth(value),
              ),
            ],
            // Multi-account switcher (issue #12).
            const Divider(),
            _AccountsSection(),
          ],
          if (auth.mode == AuthMode.guest) ...<Widget>[
            ListTile(
              leading: const Icon(Icons.refresh),
              title: const Text('Refresh guest session'),
              subtitle: Text(
                'Guest: ${auth.guestUserId ?? "—"}',
              ),
              onTap: () =>
                  ref.read(authStateProvider.notifier).refreshGuestToken(),
            ),
          ],
          if (PlatformInfo.isWeb)
            ListTile(
              leading: const Icon(Icons.warning_amber),
              title: const Text('Web storage notice'),
              subtitle: const Text(
                'On the Web target, your API key (if you switch to '
                'API-key mode) is stored in browser-local storage '
                'without at-rest encryption.',
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

/// Multi-account section: shows the list of all accounts, the
/// currently-active one, and lets the user add / switch to / delete
/// accounts.
class _AccountsSection extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final accountsAsync = ref.watch(_allAccountsProvider);
    final auth = ref.watch(authStateProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
          child: Text(
            'Accounts',
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: Theme.of(context).colorScheme.primary,
                ),
          ),
        ),
        accountsAsync.when(
          data: (accounts) {
            return Column(
              children: <Widget>[
                for (final a in accounts)
                  ListTile(
                    leading: Icon(
                      a.id == auth.accountId
                          ? Icons.check_circle
                          : Icons.person_outline,
                      color: a.id == auth.accountId
                          ? Theme.of(context).colorScheme.primary
                          : null,
                    ),
                    title: Text(a.label),
                    subtitle:
                        Text('${a.id} · ${_formatLastUsed(a.lastUsedAt)}'),
                    trailing: a.id == 'default'
                        ? null
                        : IconButton(
                            icon: const Icon(Icons.delete_outline),
                            tooltip: 'Delete account',
                            onPressed: () async {
                              final confirmed = await showDialog<bool>(
                                context: context,
                                builder: (_) => AlertDialog(
                                  content: Text(
                                      'Delete account "${a.label}" and wipe its API key?'),
                                  actions: [
                                    TextButton(
                                      onPressed: () =>
                                          Navigator.pop(context, false),
                                      child: const Text('Cancel'),
                                    ),
                                    FilledButton(
                                      onPressed: () =>
                                          Navigator.pop(context, true),
                                      child: const Text('Delete'),
                                    ),
                                  ],
                                ),
                              );
                              if (confirmed ?? false) {
                                await ref
                                    .read(authStateProvider.notifier)
                                    .deleteAccount(a.id);
                                ref.invalidate(_allAccountsProvider);
                              }
                            },
                          ),
                    onTap: a.id == auth.accountId
                        ? null
                        : () async {
                            final ok = await ref
                                .read(authStateProvider.notifier)
                                .switchToAccount(a.id);
                            if (!ok) {
                              if (!context.mounted) return;
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text(
                                      'Could not switch account — no API key stored.'),
                                ),
                              );
                            }
                            ref.invalidate(_allAccountsProvider);
                          },
                  ),
                ListTile(
                  leading: const Icon(Icons.add),
                  title: const Text('Add account'),
                  onTap: () async {
                    final result = await showDialog<_AddAccountResult>(
                      context: context,
                      builder: (_) => const _AddAccountDialog(),
                    );
                    if (result == null) return;
                    final ok = await ref
                        .read(authStateProvider.notifier)
                        .addAccount(
                          id: result.id,
                          label: result.label,
                          apiKey: result.apiKey,
                        );
                    if (!ok) {
                      if (!context.mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text(
                              'Account with that id already exists or the database is not ready.'),
                        ),
                      );
                    }
                    ref.invalidate(_allAccountsProvider);
                  },
                ),
              ],
            );
          },
          loading: () => const Padding(
            padding: EdgeInsets.all(16),
            child: Center(child: CircularProgressIndicator()),
          ),
          error: (e, _) => Padding(
            padding: const EdgeInsets.all(16),
            child: Text('Error: $e'),
          ),
        ),
      ],
    );
  }

  String _formatLastUsed(DateTime? t) {
    if (t == null) return 'never used';
    final delta = DateTime.now().toUtc().difference(t);
    if (delta.inMinutes < 1) return 'just now';
    if (delta.inHours < 1) return '${delta.inMinutes}m ago';
    if (delta.inDays < 1) return '${delta.inHours}h ago';
    return '${delta.inDays}d ago';
  }
}

class _AddAccountResult {
  const _AddAccountResult({
    required this.id,
    required this.label,
    required this.apiKey,
  });
  final String id;
  final String label;
  final String apiKey;
}

class _AddAccountDialog extends StatefulWidget {
  const _AddAccountDialog();
  @override
  State<_AddAccountDialog> createState() => _AddAccountDialogState();
}

class _AddAccountDialogState extends State<_AddAccountDialog> {
  final _idCtrl = TextEditingController();
  final _labelCtrl = TextEditingController();
  final _keyCtrl = TextEditingController();
  bool _obscure = true;

  @override
  void dispose() {
    _idCtrl.dispose();
    _labelCtrl.dispose();
    _keyCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Add account'),
      content: SizedBox(
        width: 400,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            TextField(
              controller: _idCtrl,
              decoration: const InputDecoration(
                labelText: 'Account id (unique)',
                hintText: 'work, test, personal, ...',
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _labelCtrl,
              decoration: const InputDecoration(
                labelText: 'Label (display name)',
                hintText: 'Work account, Test account, ...',
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _keyCtrl,
              obscureText: _obscure,
              decoration: InputDecoration(
                labelText: 'API key',
                suffixIcon: IconButton(
                  icon: Icon(_obscure
                      ? Icons.visibility_outlined
                      : Icons.visibility_off_outlined),
                  onPressed: () => setState(() => _obscure = !_obscure),
                ),
              ),
            ),
          ],
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            final id = _idCtrl.text.trim();
            final label = _labelCtrl.text.trim();
            final key = _keyCtrl.text.trim();
            if (id.isEmpty || label.isEmpty || key.isEmpty) return;
            Navigator.pop(context,
                _AddAccountResult(id: id, label: label, apiKey: key));
          },
          child: const Text('Add'),
        ),
      ],
    );
  }
}

/// Provides the list of all accounts for the switcher UI.
final _allAccountsProvider = FutureProvider<List<Account>>((ref) async {
  final repo = await ref.watch(accountRepositoryProvider.future);
  return repo.listAll();
});
