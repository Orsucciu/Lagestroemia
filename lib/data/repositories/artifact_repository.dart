// Repository for the `artifacts` table.

import 'package:sqflite_common/sqflite.dart';

import '../models/models.dart';

class ArtifactRepository {
  ArtifactRepository(this._db);
  final Database _db;

  /// Returns all artifacts across all chats, newest first. Used by the
  /// Library → Artifacts view.
  Future<List<Artifact>> listAll() async {
    final rows = await _db.query('artifacts', orderBy: 'created_at DESC');
    return rows.map(Artifact.fromMap).toList(growable: false);
  }

  Future<List<Artifact>> listForMessage(String messageId) async {
    final rows = await _db.query(
      'artifacts',
      where: 'message_id = ?',
      whereArgs: [messageId],
      orderBy: 'created_at ASC',
    );
    return rows.map(Artifact.fromMap).toList(growable: false);
  }

  Future<void> upsert(Artifact a) async {
    await _db.insert('artifacts', a.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> delete(String id) async {
    await _db.delete('artifacts', where: 'id = ?', whereArgs: [id]);
  }
}
