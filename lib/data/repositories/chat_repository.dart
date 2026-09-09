// Repository for the `chats` table.
//
// All chat CRUD operations go through here. The repository keeps the
// database lookup logic in one place; the UI never touches SQL directly.

import 'package:sqflite_common/sqflite.dart';

import '../models/models.dart';
import 'package:logging/logging.dart';

class ChatRepository {
  ChatRepository(this._db);
  final Database _db;
  static final Logger _log = Logger('lagestroemia.repo.chat');

  /// Returns all non-archived chats, newest first.
  Future<List<Chat>> list({bool includeArchived = false}) async {
    final rows = await _db.query(
      'chats',
      where: includeArchived ? null : 'archived = 0',
      orderBy: 'updated_at DESC',
    );
    return rows.map(Chat.fromMap).toList(growable: false);
  }

  /// Returns one chat by id, or null.
  Future<Chat?> findById(String id) async {
    final rows = await _db.query('chats', where: 'id = ?', whereArgs: [id]);
    if (rows.isEmpty) return null;
    return Chat.fromMap(rows.first);
  }

  /// Inserts or replaces a chat row.
  Future<void> upsert(Chat chat) async {
    _log.fine('upsert chat ${chat.id} title="${chat.title}"');
    await _db.insert('chats', chat.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  /// Updates only `title`, `model`, `system_prompt_id`, `archived`,
  /// `updated_at`. Faster than [upsert] for the common "rename" case.
  Future<void> updateMeta(Chat chat) async {
    await _db.update(
      'chats',
      {
        'title': chat.title,
        'model': chat.model,
        'system_prompt_id': chat.systemPromptId,
        'archived': chat.archived ? 1 : 0,
        'updated_at': chat.updatedAt.millisecondsSinceEpoch,
      },
      where: 'id = ?',
      whereArgs: [chat.id],
    );
  }

  /// Deletes a chat and all its messages, attachments and artifacts (cascade).
  Future<void> delete(String id) async {
    _log.fine('delete chat $id');
    await _db.delete('chats', where: 'id = ?', whereArgs: [id]);
  }

  /// Convenience: creates a new chat with sensible defaults.
  Future<Chat> create({String? title, String? model, String? systemPromptId}) async {
    final now = DateTime.now().toUtc();
    final chat = Chat(
      id: _uuid(),
      title: title ?? 'New chat',
      model: model,
      systemPromptId: systemPromptId,
      createdAt: now,
      updatedAt: now,
      archived: false,
    );
    await upsert(chat);
    return chat;
  }

  /// Touch the updated_at timestamp. Called whenever a new message is added
  /// to the chat so the chat list ordering stays correct.
  Future<void> touch(String id) async {
    await _db.update(
      'chats',
      {'updated_at': DateTime.now().toUtc().millisecondsSinceEpoch},
      where: 'id = ?',
      whereArgs: [id],
    );
  }
}

/// Trivial UUID v4 generator. We avoid pulling in a `uuid` package just for
/// this one call site.
String _uuid() {
  // Adapted from the public-domain snippet in RFC 4122 §4.4.
  final r = List<int>.generate(16, (_) => _randomByte());
  r[6] = (r[6] & 0x0f) | 0x40; // version 4
  r[8] = (r[8] & 0x3f) | 0x80; // variant 10
  final hex = r.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
      '${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
}

int _randomByte() {
  // DateTime.now().microsecondsSinceEpoch gives ~1us resolution. We XOR
  // several sources to reduce correlation.
  final now = DateTime.now().microsecondsSinceEpoch;
  return (now ^ (now >> 8) ^ (now >> 16) ^ (now >> 24)) & 0xff;
}
