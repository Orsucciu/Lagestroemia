// Repository for the `messages` table.

import 'package:sqflite_common/sqflite.dart';

import '../models/models.dart';
import 'package:logging/logging.dart';

class MessageRepository {
  MessageRepository(this._db);
  final Database _db;
  static final Logger _log = Logger('lagestroemia.repo.message');

  /// Returns all messages in a chat, oldest first.
  Future<List<ChatMessage>> listForChat(String chatId) async {
    final rows = await _db.query(
      'messages',
      where: 'chat_id = ?',
      whereArgs: [chatId],
      orderBy: 'created_at ASC',
    );
    return rows.map(ChatMessage.fromMap).toList(growable: false);
  }

  /// Returns a single message by id, or null.
  Future<ChatMessage?> findById(String id) async {
    final rows = await _db.query('messages', where: 'id = ?', whereArgs: [id]);
    if (rows.isEmpty) return null;
    return ChatMessage.fromMap(rows.first);
  }

  /// Inserts or replaces a message.
  Future<void> upsert(ChatMessage msg) async {
    _log.fine('upsert message ${msg.id} role=${msg.role.wire} '
        'len=${msg.content.length}');
    await _db.insert('messages', msg.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  /// Updates the assistant message's content (used while streaming — we
  /// persist every chunk so a crashed app resumes from the last seen token).
  Future<void> updateContent(
    String id, {
    String? content,
    String? reasoning,
    String? toolCalls,
  }) async {
    final values = <String, Object?>{};
    if (content != null) values['content'] = content;
    if (reasoning != null) values['reasoning'] = reasoning;
    if (toolCalls != null) values['tool_calls'] = toolCalls;
    if (values.isEmpty) return;
    await _db.update('messages', values,
        where: 'id = ?', whereArgs: [id]);
  }

  /// Deletes a message.
  Future<void> delete(String id) async {
    await _db.delete('messages', where: 'id = ?', whereArgs: [id]);
  }
}
