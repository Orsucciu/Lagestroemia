// SQLite database for the local cache of chats, messages, documents,
// artifacts, system prompts and settings.
//
// Schema design:
//  - `chats`          — one row per conversation. A chat owns messages.
//  - `messages`       — one row per assistant/user/tool message in a chat.
//                      Multi-modal content is stored as JSON in `content_json`.
//  - `attachments`   — one row per file attached to a message. References
//                      the local file path or a z.ai file id.
//  - `artifacts`      — one row per generated code/document artifact produced
//                      by an assistant message. Indexed by message id.
//  - `system_prompts` — saved system prompts (reusable across chats).
//  - `accounts`       — locally cached profile info for each API key.
//  - `kv`             — generic key/value store for settings not big enough
//                      to deserve a dedicated column.
//
// The schema lives in a single `_schemaV1` string. Future migrations add
// further `_schemaV2`, ... blocks and are run conditionally inside
// [DatabaseHelper._migrate]. The user_version PRAGMA is the migration pointer.

import 'dart:convert' show jsonEncode, jsonDecode;

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:logging/logging.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_common/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:sqflite_common_ffi_web/sqflite_ffi_web.dart';

import '../../core/platform/platform_info.dart';

/// One-line schema for v1. Each statement is separated by a `;`.
const String _schemaV1 = '''
CREATE TABLE chats (
  id            TEXT PRIMARY KEY,
  title         TEXT NOT NULL,
  model         TEXT,
  system_prompt_id TEXT,
  created_at    INTEGER NOT NULL,
  updated_at    INTEGER NOT NULL,
  archived      INTEGER NOT NULL DEFAULT 0
);

CREATE TABLE messages (
  id            TEXT PRIMARY KEY,
  chat_id       TEXT NOT NULL,
  role          TEXT NOT NULL,           -- 'user' | 'assistant' | 'tool' | 'system'
  content       TEXT NOT NULL,           -- plain text for display
  content_json  TEXT,                    -- JSON for multi-modal content (vision, files)
  reasoning     TEXT,                    -- reasoning_content (GLM-4.6+) or NULL
  tool_calls    TEXT,                    -- JSON array of tool_call objects
  created_at    INTEGER NOT NULL,
  FOREIGN KEY(chat_id) REFERENCES chats(id) ON DELETE CASCADE
);
CREATE INDEX idx_messages_chat ON messages(chat_id, created_at);

CREATE TABLE attachments (
  id            TEXT PRIMARY KEY,
  message_id    TEXT NOT NULL,
  filename      TEXT NOT NULL,
  mime_type     TEXT NOT NULL,
  byte_size     INTEGER NOT NULL,
  local_path    TEXT,                    -- absolute path under app data dir, or NULL
  remote_id     TEXT,                    -- z.ai /paas/v4/files id, or NULL
  created_at    INTEGER NOT NULL,
  FOREIGN KEY(message_id) REFERENCES messages(id) ON DELETE CASCADE
);
CREATE INDEX idx_attachments_message ON attachments(message_id);

CREATE TABLE artifacts (
  id            TEXT PRIMARY KEY,
  message_id    TEXT NOT NULL,
  kind          TEXT NOT NULL,           -- 'code' | 'markdown' | 'html' | 'svg' | 'json'
  language      TEXT,                    -- for code: 'dart', 'python', ...
  name          TEXT,                    -- user-visible title
  body          TEXT NOT NULL,           -- the artifact content
  created_at    INTEGER NOT NULL,
  FOREIGN KEY(message_id) REFERENCES messages(id) ON DELETE CASCADE
);
CREATE INDEX idx_artifacts_message ON artifacts(message_id);

CREATE TABLE system_prompts (
  id            TEXT PRIMARY KEY,
  name          TEXT NOT NULL,
  body          TEXT NOT NULL,
  category      TEXT,
  builtin       INTEGER NOT NULL DEFAULT 0,
  created_at    INTEGER NOT NULL,
  updated_at    INTEGER NOT NULL
);

CREATE TABLE accounts (
  id            TEXT PRIMARY KEY,        -- 'default' for now; multi-account comes later
  label         TEXT NOT NULL,
  api_base_url  TEXT NOT NULL,
  -- The API key itself is stored in OS secure storage, NOT here.
  -- We only keep non-sensitive metadata.
  created_at    INTEGER NOT NULL,
  last_used_at  INTEGER
);

CREATE TABLE kv (
  key           TEXT PRIMARY KEY,
  value         TEXT NOT NULL
);
''';

/// Latest schema version. Bump this whenever `_schemaVN` is extended.
const int _latestVersion = 1;

/// Thrown by [DatabaseHelper] for unrecoverable failures.
class DatabaseException implements Exception {
  const DatabaseException(this.message);
  final String message;
  @override
  String toString() => 'DatabaseException: $message';
}

/// Wraps the [DatabaseFactory] + a [Database] instance and exposes a single
/// [database] getter used by repositories.
///
/// Why this exists: SQLite on Flutter needs a different factory per platform:
///  - Linux/Windows desktop   → `databaseFactoryFfi`
///  - Android                 → the bundled `sqflite` plugin (handled by the
///                              package's default factory)
///  - Web (WASM + JS)         → `databaseFactoryFfiWeb`
///
/// We pick the right factory once and pass it to a single [openDatabase]
/// call, so the rest of the app does not need to care about the platform.
class DatabaseHelper {
  DatabaseHelper._();
  /// Test-only constructor that allows subclasses to override [database]
  /// with a custom in-memory database. Used by `auth_state_test.dart`.
  @visibleForTesting
  DatabaseHelper.forTest();
  static final DatabaseHelper instance = DatabaseHelper._();

  static final Logger _log = Logger('lagestroemia.database');

  Database? _db;
  DatabaseFactory? _factory;

  /// Returns the singleton database, opening it lazily on first access.
  Future<Database> get database async {
    if (_db != null && _db!.isOpen) return _db!;
    _db = await _open();
    return _db!;
  }

  /// Returns the [DatabaseFactory] in use. Useful for tests that need to
  /// point at an in-memory database.
  Future<DatabaseFactory> get factory async {
    if (_factory != null) return _factory!;
    _factory = _pickFactory();
    return _factory!;
  }

  /// Closes the database. Used on app shutdown and in tests.
  Future<void> close() async {
    final db = _db;
    if (db != null && db.isOpen) {
      await db.close();
    }
    _db = null;
  }

  Future<Database> _open() async {
    final factory = await this.factory;
    final String path = await _resolvePath();

    _log.info('Opening SQLite database at $path');
    return factory.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: _latestVersion,
        onConfigure: (db) async {
          // Enable foreign keys and cascading deletes.
          await db.execute('PRAGMA foreign_keys = ON');
        },
        onCreate: (db, version) async {
          _log.info('Creating database (v$version)');
          for (final stmt in _splitStatements(_schemaV1)) {
            await db.execute(stmt);
          }
          await db.setVersion(version);
          await _seedBuiltinPrompts(db);
        },
        onUpgrade: (db, oldVersion, newVersion) async {
          _log.info('Upgrading database v$oldVersion → v$newVersion');
          // Future migrations go here. For v1 there is nothing to migrate.
          // Each step upgrades from N to N+1.
          // for (var v = oldVersion + 1; v <= newVersion; v++) { _migrateTo(db, v); }
        },
      ),
    );
  }

  /// Picks the right [DatabaseFactory] for the current platform.
  ///
  /// This is called once. Web must use `databaseFactoryFfiWeb`; native uses
  /// `databaseFactoryFfi`; Android uses the bundled sqflite plugin which is
  /// the default `databaseFactory` global.
  DatabaseFactory _pickFactory() {
    if (PlatformInfo.isWeb) {
      return databaseFactoryFfiWeb;
    }
    if (PlatformInfo.isLinux || PlatformInfo.isWindows || PlatformInfo.isMacOS) {
      sqfliteFfiInit();
      return databaseFactoryFfi;
    }
    // Android / iOS — let the bundled sqflite plugin decide.
    // This branch is reached only when `dart:io` is available and the
    // platform is mobile. The default global is already wired correctly.
    return databaseFactory;
  }

  /// Resolves the absolute path of the SQLite file.
  ///
  /// On native we use `path_provider`'s application-support directory.
  /// On Web the path is just a name (the actual file lives in IndexedDB via
  /// the FFI-web shim).
  Future<String> _resolvePath() async {
    if (PlatformInfo.isWeb) {
      // databaseFactoryFfiWeb uses this as a logical name; it is opaque
      // to the app — the data is stored in IndexedDB under that name.
      return 'lagestroemia.sqlite';
    }
    final dir = await getApplicationSupportDirectory();
    return p.join(dir.path, 'lagestroemia.sqlite');
  }

  Future<void> _seedBuiltinPrompts(Database db) async {
    final now = DateTime.now().toUtc().millisecondsSinceEpoch;
    final entries = <Map<String, Object?>>[
      {
        'id': 'builtin-default',
        'name': 'Default Assistant',
        'body': 'You are a helpful assistant.',
        'category': 'general',
        'builtin': 1,
        'created_at': now,
        'updated_at': now,
      },
      {
        'id': 'builtin-coder',
        'name': 'Code Helper',
        'body':
            'You are a senior software engineer. Answer concisely with code '
            'snippets, comment non-obvious lines, and prefer idiomatic '
            'solutions in the user\'s chosen language.',
        'category': 'coding',
        'builtin': 1,
        'created_at': now,
        'updated_at': now,
      },
      {
        'id': 'builtin-explainer',
        'name': 'Concept Explainer',
        'body': 'You explain concepts clearly, step by step, with one '
            'concrete example per step. You adjust depth to the user\'s '
            'questions.',
        'category': 'learning',
        'builtin': 1,
        'created_at': now,
        'updated_at': now,
      },
      {
        'id': 'builtin-translator',
        'name': 'Translator',
        'body': 'You translate the user\'s text into the language they '
            'name. You preserve tone and structure. If they do not name a '
            'language, you ask.',
        'category': 'language',
        'builtin': 1,
        'created_at': now,
        'updated_at': now,
      },
    ];
    for (final entry in entries) {
      await db.insert('system_prompts', entry,
          conflictAlgorithm: ConflictAlgorithm.ignore);
    }
  }
}

/// Splits a multi-statement SQL string into individual statements, stripping
/// comments and trailing whitespace.
List<String> _splitStatements(String sql) {
  // Strip block comments.
  final noBlocks = sql.replaceAll(RegExp(r'/\*.*?\*/', dotAll: true), '');
  final statements = <String>[];
  for (final raw in noBlocks.split(';')) {
    final stripped = raw.trim();
    // Skip line-comment-only fragments and empties.
    final withoutLineComments = stripped
        .split('\n')
        .where((l) => !l.trimLeft().startsWith('--'))
        .join('\n')
        .trim();
    if (withoutLineComments.isNotEmpty) statements.add(withoutLineComments);
  }
  return statements;
}

/// Tiny JSON helpers exposed for repository code that round-trips multi-modal
/// content. Kept here so model classes do not need to import `dart:convert`
/// directly.
String encodeJson(Object? value) => jsonEncode(value);
Object? decodeJson(String source) => jsonDecode(source);
