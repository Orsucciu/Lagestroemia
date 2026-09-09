// Tests for the auth state's new JWT and multi-account features.
//
// These tests use a mock SecureStorageService and an in-memory
// AccountRepository so we can verify the AuthNotifier logic without
// touching the OS keychain or the network.
//
// We can't easily override `accountRepositoryProvider` (which is a
// FutureProvider and doesn't have `overrideWithValue`); instead we use
// the real provider which opens a temporary SQLite database via
// `databaseFactoryFfi`.

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common/sqflite.dart' show Database;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:lagestroemia/core/auth/zai_jwt.dart';
import 'package:lagestroemia/core/storage/secure_storage_service.dart';
import 'package:lagestroemia/data/database/database_helper.dart';
import 'package:lagestroemia/state/auth_state.dart';
import 'package:lagestroemia/state/providers.dart';

class _MockSecureStorage implements SecureStorageService {
  final Map<String, String> _store = {};

  @override
  Future<String?> getApiKey() async => _store['lagestroemia.api_key'];

  @override
  Future<void> setApiKey(String value) async {
    _store['lagestroemia.api_key'] = value;
  }

  @override
  Future<void> deleteApiKey() async {
    _store.remove('lagestroemia.api_key');
  }

  @override
  Future<String?> getApiKeyForAccount(String accountId) async {
    if (accountId == 'default') return _store['lagestroemia.api_key'];
    return _store['lagestroemia.api_key.$accountId'];
  }

  @override
  Future<void> setApiKeyForAccount(String accountId, String value) async {
    if (accountId == 'default') {
      _store['lagestroemia.api_key'] = value;
    } else {
      _store['lagestroemia.api_key.$accountId'] = value;
    }
  }

  @override
  Future<void> deleteApiKeyForAccount(String accountId) async {
    if (accountId == 'default') {
      _store.remove('lagestroemia.api_key');
    } else {
      _store.remove('lagestroemia.api_key.$accountId');
    }
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();

  late ProviderContainer container;
  late _MockSecureStorage secure;
  late SharedPreferences prefs;

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    prefs = await SharedPreferences.getInstance();

    // Point the DatabaseHelper at a temp file for the test run.
    // (DatabaseHelper.instance uses path_provider normally, but in
    // tests we override factory + path.)
    secure = _MockSecureStorage();
    // Reset the static database cache so each test starts fresh.
    _TestDbHelper.resetCache();
    container = ProviderContainer(
      overrides: <Override>[
        secureStorageProvider.overrideWithValue(secure),
        dioProvider.overrideWithValue(Dio()),
        sharedPrefsProvider.overrideWithValue(prefs),
        databaseHelperProvider.overrideWithValue(_TestDbHelper()),
      ],
    );
  });

  tearDown(() async {
    container.dispose();
  });

  group('AuthState JWT mode', () {
    test('bearerToken returns raw key when useJwtAuth is false', () {
      final state = AuthState(
        mode: AuthMode.apiKey,
        apiKey: 'testid.testsecret',
        useJwtAuth: false,
        status: AuthStatus.signedIn,
      );
      expect(state.bearerToken, 'testid.testsecret');
    });

    test('bearerToken returns signed JWT when useJwtAuth is true', () {
      final state = AuthState(
        mode: AuthMode.apiKey,
        apiKey: 'testid.testsecret',
        useJwtAuth: true,
        status: AuthStatus.signedIn,
      );
      final token = state.bearerToken;
      expect(token, isNotNull);
      // Should look like a JWT (three dot-separated base64url parts).
      expect(token!.split('.').length, 3);
    });

    test('bearerToken falls back to raw key when key is not composite', () {
      final state = AuthState(
        mode: AuthMode.apiKey,
        apiKey: 'just-an-api-key-without-dot',
        useJwtAuth: true,
        status: AuthStatus.signedIn,
      );
      // useJwtAuth is on but key has no dot → falls back to raw key.
      expect(state.bearerToken, 'just-an-api-key-without-dot');
    });

    test('bearerToken returns null when not signed in', () {
      const state = AuthState(mode: AuthMode.apiKey);
      expect(state.bearerToken, isNull);
    });
  });

  group('AuthNotifier multi-account (with real database)', () {
    test('addAccount persists and switches to the new account', () async {
      final auth = container.read(authStateProvider.notifier);
      final ok = await auth.addAccount(
        id: 'work',
        label: 'Work account',
        apiKey: 'workid.worksecret',
      );
      expect(ok, isTrue);
      final state = container.read(authStateProvider);
      expect(state.accountId, 'work');
      expect(state.apiKey, 'workid.worksecret');
      expect(state.mode, AuthMode.apiKey);

      // Stored in the per-account slot in secure storage.
      final stored = await secure.getApiKeyForAccount('work');
      expect(stored, 'workid.worksecret');
    });

    test('addAccount returns false if id already exists', () async {
      final auth = container.read(authStateProvider.notifier);
      await auth.addAccount(
        id: 'work',
        label: 'Work account',
        apiKey: 'workid.worksecret',
      );
      // Reset state and try again with same id.
      final ok = await auth.addAccount(
        id: 'work',
        label: 'Other',
        apiKey: 'other',
      );
      expect(ok, isFalse);
    });

    test('switchToAccount loads the key from secure storage', () async {
      final auth = container.read(authStateProvider.notifier);
      await auth.addAccount(
        id: 'work',
        label: 'Work',
        apiKey: 'workid.worksecret',
      );
      // The state now has accountId='work'. To verify switchToAccount
      // works, we need to be on a different account first — use
      // signInWithKey on 'default' to set a different account.
      // (We can't call switchToAccount('default') because that needs a
      // stored key, which we don't have.)
      // Instead, manually re-create the AuthState via the addAccount
      // path to verify switchToAccount works.
      // First, add a second account we can switch away to.
      await auth.addAccount(
        id: 'personal',
        label: 'Personal',
        apiKey: 'personalid.personalsecret',
      );
      expect(container.read(authStateProvider).accountId, 'personal');
      // Now switch back to 'work'.
      final ok = await auth.switchToAccount('work');
      expect(ok, isTrue);
      expect(container.read(authStateProvider).accountId, 'work');
      expect(
          container.read(authStateProvider).apiKey, 'workid.worksecret');
    });

    test('switchToAccount returns false for unknown account', () async {
      final auth = container.read(authStateProvider.notifier);
      final ok = await auth.switchToAccount('does-not-exist');
      expect(ok, isFalse);
    });

    test('deleteAccount refuses to delete the default account', () async {
      final auth = container.read(authStateProvider.notifier);
      final ok = await auth.deleteAccount('default');
      expect(ok, isFalse);
    });

    test('setUseJwtAuth toggles and persists to prefs', () async {
      final auth = container.read(authStateProvider.notifier);
      // Sign in with a composite key.
      await auth.signInWithKey('testid.testsecret');
      expect(container.read(authStateProvider).useJwtAuth, isFalse);
      // Turn on.
      await auth.setUseJwtAuth(true);
      expect(container.read(authStateProvider).useJwtAuth, isTrue);
      expect(prefs.getBool('lagestroemia.use_jwt_auth'), isTrue);
      // Turn off.
      await auth.setUseJwtAuth(false);
      expect(container.read(authStateProvider).useJwtAuth, isFalse);
      expect(prefs.getBool('lagestroemia.use_jwt_auth'), isFalse);
    });

    test('setUseJwtAuth refuses to turn on when key is not composite',
        () async {
      final auth = container.read(authStateProvider.notifier);
      await auth.signInWithKey('just-a-key-without-dot');
      await auth.setUseJwtAuth(true);
      // Should have been rejected.
      expect(container.read(authStateProvider).useJwtAuth, isFalse);
    });
  });

  group('JWT signed by AuthState.bearerToken matches Python reference', () {
    test('with testid.testsecret at 2025-01-01 00:00 UTC', () {
      final parts = ZaiApiKeyParts(id: 'testid', secret: 'testsecret');
      final jwt = signZaiJwt(
        parts: parts,
        now: DateTime.utc(2025, 1, 1, 0, 0, 0),
      );
      const expected =
          'eyJhbGciOiJIUzI1NiIsInNpZ25fdHlwZSI6IlNJR04iLCJ0eXAiOiJKV1QifQ'
          '.eyJhcGlfa2V5IjoidGVzdGlkIiwiZXhwIjoxNzM1NjkzMjAwMDAwLCJ0aW1l'
          'c3RhbXAiOjE3MzU2ODk2MDAwMDB9.Sn_GgYe5VQf6Vl2zKKv_J477yAs-smpB'
          '3s5wJA3x79w';
      expect(jwt, expected);
    });
  });
}

/// Test-only DatabaseHelper that uses an in-memory SQLite database.
class _TestDbHelper extends DatabaseHelper {
  _TestDbHelper() : super.forTest();

  /// Cached in-memory database so subsequent reads return the same
  /// instance (otherwise each `database` getter call would open a new
  /// :memory: db and the data wouldn't survive between calls).
  static Database? _cache;

  /// Clears the cache. Called from `setUp` so each test starts with
  /// a fresh database.
  static void resetCache() {
    _cache = null;
  }

  @override
  Future<Database> get database async {
    if (_cache != null) return _cache!;
    final factory = databaseFactoryFfi;
    _cache = await factory.openDatabase(
      // Use a unique name so different test runs don't share state via
      // the sqflite_common_ffi process pool.
      'test-${DateTime.now().microsecondsSinceEpoch}.db',
      options: OpenDatabaseOptions(
        version: 1,
        onCreate: (db, _) async {
          await db.execute('CREATE TABLE chats (id TEXT PRIMARY KEY, title '
              'TEXT NOT NULL, model TEXT, system_prompt_id TEXT, created_at '
              'INTEGER NOT NULL, updated_at INTEGER NOT NULL, archived INTEGER '
              'NOT NULL DEFAULT 0)');
          await db.execute('CREATE TABLE messages (id TEXT PRIMARY KEY, '
              'chat_id TEXT NOT NULL, role TEXT NOT NULL, content TEXT NOT '
              'NULL, content_json TEXT, reasoning TEXT, tool_calls TEXT, '
              'created_at INTEGER NOT NULL)');
          await db.execute('CREATE TABLE attachments (id TEXT PRIMARY KEY, '
              'message_id TEXT NOT NULL, filename TEXT NOT NULL, mime_type '
              'TEXT NOT NULL, byte_size INTEGER NOT NULL, local_path TEXT, '
              'remote_id TEXT, created_at INTEGER NOT NULL)');
          await db.execute('CREATE TABLE artifacts (id TEXT PRIMARY KEY, '
              'message_id TEXT NOT NULL, kind TEXT NOT NULL, language TEXT, '
              'name TEXT, body TEXT NOT NULL, created_at INTEGER NOT NULL)');
          await db.execute('CREATE TABLE system_prompts (id TEXT PRIMARY '
              'KEY, name TEXT NOT NULL, body TEXT NOT NULL, category TEXT, '
              'builtin INTEGER NOT NULL DEFAULT 0, created_at INTEGER NOT '
              'NULL, updated_at INTEGER NOT NULL)');
          await db.execute('CREATE TABLE accounts (id TEXT PRIMARY KEY, '
              'label TEXT NOT NULL, api_base_url TEXT NOT NULL, created_at '
              'INTEGER NOT NULL, last_used_at INTEGER)');
          await db.execute('CREATE TABLE kv (key TEXT PRIMARY KEY, value '
              'TEXT NOT NULL)');
        },
      ),
    );
    return _cache!;
  }
}
