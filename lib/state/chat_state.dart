// Chat state — list of chats, current chat id, current messages, send action.
//
// The state is intentionally fine-grained:
//  - [chatListProvider]        — the home-screen chat list,
//  - [currentChatIdProvider]    — the chat the user has open right now,
//  - [currentChatMessagesProvider] — messages of the current chat,
//  - [chatComposerProvider]    — composer input + send action.

import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform, File, stdout, stderr, FileMode;

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../core/config/app_config.dart';
import '../data/models/models.dart';
import '../state/anon_profiles_state.dart';
import '../state/auth_state.dart' show AuthMode;
import 'providers.dart';

const _uuid = Uuid();

void _debugLog(String msg) {
  final line = '[${DateTime.now().toIso8601String()}] ' + msg;
  print(line);
  if (kIsWeb) return;
  try { stdout.writeln(line); stdout.flush(); } catch (_) {}
  try { stderr.writeln(line); } catch (_) {}
  try {
    final dir = Platform.environment['TEMP'] ?? '/tmp';
    File('${dir}/lagestroemia_debug.log')
        .writeAsStringSync('${line}\n', mode: FileMode.append);
  } catch (_) {}
}

// ---- chat list ----------------------------------------------------------

final chatListProvider =
    AsyncNotifierProvider<ChatListNotifier, List<Chat>>(ChatListNotifier.new);

class ChatListNotifier extends AsyncNotifier<List<Chat>> {
  @override
  Future<List<Chat>> build() async {
    final repo = await ref.watch(chatRepositoryProvider.future);
    final anonProfiles = ref.watch(anonProfilesProvider);
    // Filter chats by the active anonymous profile (if any).
    final profileId = anonProfiles.active?.id;
    return repo.list(profileId: profileId);
  }

  Future<Chat> createNewChat({String? model, String? systemPromptId}) async {
    final repo = await ref.watch(chatRepositoryProvider.future);
    final anonProfiles = ref.read(anonProfilesProvider);
    final profileId = anonProfiles.active?.id;
    final chat = await repo.create(
      model: model,
      systemPromptId: systemPromptId,
      profileId: profileId,
    );
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

/// Lists ALL chats across ALL profiles (including archived ones) for
/// the "Continue from history" dialog. Not filtered by the active
/// anonymous profile.
final allChatsForHistoryProvider = FutureProvider<List<Chat>>((ref) async {
  final repo = await ref.watch(chatRepositoryProvider.future);
  return repo.listAll(includeArchived: true);
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
    this.autoRetryAttempt = 0,
    this.autoRetryMaxAttempts = 5,
    this.autoRetryNextDelaySecs = 0,
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

  /// Auto-retry: current attempt number (0 = first try, 1 = first retry,
  /// ..., autoRetryMaxAttempts = last retry). The UI shows
  /// "Auto-retrying in Xs (attempt N/M)..." when autoRetryAttempt > 0.
  final int autoRetryAttempt;

  /// Auto-retry: maximum number of retries before giving up.
  /// Default: 5 (so total of 6 attempts including the initial one).
  final int autoRetryMaxAttempts;

  /// Auto-retry: seconds until the next retry. 0 = not retrying.
  final int autoRetryNextDelaySecs;

  bool get isAutoRetrying => autoRetryAttempt > 0 && autoRetryNextDelaySecs > 0;

  ChatComposerState copyWith({
    String? input,
    List<AttachedFile>? attachedFiles,
    bool? isSending,
    Object? error = _sentinel,
    String? streamedText,
    String? streamedReasoning,
    bool? streaming,
    bool? captchaRequired,
    int? autoRetryAttempt,
    int? autoRetryMaxAttempts,
    int? autoRetryNextDelaySecs,
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
      autoRetryAttempt: autoRetryAttempt ?? this.autoRetryAttempt,
      autoRetryMaxAttempts:
          autoRetryMaxAttempts ?? this.autoRetryMaxAttempts,
      autoRetryNextDelaySecs:
          autoRetryNextDelaySecs ?? this.autoRetryNextDelaySecs,
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

  /// Toggles the per-chat `agentMode` flag and persists it to the database.
  /// The UI should only call this when the current model is agent-capable
  /// (otherwise the toggle is disabled).
  Future<void> setAgentMode(bool value) async {
    final chatId = _ref.read(currentChatIdProvider);
    if (chatId == null) return;
    final chatRepo = await _ref.read(chatRepositoryProvider.future);
    final chat = await chatRepo.findById(chatId);
    if (chat == null) return;
    final updated = chat.copyWith(
      agentMode: value,
      updatedAt: DateTime.now().toUtc(),
    );
    await chatRepo.updateMeta(updated);
    _ref.invalidate(currentChatProvider);
  }

  /// Toggles the per-chat `deepThink` flag and persists it to the database.
  /// The UI should only call this when the current model supports deep
  /// thinking (otherwise the toggle is disabled).
  Future<void> setDeepThink(bool value) async {
    final chatId = _ref.read(currentChatIdProvider);
    if (chatId == null) return;
    final chatRepo = await _ref.read(chatRepositoryProvider.future);
    final chat = await chatRepo.findById(chatId);
    if (chat == null) return;
    final updated = chat.copyWith(
      deepThink: value,
      updatedAt: DateTime.now().toUtc(),
    );
    await chatRepo.updateMeta(updated);
    _ref.invalidate(currentChatProvider);
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
    _debugLog('[CHAT] send() called');
    if (state.streaming || state.isSending) {
      _debugLog('[CHAT] send(): already streaming/sending — ignoring');
      return;
    }
    final text = state.input.trim();
    if (text.isEmpty && state.attachedFiles.isEmpty) {
      _debugLog('[CHAT] send(): empty input + no attachments — ignoring');
      return;
    }
    _debugLog('[CHAT] send(): text length=${text.length}, attachments=${state.attachedFiles.length}');
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
      _debugLog('[CHAT] send(): apiClient is null — not signed in');
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
      _debugLog('[CHAT] send(): chat $chatId not found');
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
    _debugLog('[CHAT] send(): model=$model, agentMode=${chat.agentMode}, deepThink=${chat.deepThink}');

    // Build OpenAI-shaped messages payload.
    final priorMessages = await msgRepo.listForChat(chatId);
    // Note: use growable: true (the default) here so we can .add() the
    // user message below. The previous `growable: false` made the list
    // fixed-length, and `add()` threw `Unsupported operation: add` on
    // the Web target (sqflite_common_ffi_web's JS arrays enforce
    // fixed-length strictly, while native SQLite does not).
    final List<Map<String, Object?>> wirePayload =
        priorMessages.map((m) => m.toWirePayload()).toList();

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

    // Build the thinking parameter: only enabled when the chat's
    // deepThink toggle is on AND the current model supports it.
    Map<String, Object?>? thinkingParam;
    if (chat.deepThink) {
      final isDeepThinkCapable = auth.mode == AuthMode.guest
          ? AppConfig.isChatZaiDeepThinkModel(model)
          : AppConfig.isApiZaiDeepThinkModel(model);
      if (isDeepThinkCapable) {
        thinkingParam = <String, Object?>{'type': 'enabled'};
        _debugLog('[CHAT] send(): deep think enabled for model=$model');
      } else {
        _debugLog('[CHAT] send(): deepThink is on but model=$model does not support it — ignoring');
      }
    }

    _debugLog('[CHAT] send(): starting stream to ${client.chatCompletionsPathFor(model: model, agentMode: chat.agentMode)}');

    // Stream with auto-retry!
    int retryAttempt = 0;
    const maxRetries = 5;
    bool success = false;
    bool cancelled = false;
    String? finishReason;

    while (retryAttempt <= maxRetries && !cancelled) {
      _cancelToken = CancelToken();
      final stream = client.chatCompletionStream(
        messages: wirePayload,
        model: model,
        agentMode: chat.agentMode,
        thinking: thinkingParam,
        cancelToken: _cancelToken,
      );
      final buf = StringBuffer();
      final reasoningBuf = StringBuffer();
      finishReason = null;
      cancelled = false;
      bool shouldRetry = false;
      ApiError? retryError;

      await for (final chunk in stream) {
        if (chunk.error != null) {
          final code = chunk.error!.code;
          final msg = chunk.error!.message;
          _debugLog('[CHAT] send(): stream error kind=${chunk.error!.kind} code=$code msg=$msg');
          final isCaptcha =
              code == 'FRONTEND_CAPTCHA_REQUIRED' ||
              msg.toLowerCase().contains('captcha');
          if (isCaptcha) {
            _debugLog('[CHAT] send(): captcha required — stashing input for retry');
            _stashedSend = _StashedSend(
              input: text,
              attachedFiles: state.attachedFiles);
            state = state.copyWith(
              streaming: false,
              isSending: false,
              captchaRequired: true,
              error: chunk.error,
              autoRetryAttempt: 0,
              autoRetryNextDelaySecs: 0,
            );
            await msgRepo.delete(assistantId);
            _ref.invalidate(currentChatMessagesProvider);
            return;
          }
          // Upgrade 403 "Model not available for current user level"
          // (chat.z.ai's response when a guest user picks a flagship
          // model like glm-5.3) to a specific error kind so the UI
          // can show a helpful message instead of the generic auth
          // error.
          final original = chunk.error!;
          final msgLower = msg.toLowerCase();
          final isModelNotAllowed =
              (code == '403' || original.httpStatus == 403) &&
              (msgLower.contains('not available') ||
                  msgLower.contains('user level') ||
                  msgLower.contains('permission') ||
                  msgLower.contains('insufficient'));
          final effectiveError = isModelNotAllowed
              ? ApiError(
                  message: msg,
                  code: code,
                  httpStatus: original.httpStatus,
                  kind: ApiErrorKind.modelNotAllowed,
                  cause: original.cause,
                )
              : original;
          // Check if the error is retryable (server overload, quota,
          // rate limit, network).
          final kind = effectiveError.kind;
          if (retryAttempt < maxRetries &&
              (kind == ApiErrorKind.server ||
               kind == ApiErrorKind.rateLimit ||
               kind == ApiErrorKind.quota ||
               kind == ApiErrorKind.network)) {
            _debugLog('[CHAT] send(): retryable error (attempt ${retryAttempt + 1}/$maxRetries)');
            shouldRetry = true;
            retryError = effectiveError;
            break;
          }
          // Non-retryable error — show it.
          _debugLog('[CHAT] send(): non-retryable error — surfacing to UI');
          state = state.copyWith(
            streaming: false,
            isSending: false,
            error: effectiveError,
            autoRetryAttempt: 0,
            autoRetryNextDelaySecs: 0,
          );
          return;
        }
        if (chunk.finishReason == 'cancelled') {
          _debugLog('[CHAT] send(): stream cancelled by user');
          cancelled = true;
          break;
        }
        if (chunk.contentDelta != null) buf.write(chunk.contentDelta);
        if (chunk.reasoningDelta != null) reasoningBuf.write(chunk.reasoningDelta);
        if (chunk.finishReason != null) finishReason = chunk.finishReason;
        await msgRepo.updateContent(
          assistantId,
          content: buf.toString(),
          reasoning: reasoningBuf.toString(),
        );
        // Invalidate the messages provider so the message bubble
        // re-renders with the latest streamed text. Without this the
        // UI only updates once at the end of the stream, so the user
        // sees nothing during streaming.
        _ref.invalidate(currentChatMessagesProvider);
        state = state.copyWith(
          streamedText: buf.toString(),
          streamedReasoning: reasoningBuf.toString(),
        );
      }
      _cancelToken = null;

      if (cancelled) break;
      if (shouldRetry) {
        retryAttempt++;
        // Exponential backoff: 2^attempt seconds (1, 2, 4, 8, 16...)
        final delaySecs = 1 << (retryAttempt - 1); // 1, 2, 4, 8, 16
        state = state.copyWith(
          autoRetryAttempt: retryAttempt,
          autoRetryNextDelaySecs: delaySecs,
          autoRetryMaxAttempts: maxRetries,
          error: retryError,
        );
        // Countdown the delay.
        for (var remaining = delaySecs; remaining > 0; remaining--) {
          await Future<void>.delayed(const Duration(seconds: 1));
          if (state.autoRetryNextDelaySecs == 0) break; // user cancelled
          state = state.copyWith(autoRetryNextDelaySecs: remaining - 1);
        }
        if (state.autoRetryNextDelaySecs == 0 && !state.isSending) {
          // User cancelled during the delay.
          break;
        }
        // Clear the partial content for a fresh retry.
        await msgRepo.updateContent(assistantId, content: '', reasoning: '');
        state = state.copyWith(
          streamedText: '',
          streamedReasoning: '',
          autoRetryNextDelaySecs: 0,
        );
        continue;
      }
      // Stream completed (either successfully or with a non-retryable
      // finish_reason=error).
      success = true;
      break;
    }

    state = state.copyWith(
      isSending: false,
      streaming: false,
      autoRetryAttempt: 0,
      autoRetryNextDelaySecs: 0,
    );
    _ref.invalidate(currentChatMessagesProvider);
    _ref.invalidate(chatListProvider);
    _debugLog('[CHAT] send(): finished (success=$success, cancelled=$cancelled, finishReason=$finishReason)');

    if (!cancelled && !success && finishReason == 'error') {
      _debugLog('[CHAT] send(): stream ended with error');
      state = state.copyWith(error: const ApiError(
        message: 'Stream ended with an error. See logs.',
        kind: ApiErrorKind.unknown,
      ));
    }
  }

  /// Imports a conversation from a JSON array (as produced by the
  /// "Export chat → JSON" feature) into a fresh chat under the active
  /// anonymous profile. Creates the chat and all messages, then opens
  /// it in the chat view.
  ///
  /// The JSON format is:
  ///   [{"role":"user","content":"...","reasoning":"...","created_at":"..."},
  ///    {"role":"assistant","content":"...","reasoning":"...","created_at":"..."},
  ///    ...]
  ///
  /// Returns the new chat's id on success, null on failure.
  Future<String?> continueFromJson(String jsonString) async {
    try {
      final list = jsonDecode(jsonString) as List<Object?>;
      if (list.isEmpty) return null;

      final chatRepo = await _ref.read(chatRepositoryProvider.future);
      final msgRepo = await _ref.read(messageRepositoryProvider.future);
      final anonProfiles = _ref.read(anonProfilesProvider);
      final settings = _ref.read(settingsStateProvider);

      // Create a new chat for this conversation.
      final profileId = anonProfiles.active?.id;
      final firstUserMsg = list.firstWhere(
        (e) => (e as Map<String, Object?>)['role'] == 'user',
        orElse: () => list.first as Map<String, Object?>,
      );
      final title = ((firstUserMsg as Map<String, Object?>)['content']
                  as String?)
              ?.split('\n')
              .first
              .substring(0, 60) ??
          'Continued chat';
      final chat = await chatRepo.create(
        title: title,
        model: settings.model,
        profileId: profileId,
      );

      // Insert all messages.
      for (final entry in list) {
        final m = entry as Map<String, Object?>;
        final role = m['role'] as String? ?? 'user';
        final content = m['content'] as String? ?? '';
        final reasoning = m['reasoning'] as String?;
        final createdAtStr = m['created_at'] as String?;
        final createdAt = createdAtStr != null
            ? DateTime.tryParse(createdAtStr) ?? DateTime.now().toUtc()
            : DateTime.now().toUtc();

        await msgRepo.upsert(ChatMessage(
          id: _uuid.v4(),
          chatId: chat.id,
          role: MessageRole.fromWire(role),
          content: content,
          reasoning: reasoning,
          createdAt: createdAt,
        ));
      }
      await chatRepo.touch(chat.id);

      // Refresh the chat list and open the chat.
      _ref.invalidate(chatListProvider);
      _ref.read(currentChatIdProvider.notifier).state = chat.id;
      return chat.id;
    } catch (e) {
      state = state.copyWith(error: ApiError(
        message: 'Failed to import conversation: $e',
        kind: ApiErrorKind.unknown,
      ));
      return null;
    }
  }

  /// Continues a past conversation from the SQLite history into a
  /// fresh chat under the active anonymous profile (or creates a new
  /// profile if none exists). Copies all messages from the source chat
  /// into the new chat.
  ///
  /// Returns the new chat's id on success, null on failure.
  Future<String?> continueFromHistory(String sourceChatId) async {
    try {
      final chatRepo = await _ref.read(chatRepositoryProvider.future);
      final msgRepo = await _ref.read(messageRepositoryProvider.future);
      final settings = _ref.read(settingsStateProvider);
      final anonProfiles = _ref.read(anonProfilesProvider);

      // Load the source chat + its messages.
      final sourceChat = await chatRepo.findById(sourceChatId);
      if (sourceChat == null) return null;
      final sourceMessages = await msgRepo.listForChat(sourceChatId);
      if (sourceMessages.isEmpty) return null;

      // If no anonymous profile exists yet, create one.
      String? profileId = anonProfiles.active?.id;
      if (profileId == null) {
        final newProfile = await _ref
            .read(anonProfilesProvider.notifier)
            .createNew();
        profileId = newProfile?.id;
      }

      // Create the new chat.
      final newChat = await chatRepo.create(
        title: '${sourceChat.title} (continued)',
        model: sourceChat.model ?? settings.model,
        systemPromptId: sourceChat.systemPromptId,
        profileId: profileId,
      );

      // Copy all messages (with new ids, preserving order + content +
      // reasoning + tool_calls).
      for (final msg in sourceMessages) {
        await msgRepo.upsert(ChatMessage(
          id: _uuid.v4(),
          chatId: newChat.id,
          role: msg.role,
          content: msg.content,
          contentJson: msg.contentJson,
          reasoning: msg.reasoning,
          toolCalls: msg.toolCalls,
          createdAt: msg.createdAt,
        ));
      }
      await chatRepo.touch(newChat.id);

      // Refresh the chat list and open the new chat.
      _ref.invalidate(chatListProvider);
      _ref.read(currentChatIdProvider.notifier).state = newChat.id;
      return newChat.id;
    } catch (e) {
      state = state.copyWith(error: ApiError(
        message: 'Failed to continue conversation: $e',
        kind: ApiErrorKind.unknown,
      ));
      return null;
    }
  }

  /// Cancels the in-flight HTTP request (issue #6) and stops any
  /// pending auto-retry. The Dio CancelToken aborts the request
  /// server-side immediately, and the stream's `await for` loop
  /// exits cleanly.
  Future<void> cancel() async {
    final token = _cancelToken;
    if (token != null && !token.isCancelled) {
      token.cancel('user requested');
    }
    // Also clear the auto-retry countdown.
    state = state.copyWith(
      streaming: false,
      isSending: false,
      autoRetryAttempt: 0,
      autoRetryNextDelaySecs: 0,
    );
  }

  /// Regenerates the assistant response for the given message id.
  ///
  /// Deletes the assistant message at [assistantMessageId] and all
  /// assistant messages that come after it (so the new response
  /// replaces the old one), then re-runs [send] with the user
  /// message(s) that preceded it. Used by the "Regenerate" button
  /// on each assistant message bubble.
  ///
  /// If the chat is currently streaming or sending, this is a no-op
  /// (the user must wait for the current response to finish or
  /// cancel it first).
  Future<void> regenerate(String assistantMessageId) async {
    if (state.streaming || state.isSending) {
      _debugLog('[CHAT] regenerate(): ignored (already sending/streaming)');
      return;
    }
    final chatId = _ref.read(currentChatIdProvider);
    if (chatId == null) {
      _debugLog('[CHAT] regenerate(): no current chat id');
      return;
    }
    final msgRepo = await _ref.read(messageRepositoryProvider.future);
    final messages = await msgRepo.listForChat(chatId);

    // Find the index of the assistant message to regenerate.
    final idx = messages.indexWhere((m) => m.id == assistantMessageId);
    if (idx == -1) {
      _debugLog('[CHAT] regenerate(): message $assistantMessageId not found');
      return;
    }
    if (messages[idx].role != MessageRole.assistant) {
      _debugLog('[CHAT] regenerate(): message $assistantMessageId is not an '
          'assistant message');
      return;
    }

    // Find the most recent USER message before this assistant message.
    // That's the prompt we'll re-send.
    int userIdx = -1;
    for (var i = idx - 1; i >= 0; i--) {
      if (messages[i].role == MessageRole.user) {
        userIdx = i;
        break;
      }
    }
    if (userIdx == -1) {
      _debugLog('[CHAT] regenerate(): no user message found before the '
          'assistant message');
      return;
    }
    final userMessage = messages[userIdx];

    // Delete the assistant message at idx AND all messages that come
    // after it (so we don't accumulate duplicate responses).
    for (var i = messages.length - 1; i >= idx; i--) {
      await msgRepo.delete(messages[i].id);
    }
    // Also delete the user message — we'll re-add it via send().
    await msgRepo.delete(userMessage.id);
    _ref.invalidate(currentChatMessagesProvider);

    // Set the composer's input to the user's text + attachments, then
    // call send() to re-run the request.
    _debugLog('[CHAT] regenerate(): re-sending user message "${userMessage.content}"');
    state = state.copyWith(
      input: userMessage.content,
      attachedFiles: const <AttachedFile>[],  // attachments not preserved
      error: null,
      streamedText: '',
      streamedReasoning: '',
      captchaRequired: false,
    );
    await send();
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
