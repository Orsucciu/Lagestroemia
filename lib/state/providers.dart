// Global Riverpod providers.
//
// Layout:
//  - services (singletons: db, secure storage, dio, api client)
//  - repositories (one per table)
//  - settings state (theme mode, locale, model selection)
//  - account state (signed-in/out)

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart' show Level;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common/sqflite.dart' show Database;

import '../core/config/app_config.dart';
import '../core/logging/logging.dart';
import '../core/storage/secure_storage_service.dart';
import '../data/api/zai_api_client.dart';
import '../data/database/database_helper.dart';
import '../data/repositories/repositories.dart';
import 'anon_profiles_state.dart';
import 'auth_state.dart';
import 'settings_state.dart';

export 'auth_state.dart';
export 'settings_state.dart';

// ---- services ----------------------------------------------------------

/// Provides the singleton [DatabaseHelper].
final databaseHelperProvider = Provider<DatabaseHelper>((ref) {
  return DatabaseHelper.instance;
});

/// Resolves to the open [Database] (cached by [DatabaseHelper]).
final databaseProvider = FutureProvider<Database>((ref) async {
  final helper = ref.watch(databaseHelperProvider);
  return helper.database;
});

/// Provides the singleton [SecureStorageService].
final secureStorageProvider = Provider<SecureStorageService>((ref) {
  return SecureStorageService();
});

/// Provides the shared [Dio] instance.
final dioProvider = Provider<Dio>((ref) {
  return Dio();
});

/// Provides the shared [SharedPreferences] instance.
///
/// Overridden in `main()` to inject the actual instance.
final sharedPrefsProvider = Provider<SharedPreferences>((ref) {
  throw UnimplementedError('Override me in main()');
});

// ---- repositories -------------------------------------------------------

final chatRepositoryProvider = FutureProvider<ChatRepository>((ref) async {
  final db = await ref.watch(databaseProvider.future);
  return ChatRepository(db);
});

final messageRepositoryProvider =
    FutureProvider<MessageRepository>((ref) async {
  final db = await ref.watch(databaseProvider.future);
  return MessageRepository(db);
});

final attachmentRepositoryProvider =
    FutureProvider<AttachmentRepository>((ref) async {
  final db = await ref.watch(databaseProvider.future);
  return AttachmentRepository(db);
});

final artifactRepositoryProvider =
    FutureProvider<ArtifactRepository>((ref) async {
  final db = await ref.watch(databaseProvider.future);
  return ArtifactRepository(db);
});

final systemPromptRepositoryProvider =
    FutureProvider<SystemPromptRepository>((ref) async {
  final db = await ref.watch(databaseProvider.future);
  return SystemPromptRepository(db);
});

final accountRepositoryProvider =
    FutureProvider<AccountRepository>((ref) async {
  final db = await ref.watch(databaseProvider.future);
  return AccountRepository(db);
});

final kvRepositoryProvider = FutureProvider<KvRepository>((ref) async {
  final db = await ref.watch(databaseProvider.future);
  return KvRepository(db);
});

// ---- api client --------------------------------------------------------

/// Holds the current captcha verify param (set by the in-app captcha
/// widget when the user solves the Aliyun captcha in guest mode).
final captchaVerifyParamProvider = StateProvider<String?>((ref) => null);

/// Fetches the live model list from the active backend at startup.
///
/// In guest mode: calls `GET /api/models` on chat.z.ai and returns the
/// actual list of model ids the backend exposes (which can change
/// without notice — see the comment on
/// [AppConfig.chatZaiKnownModels]). On any failure (network, captcha
/// wall, parsing), falls back to [AppConfig.chatZaiKnownModels].
///
/// In API-key mode: returns [AppConfig.knownModels] (the docs don't
/// expose a list endpoint).
///
/// The chat screen watches this provider to populate its model picker.
/// The fallback is synchronous, so the picker always has at least the
/// hardcoded list to show — even before the fetch completes.
final availableModelsProvider =
    FutureProvider<List<String>>((ref) async {
  final auth = ref.watch(authStateProvider);
  if (auth.mode != AuthMode.guest) {
    return List<String>.from(AppConfig.knownModels);
  }
  final client = ref.watch(apiClientProvider);
  if (client == null) {
    return List<String>.from(AppConfig.chatZaiKnownModels);
  }
  try {
    final live = await client.listModels();
    if (live.isEmpty) {
      return List<String>.from(AppConfig.chatZaiKnownModels);
    }
    return live;
  } catch (_) {
    return List<String>.from(AppConfig.chatZaiKnownModels);
  }
});

/// Resolves to a [ZaiApiClient] using the current auth mode, captcha
/// param, and (in guest mode) the active anonymous profile's guest
/// token. Returns `null` if the user is not signed in at all.
///
/// In guest mode, if an anonymous profile is active, its guest JWT
/// takes precedence over the main auth state's guest token. This is
/// what enables "anonymous tabs" — each tab switches the active
/// profile, which switches the bearer token, which isolates the
/// chat session.
final apiClientProvider = Provider<ZaiApiClient?>((ref) {
  final auth = ref.watch(authStateProvider);
  final settings = ref.watch(settingsStateProvider);
  final captchaParam = ref.watch(captchaVerifyParamProvider);
  final anonProfiles = ref.watch(anonProfilesProvider);
  if (!auth.signedIn) return null;
  final dio = ref.watch(dioProvider);
  final backend = auth.mode == AuthMode.guest
      ? ApiBackend.chatZai
      : ApiBackend.apiZai;
  // For API-key mode, the user may have overridden the base URL via
  // Settings; for guest mode, always use chat.z.ai.
  final baseUrl = auth.mode == AuthMode.guest ? null : settings.apiBaseUrl;
  // In guest mode, prefer the active anonymous profile's guest token
  // (so the chat completions are isolated to that profile).
  String bearerToken;
  if (auth.mode == AuthMode.guest) {
    final activeProfile = anonProfiles.active;
    bearerToken = activeProfile?.guestToken ?? auth.bearerToken!;
  } else {
    bearerToken = auth.bearerToken!;
  }
  return ZaiApiClient(
    bearerToken: bearerToken,
    apiBaseUrl: baseUrl,
    backend: backend,
    dio: dio,
    captchaVerifyParam: captchaParam,
  );
});

// ---- logging -----------------------------------------------------------

/// Call from `main()` once.
void initAppLogger() {
  initLogging(Level.INFO);
}
