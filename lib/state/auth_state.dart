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
// The two endpoints are different shapes:
//  - api.z.ai is the documented OpenAI-compatible public API,
//  - chat.z.ai is the open-webui-style internal API used by the website
//    (different SSE format: `data: {"type": "chat:completion", "data": ...}`).
//
// [AuthState.mode] tells the rest of the app which path to use.

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/config/app_config.dart';
import '../core/result/result.dart';
import '../core/storage/secure_storage_service.dart';
import '../data/api/zai_api_client.dart';
import '../data/models/models.dart';
import 'providers.dart';

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
    this.apiKey,
    this.jwtSecret,
    this.guestToken,
    this.guestUserId,
    this.status = AuthStatus.signedOut,
    this.lastError,
  });

  final AuthMode mode;

  /// z.ai API key. Only set in [AuthMode.apiKey].
  final String? apiKey;
  final String? jwtSecret;

  /// chat.z.ai guest JWT. Only set in [AuthMode.guest].
  final String? guestToken;
  final String? guestUserId;

  final AuthStatus status;
  final String? lastError;

  /// True if the user is signed in (in either mode).
  bool get signedIn =>
      (mode == AuthMode.guest && guestToken != null && guestToken!.isNotEmpty) ||
      (mode == AuthMode.apiKey && apiKey != null && apiKey!.isNotEmpty) &&
          status == AuthStatus.signedIn;

  /// Returns the Bearer token to use in API requests, depending on mode.
  String? get bearerToken =>
      mode == AuthMode.guest ? guestToken : (mode == AuthMode.apiKey ? apiKey : null);

  /// Returns the API base URL to use, depending on mode.
  String get apiBaseUrl => mode == AuthMode.guest
      ? AppConfig.chatZaiApiBaseUrl
      : AppConfig.defaultApiBaseUrl;

  AuthState copyWith({
    AuthMode? mode,
    Object? apiKey = _sentinel,
    Object? jwtSecret = _sentinel,
    Object? guestToken = _sentinel,
    Object? guestUserId = _sentinel,
    AuthStatus? status,
    Object? lastError = _sentinel,
  }) {
    return AuthState(
      mode: mode ?? this.mode,
      apiKey: identical(apiKey, _sentinel) ? this.apiKey : apiKey as String?,
      jwtSecret: identical(jwtSecret, _sentinel) ? this.jwtSecret : jwtSecret as String?,
      guestToken:
          identical(guestToken, _sentinel) ? this.guestToken : guestToken as String?,
      guestUserId: identical(guestUserId, _sentinel)
          ? this.guestUserId
          : guestUserId as String?,
      status: status ?? this.status,
      lastError:
          identical(lastError, _sentinel) ? this.lastError : lastError as String?,
    );
  }
}

const Object _sentinel = Object();

enum AuthStatus { signedOut, loading, signedIn, error }

/// Notifier that owns the [AuthState].
class AuthNotifier extends StateNotifier<AuthState> {
  AuthNotifier(this._secure, this._dio) : super(const AuthState());

  final SecureStorageService _secure;
  final Dio _dio;

  /// Called from the splash screen.
  ///
  /// 1. If an API key is present in secure storage, transition to
  ///    [AuthMode.apiKey].
  /// 2. Otherwise, automatically fetch a guest token from
  ///    `GET https://chat.z.ai/api/v1/auths/` and transition to
  ///    [AuthMode.guest].
  /// 3. If the guest fetch fails too, fall back to [AuthStatus.error] — the
  ///    UI will offer to retry or to switch to API-key mode.
  Future<void> restore() async {
    state = state.copyWith(status: AuthStatus.loading);
    try {
      final key = await _secure.getApiKey();
      final secret = await _secure.getJwtSecret();
      if (key != null && key.isNotEmpty) {
        state = AuthState(
          mode: AuthMode.apiKey,
          apiKey: key,
          jwtSecret: secret,
          status: AuthStatus.signedIn,
        );
        return;
      }
      // No API key → try guest mode.
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
    } catch (e) {
      state = AuthState(
        status: AuthStatus.error,
        lastError: e.toString(),
      );
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

  /// Switch to API-key mode and persist the key.
  Future<void> signInWithKey(String apiKey, {String? jwtSecret}) async {
    state = state.copyWith(status: AuthStatus.loading);
    try {
      await _secure.setApiKey(apiKey);
      if (jwtSecret != null) {
        await _secure.setJwtSecret(jwtSecret);
      }
      state = AuthState(
        mode: AuthMode.apiKey,
        apiKey: apiKey,
        jwtSecret: jwtSecret,
        status: AuthStatus.signedIn,
      );
    } catch (e) {
      state = AuthState(
        status: AuthStatus.error,
        lastError: e.toString(),
      );
    }
  }

  /// Sign out: clear the API key (and drop the guest token if in guest mode).
  Future<void> signOut() async {
    await _secure.deleteApiKey();
    await _secure.setJwtSecret(null);
    state = const AuthState(status: AuthStatus.signedOut);
  }

  /// Fetches a guest token from `GET https://chat.z.ai/api/v1/auths/`.
  ///
  /// Returns `(token, userId)` on success, null on failure.
  Future<_GuestAuth?> _fetchGuestToken() async {
    try {
      final response = await _dio.get<dynamic>(
        '${AppConfig.chatZaiApiBaseUrl}/v1/auths/',
        options: Options(
          headers: <String, Object?>{
            'Accept': 'application/json',
            'Origin': 'https://chat.z.ai',
            'Referer': 'https://chat.z.ai/',
            'User-Agent':
                'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0.0.0 Safari/537.36',
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

/// Provides the [AuthNotifier].
final authStateProvider =
    StateNotifierProvider<AuthNotifier, AuthState>((ref) {
  final secure = ref.watch(secureStorageProvider);
  final dio = ref.watch(dioProvider);
  return AuthNotifier(secure, dio);
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
