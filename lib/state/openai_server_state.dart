// State for the OpenAI-compatible local server.
//
// Owns the singleton [OpenAiApiServer] and exposes start/stop + status
// for the Settings UI. Persists the user's preferences (enabled, port,
// server API key, allow CORS) to SharedPreferences.

import 'dart:io' show Platform;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/config/app_config.dart';
import '../data/api/openai_api_server.dart';
import 'auth_state.dart';
import 'providers.dart';

/// Keys for persistence in SharedPreferences.
const String _kPrefEnabled = '${AppConfig.prefsPrefix}oai_server_enabled';
const String _kPrefPort = '${AppConfig.prefsPrefix}oai_server_port';
const String _kPrefServerApiKey =
    '${AppConfig.prefsPrefix}oai_server_api_key';
const String _kPrefAllowCors = '${AppConfig.prefsPrefix}oai_server_allow_cors';

/// Notifier that owns the [OpenAiApiServer] and persists preferences.
class OpenAiServerNotifier extends StateNotifier<OpenAiServerStatus> {
  OpenAiServerNotifier(this._ref, this._prefs)
      : super(const OpenAiServerStatus()) {
    _server = OpenAiApiServer(
      bearerTokenProvider: () => _ref.read(authStateProvider).bearerToken,
    );
  }

  final Ref _ref;
  final SharedPreferences _prefs;
  late final OpenAiApiServer _server;

  /// Reads the persisted config (or defaults).
  OpenAiServerConfig loadConfig() {
    return OpenAiServerConfig(
      enabled: _prefs.getBool(_kPrefEnabled) ?? false,
      port: _prefs.getInt(_kPrefPort) ?? 8081,
      serverApiKey: _prefs.getString(_kPrefServerApiKey) ?? '',
      allowCors: _prefs.getBool(_kPrefAllowCors) ?? true,
    );
  }

  /// Starts the server with the given config (or the persisted config
  /// if [config] is null). Persists the config first.
  Future<OpenAiServerStatus> start({OpenAiServerConfig? config}) async {
    final cfg = config ?? loadConfig();
    await _persist(cfg.copyWith(enabled: true));
    final status = await _server.start(cfg);
    state = status;
    return status;
  }

  /// Stops the server.
  Future<void> stop() async {
    await _server.stop();
    await _persist(loadConfig().copyWith(enabled: false));
    state = const OpenAiServerStatus();
  }

  /// Toggles the server on/off based on [enabled]. Persists the config.
  Future<void> setEnabled(bool enabled) async {
    final cfg = loadConfig();
    if (enabled) {
      await start(config: cfg);
    } else {
      await stop();
    }
  }

  /// Updates the port and restarts if running. Persists.
  Future<void> setPort(int port) async {
    final cfg = loadConfig().copyWith(port: port);
    await _persist(cfg);
    if (state.running) {
      await stop();
      await start(config: cfg);
    }
  }

  /// Updates the server API key. Persists.
  Future<void> setServerApiKey(String key) async {
    final cfg = loadConfig().copyWith(serverApiKey: key);
    await _persist(cfg);
  }

  /// Toggles CORS. Persists.
  Future<void> setAllowCors(bool value) async {
    final cfg = loadConfig().copyWith(allowCors: value);
    await _persist(cfg);
  }

  /// On app start, re-opens the server if it was running before.
  /// Called from the splash screen or main(). Returns the new status.
  Future<OpenAiServerStatus> restoreIfEnabled() async {
    if (!Platform.isLinux && !Platform.isWindows && !Platform.isAndroid) {
      // Web/iOS/macOS: skip (Web can't bind; iOS/macOS need entitlements
      // we don't ship yet).
      return const OpenAiServerStatus();
    }
    final cfg = loadConfig();
    if (!cfg.enabled) {
      return const OpenAiServerStatus();
    }
    final status = await _server.start(cfg);
    state = status;
    return status;
  }

  Future<void> _persist(OpenAiServerConfig cfg) async {
    await _prefs.setBool(_kPrefEnabled, cfg.enabled);
    await _prefs.setInt(_kPrefPort, cfg.port);
    await _prefs.setString(_kPrefServerApiKey, cfg.serverApiKey);
    await _prefs.setBool(_kPrefAllowCors, cfg.allowCors);
  }
}

/// Provides the [OpenAiServerNotifier]. The notifier persists the
/// user's preferences and owns the singleton [OpenAiApiServer].
final openAiServerProvider =
    StateNotifierProvider<OpenAiServerNotifier, OpenAiServerStatus>((ref) {
  final prefs = ref.watch(sharedPrefsProvider);
  return OpenAiServerNotifier(ref, prefs);
});
