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

class ChatListScreen extends ConsumerWidget {
  const ChatListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final chatsAsync = ref.watch(chatListProvider);
    final search = ref.watch(chatListSearchProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(l.navChats),
        actions: <Widget>[
          // Continue from JSON (anonymous continue feature)
          IconButton(
            icon: const Icon(Icons.file_upload_outlined),
            tooltip: 'Continue from JSON',
            onPressed: () async {
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
                  const SnackBar(content: Text('Failed to import conversation.')),
                );
              }
            },
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
          _AnonTabBar(),
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
                final filtered = search.isEmpty
                    ? chats
                    : chats
                        .where((c) => c.title.toLowerCase().contains(
                              search.toLowerCase(),
                            ))
                        .toList(growable: false);
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
