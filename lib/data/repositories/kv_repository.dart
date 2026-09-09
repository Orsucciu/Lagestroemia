// Generic KV store backed by the `kv` table. Used for settings that don't
// deserve their own column (e.g. last-selected system prompt id, last window
// size, recent search queries).

import 'package:sqflite_common/sqflite.dart';

class KvRepository {
  KvRepository(this._db);
  final Database _db;

  Future<String?> get(String key) async {
    final rows = await _db.query('kv', where: 'key = ?', whereArgs: [key]);
    if (rows.isEmpty) return null;
    return rows.first['value'] as String;
  }

  Future<void> set(String key, String value) async {
    await _db.insert('kv', {'key': key, 'value': value},
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> remove(String key) async {
    await _db.delete('kv', where: 'key = ?', whereArgs: [key]);
  }
}
