// Anonymous profile tabs.
//
// Each "profile" is a completely isolated chat session with its own
// guest JWT and its own chat list. The point is to be able to open
// several tabs side-by-side, each with a fresh anonymous identity, so
// the user can re-run a question without prior state affecting the
// answer.
//
// A profile has:
//  - id (uuid v4)
//  - label (user-visible, e.g. "Tab 1", "Tab 2")
//  - guestToken (a freshly-fetched chat.z.ai guest JWT)
//  - guestUserId (the id returned by /api/v1/auths/)
//  - createdAt
//
// Profiles are persisted to SharedPreferences as a JSON list. The
// active profile id is also persisted.

import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/config/app_config.dart';
import 'providers.dart';

/// One anonymous profile. Stored as a JSON list in SharedPreferences.
class AnonProfile {
  const AnonProfile({
    required this.id,
    required this.label,
    required this.guestToken,
    required this.guestUserId,
    required this.createdAt,
  });

  final String id;
  final String label;
  final String guestToken;
  final String? guestUserId;
  final DateTime createdAt;

  Map<String, Object?> toJson() => <String, Object?>{
        'id': id,
        'label': label,
        'guest_token': guestToken,
        'guest_user_id': guestUserId,
        'created_at': createdAt.toIso8601String(),
      };

  factory AnonProfile.fromJson(Map<String, Object?> m) {
    return AnonProfile(
      id: m['id']! as String,
      label: m['label']! as String,
      guestToken: m['guest_token']! as String,
      guestUserId: m['guest_user_id'] as String?,
      createdAt:
          DateTime.tryParse(m['created_at'] as String? ?? '') ??
              DateTime.now(),
    );
  }
}

const String _kPrefProfiles = '${AppConfig.prefsPrefix}anon_profiles';
const String _kPrefActiveProfile = '${AppConfig.prefsPrefix}anon_active';

/// State for the anonymous profiles.
class AnonProfilesState {
  const AnonProfilesState({
    this.profiles = const <AnonProfile>[],
    this.activeId,
    this.status = AnonProfilesStatus.idle,
    this.lastError,
  });

  final List<AnonProfile> profiles;
  final String? activeId;

  /// 'idle' | 'loading' | 'error'
  final AnonProfilesStatus status;
  final String? lastError;

  AnonProfile? get active =>
      activeId == null ? null : profiles.firstWhere(
        (p) => p.id == activeId,
        orElse: () => profiles.first,
      );

  AnonProfilesState copyWith({
    List<AnonProfile>? profiles,
    Object? activeId = _sentinel,
    AnonProfilesStatus? status,
    Object? lastError = _sentinel,
  }) {
    return AnonProfilesState(
      profiles: profiles ?? this.profiles,
      activeId: identical(activeId, _sentinel)
          ? this.activeId
          : activeId as String?,
      status: status ?? this.status,
      lastError: identical(lastError, _sentinel)
          ? this.lastError
          : lastError as String?,
    );
  }
}

const Object _sentinel = Object();

enum AnonProfilesStatus { idle, loading, error }

/// Notifier that owns the [AnonProfilesState].
///
/// The notifier persists profiles to SharedPreferences as a JSON list.
/// It uses a separate [Dio] instance (not the shared one) so its
/// fetches don't interfere with the main auth flow.
class AnonProfilesNotifier extends StateNotifier<AnonProfilesState> {
  AnonProfilesNotifier(this._dio, this._prefs)
      : super(const AnonProfilesState());

  static final Logger _log = Logger('lagestroemia.anon_profiles');
  final Dio _dio;
  final SharedPreferences _prefs;

  /// Loads persisted profiles from prefs and sets them as the current
  /// state. Called from the splash screen on app start.
  Future<void> restore() async {
    final raw = _prefs.getString(_kPrefProfiles);
    if (raw == null) {
      state = const AnonProfilesState();
      return;
    }
    try {
      final list = jsonDecode(raw) as List<Object?>;
      final profiles = list
          .map((e) => AnonProfile.fromJson(e as Map<String, Object?>))
          .toList(growable: false);
      final activeId = _prefs.getString(_kPrefActiveProfile);
      state = AnonProfilesState(
        profiles: profiles,
        activeId: activeId,
      );
    } catch (e) {
      _log.warning('restore failed: $e');
      state = AnonProfilesState(status: AnonProfilesStatus.error, lastError: e.toString());
    }
  }

  /// Creates a new anonymous profile (fetches a fresh guest JWT from
  /// chat.z.ai). Returns the new profile on success, null on failure.
  Future<AnonProfile?> createNew({String? label}) async {
    state = state.copyWith(status: AnonProfilesStatus.loading, lastError: null);
    try {
      final guest = await _fetchGuestToken();
      if (guest == null) {
        state = state.copyWith(
          status: AnonProfilesStatus.error,
          lastError: 'Could not reach chat.z.ai for guest signup.',
        );
        return null;
      }
      final id = DateTime.now().microsecondsSinceEpoch.toString();
      final profile = AnonProfile(
        id: id,
        label: label ?? 'Tab ${state.profiles.length + 1}',
        guestToken: guest.token,
        guestUserId: guest.userId,
        createdAt: DateTime.now().toUtc(),
      );
      final next = <AnonProfile>[profile, ...state.profiles];
      state = state.copyWith(
        profiles: next,
        activeId: id,
        status: AnonProfilesStatus.idle,
      );
      await _persist();
      return profile;
    } catch (e) {
      state = state.copyWith(
        status: AnonProfilesStatus.error,
        lastError: e.toString(),
      );
      return null;
    }
  }

  /// Switches the active profile. No-op if the id is unknown.
  Future<void> setActive(String id) async {
    if (!state.profiles.any((p) => p.id == id)) return;
    state = state.copyWith(activeId: id);
    await _prefs.setString(_kPrefActiveProfile, id);
  }

  /// Deletes a profile. If the deleted profile was active, the first
  /// remaining profile becomes active (or null if no profiles left).
  Future<void> delete(String id) async {
    final next = state.profiles.where((p) => p.id != id).toList(growable: false);
    String? newActive = state.activeId;
    if (state.activeId == id) {
      newActive = next.isEmpty ? null : next.first.id;
    }
    state = state.copyWith(
      profiles: next,
      activeId: newActive,
    );
    await _persist();
  }

  Future<void> _persist() async {
    await _prefs.setString(
      _kPrefProfiles,
      jsonEncode(state.profiles.map((p) => p.toJson()).toList()),
    );
    if (state.activeId != null) {
      await _prefs.setString(_kPrefActiveProfile, state.activeId!);
    } else {
      await _prefs.remove(_kPrefActiveProfile);
    }
  }

  Future<_GuestAuth?> _fetchGuestToken() async {
    try {
      // Pick a User-Agent appropriate for the platform. On Web the
      // browser sets its own UA anyway; we still send one explicitly
      // because some CDNs/firewalls block requests without a UA.
      final ua = kIsWeb
          ? 'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, '
              'like Gecko) Chrome/130.0.0.0 Safari/537.36'
          : (Platform.isAndroid || Platform.isIOS
              ? 'Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36 (KHTML, '
                  'like Gecko) Chrome/130.0.0.0 Mobile Safari/537.36'
              : 'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, '
                  'like Gecko) Chrome/130.0.0.0 Safari/537.36');
      final response = await _dio.get<dynamic>(
        '${AppConfig.chatZaiApiBaseUrl}/v1/auths/',
        options: Options(
          sendTimeout: const Duration(seconds: 10),
          receiveTimeout: const Duration(seconds: 10),
          headers: <String, Object?>{
            'Accept': 'application/json',
            'Origin': 'https://chat.z.ai',
            'Referer': 'https://chat.z.ai/',
            'User-Agent': ua,
            'X-FE-Version': AppConfig.chatZaiFeVersion,
          },
        ),
      );
      final data = response.data;
      final m = data is String
          ? Map<String, Object?>.from(response.data as Map)
          : Map<String, Object?>.from(data as Map);
      final token = m['token'] as String?;
      final id = m['id'] as String?;
      if (token == null || token.isEmpty) return null;
      return _GuestAuth(token: token, userId: id);
    } catch (e) {
      return null;
    }
  }
}

class _GuestAuth {
  const _GuestAuth({required this.token, this.userId});
  final String token;
  final String? userId;
}

/// Provides the [AnonProfilesNotifier].
final anonProfilesProvider =
    StateNotifierProvider<AnonProfilesNotifier, AnonProfilesState>((ref) {
  final dio = ref.watch(dioProvider);
  final prefs = ref.watch(sharedPrefsProvider);
  return AnonProfilesNotifier(dio, prefs);
});
