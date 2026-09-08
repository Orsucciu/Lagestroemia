// Repository for the `system_prompts` table.

import 'package:sqflite_common/sqflite.dart';

import '../models/models.dart';

class SystemPromptRepository {
  SystemPromptRepository(this._db);
  final Database _db;

  Future<List<SystemPrompt>> listAll() async {
    final rows = await _db.query(
      'system_prompts',
      orderBy: 'builtin DESC, name ASC',
    );
    return rows.map(SystemPrompt.fromMap).toList(growable: false);
  }

  Future<SystemPrompt?> findById(String id) async {
    final rows = await _db.query('system_prompts',
        where: 'id = ?', whereArgs: [id]);
    if (rows.isEmpty) return null;
    return SystemPrompt.fromMap(rows.first);
  }

  Future<void> upsert(SystemPrompt p) async {
    await _db.insert('system_prompts', p.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> delete(String id) async {
    // Builtin prompts cannot be deleted, only hidden. The MVP does not
    // implement hiding — we just refuse here and rely on the UI to never
    // expose a delete button for builtins.
    final row = await findById(id);
    if (row != null && row.builtin) return;
    await _db.delete('system_prompts', where: 'id = ?', whereArgs: [id]);
  }
}
