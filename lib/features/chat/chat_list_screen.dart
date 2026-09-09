// Chat list screen — the home screen. Lists all chats with a search bar
// and lets the user create, rename, archive or delete.
//
// Search filters by title (case-insensitive substring match).

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../l10n/generated/app_localizations.dart';
import '../../state/chat_state.dart';
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
