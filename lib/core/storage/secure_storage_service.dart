// Wraps `flutter_secure_storage` so the rest of the app does not have to
// know about platform-specific keychain quirks.
//
// Supports multi-account storage: each account has its own API key slot
// in the OS keychain, namespaced by the account id. The "default"
// account uses the legacy keys for backwards compatibility.

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:logging/logging.dart';

import '../config/app_config.dart';

/// Thrown if secure storage is not available on the current platform.
class SecureStorageException implements Exception {
  const SecureStorageException(this.message);
  final String message;
  @override
  String toString() => 'SecureStorageException: $message';
}

/// Encapsulates access to the OS keychain / browser storage.
class SecureStorageService {
  SecureStorageService([FlutterSecureStorage? storage])
      : _storage = storage ??
            const FlutterSecureStorage(
              aOptions: AndroidOptions(encryptedSharedPreferences: true),
              iOptions: IOSOptions(),
              lOptions: LinuxOptions(),
              wOptions: WindowsOptions(),
              webOptions: WebOptions(),
            );

  final FlutterSecureStorage _storage;
  static final Logger _log = Logger('lagestroemia.storage.secure');

  // ---- Legacy single-account helpers (kept for backwards compat) ------

  Future<String?> getApiKey() async => _read(AppConfig.secureKeyApiKey);
  Future<void> setApiKey(String value) async =>
      _write(AppConfig.secureKeyApiKey, value);
  Future<void> deleteApiKey() async => _delete(AppConfig.secureKeyApiKey);

  // ---- Per-account helpers (multi-account support, issue #12) --------

  /// Returns the API key for the given account id, or null if not stored.
  ///
  /// For the 'default' account this reads the legacy key so existing
  /// installs keep working. For other ids this reads
  /// `lagestroemia.api_key.<id>`.
  Future<String?> getApiKeyForAccount(String accountId) async {
    if (accountId == 'default') return _read(AppConfig.secureKeyApiKey);
    return _read('${AppConfig.secureKeyApiKey}.$accountId');
  }

  /// Writes the API key for the given account id.
  Future<void> setApiKeyForAccount(String accountId, String value) async {
    if (accountId == 'default') {
      await _write(AppConfig.secureKeyApiKey, value);
      return;
    }
    await _write('${AppConfig.secureKeyApiKey}.$accountId', value);
  }

  /// Deletes the API key for the given account id.
  Future<void> deleteApiKeyForAccount(String accountId) async {
    if (accountId == 'default') {
      await _delete(AppConfig.secureKeyApiKey);
      return;
    }
    await _delete('${AppConfig.secureKeyApiKey}.$accountId');
  }

  // ---- low-level primitives -------------------------------------------

  Future<String?> _read(String key) async {
    try {
      return await _storage.read(key: key);
    } catch (e) {
      _log.warning('read($key) failed: $e');
      throw SecureStorageException('Could not read $key: $e');
    }
  }

  Future<void> _write(String key, String value) async {
    try {
      await _storage.write(key: key, value: value);
    } catch (e) {
      _log.warning('write($key) failed: $e');
      throw SecureStorageException('Could not write $key: $e');
    }
  }

  Future<void> _delete(String key) async {
    try {
      await _storage.delete(key: key);
    } catch (e) {
      _log.warning('delete($key) failed: $e');
      throw SecureStorageException('Could not delete $key: $e');
    }
  }
}
