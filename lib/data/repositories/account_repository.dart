// Repository for the `accounts` table.

import 'package:sqflite_common/sqflite.dart';

import '../models/models.dart';

class AccountRepository {
  AccountRepository(this._db);
  final Database _db;

  /// MVP: always returns one row with id = 'default'. If it does not exist
  /// yet, this returns null and the caller is expected to create it from
  /// AppConfig defaults.
  Future<Account?> findDefault() async {
    final rows = await _db.query('accounts',
        where: "id = 'default'");
    if (rows.isEmpty) return null;
    return Account.fromMap(rows.first);
  }

  Future<void> upsert(Account a) async {
    await _db.insert('accounts', a.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> touchLastUsed() async {
    await _db.update(
      'accounts',
      {'last_used_at': DateTime.now().toUtc().millisecondsSinceEpoch},
      where: "id = 'default'",
    );
  }
}
