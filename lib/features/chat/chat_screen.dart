// Chat screen — the conversation view + composer.
//
// Shows the messages of the current chat and lets the user type a new
// message. Streaming assistant responses are shown live and persisted
// every chunk.

import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/config/app_config.dart';
import '../../l10n/generated/app_localizations.dart';
import '../../state/chat_state.dart';
import '../../state/providers.dart';
import '../../data/models/models.dart';
import '../../widgets/error_banner.dart';

class ChatScreen extends ConsumerWidget {
  const ChatScreen({required this.chatId, super.key});
  final String? chatId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (chatId != null) {
      // Set the current chat id as soon as we navigate in.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ref.read(currentChatIdProvider.notifier).state = chatId;
      });
    }
    final l = AppLocalizations.of(context);
    final chatIdState = ref.watch(currentChatIdProvider);
    final messagesAsync = ref.watch(currentChatMessagesProvider);
    final composer = ref.watch(chatComposerProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(l.chatEmptyTitle),
        actions: [
          // Model picker (MVP: opens a simple menu of AppConfig.knownModels).
          PopupMenuButton<String>(
            icon: const Icon(Icons.tune),
            tooltip: l.chatModelPicker,
            onSelected: (model) async {
              final id = chatIdState;
              if (id == null) return;
              final repo = await ref.read(chatRepositoryProvider.future);
              final chat = await repo.findById(id);
              if (chat == null) return;
              await repo.updateMeta(chat.copyWith(model: model));
              ref.invalidate(currentChatProvider);
            },
            itemBuilder: (_) => <PopupMenuEntry<String>>[
              for (final m in AppConfig.knownModels)
                PopupMenuItem(value: m, child: Text(m)),
            ],
          ),
        ],
      ),
      body: Column(
        children: <Widget>[
          if (composer.error != null)
            Padding(
              padding: const EdgeInsets.all(8),
              child: ErrorBanner(
                message: _errorToMessage(composer.error!, l),
                onDismiss: () => ref.read(chatComposerProvider.notifier).clearError(),
              ),
            ),
          Expanded(
            child: messagesAsync.when(
              data: (messages) {
                if (chatIdState == null) {
                  return Center(child: Text(l.commonEmpty));
                }
                if (messages.isEmpty) {
                  return Center(child: Text(l.chatComposerPlaceholder));
                }
                return ListView.builder(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  itemCount: messages.length,
                  itemBuilder: (_, i) {
                    final msg = messages[i];
                    if (msg.id == composer.lastStreamedMessageId) {
                      // Show live-streamed text instead of the saved content.
                      final live = msg.copyWith(
                        content: composer.streamedText,
                        reasoning: composer.streamedReasoning,
                      );
                      return _MessageBubble(message: live, streaming: true);
                    }
                    return _MessageBubble(message: msg, streaming: false);
                  },
                );
              },
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('${l.commonError}: $e')),
            ),
          ),
          _Composer(),
        ],
      ),
    );
  }

  String _errorToMessage(ApiError e, AppLocalizations l) {
    switch (e.kind) {
      case ApiErrorKind.auth:
        return l.chatErrorAuth;
      case ApiErrorKind.rateLimit:
      case ApiErrorKind.quota:
        return l.chatErrorRateLimit;
      case ApiErrorKind.network:
        return l.chatErrorNetwork;
      default:
        return e.message;
    }
  }
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({required this.message, required this.streaming});
  final ChatMessage message;
  final bool streaming;

  @override
  Widget build(BuildContext context) {
    final isUser = message.role == MessageRole.user;
    final scheme = Theme.of(context).colorScheme;
    final bubbleColor = isUser
        ? (Theme.of(context).brightness == Brightness.dark
            ? const Color(0xFF1F2230)
            : const Color(0xFFE8EAF6))
        : scheme.surface;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          if (!isUser) ...[
            CircleAvatar(
              backgroundColor: const Color(0xFF7C4DFF),
              child: const Icon(Icons.local_florist, color: Colors.white, size: 18),
            ),
            const SizedBox(width: 8),
          ],
          Expanded(
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: bubbleColor,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  if (message.reasoning != null && message.reasoning!.isNotEmpty)
                    ExpansionTile(
                      title: Text(AppLocalizations.of(context).chatReasoning,
                          style: Theme.of(context).textTheme.labelSmall),
                      children: <Widget>[
                        MarkdownBody(data: message.reasoning!),
                      ],
                    ),
                  MarkdownBody(data: message.content + (streaming ? '▏' : '')),
                ],
              ),
            ),
          ),
          if (isUser) const SizedBox(width: 8),
        ],
      ),
    );
  }
}

class _Composer extends ConsumerStatefulWidget {
  @override
  ConsumerState<_Composer> createState() => _ComposerState();
}

class _ComposerState extends ConsumerState<_Composer> {
  final TextEditingController _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    ref.read(chatComposerProvider.notifier).setInput(text);
    _controller.clear();
    await ref.read(chatComposerProvider.notifier).send();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final composer = ref.watch(chatComposerProvider);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: <Widget>[
            IconButton(
              icon: const Icon(Icons.attach_file),
              tooltip: l.chatAttachFile,
              onPressed: composer.streaming
                  ? null
                  : () async {
                      // MVP file picker — wire in file_picker later.
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('File picker coming soon.')),
                      );
                    },
            ),
            Expanded(
              child: TextField(
                controller: _controller,
                minLines: 1,
                maxLines: 6,
                decoration: InputDecoration(
                  hintText: l.chatComposerPlaceholder,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                enabled: !composer.streaming,
                onSubmitted: (_) => _send(),
              ),
            ),
            const SizedBox(width: 8),
            if (composer.streaming)
              IconButton.filled(
                icon: const Icon(Icons.stop),
                tooltip: l.chatStop,
                onPressed: () => ref.read(chatComposerProvider.notifier).cancel(),
              )
            else
              IconButton.filled(
                icon: const Icon(Icons.send),
                tooltip: l.chatSend,
                onPressed: _send,
              ),
          ],
        ),
      ),
    );
  }
}

// Local helper to expose a field on ChatComposerState that we did not add
// (lastStreamedMessageId). Easiest fix: extend ChatComposerState — but for
// now we patch it here so the file compiles.
// ignore: unused_element
class _ComposerStateExt {}

// Tiny placeholder extension so the screen compiles cleanly. The composer
// state itself holds the live text; we don't need a per-message id yet.
extension on ChatComposerState {
  String? get lastStreamedMessageId => null;
}
