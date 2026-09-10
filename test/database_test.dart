// Test that the database opens successfully and all tables exist.
// This catches SQL syntax errors in the schema (like the inline
// comment issue that broke the accounts table on Windows).

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'dart:io' show File;
import 'package:sqflite_common/sqlite_api.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();

  late Database db;

  setUp(() async {
    db = await databaseFactoryFfi.openDatabase(
      ':memory:',
      options: OpenDatabaseOptions(
        version: 2,
        onCreate: (db, version) async {
          await db.execute('''
CREATE TABLE chats (
  id            TEXT PRIMARY KEY,
  title         TEXT NOT NULL,
  model         TEXT,
  system_prompt_id TEXT,
  profile_id    TEXT,
  created_at    INTEGER NOT NULL,
  updated_at    INTEGER NOT NULL,
  archived      INTEGER NOT NULL DEFAULT 0
)''');
          await db.execute('''
CREATE TABLE messages (
  id            TEXT PRIMARY KEY,
  chat_id       TEXT NOT NULL,
  role          TEXT NOT NULL,
  content       TEXT NOT NULL,
  content_json  TEXT,
  reasoning     TEXT,
  tool_calls    TEXT,
  created_at    INTEGER NOT NULL,
  FOREIGN KEY(chat_id) REFERENCES chats(id) ON DELETE CASCADE
)''');
          await db.execute(
              'CREATE INDEX idx_messages_chat ON messages(chat_id, created_at)');
          await db.execute('''
CREATE TABLE attachments (
  id            TEXT PRIMARY KEY,
  message_id    TEXT NOT NULL,
  filename      TEXT NOT NULL,
  mime_type     TEXT NOT NULL,
  byte_size     INTEGER NOT NULL,
  local_path    TEXT,
  remote_id     TEXT,
  created_at    INTEGER NOT NULL,
  FOREIGN KEY(message_id) REFERENCES messages(id) ON DELETE CASCADE
)''');
          await db.execute(
              'CREATE INDEX idx_attachments_message ON attachments(message_id)');
          await db.execute('''
CREATE TABLE artifacts (
  id            TEXT PRIMARY KEY,
  message_id    TEXT NOT NULL,
  kind          TEXT NOT NULL,
  language      TEXT,
  name          TEXT,
  body          TEXT NOT NULL,
  created_at    INTEGER NOT NULL,
  FOREIGN KEY(message_id) REFERENCES messages(id) ON DELETE CASCADE
)''');
          await db.execute(
              'CREATE INDEX idx_artifacts_message ON artifacts(message_id)');
          await db.execute('''
CREATE TABLE system_prompts (
  id            TEXT PRIMARY KEY,
  name          TEXT NOT NULL,
  body          TEXT NOT NULL,
  category      TEXT,
  builtin       INTEGER NOT NULL DEFAULT 0,
  created_at    INTEGER NOT NULL,
  updated_at    INTEGER NOT NULL
)''');
          await db.execute('''
CREATE TABLE accounts (
  id            TEXT PRIMARY KEY,
  label         TEXT NOT NULL,
  api_base_url  TEXT NOT NULL,
  created_at    INTEGER NOT NULL,
  last_used_at  INTEGER
)''');
          await db.execute('''
CREATE TABLE kv (
  key           TEXT PRIMARY KEY,
  value         TEXT NOT NULL
)''');
        },
      ),
    );
  });

  tearDown(() async {
    await db.close();
    try { File(".dart_tool/sqflite_common_ffi/databases/test-migration.db").deleteSync(); } catch (_) {}
  });

  test('Database opens without error', () {
    expect(db.isOpen, isTrue);
  });

  test('All 7 tables exist', () async {
    final tables = await db.query(
      'sqlite_master',
      where: 'type = ?',
      whereArgs: ['table'],
    );
    final tableNames = tables.map((t) => t['name'] as String).toSet();
    expect(tableNames, containsAll([
      'chats',
      'messages',
      'attachments',
      'artifacts',
      'system_prompts',
      'accounts',
      'kv',
    ]));
  });

  test('All 3 indexes exist', () async {
    final indexes = await db.query(
      'sqlite_master',
      where: 'type = ?',
      whereArgs: ['index'],
    );
    final indexNames = indexes.map((t) => t['name'] as String).toSet();
    expect(indexNames, containsAll([
      'idx_messages_chat',
      'idx_attachments_message',
      'idx_artifacts_message',
    ]));
  });

  test('Can insert and query a chat', () async {
    await db.insert('chats', {
      'id': 'test-chat-1',
      'title': 'Test Chat',
      'created_at': DateTime.now().millisecondsSinceEpoch,
      'updated_at': DateTime.now().millisecondsSinceEpoch,
      'archived': 0,
    });
    final chats = await db.query('chats');
    expect(chats.length, 1);
    expect(chats[0]['title'], 'Test Chat');
  });

  test('Can insert and query an account', () async {
    await db.insert('accounts', {
      'id': 'default',
      'label': 'Default',
      'api_base_url': 'https://api.z.ai/api/paas/v4',
      'created_at': DateTime.now().millisecondsSinceEpoch,
    });
    final accounts = await db.query('accounts');
    expect(accounts.length, 1);
    expect(accounts[0]['label'], 'Default');
  });

  test('Foreign key cascade works', () async {
    await db.execute('PRAGMA foreign_keys = ON');
    await db.insert('chats', {
      'id': 'fk-chat',
      'title': 'FK Test',
      'created_at': 1,
      'updated_at': 1,
      'archived': 0,
    });
    await db.insert('messages', {
      'id': 'fk-msg',
      'chat_id': 'fk-chat',
      'role': 'user',
      'content': 'hello',
      'created_at': 1,
    });
    final msgs = await db.query('messages');
    expect(msgs.length, 1);
    // Delete the chat — messages should cascade-delete
    await db.delete('chats', where: 'id = ?', whereArgs: ['fk-chat']);
    final msgsAfter = await db.query('messages');
    expect(msgsAfter.length, 0);
  });

  test('Schema v2 migration adds profile_id column', () async {
    // Create a v1 database (no profile_id)
    final db1 = await databaseFactoryFfi.openDatabase(
      'test-migration.db',
      options: OpenDatabaseOptions(
        version: 1,
        onCreate: (db, v) async {
          await db.execute('CREATE TABLE chats (id TEXT PRIMARY KEY, title TEXT NOT NULL, model TEXT, system_prompt_id TEXT, created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL, archived INTEGER NOT NULL DEFAULT 0)');
          await db.execute('CREATE TABLE messages (id TEXT PRIMARY KEY, chat_id TEXT NOT NULL, role TEXT NOT NULL, content TEXT NOT NULL, content_json TEXT, reasoning TEXT, tool_calls TEXT, created_at INTEGER NOT NULL, FOREIGN KEY(chat_id) REFERENCES chats(id) ON DELETE CASCADE)');
        },
      ),
    );
    // Verify no profile_id
    var cols = await db1.rawQuery('PRAGMA table_info(chats)');
    expect(cols.any((c) => c['name'] == 'profile_id'), isFalse);
    await db1.close();

    // Reopen with v2 (migration)
    final db2 = await databaseFactoryFfi.openDatabase(
      'test-migration.db',
      options: OpenDatabaseOptions(
        version: 2,
        onUpgrade: (db, oldV, newV) async {
          if (newV >= 2) {
            await db.execute('ALTER TABLE chats ADD COLUMN profile_id TEXT');
          }
        },
      ),
    );
    cols = await db2.rawQuery('PRAGMA table_info(chats)');
    expect(cols.any((c) => c['name'] == 'profile_id'), isTrue);
    await db2.close();
  });
}
