// Chat state — list of chats, current chat id, current messages, send action.
//
// The state is intentionally fine-grained:
//  - [chatListProvider]        — the home-screen chat list,
//  - [currentChatIdProvider]    — the chat the user has open right now,
//  - [currentChatMessagesProvider] — messages of the current chat,
//  - [chatComposerProvider]    — composer input + send action.

import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../data/api/zai_api_client.dart';
import '../data/models/models.dart';
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
  });

  final String input;
  final List<AttachedFile> attachedFiles;
  final bool isSending;
  final ApiError? error;
  final String streamedText;
  final String streamedReasoning;
  final bool streaming;

  ChatComposerState copyWith({
    String? input,
    List<AttachedFile>? attachedFiles,
    bool? isSending,
    Object? error = _sentinel,
    String? streamedText,
    String? streamedReasoning,
    bool? streaming,
  }) {
    return ChatComposerState(
      input: input ?? this.input,
      attachedFiles: attachedFiles ?? this.attachedFiles,
      isSending: isSending ?? this.isSending,
      error: identical(error, _sentinel) ? this.error : error as ApiError?,
      streamedText: streamedText ?? this.streamedText,
      streamedReasoning: streamedReasoning ?? this.streamedReasoning,
      streaming: streaming ?? this.streaming,
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

  void setInput(String value) {
    state = state.copyWith(input: value);
  }

  void attachFile(AttachedFile file) {
    state = state.copyWith(attachedFiles: [...state.attachedFiles, file]);
  }

  void clearAttachments() {
    state = state.copyWith(attachedFiles: const <AttachedFile>[]);
  }

  void clearError() {
    state = state.copyWith(error: null);
  }

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
      attachedFiles: const <AttachedFile>[],
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
    final model = chat.model ?? settings.model;

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
      contentJson: state.attachedFiles.isEmpty ? null : jsonEncode(userMessagePayload['content']),
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
    final stream = client.chatCompletionStream(
      messages: wirePayload,
      model: model,
    );
    final buf = StringBuffer();
    final reasoningBuf = StringBuffer();
    String? finishReason;
    await for (final chunk in stream) {
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
    state = state.copyWith(
      isSending: false,
      streaming: false,
    );
    _ref.invalidate(currentChatMessagesProvider);
    _ref.invalidate(chatListProvider);

    if (finishReason == 'error') {
      state = state.copyWith(error: const ApiError(
        message: 'Stream ended with an error. See logs.',
        kind: ApiErrorKind.unknown,
      ));
    }
  }

  Future<void> cancel() async {
    // MVP: we don't pass a CancelToken into the streaming call yet.
    // Setting `streaming=false` here is a soft cancel — the underlying
    // stream keeps going until the next chunk lands.
    state = state.copyWith(streaming: false, isSending: false);
  }
}

String _dataUri(AttachedFile f) {
  final b64 = base64Encode(f.bytes);
  return 'data:${f.mimeType};base64,$b64';
}
