// Repository for the `attachments` table.

import 'package:sqflite_common/sqflite.dart';

import '../models/models.dart';

class AttachmentRepository {
  AttachmentRepository(this._db);
  final Database _db;

  Future<List<Attachment>> listForMessage(String messageId) async {
    final rows = await _db.query(
      'attachments',
      where: 'message_id = ?',
      whereArgs: [messageId],
      orderBy: 'created_at ASC',
    );
    return rows.map(Attachment.fromMap).toList(growable: false);
  }

  /// Returns all attachments across all chats, newest first.
  /// Joins the `messages` table to get the chat id and the chat title via
  /// the `chats` table.
  Future<List<AttachmentWithChat>> listAll() async {
    final rows = await _db.rawQuery('''
      SELECT a.*, m.chat_id AS chat_id, c.title AS chat_title
      FROM attachments a
      LEFT JOIN messages m ON a.message_id = m.id
      LEFT JOIN chats c ON m.chat_id = c.id
      ORDER BY a.created_at DESC
    ''');
    return rows.map(AttachmentWithChat.fromMap).toList(growable: false);
  }

  Future<void> upsert(Attachment a) async {
    await _db.insert('attachments', a.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> delete(String id) async {
    await _db.delete('attachments', where: 'id = ?', whereArgs: [id]);
  }
}

/// Attachment row joined with its parent chat's title (for the Files
/// library view).
class AttachmentWithChat {
  const AttachmentWithChat({
    required this.attachment,
    required this.chatId,
    required this.chatTitle,
  });

  final Attachment attachment;
  final String? chatId;
  final String? chatTitle;

  factory AttachmentWithChat.fromMap(Map<String, Object?> row) {
    return AttachmentWithChat(
      attachment: Attachment(
        id: row['id']! as String,
        messageId: row['message_id']! as String,
        filename: row['filename']! as String,
        mimeType: row['mime_type']! as String,
        byteSize: row['byte_size']! as int,
        localPath: row['local_path'] as String?,
        remoteId: row['remote_id'] as String?,
        createdAt: DateTime.fromMillisecondsSinceEpoch(
            row['created_at']! as int),
      ),
      chatId: row['chat_id'] as String?,
      chatTitle: row['chat_title'] as String?,
    );
  }
}
