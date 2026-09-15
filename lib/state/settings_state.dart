// Settings state — persists to SharedPreferences and is exposed via Riverpod.
//
// We avoid pulling in `riverpod_generator` for the MVP (manual Notifier is
// shorter than the generated equivalent for this small slice of state).
//
// The state is read once at app start from prefs and then kept in memory
// for synchronous UI access. Mutations write back to prefs.

import 'package:flutter/material.dart' show ThemeMode;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/config/app_config.dart';

/// Immutable settings snapshot.
class SettingsState {
  const SettingsState({
    this.themeMode = ThemeMode.system,
    this.localeTag = 'en',
    this.model = AppConfig.defaultModel,
    this.apiBaseUrl = AppConfig.defaultApiBaseUrl,
    this.sendOnEnter = true,
  });

  final ThemeMode themeMode;

  /// BCP-47 tag. `null` means "follow system".
  final String? localeTag;

  /// Selected model id (used as the default for new chats).
  final String model;

  /// z.ai API base URL.
  final String apiBaseUrl;

  /// When true, pressing Enter sends the message (Shift+Enter inserts a
  /// newline). When false, Ctrl+Enter sends and Enter inserts a newline.
  final bool sendOnEnter;

  SettingsState copyWith({
    ThemeMode? themeMode,
    Object? localeTag = _sentinel,
    String? model,
    String? apiBaseUrl,
    bool? sendOnEnter,
  }) {
    return SettingsState(
      themeMode: themeMode ?? this.themeMode,
      localeTag: identical(localeTag, _sentinel) ? this.localeTag : localeTag as String?,
      model: model ?? this.model,
      apiBaseUrl: apiBaseUrl ?? this.apiBaseUrl,
      sendOnEnter: sendOnEnter ?? this.sendOnEnter,
    );
  }
}

const Object _sentinel = Object();

/// Notifier that owns the [SettingsState] and persists every change back
/// to [SharedPreferences].
class SettingsNotifier extends StateNotifier<SettingsState> {
  SettingsNotifier(this._prefs) : super(const SettingsState()) {
    _load();
  }

  final SharedPreferences _prefs;

  static const _kPrefSendOnEnter = '${AppConfig.prefsPrefix}send_on_enter';

  void _load() {
    final mode = _prefs.getString(AppConfig.prefsKeyThemeMode);
    final locale = _prefs.getString(AppConfig.prefsKeyLocale);
    final model = _prefs.getString(AppConfig.prefsKeyModel);
    final baseUrl = _prefs.getString(AppConfig.prefsKeyApiBaseUrl);
    final sendOnEnter = _prefs.getBool(_kPrefSendOnEnter) ?? true;
    state = SettingsState(
      themeMode: _parseThemeMode(mode),
      localeTag: locale,
      model: model ?? AppConfig.defaultModel,
      apiBaseUrl: baseUrl ?? AppConfig.defaultApiBaseUrl,
      sendOnEnter: sendOnEnter,
    );
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    state = state.copyWith(themeMode: mode);
    await _prefs.setString(AppConfig.prefsKeyThemeMode, _stringifyThemeMode(mode));
  }

  Future<void> setLocale(String? localeTag) async {
    state = state.copyWith(localeTag: localeTag);
    if (localeTag == null) {
      await _prefs.remove(AppConfig.prefsKeyLocale);
    } else {
      await _prefs.setString(AppConfig.prefsKeyLocale, localeTag);
    }
  }

  Future<void> setModel(String model) async {
    state = state.copyWith(model: model);
    await _prefs.setString(AppConfig.prefsKeyModel, model);
  }

  Future<void> setApiBaseUrl(String url) async {
    state = state.copyWith(apiBaseUrl: url);
    await _prefs.setString(AppConfig.prefsKeyApiBaseUrl, url);
  }

  Future<void> setSendOnEnter(bool value) async {
    state = state.copyWith(sendOnEnter: value);
    await _prefs.setBool(_kPrefSendOnEnter, value);
  }

  ThemeMode _parseThemeMode(String? s) {
    switch (s) {
      case 'light':
        return ThemeMode.light;
      case 'dark':
        return ThemeMode.dark;
      default:
        return ThemeMode.system;
    }
  }

  String _stringifyThemeMode(ThemeMode mode) {
    switch (mode) {
      case ThemeMode.light:
        return 'light';
      case ThemeMode.dark:
        return 'dark';
      case ThemeMode.system:
        return 'system';
    }
  }
}

/// Provides the [SettingsNotifier].
final settingsStateProvider =
    StateNotifierProvider<SettingsNotifier, SettingsState>((ref) {
  throw UnimplementedError('Override me in main()');
});
