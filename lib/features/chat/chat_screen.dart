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
import '../../data/api/zai_api_client.dart' show ModelInfo;
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
    final modelsAsync = ref.watch(availableModelsProvider);

    // The model list is now fetched live from the backend (with a
    // hardcoded fallback — see availableModelsProvider). Each entry has
    // both an id (sent to the API) and a display name (shown in the
    // picker). The picker shows the fallback list immediately while
    // the fetch is in flight, then swaps in the live list when it
    // arrives.
    final fallbackModels = auth.mode == AuthMode.guest
        ? AppConfig.chatZaiKnownModels
        : AppConfig.knownModels;
    final List<ModelInfo> knownModels = modelsAsync.valueOrNull ??
        [
          for (final id in fallbackModels) ModelInfo(id: id, name: id),
        ];

    // Currently-selected model (or the default for the active backend).
    final currentModel = currentChat.valueOrNull?.model ??
        (auth.mode == AuthMode.guest
            ? AppConfig.defaultGuestModel
            : AppConfig.defaultModel);

    // Display name for the currently-selected model. Falls back to the
    // raw id if the live list hasn't loaded yet or the model isn't in it.
    final currentModelDisplay = knownModels
        .firstWhere(
          (m) => m.id == currentModel,
          orElse: () => ModelInfo(id: currentModel, name: currentModel),
        )
        .name;

    // Capabilities of the current model.
    final isAgentCapable = auth.mode == AuthMode.guest
        ? AppConfig.isChatZaiAgentModel(currentModel)
        : AppConfig.isApiZaiAgentModel(currentModel);
    final isDeepThinkCapable = auth.mode == AuthMode.guest
        ? AppConfig.isChatZaiDeepThinkModel(currentModel)
        : AppConfig.isApiZaiDeepThinkModel(currentModel);

    final chat = currentChat.valueOrNull;
    final agentModeOn = chat?.agentMode ?? false;
    final deepThinkOn = chat?.deepThink ?? false;

    final scrollController = ScrollController();
    return Scaffold(
      appBar: AppBar(
        title: Text(currentChat.valueOrNull?.title ?? l.chatEmptyTitle),
        actions: <Widget>[
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
                final c = await repo.findById(id);
                if (c == null) return;
                await repo.updateMeta(
                  c.copyWith(
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
          // Mode bar: model picker + Chat/Agent toggle + Deep think toggle.
          // These are separate toggles (issue: model picker UI bug). Each
          // toggle is only enabled when the current model supports it.
          _ModeBar(
            knownModels: knownModels,
            currentModelId: currentModel,
            currentModelDisplay: currentModelDisplay,
            onModelSelected: (model) async {
              final id = chatIdState;
              if (id == null) return;
              final repo = await ref.read(chatRepositoryProvider.future);
              final c = await repo.findById(id);
              if (c == null) return;
              await repo.updateMeta(c.copyWith(model: model));
              ref.invalidate(currentChatProvider);
            },
            isAgentCapable: isAgentCapable,
            agentModeOn: agentModeOn,
            onAgentModeToggled: (v) =>
                ref.read(chatComposerProvider.notifier).setAgentMode(v),
            isDeepThinkCapable: isDeepThinkCapable,
            deepThinkOn: deepThinkOn,
            onDeepThinkToggled: (v) =>
                ref.read(chatComposerProvider.notifier).setDeepThink(v),
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
          // Auto-retry status indicator
          if (composer.isAutoRetrying)
            Padding(
              padding: const EdgeInsets.all(8),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.tertiaryContainer,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: <Widget>[
                    const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Server overloaded. Auto-retrying in '
                        '${composer.autoRetryNextDelaySecs}s '
                        '(attempt ${composer.autoRetryAttempt}/'
                        '${composer.autoRetryMaxAttempts})…',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                    TextButton(
                      onPressed: () =>
                          ref.read(chatComposerProvider.notifier).cancel(),
                      child: const Text('Cancel'),
                    ),
                  ],
                ),
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

/// Mode bar shown above the message list. Hosts three independent
/// controls that previously were conflated inside the model picker:
///
///   1. The model picker (PopupMenuButton) — just shows model names,
///      nothing else. The whole row of "model name + agent badge" was
///      the bug the user reported.
///   2. A "Chat / Agent" [Switch] — only enabled when the currently
///      selected model is agent-capable. When on, send() routes the
///      request through the agent endpoint.
///   3. A "Deep think" [Switch] — only enabled when the currently
///      selected model supports deep thinking. When on, send() adds
///      `thinking: {type: enabled}` to the request body.
///
/// The switches are disabled (greyed out + unclickable) when the
/// current model doesn't support the corresponding capability, instead
/// of being hidden, so the user can see the option exists.
class _ModeBar extends StatelessWidget {
  const _ModeBar({
    required this.knownModels,
    required this.currentModelId,
    required this.currentModelDisplay,
    required this.onModelSelected,
    required this.isAgentCapable,
    required this.agentModeOn,
    required this.onAgentModeToggled,
    required this.isDeepThinkCapable,
    required this.deepThinkOn,
    required this.onDeepThinkToggled,
  });

  final List<ModelInfo> knownModels;
  final String currentModelId;
  final String currentModelDisplay;
  final ValueChanged<String> onModelSelected;
  final bool isAgentCapable;
  final bool agentModeOn;
  final ValueChanged<bool> onAgentModeToggled;
  final bool isDeepThinkCapable;
  final bool deepThinkOn;
  final ValueChanged<bool> onDeepThinkToggled;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      color: theme.colorScheme.surfaceContainerLow,
      child: Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 8,
        runSpacing: 4,
        children: <Widget>[
          // Model picker — shows the display name (e.g. "GLM-5.3-Flash"),
          // not the raw id (e.g. "x-preview-l"). The id is the value
          // passed to onModelSelected.
          PopupMenuButton<String>(
            tooltip: 'Select model',
            onSelected: onModelSelected,
            itemBuilder: (_) => <PopupMenuEntry<String>>[
              for (final m in knownModels)
                PopupMenuItem(
                  value: m.id,
                  child: Row(
                    children: <Widget>[
                      if (m.id == currentModelId)
                        const Icon(Icons.check, size: 18)
                      else
                        const SizedBox(width: 18),
                      const SizedBox(width: 8),
                      Expanded(child: Text(m.name)),
                    ],
                  ),
                ),
            ],
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Icon(Icons.tune, size: 18, color: theme.colorScheme.primary),
                  const SizedBox(width: 6),
                  Text(
                    currentModelDisplay,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(width: 4),
                  const Icon(Icons.arrow_drop_down, size: 18),
                ],
              ),
            ),
          ),
          // Chat / Agent toggle.
          _ToggleChip(
            label: 'Agent',
            icon: Icons.smart_toy_outlined,
            enabled: isAgentCapable,
            value: agentModeOn,
            onChanged: onAgentModeToggled,
            tooltip: isAgentCapable
                ? 'Route requests through the agent endpoint for this model'
                : 'This model does not support agent mode',
          ),
          // Deep think toggle.
          _ToggleChip(
            label: 'Deep think',
            icon: Icons.psychology_outlined,
            enabled: isDeepThinkCapable,
            value: deepThinkOn,
            onChanged: onDeepThinkToggled,
            tooltip: isDeepThinkCapable
                ? 'Stream the model\'s reasoning before its final answer'
                : 'This model does not support deep thinking',
          ),
        ],
      ),
    );
  }
}

/// A compact, Material-3-styled toggle chip used inside the [_ModeBar].
///
/// Renders a labelled [FilterChip]-like affordance: an icon + a text
/// label + a small [Switch]. When [enabled] is false, the entire chip
/// is greyed out and the [Switch] is disabled. The chip's [tooltip]
/// explains why it's disabled (or what it does when on).
class _ToggleChip extends StatelessWidget {
  const _ToggleChip({
    required this.label,
    required this.icon,
    required this.enabled,
    required this.value,
    required this.onChanged,
    required this.tooltip,
  });

  final String label;
  final IconData icon;
  final bool enabled;
  final bool value;
  final ValueChanged<bool> onChanged;
  final String tooltip;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final fgColor = enabled
        ? (value ? colorScheme.onPrimaryContainer : colorScheme.onSurface)
        : colorScheme.onSurfaceVariant.withValues(alpha: 0.4);
    return Tooltip(
      message: tooltip,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(
          color: enabled && value
              ? colorScheme.primaryContainer
              : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(icon, size: 16, color: fgColor),
            const SizedBox(width: 4),
            Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(color: fgColor),
            ),
            const SizedBox(width: 4),
            SizedBox(
              width: 28,
              height: 18,
              child: Switch(
                value: value,
                onChanged: enabled ? onChanged : null,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

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
