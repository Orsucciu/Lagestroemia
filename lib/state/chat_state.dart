// Chat state — list of chats, current chat id, current messages, send action.
//
// The state is intentionally fine-grained:
//  - [chatListProvider]        — the home-screen chat list,
//  - [currentChatIdProvider]    — the chat the user has open right now,
//  - [currentChatMessagesProvider] — messages of the current chat,
//  - [chatComposerProvider]    — composer input + send action.

import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../core/config/app_config.dart';
import '../data/api/zai_api_client.dart';
import '../data/models/models.dart';
import '../state/auth_state.dart' show AuthMode;
import 'providers.dart';

const _uuid = Uuid();

// ---- chat list ----------------------------------------------------------

final chatListProvider =
    AsyncNotifierProvider<ChatListNotifier, List<Chat>>(ChatListNotifier.new);

class ChatListNotifier extends AsyncNotifier<List<Chat>> {
  @override
  Future<List<Chat>> build() async {
    final repo = await ref.watch(chatRepositoryProvider.future);
    return repo.list();
  }

  Future<Chat> createNewChat({String? model, String? systemPromptId}) async {
    final repo = await ref.watch(chatRepositoryProvider.future);
    final chat = await repo.create(model: model, systemPromptId: systemPromptId);
    state = AsyncData([chat, ...?state.valueOrNull]);
    return chat;
  }

  Future<void> renameChat(Chat chat, String title) async {
    final repo = await ref.watch(chatRepositoryProvider.future);
    final updated = chat.copyWith(title: title, updatedAt: DateTime.now().toUtc());
    await repo.updateMeta(updated);
    _replaceInList(updated);
  }

  Future<void> archiveChat(Chat chat) async {
    final repo = await ref.watch(chatRepositoryProvider.future);
    final updated = chat.copyWith(archived: true, updatedAt: DateTime.now().toUtc());
    await repo.updateMeta(updated);
    _replaceInList(updated);
  }

  Future<void> deleteChat(String id) async {
    final repo = await ref.watch(chatRepositoryProvider.future);
    await repo.delete(id);
    final current = state.valueOrNull ?? const <Chat>[];
    state = AsyncData(current.where((c) => c.id != id).toList(growable: false));
  }

  void _replaceInList(Chat updated) {
    final current = state.valueOrNull ?? const <Chat>[];
    final next = [
      for (final c in current)
        if (c.id == updated.id) updated else c,
    ];
    state = AsyncData(next);
  }
}

// ---- current chat ------------------------------------------------------

final currentChatIdProvider = StateProvider<String?>((ref) => null);

final currentChatProvider = FutureProvider<Chat?>((ref) async {
  final id = ref.watch(currentChatIdProvider);
  if (id == null) return null;
  final repo = await ref.watch(chatRepositoryProvider.future);
  return repo.findById(id);
});

final currentChatMessagesProvider = FutureProvider<List<ChatMessage>>((ref) async {
  final id = ref.watch(currentChatIdProvider);
  ref.watch(chatListProvider);
  if (id == null) return const <ChatMessage>[];
  final repo = await ref.watch(messageRepositoryProvider.future);
  return repo.listForChat(id);
});

// ---- composer + send ---------------------------------------------------

/// Composer state for the currently-open chat.
class ChatComposerState {
  ChatComposerState({
    this.input = '',
    this.attachedFiles = const <AttachedFile>[],
    this.isSending = false,
    this.error,
    this.streamedText = '',
    this.streamedReasoning = '',
    this.streaming = false,
    this.captchaRequired = false,
  });

  final String input;
  final List<AttachedFile> attachedFiles;
  final bool isSending;
  final ApiError? error;
  final String streamedText;
  final String streamedReasoning;
  final bool streaming;

  /// Set when the last chat completion request failed with the
  /// `FRONTEND_CAPTCHA_REQUIRED` error. The UI should render the in-app
  /// Aliyun captcha widget and re-send once the user solves it.
  final bool captchaRequired;

  ChatComposerState copyWith({
    String? input,
    List<AttachedFile>? attachedFiles,
    bool? isSending,
    Object? error = _sentinel,
    String? streamedText,
    String? streamedReasoning,
    bool? streaming,
    bool? captchaRequired,
  }) {
    return ChatComposerState(
      input: input ?? this.input,
      attachedFiles: attachedFiles ?? this.attachedFiles,
      isSending: isSending ?? this.isSending,
      error: identical(error, _sentinel) ? this.error : error as ApiError?,
      streamedText: streamedText ?? this.streamedText,
      streamedReasoning: streamedReasoning ?? this.streamedReasoning,
      streaming: streaming ?? this.streaming,
      captchaRequired: captchaRequired ?? this.captchaRequired,
    );
  }
}

const Object _sentinel = Object();

class AttachedFile {
  const AttachedFile({
    required this.name,
    required this.mimeType,
    required this.bytes,
  });
  final String name;
  final String mimeType;
  final List<int> bytes;
}

final chatComposerProvider =
    StateNotifierProvider<ChatComposerNotifier, ChatComposerState>(
        ChatComposerNotifier.new);

class ChatComposerNotifier extends StateNotifier<ChatComposerState> {
  ChatComposerNotifier(this._ref) : super(ChatComposerState());
  final Ref _ref;

  /// CancelToken for the in-flight streaming request, if any. Used by
  /// `cancel()` to abort the HTTP request (issue #6).
  CancelToken? _cancelToken;

  void setInput(String value) {
    state = state.copyWith(input: value);
  }

  void attachFile(AttachedFile file) {
    state = state.copyWith(attachedFiles: [...state.attachedFiles, file]);
  }

  void removeAttachment(int index) {
    final next = [...state.attachedFiles];
    if (index >= 0 && index < next.length) {
      next.removeAt(index);
      state = state.copyWith(attachedFiles: next);
    }
  }

  void clearAttachments() {
    state = state.copyWith(attachedFiles: const <AttachedFile>[]);
  }

  void clearError() {
    state = state.copyWith(error: null, captchaRequired: false);
  }

  /// Sets the captcha verify param (after the user solves the in-app
  /// Aliyun captcha) and immediately re-tries the last send.
  Future<void> setCaptchaAndRetry(String captchaVerifyParam) async {
    _ref.read(captchaVerifyParamProvider.notifier).state = captchaVerifyParam;
    state = state.copyWith(captchaRequired: false, error: null);
    // Re-send with the previously-stashed input. We saved the last input
    // (and attachments) before showing the captcha prompt.
    if (_stashedSend != null) {
      final stash = _stashedSend!;
      _stashedSend = null;
      state = state.copyWith(
        input: stash.input,
        attachedFiles: stash.attachedFiles,
      );
      await send();
    }
  }

  _StashedSend? _stashedSend;

  Future<void> send() async {
    if (state.streaming || state.isSending) return;
    final text = state.input.trim();
    if (text.isEmpty && state.attachedFiles.isEmpty) return;
    state = state.copyWith(
      input: '',
      isSending: true,
      error: null,
      streamedText: '',
      streamedReasoning: '',
      streaming: true,
      captchaRequired: false,
    );

    final client = _ref.read(apiClientProvider);
    if (client == null) {
      state = state.copyWith(
        isSending: false,
        streaming: false,
        error: const ApiError(message: 'Not signed in.', kind: ApiErrorKind.auth),
      );
      return;
    }

    final chatRepo = await _ref.read(chatRepositoryProvider.future);
    final msgRepo = await _ref.read(messageRepositoryProvider.future);
    final settings = _ref.read(settingsStateProvider);
    final auth = _ref.read(authStateProvider);

    // Resolve the chat to send into (creating one if the user picked "new chat").
    String chatId = _ref.read(currentChatIdProvider) ??
        (await chatRepo.create(model: settings.model)).id;
    _ref.read(currentChatIdProvider.notifier).state = chatId;
    final chat = await chatRepo.findById(chatId);
    if (chat == null) {
      state = state.copyWith(
        isSending: false,
        streaming: false,
        error: const ApiError(message: 'Chat not found.'),
      );
      return;
    }
    final defaultModel = auth.mode == AuthMode.guest
        ? AppConfig.defaultGuestModel
        : settings.model;
    final model = chat.model ?? defaultModel;

    // Build OpenAI-shaped messages payload.
    final priorMessages = await msgRepo.listForChat(chatId);
    final List<Map<String, Object?>> wirePayload =
        priorMessages.map((m) => m.toWirePayload()).toList(growable: false);

    // Compose content for the user message (plain text or multi-modal).
    final String userText = text.isEmpty ? '(no text)' : text;
    Map<String, Object?> userMessagePayload;
    if (state.attachedFiles.isEmpty) {
      userMessagePayload = <String, Object?>{
        'role': 'user',
        'content': userText,
      };
    } else {
      // Multi-modal content list.
      final content = <Map<String, Object?>>[
        <String, Object?>{'type': 'text', 'text': userText},
        for (final f in state.attachedFiles)
          if (f.mimeType.startsWith('image/'))
            <String, Object?>{
              'type': 'image_url',
              'image_url': <String, Object?>{
                'url': _dataUri(f),
              },
            }
          else
            <String, Object?>{
              'type': 'file',
              'file': <String, Object?>{
                'file_data': _dataUri(f),
              },
            },
      ];
      userMessagePayload = <String, Object?>{
        'role': 'user',
        'content': content,
      };
    }
    wirePayload.add(userMessagePayload);

    // Persist the user message locally.
    final now = DateTime.now().toUtc();
    final userMessage = ChatMessage(
      id: _uuid.v4(),
      chatId: chatId,
      role: MessageRole.user,
      content: userText,
      contentJson: state.attachedFiles.isEmpty
          ? null
          : jsonEncode(userMessagePayload['content']),
      createdAt: now,
    );
    await msgRepo.upsert(userMessage);
    await chatRepo.touch(chatId);

    // Refresh the messages list before streaming.
    _ref.invalidate(currentChatMessagesProvider);

    // Create the assistant placeholder message.
    final assistantId = _uuid.v4();
    final assistant = ChatMessage(
      id: assistantId,
      chatId: chatId,
      role: MessageRole.assistant,
      content: '',
      createdAt: DateTime.now().toUtc(),
    );
    await msgRepo.upsert(assistant);

    // Stream!
    _cancelToken = CancelToken();
    final stream = client.chatCompletionStream(
      messages: wirePayload,
      model: model,
      cancelToken: _cancelToken,
    );
    final buf = StringBuffer();
    final reasoningBuf = StringBuffer();
    final toolCallsBuf = StringBuffer();
    String? finishReason;
    bool cancelled = false;
    await for (final chunk in stream) {
      if (chunk.error != null) {
        // Detect the captcha-required error.
        final code = chunk.error!.code;
        final msg = chunk.error!.message;
        final isCaptcha =
            code == 'FRONTEND_CAPTCHA_REQUIRED' ||
            msg.toLowerCase().contains('captcha');
        if (isCaptcha) {
          // Stash the send so we can retry after the user solves the captcha.
          _stashedSend = _StashedSend(input: text, attachedFiles: state.attachedFiles);
          state = state.copyWith(
            streaming: false,
            isSending: false,
            captchaRequired: true,
            error: chunk.error,
          );
          // Roll back the empty assistant placeholder so we don't show a
          // blank bubble.
          await msgRepo.delete(assistantId);
          _ref.invalidate(currentChatMessagesProvider);
          return;
        }
        state = state.copyWith(
          streaming: false,
          isSending: false,
          error: chunk.error,
        );
        return;
      }
      if (chunk.finishReason == 'cancelled') {
        cancelled = true;
        break;
      }
      if (chunk.contentDelta != null) buf.write(chunk.contentDelta);
      if (chunk.reasoningDelta != null) reasoningBuf.write(chunk.reasoningDelta);
      if (chunk.finishReason != null) finishReason = chunk.finishReason;
      // Persist every chunk so a crashed app can resume.
      await msgRepo.updateContent(
        assistantId,
        content: buf.toString(),
        reasoning: reasoningBuf.toString(),
      );
      state = state.copyWith(
        streamedText: buf.toString(),
        streamedReasoning: reasoningBuf.toString(),
      );
    }
    _cancelToken = null;
    state = state.copyWith(
      isSending: false,
      streaming: false,
    );
    _ref.invalidate(currentChatMessagesProvider);
    _ref.invalidate(chatListProvider);

    if (!cancelled && finishReason == 'error') {
      state = state.copyWith(error: const ApiError(
        message: 'Stream ended with an error. See logs.',
        kind: ApiErrorKind.unknown,
      ));
    }
  }

  /// Cancels the in-flight HTTP request (issue #6). The Dio CancelToken
  /// aborts the request server-side immediately, and the stream's
  /// `await for` loop exits cleanly.
  Future<void> cancel() async {
    final token = _cancelToken;
    if (token != null && !token.isCancelled) {
      token.cancel('user requested');
    }
    // The stream will yield a `cancelled` chunk and we'll exit the loop
    // cleanly. Setting `streaming=false` here is a soft hint for the UI.
    state = state.copyWith(streaming: false, isSending: false);
  }
}

class _StashedSend {
  _StashedSend({required this.input, required this.attachedFiles});
  final String input;
  final List<AttachedFile> attachedFiles;
}

String _dataUri(AttachedFile f) {
  final b64 = base64Encode(f.bytes);
  return 'data:${f.mimeType};base64,$b64';
}
