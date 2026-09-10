// State for the OpenAI-compatible local server.
//
// Owns the singleton [OpenAiApiServer] and exposes start/stop + status
// for the Settings UI. Persists the user's preferences (enabled, port,
// server API key, allow CORS) to SharedPreferences.

import 'dart:io' show Platform;

import 'dart:io' show Platform, File, stdout, stderr, FileMode;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/config/app_config.dart';
import '../data/api/openai_api_server.dart';
import 'anon_profiles_state.dart';
import 'auth_state.dart';
import 'providers.dart';

void _debugLog(String msg) {
  final line = '[${DateTime.now().toIso8601String()}] ' + msg;
  print(line);
  if (kIsWeb) return;
  try { stdout.writeln(line); stdout.flush(); } catch (_) {}
  try {
    final dir = Platform.environment['TEMP'] ?? '/tmp';
    File('${dir}/lagestroemia_debug.log')
        .writeAsStringSync('${line}\n', mode: FileMode.append);
  } catch (_) {}
}



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
      bearerTokenProvider: () {
        final auth = _ref.read(authStateProvider);
        if (!auth.signedIn) return null;
        // In guest mode, prefer the active anonymous profile's guest
        // token (so the OpenAI-compat server also benefits from
        // profile isolation).
        if (auth.mode == AuthMode.guest) {
          final activeProfile = _ref.read(anonProfilesProvider).active;
          if (activeProfile != null) return activeProfile.guestToken;
        }
        return auth.bearerToken;
      },
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
    // ignore: avoid_print
    _debugLog('[SERVER] restoreIfEnabled(): platform=${Platform.operatingSystem}');
    if (!Platform.isLinux && !Platform.isWindows && !Platform.isAndroid) {
      // ignore: avoid_print
      _debugLog('[SERVER] restoreIfEnabled(): skipping (platform not supported)');
      return const OpenAiServerStatus();
    }
    final cfg = loadConfig();
    // ignore: avoid_print
    _debugLog('[SERVER] restoreIfEnabled(): enabled=${cfg.enabled}, port=${cfg.port}');
    if (!cfg.enabled) {
      return const OpenAiServerStatus();
    }
    // ignore: avoid_print
    _debugLog('[SERVER] restoreIfEnabled(): starting server...');
    final status = await _server.start(cfg);
    state = status;
    // ignore: avoid_print
    _debugLog('[SERVER] restoreIfEnabled(): status running=${status.running}, error=${status.error}');
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
