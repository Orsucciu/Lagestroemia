// Chat list screen — the home screen. Lists all chats with a search bar
// and lets the user create, rename, archive or delete.
//
// Search filters by title (case-insensitive substring match).

import 'dart:convert' show utf8;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../l10n/generated/app_localizations.dart';
import '../../state/anon_profiles_state.dart';
import '../../state/auth_state.dart' show AuthMode;
import '../../state/chat_state.dart';
import '../../state/providers.dart';
import '../../data/models/models.dart';

/// Search query for the chat list. Empty means "show all".
final chatListSearchProvider = StateProvider<String>((ref) => '');

/// Selected model filter for the chat list. Null means "show all models".
final chatListModelFilterProvider = StateProvider<String?>((ref) => null);

class ChatListScreen extends ConsumerWidget {
  const ChatListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final chatsAsync = ref.watch(chatListProvider);
    final search = ref.watch(chatListSearchProvider);
    final modelFilter = ref.watch(chatListModelFilterProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(l.navChats),
        actions: <Widget>[
          // Continue menu (JSON upload + history)
          PopupMenuButton<String>(
            icon: const Icon(Icons.forward),
            tooltip: 'Continue conversation',
            onSelected: (value) async {
              if (value == 'from_json') {
                final result = await FilePicker.platform.pickFiles(
                  type: FileType.custom,
                  allowedExtensions: ['json'],
                  withData: true,
                );
                if (result == null || result.files.isEmpty) return;
                final bytes = result.files.first.bytes;
                if (bytes == null) return;
                final jsonString = utf8.decode(bytes);
                final chatId = await ref
                    .read(chatComposerProvider.notifier)
                    .continueFromJson(jsonString);
                if (chatId != null && context.mounted) {
                  context.go('/chat/$chatId');
                } else {
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                        content: Text('Failed to import conversation.')),
                  );
                }
              } else if (value == 'from_history') {
                final chatId = await showDialog<String>(
                  context: context,
                  builder: (_) => const _ContinueFromHistoryDialog(),
                );
                if (chatId == null) return;
                final newChatId = await ref
                    .read(chatComposerProvider.notifier)
                    .continueFromHistory(chatId);
                if (newChatId != null && context.mounted) {
                  context.go('/chat/$newChatId');
                } else {
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                        content:
                            Text('Failed to continue conversation.')),
                  );
                }
              }
            },
            itemBuilder: (_) => const <PopupMenuEntry<String>>[
              PopupMenuItem(
                value: 'from_history',
                child: Row(
                  children: <Widget>[
                    Icon(Icons.history, size: 18),
                    SizedBox(width: 8),
                    Text('Continue from history'),
                  ],
                ),
              ),
              PopupMenuItem(
                value: 'from_json',
                child: Row(
                  children: <Widget>[
                    Icon(Icons.file_upload_outlined, size: 18),
                    SizedBox(width: 8),
                    Text('Continue from JSON file'),
                  ],
                ),
              ),
            ],
          ),
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: l.chatNew,
            onPressed: () async {
              final chat = await ref
                  .read(chatListProvider.notifier)
                  .createNewChat();
              if (!context.mounted) return;
              context.go('/chat/${chat.id}');
            },
          ),
        ],
      ),
      body: Column(
        children: <Widget>[
          // Anonymous tab switcher (only shown in guest mode).
          const _AnonTabBar(),
          // Model filter tabs — group chats by model.
          chatsAsync.when(
            data: (chats) => _ModelTabBar(chats: chats),
            loading: () => const SizedBox.shrink(),
            error: (_, __) => const SizedBox.shrink(),
          ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              decoration: InputDecoration(
                hintText: l.commonSearch,
                prefixIcon: const Icon(Icons.search),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              onChanged: (value) =>
                  ref.read(chatListSearchProvider.notifier).state = value,
            ),
          ),
          Expanded(
            child: chatsAsync.when(
              data: (chats) {
                // Apply model filter + search filter.
                var filtered = chats;
                if (modelFilter != null) {
                  filtered = filtered
                      .where((c) => (c.model ?? 'default') == modelFilter)
                      .toList(growable: false);
                }
                if (search.isNotEmpty) {
                  filtered = filtered
                      .where((c) => c.title.toLowerCase().contains(
                            search.toLowerCase(),
                          ))
                      .toList(growable: false);
                }
                if (filtered.isEmpty) {
                  return Center(child: Text(l.commonEmpty));
                }
                return ListView.builder(
                  itemCount: filtered.length,
                  itemBuilder: (_, i) {
                    final chat = filtered[i];
                    return _ChatTile(chat: chat);
                  },
                );
              },
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('${l.commonError}: $e')),
            ),
          ),
        ],
      ),
    );
  }
}

/// Horizontal scrollable row of model tabs. Each tab represents a
/// model that has at least one chat. Tapping a tab filters the chat
/// list to that model. The "All" tab shows every chat regardless of
/// model.
class _ModelTabBar extends ConsumerWidget {
  const _ModelTabBar({required this.chats});
  final List<Chat> chats;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selected = ref.watch(chatListModelFilterProvider);
    // Build the list of unique models from the chats.
    final models = <String>{};
    for (final c in chats) {
      models.add(c.model ?? 'default');
    }
    if (models.isEmpty) return const SizedBox.shrink();

    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: <Widget>[
            _ModelTab(
              label: 'All',
              selected: selected == null,
              onTap: () =>
                  ref.read(chatListModelFilterProvider.notifier).state = null,
              theme: theme,
            ),
            for (final m in models) ...<Widget>[
              const SizedBox(width: 4),
              _ModelTab(
                label: m,
                selected: selected == m,
                onTap: () =>
                    ref.read(chatListModelFilterProvider.notifier).state = m,
                theme: theme,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ModelTab extends StatelessWidget {
  const _ModelTab({
    required this.label,
    required this.selected,
    required this.onTap,
    required this.theme,
  });
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected
          ? theme.colorScheme.primaryContainer
          : theme.colorScheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Text(
            label,
            style: theme.textTheme.labelMedium?.copyWith(
              color: selected
                  ? theme.colorScheme.onPrimaryContainer
                  : theme.colorScheme.onSurfaceVariant,
              fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
            ),
          ),
        ),
      ),
    );
  }
}

class _ChatTile extends ConsumerWidget {
  const _ChatTile({required this.chat});
  final Chat chat;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    return ListTile(
      title: Text(chat.title),
      subtitle: Text(chat.updatedAt.toLocal().toString()),
      onTap: () => context.go('/chat/${chat.id}'),
      trailing: PopupMenuButton<String>(
        onSelected: (value) async {
          switch (value) {
            case 'rename':
              await _showRenameDialog(context, ref, chat);
            case 'archive':
              await ref.read(chatListProvider.notifier).archiveChat(chat);
            case 'delete':
              final confirmed = await _confirm(context, l.commonConfirmDelete);
              if (confirmed) {
                await ref.read(chatListProvider.notifier).deleteChat(chat.id);
              }
          }
        },
        itemBuilder: (_) => <PopupMenuEntry<String>>[
          PopupMenuItem(value: 'rename', child: Text(l.commonRename)),
          PopupMenuItem(value: 'archive', child: Text(l.libraryChatsArchived)),
          PopupMenuItem(value: 'delete', child: Text(l.commonDelete)),
        ],
      ),
    );
  }

  Future<void> _showRenameDialog(
      BuildContext context, WidgetRef ref, Chat chat) async {
    final controller = TextEditingController(text: chat.title);
    final result = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(AppLocalizations.of(context).commonRename),
        content: TextField(controller: controller, autofocus: true),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(AppLocalizations.of(context).commonCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: Text(AppLocalizations.of(context).commonSave),
          ),
        ],
      ),
    );
    if (result != null && result.isNotEmpty) {
      await ref.read(chatListProvider.notifier).renameChat(chat, result);
    }
  }

  Future<bool> _confirm(BuildContext context, String message) async {
    final l = AppLocalizations.of(context);
    final r = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(l.commonNo),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(l.commonYes),
          ),
        ],
      ),
    );
    return r ?? false;
  }
}

/// Anonymous tab switcher bar. Shows horizontal scrollable row of tabs.
class _AnonTabBar extends ConsumerWidget {
  const _AnonTabBar();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final anonProfiles = ref.watch(anonProfilesProvider);
    final auth = ref.watch(authStateProvider);

    // Only show in guest mode with at least 1 profile.
    if (auth.mode != AuthMode.guest || anonProfiles.profiles.isEmpty) {
      return const SizedBox.shrink();
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Row(
        children: <Widget>[
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: <Widget>[
                  for (final p in anonProfiles.profiles)
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: FilterChip(
                        label: Text(p.label),
                        selected: p.id == anonProfiles.activeId,
                        onSelected: (_) async {
                          await ref
                              .read(anonProfilesProvider.notifier)
                              .setActive(p.id);
                          ref.invalidate(chatListProvider);
                        },
                        onDeleted: p.id == anonProfiles.activeId &&
                                anonProfiles.profiles.length > 1
                            ? () async {
                                await ref
                                    .read(anonProfilesProvider.notifier)
                                    .delete(p.id);
                                ref.invalidate(chatListProvider);
                              }
                            : null,
                      ),
                    ),
                ],
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.add_circle_outline, size: 20),
            tooltip: 'New anonymous tab',
            onPressed: () async {
              await ref.read(anonProfilesProvider.notifier).createNew();
              ref.invalidate(chatListProvider);
            },
          ),
        ],
      ),
    );
  }
}

/// Dialog that lists ALL past conversations from the SQLite history
/// (across all profiles) so the user can pick one to continue in a
/// fresh anonymous chat.
class _ContinueFromHistoryDialog extends ConsumerWidget {
  const _ContinueFromHistoryDialog();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final allChatsAsync = ref.watch(allChatsForHistoryProvider);
    return AlertDialog(
      title: const Text('Continue from history'),
      content: SizedBox(
        width: 500,
        child: allChatsAsync.when(
          data: (chats) {
            if (chats.isEmpty) {
              return const Center(
                child: Text('No past conversations found.'),
              );
            }
            return ListView.builder(
              shrinkWrap: true,
              itemCount: chats.length,
              itemBuilder: (context, i) {
                final chat = chats[i];
                return ListTile(
                  leading: const Icon(Icons.chat_bubble_outline, size: 18),
                  title: Text(
                    chat.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text(
                    '${chat.model ?? "default"} \u00b7 '
                    '${chat.updatedAt.toLocal().toString().substring(0, 16)}'
                    '${chat.profileId != null ? " \u00b7 Tab ${chat.profileId!.substring(0, 6)}" : ""}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  onTap: () => Navigator.of(context).pop(chat.id),
                );
              },
            );
          },
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(child: Text('Error: $e')),
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
      ],
    );
  }
}
