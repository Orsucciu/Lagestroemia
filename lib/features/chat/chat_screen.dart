// Chat screen — the conversation view + composer.
//
// Shows the messages of the current chat and lets the user type a new
// message. Streaming assistant responses are shown live and persisted
// every chunk.

import 'dart:convert';
import 'dart:io' show File;
import 'dart:typed_data' show Uint8List;

import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';

import '../../core/config/app_config.dart';
import '../../l10n/generated/app_localizations.dart';
import '../../state/auth_state.dart';
import '../../state/chat_state.dart';
import '../../state/providers.dart';
import '../../data/models/models.dart';
import '../../widgets/aliyun_captcha_widget.dart';
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
    final auth = ref.watch(authStateProvider);
    final chatIdState = ref.watch(currentChatIdProvider);
    final messagesAsync = ref.watch(currentChatMessagesProvider);
    final composer = ref.watch(chatComposerProvider);
    final currentChat = ref.watch(currentChatProvider);

    // The model list depends on the auth mode (different backends expose
    // different models).
    final knownModels = auth.mode == AuthMode.guest
        ? AppConfig.chatZaiKnownModels
        : AppConfig.knownModels;

    final scrollController = ScrollController();
    return Scaffold(
      appBar: AppBar(
        title: Text(currentChat.valueOrNull?.title ?? l.chatEmptyTitle),
        actions: <Widget>[
          // Model picker
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
              for (final m in knownModels)
                PopupMenuItem(
                  value: m,
                  child: Row(
                    children: <Widget>[
                      Expanded(child: Text(m)),
                      if (AppConfig.isChatZaiAgentModel(m) &&
                          auth.mode == AuthMode.guest)
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color:
                                Theme.of(context).colorScheme.primaryContainer,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            'agent',
                            style: Theme.of(context).textTheme.labelSmall,
                          ),
                        ),
                      if (AppConfig.isApiZaiAgentModel(m) &&
                          auth.mode == AuthMode.apiKey)
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color:
                                Theme.of(context).colorScheme.primaryContainer,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            'agent',
                            style: Theme.of(context).textTheme.labelSmall,
                          ),
                        ),
                    ],
                  ),
                ),
            ],
          ),
          // Per-chat system prompt picker (issue #4)
          Consumer(builder: (context, ref2, _) {
            final promptsAsync = ref2.watch(_allPromptsForPickerProvider);
            return PopupMenuButton<String>(
              icon: const Icon(Icons.badge_outlined),
              tooltip: l.chatSystemPrompt,
              onSelected: (promptId) async {
                final id = chatIdState;
                if (id == null) return;
                final repo = await ref.read(chatRepositoryProvider.future);
                final chat = await repo.findById(id);
                if (chat == null) return;
                await repo.updateMeta(
                  chat.copyWith(
                      systemPromptId:
                          promptId == 'none' ? null : promptId),
                );
                ref.invalidate(currentChatProvider);
              },
              itemBuilder: (_) => <PopupMenuEntry<String>>[
                const PopupMenuItem(value: 'none', child: Text('— none —')),
                ...?promptsAsync.valueOrNull?.map(
                  (p) => PopupMenuItem(value: p.id, child: Text(p.name)),
                ),
              ],
            );
          }),
          // Export chat menu (issue #10)
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert),
            onSelected: (value) async {
              if (value == 'export_md') {
                await _exportChat(context, ref, chatIdState, asMarkdown: true);
              } else if (value == 'export_json') {
                await _exportChat(context, ref, chatIdState, asMarkdown: false);
              }
            },
            itemBuilder: (_) => <PopupMenuEntry<String>>[
              const PopupMenuItem(value: 'export_md', child: Text('Export as Markdown')),
              const PopupMenuItem(value: 'export_json', child: Text('Export as JSON')),
            ],
          ),
        ],
      ),
      body: Column(
        children: <Widget>[
          // Auth mode banner
          if (auth.mode == AuthMode.guest)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              child: Row(
                children: <Widget>[
                  const Icon(Icons.person_outline, size: 16),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Guest mode — free, captcha required per session',
                      style: Theme.of(context).textTheme.labelSmall,
                    ),
                  ),
                ],
              ),
            ),
          if (composer.error != null)
            Padding(
              padding: const EdgeInsets.all(8),
              child: ErrorBanner(
                message: _errorToMessage(composer.error!, l),
                onDismiss: () =>
                    ref.read(chatComposerProvider.notifier).clearError(),
              ),
            ),
          // Captcha-required prompt
          if (composer.captchaRequired)
            Padding(
              padding: const EdgeInsets.all(12),
              child: _CaptchaPrompt(
                onSolved: (param) async {
                  await ref
                      .read(chatComposerProvider.notifier)
                      .setCaptchaAndRetry(param);
                },
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
                  controller: scrollController,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  itemCount: messages.length,
                  itemBuilder: (_, i) {
                    final msg = messages[i];
                    return _MessageBubble(
                      message: msg,
                      streaming: false,
                    );
                  },
                );
              },
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('${l.commonError}: $e')),
            ),
          ),
          _Composer(scrollController: scrollController),
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

  Future<void> _exportChat(
    BuildContext context,
    WidgetRef ref,
    String? chatId, {
    required bool asMarkdown,
  }) async {
    if (chatId == null) return;
    final msgRepo = await ref.read(messageRepositoryProvider.future);
    final chatRepo = await ref.read(chatRepositoryProvider.future);
    final chat = await chatRepo.findById(chatId);
    if (chat == null) return;
    final messages = await msgRepo.listForChat(chatId);

    final String content;
    final String ext;
    if (asMarkdown) {
      ext = 'md';
      final buf = StringBuffer('# ${chat.title}\n\n');
      for (final m in messages) {
        buf.write('### ${m.role.wire}\n\n');
        if (m.reasoning != null && m.reasoning!.isNotEmpty) {
          buf.write('> **Reasoning:**\n> ${m.reasoning}\n\n');
        }
        buf.write('${m.content}\n\n');
      }
      content = buf.toString();
    } else {
      ext = 'json';
      final list = <Map<String, Object?>>[
        for (final m in messages)
          <String, Object?>{
            'role': m.role.wire,
            'content': m.content,
            if (m.reasoning != null) 'reasoning': m.reasoning,
            'created_at': m.createdAt.toIso8601String(),
          },
      ];
      content = const JsonEncoder.withIndent('  ').convert(list);
    }

    final filename = '${chat.title.replaceAll(RegExp(r'[^\w-]'), '_')}.$ext';
    final saveResult = await FilePicker.platform.saveFile(
      dialogTitle: 'Export chat',
      fileName: filename,
      bytes: Uint8List.fromList(utf8.encode(content)),
    );
    // On desktop, saveFile returns a path; we need to write the file.
    // On web, the bytes were already saved by FilePicker.
    if (saveResult != null && saveResult.isNotEmpty) {
      try {
        await File(saveResult).writeAsBytes(utf8.encode(content));
      } catch (_) {
        // May be bytes-only on web; ignore.
      }
    }
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Exported $filename')),
    );
  }
}

final _allPromptsForPickerProvider = FutureProvider<List<SystemPrompt>>((ref) async {
  final repo = await ref.watch(systemPromptRepositoryProvider.future);
  return repo.listAll();
});

class _CaptchaPrompt extends StatelessWidget {
  const _CaptchaPrompt({required this.onSolved});
  final ValueChanged<String> onSolved;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: <Widget>[
          const Icon(Icons.verified_user_outlined),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Verification required — solve the captcha to send.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
          const SizedBox(width: 8),
          FilledButton(
            onPressed: () async {
              final param = await showDialog<Object?>(
                context: context,
                builder: (_) => const CaptchaDialog(),
              );
              if (param is String && param.isNotEmpty) {
                onSolved(param);
              }
            },
            child: const Text('Solve captcha'),
          ),
        ],
      ),
    );
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
          if (!isUser) ...<Widget>[
            const CircleAvatar(
              backgroundColor: Color(0xFF7C4DFF),
              child: Icon(Icons.local_florist, color: Colors.white, size: 18),
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
                  // Render inline image attachments (issue #5)
                  if (message.contentJson != null)
                    ..._buildInlineAttachments(message.contentJson!),

                  if (message.reasoning != null &&
                      message.reasoning!.isNotEmpty)
                    ExpansionTile(
                      title: Text(AppLocalizations.of(context).chatReasoning,
                          style: Theme.of(context).textTheme.labelSmall),
                      children: <Widget>[
                        MarkdownBody(data: message.reasoning!),
                      ],
                    ),

                  // Render tool calls (issue #11)
                  if (message.toolCalls != null &&
                      message.toolCalls!.isNotEmpty)
                    _ToolCallsView(toolCallsJson: message.toolCalls!),

                  MarkdownBody(
                      data: message.content + (streaming ? '▏' : '')),
                ],
              ),
            ),
          ),
          if (isUser) const SizedBox(width: 8),
        ],
      ),
    );
  }

  List<Widget> _buildInlineAttachments(String contentJson) {
    try {
      final list = jsonDecode(contentJson);
      if (list is! List) return const <Widget>[];
      return <Widget>[
        for (final entry in list)
          if (entry is Map)
            () {
              final type = entry['type'];
              if (type == 'image_url') {
                final url = (entry['image_url'] as Map?)?['url'] as String?;
                if (url == null) return const SizedBox.shrink();
                final data = _extractBase64(url);
                if (data == null) return const SizedBox.shrink();
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Image.memory(
                    data,
                    width: 200,
                    fit: BoxFit.contain,
                  ),
                );
              }
              if (type == 'file') {
                final filename =
                    (entry['file'] as Map?)?['filename'] as String? ??
                        'attachment';
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Chip(
                    avatar: const Icon(Icons.attach_file),
                    label: Text(filename),
                  ),
                );
              }
              return const SizedBox.shrink();
            }(),
      ];
    } catch (_) {
      return const <Widget>[];
    }
  }

  static Uint8List? _extractBase64(String dataUri) {
    final commaIdx = dataUri.indexOf(',');
    if (commaIdx == -1) return null;
    final b64 = dataUri.substring(commaIdx + 1);
    try {
      return Uint8List.fromList(base64Decode(b64));
    } catch (_) {
      return null;
    }
  }
}

class _ToolCallsView extends StatelessWidget {
  const _ToolCallsView({required this.toolCallsJson});
  final String toolCallsJson;

  @override
  Widget build(BuildContext context) {
    List<dynamic> calls;
    try {
      calls = jsonDecode(toolCallsJson) as List;
    } catch (_) {
      return const SizedBox.shrink();
    }
    if (calls.isEmpty) return const SizedBox.shrink();
    return ExpansionTile(
      title: Text('${calls.length} tool call(s)',
          style: Theme.of(context).textTheme.labelSmall),
      children: <Widget>[
        for (final c in calls)
          if (c is Map)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    'fn: ${(c['function'] as Map?)?['name'] ?? c['type'] ?? 'unknown'}',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    const JsonEncoder.withIndent('  ')
                        .convert((c['function'] as Map?)?['arguments'] ?? c),
                    style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                  ),
                ],
              ),
            ),
      ],
    );
  }
}

class _Composer extends ConsumerStatefulWidget {
  const _Composer({required this.scrollController});
  final ScrollController scrollController;

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
    if (text.isEmpty && ref.read(chatComposerProvider).attachedFiles.isEmpty) {
      return;
    }
    ref.read(chatComposerProvider.notifier).setInput(text);
    _controller.clear();
    await ref.read(chatComposerProvider.notifier).send();
    // Scroll to bottom after sending.
    if (widget.scrollController.hasClients) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        widget.scrollController.animateTo(
          widget.scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      });
    }
  }

  Future<void> _pickFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.any,
      allowMultiple: true,
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;
    for (final f in result.files) {
      final bytes = f.bytes ?? (f.path == null ? null : await File(f.path!).readAsBytes());
      if (bytes == null) continue;
      ref.read(chatComposerProvider.notifier).attachFile(AttachedFile(
        name: f.name,
        mimeType: 'application/octet-stream', // file_picker doesn't expose mime
        bytes: bytes,
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final composer = ref.watch(chatComposerProvider);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            // Attachment chips (issue #1)
            if (composer.attachedFiles.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: <Widget>[
                    for (int i = 0; i < composer.attachedFiles.length; i++)
                      Chip(
                        avatar: Icon(
                          composer.attachedFiles[i].mimeType.startsWith('image/')
                              ? Icons.image
                              : Icons.attach_file,
                          size: 16,
                        ),
                        label: Text(composer.attachedFiles[i].name),
                        onDeleted: () => ref
                            .read(chatComposerProvider.notifier)
                            .removeAttachment(i),
                      ),
                  ],
                ),
              ),
            Row(
              children: <Widget>[
                IconButton(
                  icon: const Icon(Icons.attach_file),
                  tooltip: l.chatAttachFile,
                  onPressed: composer.streaming ? null : _pickFile,
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
                    onPressed: () =>
                        ref.read(chatComposerProvider.notifier).cancel(),
                  )
                else
                  IconButton.filled(
                    icon: const Icon(Icons.send),
                    tooltip: l.chatSend,
                    onPressed: _send,
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
