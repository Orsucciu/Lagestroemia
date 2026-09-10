part of 'models.dart';

/// A conversation. Owns many [ChatMessage]s.
@immutable
class Chat {
  const Chat({
    required this.id,
    required this.title,
    this.model,
    this.systemPromptId,
    this.profileId,
    required this.createdAt,
    required this.updatedAt,
    this.archived = false,
    this.agentMode = false,
    this.deepThink = false,
  });

  /// UUID (v4) generated client-side.
  final String id;

  /// Human-readable title. Initial value is the first user message truncated;
  /// the user can rename it.
  final String title;

  /// Model id used for the assistant responses in this chat. May be null if
  /// the user has not chosen one yet (in which case the global default
  /// applies).
  final String? model;

  /// System prompt applied to every message in this chat.
  final String? systemPromptId;

  /// Anonymous profile id this chat belongs to. Null = main account
  /// (either API-key mode or the default guest session). Non-null =
  /// this chat belongs to an anonymous tab and uses that tab's
  /// guest JWT.
  final String? profileId;

  final DateTime createdAt;
  final DateTime updatedAt;

  /// Archived chats are hidden from the main list.
  final bool archived;

  /// Per-chat toggle: when true, chat completions go through the agent
  /// endpoint (`/api/agent/v2/chat/completions` on chat.z.ai or the
  /// public agent API on api.z.ai) instead of the regular chat endpoint.
  /// Only meaningful when the current [model] is agent-capable
  /// (see [AppConfig.chatZaiAgentCapableModels] /
  /// [AppConfig.apiZaiAgentCapableModels]).
  final bool agentMode;

  /// Per-chat toggle: when true, the request body includes
  /// `thinking: {type: enabled}` so the model streams its reasoning
  /// before the final answer. Only meaningful when the current [model]
  /// supports deep thinking (see
  /// [AppConfig.chatZaiDeepThinkCapableModels] /
  /// [AppConfig.apiZaiDeepThinkCapableModels]).
  final bool deepThink;

  /// Returns a copy of this chat with the given fields replaced.
  Chat copyWith({
    String? id,
    String? title,
    Object? model = _sentinel,
    Object? systemPromptId = _sentinel,
    Object? profileId = _sentinel,
    DateTime? createdAt,
    DateTime? updatedAt,
    bool? archived,
    bool? agentMode,
    bool? deepThink,
  }) {
    return Chat(
      id: id ?? this.id,
      title: title ?? this.title,
      model: identical(model, _sentinel) ? this.model : model as String?,
      systemPromptId: identical(systemPromptId, _sentinel)
          ? this.systemPromptId
          : systemPromptId as String?,
      profileId: identical(profileId, _sentinel)
          ? this.profileId
          : profileId as String?,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      archived: archived ?? this.archived,
      agentMode: agentMode ?? this.agentMode,
      deepThink: deepThink ?? this.deepThink,
    );
  }

  factory Chat.fromMap(Map<String, Object?> row) {
    return Chat(
      id: row['id']! as String,
      title: row['title']! as String,
      model: row['model'] as String?,
      systemPromptId: row['system_prompt_id'] as String?,
      profileId: row['profile_id'] as String?,
      createdAt: DateTime.fromMillisecondsSinceEpoch(row['created_at']! as int),
      updatedAt: DateTime.fromMillisecondsSinceEpoch(row['updated_at']! as int),
      archived: (row['archived'] as int?) == 1,
      agentMode: (row['agent_mode'] as int?) == 1,
      deepThink: (row['deep_think'] as int?) == 1,
    );
  }

  Map<String, Object?> toMap() => <String, Object?>{
        'id': id,
        'title': title,
        'model': model,
        'system_prompt_id': systemPromptId,
        'profile_id': profileId,
        'created_at': createdAt.millisecondsSinceEpoch,
        'updated_at': updatedAt.millisecondsSinceEpoch,
        'archived': archived ? 1 : 0,
        'agent_mode': agentMode ? 1 : 0,
        'deep_think': deepThink ? 1 : 0,
      };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Chat &&
          other.id == id &&
          other.title == title &&
          other.model == model &&
          other.systemPromptId == systemPromptId &&
          other.profileId == profileId &&
          other.createdAt == createdAt &&
          other.updatedAt == updatedAt &&
          other.archived == archived &&
          other.agentMode == agentMode &&
          other.deepThink == deepThink);

  @override
  int get hashCode => Object.hash(
        id,
        title,
        model,
        systemPromptId,
        profileId,
        createdAt,
        updatedAt,
        archived,
        agentMode,
        deepThink,
      );
}

/// Sentinel value used by [Chat.copyWith] to distinguish "leave unchanged"
/// from "set to null". We can't use `null` because that is a valid value
/// for nullable fields.
const Object _sentinel = Object();
