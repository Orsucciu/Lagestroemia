part of 'models.dart';

/// A reusable system prompt. Builtin entries are seeded on first run; user
/// entries are added via the Prompts UI.
@immutable
class SystemPrompt {
  const SystemPrompt({
    required this.id,
    required this.name,
    required this.body,
    this.category,
    this.builtin = false,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String name;
  final String body;
  final String? category;
  final bool builtin;
  final DateTime createdAt;
  final DateTime updatedAt;

  SystemPrompt copyWith({
    String? id,
    String? name,
    String? body,
    Object? category = _sentinel,
    bool? builtin,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return SystemPrompt(
      id: id ?? this.id,
      name: name ?? this.name,
      body: body ?? this.body,
      category: identical(category, _sentinel) ? this.category : category as String?,
      builtin: builtin ?? this.builtin,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  factory SystemPrompt.fromMap(Map<String, Object?> row) {
    return SystemPrompt(
      id: row['id']! as String,
      name: row['name']! as String,
      body: row['body']! as String,
      category: row['category'] as String?,
      builtin: (row['builtin'] as int) == 1,
      createdAt: DateTime.fromMillisecondsSinceEpoch(row['created_at']! as int),
      updatedAt: DateTime.fromMillisecondsSinceEpoch(row['updated_at']! as int),
    );
  }

  Map<String, Object?> toMap() => <String, Object?>{
        'id': id,
        'name': name,
        'body': body,
        'category': category,
        'builtin': builtin ? 1 : 0,
        'created_at': createdAt.millisecondsSinceEpoch,
        'updated_at': updatedAt.millisecondsSinceEpoch,
      };
}
