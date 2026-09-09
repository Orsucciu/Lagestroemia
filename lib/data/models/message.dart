part of 'models.dart';

/// Role of a [ChatMessage]. Matches OpenAI's chat completions schema so it
/// can be sent over the wire as-is.
enum MessageRole {
  system,
  user,
  assistant,
  tool;

  String get wire => name;

  static MessageRole fromWire(String wire) {
    return MessageRole.values.firstWhere(
      (r) => r.wire == wire,
      orElse: () => throw ArgumentError.value(wire, 'wire', 'Unknown role'),
    );
  }
}

/// One message in a [Chat]. May be a plain text user message, an assistant
/// reply (possibly with reasoning + tool calls), a system message, or a tool
/// result.
@immutable
class ChatMessage {
  const ChatMessage({
    required this.id,
    required this.chatId,
    required this.role,
    required this.content,
    this.contentJson,
    this.reasoning,
    this.toolCalls,
    required this.createdAt,
  });

  final String id;
  final String chatId;
  final MessageRole role;

  /// Plain text used for display. For multimodal messages this is the
  /// shortest reasonable text-only view (e.g. "[image] please describe").
  final String content;

  /// JSON-serialised multi-modal content (OpenAI shape, list of
  /// `{type, text|image_url|file}` entries). `null` for plain text.
  final String? contentJson;

  /// GLM-4.6+ reasoning content (chain-of-thought shown separately from the
  /// main reply). `null` for non-reasoning models or user messages.
  final String? reasoning;

  /// JSON-serialised list of tool calls issued by the assistant. `null`
  /// unless the assistant invoked a tool.
  final String? toolCalls;

  final DateTime createdAt;

  ChatMessage copyWith({
    String? id,
    String? chatId,
    MessageRole? role,
    String? content,
    Object? contentJson = _sentinel,
    Object? reasoning = _sentinel,
    Object? toolCalls = _sentinel,
    DateTime? createdAt,
  }) {
    return ChatMessage(
      id: id ?? this.id,
      chatId: chatId ?? this.chatId,
      role: role ?? this.role,
      content: content ?? this.content,
      contentJson: identical(contentJson, _sentinel)
          ? this.contentJson
          : contentJson as String?,
      reasoning: identical(reasoning, _sentinel)
          ? this.reasoning
          : reasoning as String?,
      toolCalls: identical(toolCalls, _sentinel)
          ? this.toolCalls
          : toolCalls as String?,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  factory ChatMessage.fromMap(Map<String, Object?> row) {
    return ChatMessage(
      id: row['id']! as String,
      chatId: row['chat_id']! as String,
      role: MessageRole.fromWire(row['role']! as String),
      content: row['content']! as String,
      contentJson: row['content_json'] as String?,
      reasoning: row['reasoning'] as String?,
      toolCalls: row['tool_calls'] as String?,
      createdAt: DateTime.fromMillisecondsSinceEpoch(row['created_at']! as int),
    );
  }

  Map<String, Object?> toMap() => <String, Object?>{
        'id': id,
        'chat_id': chatId,
        'role': role.wire,
        'content': content,
        'content_json': contentJson,
        'reasoning': reasoning,
        'tool_calls': toolCalls,
        'created_at': createdAt.millisecondsSinceEpoch,
      };

  /// Returns the wire-payload representation expected by the chat
  /// completions endpoint.
  ///
  /// If [contentJson] is set (multi-modal) we send it as the parsed list;
  /// otherwise we send the plain `content` string.
  Map<String, Object?> toWirePayload() {
    return <String, Object?>{
      'role': role.wire,
      'content': contentJson ?? content,
    };
  }
}
