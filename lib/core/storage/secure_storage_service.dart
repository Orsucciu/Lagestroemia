// Wraps `flutter_secure_storage` so the rest of the app does not have to
// know about platform-specific keychain quirks. We expose two helpers:
//  - `getApiKey()` / `setApiKey()` for the z.ai Bearer token,
//  - `getJwtSecret()` / `setJwtSecret()` for the optional JWT signing
//    secret that some z.ai API keys (in form `<id>.<secret>`) come with.

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:logging/logging.dart';

import '../config/app_config.dart';

/// Thrown if secure storage is not available on the current platform (e.g.
/// the Web target without secure context, or an unrooted Android).
class SecureStorageException implements Exception {
  const SecureStorageException(this.message);
  final String message;
  @override
  String toString() => 'SecureStorageException: $message';
}

/// Encapsulates access to the OS keychain / browser storage.
///
/// On Linux this uses `libsecret` (via `secret_storage`) which the user
/// must have set up (typically the GNOME keyring is running). On Windows
/// this uses the Credential Manager. On Android this uses the Android
/// Keystore. On Web this falls back to browser-local `sessionStorage`
/// (encrypted with a per-session key) — the MVP does not promise at-rest
/// security on the Web target.
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

  Future<String?> getApiKey() async => _read(AppConfig.secureKeyApiKey);
  Future<void> setApiKey(String value) async =>
      _write(AppConfig.secureKeyApiKey, value);
  Future<void> deleteApiKey() async => _delete(AppConfig.secureKeyApiKey);

  Future<String?> getJwtSecret() async => _read(AppConfig.secureKeyJwtSecret);
  Future<void> setJwtSecret(String? value) async {
    if (value == null) {
      await _delete(AppConfig.secureKeyJwtSecret);
      return;
    }
    await _write(AppConfig.secureKeyJwtSecret, value);
  }

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
