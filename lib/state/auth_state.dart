// Authentication state — owns the in-memory API key (never persisted to
// disk; only the OS keychain holds it) and exposes `signedIn` for the UI.
//
// The flow on app start is:
//   1. The splash screen reads the API key from `SecureStorageService`.
//   2. If a key is present, the splash routes to the chat list.
//   3. If absent, the splash routes to the auth screen.
//   4. After the user pastes a key, the auth screen validates it by
//      making a tiny HTTP call (e.g. `/tokenizer` with empty input) and,
//      on success, stores it via [SecureStorageService] and updates this
//      notifier.
//
// We do not actually call z.ai to validate the key in the MVP — z.ai does
// not have a `GET /me` endpoint. The MVP just stores the key and lets the
// first real chat call tell us if the key is good. A "Test now" button in
// Settings does a trivial chat completions call instead.

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/result/result.dart';
import '../core/storage/secure_storage_service.dart';
import '../data/api/zai_api_client.dart';
import '../data/models/models.dart';
import 'providers.dart';

/// Immutable snapshot of the auth state.
class AuthState {
  const AuthState({
    this.apiKey,
    this.jwtSecret,
    this.status = AuthStatus.signedOut,
    this.lastError,
  });

  final String? apiKey;
  final String? jwtSecret;
  final AuthStatus status;
  final String? lastError;

  bool get signedIn => apiKey != null && apiKey!.isNotEmpty && status == AuthStatus.signedIn;

  AuthState copyWith({
    Object? apiKey = _sentinel,
    Object? jwtSecret = _sentinel,
    AuthStatus? status,
    Object? lastError = _sentinel,
  }) {
    return AuthState(
      apiKey: identical(apiKey, _sentinel) ? this.apiKey : apiKey as String?,
      jwtSecret: identical(jwtSecret, _sentinel) ? this.jwtSecret : jwtSecret as String?,
      status: status ?? this.status,
      lastError: identical(lastError, _sentinel) ? this.lastError : lastError as String?,
    );
  }
}

const Object _sentinel = Object();

enum AuthStatus { signedOut, loading, signedIn, error }

/// Notifier that owns the [AuthState] and coordinates with
/// [SecureStorageService].
class AuthNotifier extends StateNotifier<AuthState> {
  AuthNotifier(this._secure) : super(const AuthState());

  final SecureStorageService _secure;

  /// Called from the splash screen. Reads the API key from secure
  /// storage; if present, transitions to [AuthStatus.signedIn].
  Future<void> restore() async {
    state = state.copyWith(status: AuthStatus.loading);
    try {
      final key = await _secure.getApiKey();
      final secret = await _secure.getJwtSecret();
      if (key != null && key.isNotEmpty) {
        state = AuthState(
          apiKey: key,
          jwtSecret: secret,
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

  /// Saves the API key to secure storage and transitions to signedIn.
  ///
  /// The caller is expected to have already validated the key (e.g. by
  /// making a tiny API call). We just persist it.
  Future<void> signInWithKey(String apiKey, {String? jwtSecret}) async {
    state = state.copyWith(status: AuthStatus.loading);
    try {
      await _secure.setApiKey(apiKey);
      if (jwtSecret != null) {
        await _secure.setJwtSecret(jwtSecret);
      }
      state = AuthState(
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

  /// Wipes the API key and transitions to signedOut.
  Future<void> signOut() async {
    await _secure.deleteApiKey();
    await _secure.setJwtSecret(null);
    state = const AuthState(status: AuthStatus.signedOut);
  }
}

/// Provides the [AuthNotifier].
final authStateProvider =
    StateNotifierProvider<AuthNotifier, AuthState>((ref) {
  final secure = ref.watch(secureStorageProvider);
  return AuthNotifier(secure);
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
