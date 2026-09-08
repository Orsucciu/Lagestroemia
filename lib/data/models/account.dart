part of 'models.dart';

/// Locally cached metadata about an account. The API key itself is stored
/// in the OS keychain via `flutter_secure_storage`; this row only carries
/// non-sensitive display info (label + base URL + timestamps).
@immutable
class Account {
  const Account({
    required this.id,
    required this.label,
    required this.apiBaseUrl,
    required this.createdAt,
    this.lastUsedAt,
  });

  /// Always `'default'` in the MVP. Reserved for multi-account support.
  final String id;
  final String label;
  final String apiBaseUrl;
  final DateTime createdAt;
  final DateTime? lastUsedAt;

  Account copyWith({
    String? id,
    String? label,
    String? apiBaseUrl,
    DateTime? createdAt,
    Object? lastUsedAt = _sentinel,
  }) {
    return Account(
      id: id ?? this.id,
      label: label ?? this.label,
      apiBaseUrl: apiBaseUrl ?? this.apiBaseUrl,
      createdAt: createdAt ?? this.createdAt,
      lastUsedAt: identical(lastUsedAt, _sentinel)
          ? this.lastUsedAt
          : lastUsedAt as DateTime?,
    );
  }

  factory Account.fromMap(Map<String, Object?> row) {
    return Account(
      id: row['id']! as String,
      label: row['label']! as String,
      apiBaseUrl: row['api_base_url']! as String,
      createdAt: DateTime.fromMillisecondsSinceEpoch(row['created_at']! as int),
      lastUsedAt: row['last_used_at'] == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(row['last_used_at']! as int),
    );
  }

  Map<String, Object?> toMap() => <String, Object?>{
        'id': id,
        'label': label,
        'api_base_url': apiBaseUrl,
        'created_at': createdAt.millisecondsSinceEpoch,
        'last_used_at': lastUsedAt?.millisecondsSinceEpoch,
      };
}
