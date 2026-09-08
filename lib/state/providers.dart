// Global Riverpod providers.
//
// Layout:
//  - services (singletons: db, secure storage, dio, api client)
//  - repositories (one per table)
//  - settings state (theme mode, locale, model selection)
//  - account state (signed-in/out)
//  - chat list state (paginated chats, current chat, current messages)

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart' show Level;
import 'package:sqflite_common/sqflite.dart' show Database;

import '../core/config/app_config.dart';
import '../core/logging/logging.dart';
import '../core/storage/secure_storage_service.dart';
import '../data/api/zai_api_client.dart';
import '../data/database/database_helper.dart';
import '../data/models/models.dart';
import '../data/repositories/repositories.dart';
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

/// Resolves to a [ZaiApiClient] using the current API key + base URL from
/// [settingsStateProvider]. Returns `null` if the user is signed out so
/// the UI can avoid showing the chat composer.
final apiClientProvider = Provider<ZaiApiClient?>((ref) {
  final settings = ref.watch(settingsStateProvider);
  final auth = ref.watch(authStateProvider);
  if (!auth.signedIn) return null;
  final dio = ref.watch(dioProvider);
  return ZaiApiClient(
    apiKey: auth.apiKey!,
    apiBaseUrl: settings.apiBaseUrl,
    dio: dio,
  );
});

// ---- logging -----------------------------------------------------------

/// Call from `main()` once.
void initAppLogger() {
  initLogging(Level.INFO);
}
