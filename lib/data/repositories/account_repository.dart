// Repository for the `accounts` table.
//
// Stores metadata (label + base URL + timestamps) for one or more
// accounts. The API key / JWT secret for each account lives in the
// OS keychain under a per-account key (see [SecureStorageService]).

import 'package:sqflite_common/sqflite.dart';

import '../models/models.dart';

class AccountRepository {
  AccountRepository(this._db);
  final Database _db;

  /// Returns all accounts, sorted by `last_used_at DESC` (most-recent
  /// first, never-used accounts last).
  Future<List<Account>> listAll() async {
    final rows = await _db.query(
      'accounts',
      orderBy: 'last_used_at DESC, created_at DESC',
    );
    return rows.map(Account.fromMap).toList(growable: false);
  }

  /// Returns one account by id, or null.
  Future<Account?> findById(String id) async {
    final rows =
        await _db.query('accounts', where: 'id = ?', whereArgs: [id]);
    if (rows.isEmpty) return null;
    return Account.fromMap(rows.first);
  }

  /// Convenience: returns the 'default' account. For multi-account UI
  /// use [listAll] instead.
  Future<Account?> findDefault() async => findById('default');

  /// Inserts or replaces an account row.
  Future<void> upsert(Account a) async {
    await _db.insert('accounts', a.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  /// Updates `last_used_at` for the given account. Called when the
  /// user picks the account in the switcher.
  Future<void> touchLastUsed(String id) async {
    await _db.update(
      'accounts',
      {'last_used_at': DateTime.now().toUtc().millisecondsSinceEpoch},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// Deletes an account. Returns the number of rows deleted (0 or 1).
  Future<int> delete(String id) async {
    return _db.delete('accounts', where: 'id = ?', whereArgs: [id]);
  }
}
