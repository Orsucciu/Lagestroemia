// Authentication state — owns the in-memory auth tokens (never persisted to
// disk; only the OS keychain holds API-key tokens) and exposes `signedIn`
// for the UI.
//
// The app supports two auth modes:
//  - **Guest mode** (default, no API key needed): on first launch the app
//    silently calls `GET https://chat.z.ai/api/v1/auths/` which returns a
//    guest JWT. Chat completions go to
//    `POST https://chat.z.ai/api/v2/chat/completions` with that Bearer
//    token; once per session the user must solve an Aliyun captcha before
//    they can chat (we render the captcha widget in-app).
//  - **API-key mode** (optional, recommended for power users): the user
//    pastes a z.ai API key (from
//    https://z.ai/manage-apikey/apikey-list). Chat completions go to
//    `POST https://api.z.ai/api/paas/v4/chat/completions` with that Bearer
//    token; no captcha required.
//
// API-key mode supports:
//   - **JWT auth mode** (issue #8): for keys in form `<id>.<secret>`, sign
//     a short-lived JWT (HS256, ms timestamps, sign_type: SIGN header)
//     and use it as the Bearer token, instead of the raw key.
//   - **Multi-account** (issue #12): the user can add / switch / delete
//     accounts, each with its own API key stored per-account in the OS
//     keychain.

import 'dart:async';
import 'dart:io' show Platform, File, stdout, stderr, FileMode;

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/auth/zai_jwt.dart';
import '../core/config/app_config.dart';
import '../core/result/result.dart';
import '../core/storage/secure_storage_service.dart';
import '../data/api/zai_api_client.dart';
import '../data/models/models.dart';
import '../data/repositories/repositories.dart';
import 'providers.dart';

void _debugLog(String msg) {
  final line = '[${DateTime.now().toIso8601String()}] ' + msg;
  try { stdout.writeln(line); stdout.flush(); } catch (_) {}
  try { stderr.writeln(line); } catch (_) {}
  try {
    final dir = Platform.environment['TEMP'] ?? '/tmp';
    File('${dir}/lagestroemia_debug.log')
        .writeAsStringSync('${line}\n', mode: FileMode.append);
  } catch (_) {}
}



/// Which auth path is active.
enum AuthMode {
  /// No auth (initial state, before the splash screen has finished
  /// restoring any saved state).
  none,
  /// Anonymous guest using chat.z.ai/api/v2 with an Aliyun captcha per
  /// session.
  guest,
  /// Real z.ai API key using api.z.ai/api/paas/v4.
  apiKey,
}

/// Immutable snapshot of the auth state.
class AuthState {
  const AuthState({
    this.mode = AuthMode.none,
    this.accountId = 'default',
    this.apiKey,
    this.guestToken,
    this.guestUserId,
    this.useJwtAuth = false,
    this.jwtValidity = const Duration(hours: 1),
    this.status = AuthStatus.signedOut,
    this.lastError,
  });

  final AuthMode mode;

  /// The id of the active API-key account. Defaults to 'default' for
  /// backwards compat. Multi-account UI (issue #12) lets the user create
  /// additional ids like 'work', 'test', etc.
  final String accountId;

  /// z.ai API key in form `<id>.<secret>`. Only set in [AuthMode.apiKey].
  final String? apiKey;

  /// chat.z.ai guest JWT. Only set in [AuthMode.guest].
  final String? guestToken;
  final String? guestUserId;

  /// Whether to sign a short-lived JWT (HS256, ms timestamps, sign_type:
  /// SIGN header) using the secret half of [apiKey], rather than sending
  /// the raw API key as Bearer. Only meaningful in [AuthMode.apiKey] and
  /// only when the key is in `<id>.<secret>` form. (issue #8)
  final bool useJwtAuth;

  /// How long the signed JWT is valid for. Default: 1 hour.
  final Duration jwtValidity;

  final AuthStatus status;
  final String? lastError;

  /// True if the user is signed in (in either mode).
  bool get signedIn =>
      (mode == AuthMode.guest &&
          guestToken != null &&
          guestToken!.isNotEmpty) ||
      (mode == AuthMode.apiKey &&
          apiKey != null &&
          apiKey!.isNotEmpty &&
          status == AuthStatus.signedIn);

  /// Returns the parsed (id, secret) halves of [apiKey]. Returns null if
  /// the key is not in `<id>.<secret>` form.
  ZaiApiKeyParts? get apiKeyParts =>
      apiKey == null ? null : ZaiApiKeyParts.tryParse(apiKey!);

  /// Returns the Bearer token to use in API requests, depending on mode
  /// and [useJwtAuth]. If [useJwtAuth] is true and the key is composite,
  /// returns a freshly signed JWT. Otherwise returns the raw key.
  String? get bearerToken {
    if (mode == AuthMode.guest) return guestToken;
    if (mode == AuthMode.apiKey) {
      if (useJwtAuth) {
        final parts = apiKeyParts;
        if (parts != null) {
          return signZaiJwt(parts: parts, validity: jwtValidity);
        }
      }
      return apiKey;
    }
    return null;
  }

  /// Returns the API base URL to use, depending on mode.
  String get apiBaseUrl => mode == AuthMode.guest
      ? AppConfig.chatZaiApiBaseUrl
      : AppConfig.defaultApiBaseUrl;

  AuthState copyWith({
    AuthMode? mode,
    String? accountId,
    Object? apiKey = _sentinel,
    Object? guestToken = _sentinel,
    Object? guestUserId = _sentinel,
    bool? useJwtAuth,
    Duration? jwtValidity,
    AuthStatus? status,
    Object? lastError = _sentinel,
  }) {
    return AuthState(
      mode: mode ?? this.mode,
      accountId: accountId ?? this.accountId,
      apiKey:
          identical(apiKey, _sentinel) ? this.apiKey : apiKey as String?,
      guestToken: identical(guestToken, _sentinel)
          ? this.guestToken
          : guestToken as String?,
      guestUserId: identical(guestUserId, _sentinel)
          ? this.guestUserId
          : guestUserId as String?,
      useJwtAuth: useJwtAuth ?? this.useJwtAuth,
      jwtValidity: jwtValidity ?? this.jwtValidity,
      status: status ?? this.status,
      lastError: identical(lastError, _sentinel)
          ? this.lastError
          : lastError as String?,
    );
  }
}

const Object _sentinel = Object();

enum AuthStatus { signedOut, loading, signedIn, error }

/// Notifier that owns the [AuthState].
class AuthNotifier extends StateNotifier<AuthState> {
  AuthNotifier(this._ref, this._secure, this._dio, this._prefs)
      : super(const AuthState());

  final Ref _ref;
  final SecureStorageService _secure;
  final Dio _dio;
  final SharedPreferences _prefs;

  /// Lazily resolves the [AccountRepository] via Riverpod. Returns null
  /// if the database is not yet open or the provider fails.
  Future<AccountRepository?> _accountRepo() async {
    try {
      // Wait for the FutureProvider to resolve.
      return await _ref.read(accountRepositoryProvider.future);
    } catch (_) {
      return null;
    }
  }

  /// Called from the splash screen.
  ///
  /// 1. If an API key is present in secure storage, transition to
  ///    [AuthMode.apiKey] (restoring the [useJwtAuth] preference).
  /// 2. Otherwise, automatically fetch a guest token from
  ///    `GET https://chat.z.ai/api/v1/auths/` and transition to
  ///    [AuthMode.guest].
  /// 3. If the guest fetch fails too, fall back to [AuthStatus.error].
  Future<void> restore() async {
    _debugLog('[AUTH] restore() started');
    // Don't set status to loading here — that triggers the router to
    // rebuild, which can dispose the splash widget mid-restore. Instead,
    // only set the final status when we're done.
    try {
      _debugLog('[AUTH] restore(): reading API key from secure storage...');
      final key = await _secure.getApiKey().timeout(
        const Duration(seconds: 3), onTimeout: () {
        _debugLog('[AUTH] restore(): getApiKey() TIMED OUT after 3s');
        return null;
      });
      _debugLog('[AUTH] restore(): getApiKey() returned: ${key == null ? "null" : "key(${key.length} chars)"}');
      if (key != null && key.isNotEmpty) {
        _debugLog('[AUTH] restore(): API key found, signing in');
        _setAuthState(AuthState(
          mode: AuthMode.apiKey,
          apiKey: key,
          useJwtAuth: _prefs.getBool(_kPrefUseJwtAuth) ?? false,
          status: AuthStatus.signedIn,
        ));
        return;
      }
      _debugLog('[AUTH] restore(): no API key, fetching guest token...');
      final guest = await _fetchGuestToken();
      if (guest != null) {
        _debugLog('[AUTH] restore(): guest token fetched OK');
        _setAuthState(AuthState(
          mode: AuthMode.guest,
          guestToken: guest.token,
          guestUserId: guest.userId,
          status: AuthStatus.signedIn,
        ));
      } else {
        _debugLog('[AUTH] restore(): guest token fetch returned null');
        _setAuthState(const AuthState(status: AuthStatus.signedOut));
      }
    } catch (e) {
      _debugLog('[AUTH] restore(): EXCEPTION: $e');
      _setAuthState(AuthState(
        status: AuthStatus.error,
        lastError: e.toString(),
      ));
    }
    _debugLog('[AUTH] restore() finished, status=${state.status}, mode=${state.mode}');
  }

  /// Safely sets the auth state. Catches any errors from StateNotifier
  /// listeners (e.g. the router rebuilding) so the restore() flow
  /// doesn't crash.
  void _setAuthState(AuthState newState) {
    try {
      state = newState;
    } catch (e) {
      _debugLog('[AUTH] _setAuthState: listener threw: $e (state still set)');
      // The state is still set even if a listener throws — StateNotifier
      // sets the state before notifying listeners.
    }
  }

  /// Force guest mode (used by the auth screen's "Continue as guest" button
  /// when the user does not want to enter an API key).
  Future<void> continueAsGuest() async {
    state = state.copyWith(status: AuthStatus.loading);
    try {
      final guest = await _fetchGuestToken();
      if (guest != null) {
        state = AuthState(
          mode: AuthMode.guest,
          guestToken: guest.token,
          guestUserId: guest.userId,
          status: AuthStatus.signedIn,
        );
      } else {
        state = const AuthState(
          status: AuthStatus.error,
          lastError: 'Could not reach chat.z.ai for guest signup.',
        );
      }
    } catch (e) {
      state = AuthState(
        status: AuthStatus.error,
        lastError: e.toString(),
      );
    }
  }

  /// Switch to API-key mode and persist the key for the current account.
  Future<void> signInWithKey(String apiKey) async {
    state = state.copyWith(status: AuthStatus.loading);
    try {
      await _secure.setApiKeyForAccount(state.accountId, apiKey);
      state = AuthState(
        mode: AuthMode.apiKey,
        accountId: state.accountId,
        apiKey: apiKey,
        useJwtAuth: _prefs.getBool(_kPrefUseJwtAuth) ?? false,
        status: AuthStatus.signedIn,
      );
    } catch (e) {
      state = AuthState(
        status: AuthStatus.error,
        lastError: e.toString(),
      );
    }
  }

  /// Adds a new account with the given id, label, and API key, and
  /// switches to it (issue #12).
  ///
  /// Returns true on success, false if an account with the same id
  /// already exists or the database is not ready.
  Future<bool> addAccount({
    required String id,
    required String label,
    required String apiKey,
  }) async {
    final repo = await _accountRepo();
    if (repo == null) return false;
    if (await repo.findById(id) != null) return false;
    await repo.upsert(Account(
      id: id,
      label: label,
      apiBaseUrl: AppConfig.defaultApiBaseUrl,
      createdAt: DateTime.now().toUtc(),
    ));
    await _secure.setApiKeyForAccount(id, apiKey);
    await repo.touchLastUsed(id);
    _ref.invalidate(accountRepositoryProvider);
    state = AuthState(
      mode: AuthMode.apiKey,
      accountId: id,
      apiKey: apiKey,
      useJwtAuth: _prefs.getBool(_kPrefUseJwtAuth) ?? false,
      status: AuthStatus.signedIn,
    );
    return true;
  }

  /// Switches to the account with the given id. Loads its API key from
  /// secure storage. Returns false if no such account exists, no API key
  /// is stored for it, or the database is not ready.
  Future<bool> switchToAccount(String id) async {
    final repo = await _accountRepo();
    if (repo == null) return false;
    final account = await repo.findById(id);
    if (account == null) return false;
    final key = await _secure.getApiKeyForAccount(id);
    if (key == null || key.isEmpty) return false;
    await repo.touchLastUsed(id);
    state = AuthState(
      mode: AuthMode.apiKey,
      accountId: id,
      apiKey: key,
      useJwtAuth: _prefs.getBool(_kPrefUseJwtAuth) ?? false,
      status: AuthStatus.signedIn,
    );
    return true;
  }

  /// Deletes the account with the given id. Also wipes the API key from
  /// secure storage. If the account is currently active, falls back to
  /// guest mode.
  ///
  /// The 'default' account cannot be deleted (use signOut instead).
  /// Returns true on success.
  Future<bool> deleteAccount(String id) async {
    if (id == 'default') return false;
    final repo = await _accountRepo();
    if (repo == null) return false;
    final deleted = await repo.delete(id);
    if (deleted == 0) return false;
    await _secure.deleteApiKeyForAccount(id);
    _ref.invalidate(accountRepositoryProvider);
    if (state.accountId == id) {
      await _fallbackToGuest();
    }
    return true;
  }

  Future<void> _fallbackToGuest() async {
    final guest = await _fetchGuestToken();
    if (guest != null) {
      state = AuthState(
        mode: AuthMode.guest,
        guestToken: guest.token,
        guestUserId: guest.userId,
        status: AuthStatus.signedIn,
      );
    } else {
      state = const AuthState(status: AuthStatus.signedOut);
    }
  }

  /// Toggle JWT auth mode (issue #8). Persists to SharedPreferences so the
  /// preference survives app restarts.
  ///
  /// When [useJwtAuth] is true, [AuthState.bearerToken] returns a freshly
  /// signed JWT (HS256, ms timestamps, sign_type: SIGN header) using the
  /// secret half of the API key, instead of the raw key. Only effective
  /// when the key is in `<id>.<secret>` form — if not, this method is
  /// a no-op.
  Future<void> setUseJwtAuth(bool value) async {
    // Only allow turning on JWT auth if the key is composite.
    if (value && state.apiKeyParts == null) return;
    await _prefs.setBool(_kPrefUseJwtAuth, value);
    state = state.copyWith(useJwtAuth: value);
  }

  /// Sign out: clear the API key for the current account (and drop the
  /// guest token if in guest mode).
  Future<void> signOut() async {
    await _secure.deleteApiKeyForAccount(state.accountId);
    state = const AuthState(status: AuthStatus.signedOut);
  }

  /// Fetches a guest token from `GET https://chat.z.ai/api/v1/auths/`.
  ///
  /// Returns `(token, userId)` on success, null on failure.
  Future<_GuestAuth?> _fetchGuestToken() async {
    // ignore: avoid_print
    _debugLog('[AUTH] _fetchGuestToken(): sending GET to '
        '${AppConfig.chatZaiApiBaseUrl}/v1/auths/ ...');
    try {
      final response = await _dio.get<dynamic>(
        '${AppConfig.chatZaiApiBaseUrl}/v1/auths/',
        options: Options(
          sendTimeout: const Duration(seconds: 10),
          receiveTimeout: const Duration(seconds: 10),
          headers: <String, Object?>{
            'Accept': 'application/json',
            'Origin': 'https://chat.z.ai',
            'Referer': 'https://chat.z.ai/',
            'User-Agent': _userAgent,
            'X-FE-Version': AppConfig.chatZaiFeVersion,
          },
        ),
      );
      // ignore: avoid_print
      _debugLog('[AUTH] _fetchGuestToken(): got response '
          '(status ${response.statusCode})');
      final data = response.data;
      final m = data is String
          ? Map<String, Object?>.from(response.data as Map)
          : Map<String, Object?>.from(data as Map);
      final token = m['token'] as String?;
      final id = m['id'] as String?;
      if (token == null || token.isEmpty) return null;
      return _GuestAuth(token: token, userId: id);
    } catch (e) {
      // ignore: avoid_print
      _debugLog('[AUTH] _fetchGuestToken(): EXCEPTION: $e');
      return null;
    }
  }

  /// Refresh the guest token (used when the chat.z.ai backend says the
  /// current guest token has expired).
  Future<void> refreshGuestToken() async {
    final guest = await _fetchGuestToken();
    if (guest != null) {
      state = state.copyWith(
        guestToken: guest.token,
        guestUserId: guest.userId,
      );
    }
  }
}

class _GuestAuth {
  const _GuestAuth({required this.token, this.userId});
  final String token;
  final String? userId;
}

/// Returns a platform-appropriate User-Agent string. On Android/iOS, uses
/// a mobile UA; on desktop, uses a desktop Chrome UA. This matters because
/// some CDNs/firewalls block desktop UAs from mobile networks.
String get _userAgent {
  if (Platform.isAndroid || Platform.isIOS) {
    return 'Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36 (KHTML, '
        'like Gecko) Chrome/130.0.0.0 Mobile Safari/537.36';
  }
  return 'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like '
      'Gecko) Chrome/130.0.0.0 Safari/537.36';
}

const String _kPrefUseJwtAuth = '${AppConfig.prefsPrefix}use_jwt_auth';

/// Provides the [AuthNotifier].
final authStateProvider =
    StateNotifierProvider<AuthNotifier, AuthState>((ref) {
  final secure = ref.watch(secureStorageProvider);
  final dio = ref.watch(dioProvider);
  final prefs = ref.watch(sharedPrefsProvider);
  return AuthNotifier(ref, secure, dio, prefs);
});

/// Helper: returns the [ZaiApiClient] for a single test API call, used by
/// the auth screen's "Validate" button.
Future<Result<AssistantResponse, ApiError>> validateApiKeyViaClient(
  ZaiApiClient client,
) async {
  // Tiny request: 1 token of output, 1 user message.
  return client.chatCompletion(
    messages: <Map<String, Object?>>[
      <String, Object?>{'role': 'user', 'content': 'ping'},
    ],
    maxTokens: 1,
  );
}
