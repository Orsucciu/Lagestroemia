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

  Future<void> upsert(Attachment a) async {
    await _db.insert('attachments', a.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> delete(String id) async {
    await _db.delete('attachments', where: 'id = ?', whereArgs: [id]);
  }
}
