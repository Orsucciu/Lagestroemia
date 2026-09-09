part of 'models.dart';

/// A generated artifact (code/markdown/html/svg/json) produced by the
/// assistant and stored locally so the user can browse and re-open it
/// later without re-running the chat.
@immutable
class Artifact {
  const Artifact({
    required this.id,
    required this.messageId,
    required this.kind,
    this.language,
    this.name,
    required this.body,
    required this.createdAt,
  });

  final String id;
  final String messageId;

  /// Type of artifact, used to pick the right viewer.
  final ArtifactKind kind;

  /// For code: language id ('dart', 'python', 'rust', ...).
  final String? language;

  /// Optional user-visible title (e.g. `main.dart`).
  final String? name;

  /// Raw content.
  final String body;

  final DateTime createdAt;

  factory Artifact.fromMap(Map<String, Object?> row) {
    return Artifact(
      id: row['id']! as String,
      messageId: row['message_id']! as String,
      kind: ArtifactKind.fromWire(row['kind']! as String),
      language: row['language'] as String?,
      name: row['name'] as String?,
      body: row['body']! as String,
      createdAt: DateTime.fromMillisecondsSinceEpoch(row['created_at']! as int),
    );
  }

  Map<String, Object?> toMap() => <String, Object?>{
        'id': id,
        'message_id': messageId,
        'kind': kind.wire,
        'language': language,
        'name': name,
        'body': body,
        'created_at': createdAt.millisecondsSinceEpoch,
      };
}

enum ArtifactKind {
  code,
  markdown,
  html,
  svg,
  json,
  plain;

  String get wire => name;

  static ArtifactKind fromWire(String wire) {
    return ArtifactKind.values.firstWhere(
      (k) => k.wire == wire,
      orElse: () => ArtifactKind.plain,
    );
  }
}
