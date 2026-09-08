// Core application configuration.
//
// Centralises the constants that the rest of the app needs:
//  - the z.ai API base URL,
//  - the API key dashboard URL,
//  - the OAuth helper URLs (z.ai does not currently expose public OAuth — we
//    only ship API-key auth in the MVP),
//  - storage keys used by SecureStorage / SharedPreferences,
//  - app-wide identity (app name, version).
//
// All values are compile-time constants. The base URL is configurable per
// profile (we keep just one for now, but the indirection leaves room for a
// staging environment later).

import 'package:flutter/foundation.dart';

/// Application-wide configuration constants.
///
/// Keep all magic strings and URLs here so feature code never hardcodes
/// anything that should be easy to swap.
@immutable
class AppConfig {
  const AppConfig._();

  /// User-facing app name.
  static const String appName = 'Lagestroemia';

  /// Internal app identifier (used for shared preferences prefixes).
  static const String appId = 'com.lagestroemia';

  /// Semantic version, mirrors `pubspec.yaml`.
  static const String appVersion = '0.1.0';

  // ---- z.ai API ---------------------------------------------------------

  /// Default z.ai API base URL (OpenAI-compatible endpoint).
  ///
  /// Source: https://docs.z.ai/openapi.json — server root is
  /// `https://api.z.ai/api` and chat completions live under `/paas/v4`.
  static const String defaultApiBaseUrl = 'https://api.z.ai/api/paas/v4';

  /// Path appended to [defaultApiBaseUrl] for chat completions.
  static const String chatCompletionsPath = '/chat/completions';

  /// Path appended to [defaultApiBaseUrl] for file uploads.
  static const String filesPath = '/files';

  /// Path appended to [defaultApiBaseUrl] for tokenization (info endpoint).
  static const String tokenizerPath = '/tokenizer';

  /// Path appended to [defaultApiBaseUrl] for the web-search tool.
  static const String webSearchPath = '/web_search';

  /// Path appended to [defaultApiBaseUrl] for the reader tool.
  static const String readerPath = '/reader';

  // ---- z.ai web app URLs (used in Settings to deep-link to dashboards) --

  /// Where the user creates / rotates an API key.
  static const String apiKeyDashboardUrl = 'https://z.ai/manage-apikey/apikey-list';

  /// Where the user subscribes to the Coding Plan (pay-as-you-go is also
  /// available from this page).
  static const String subscribeUrl = 'https://z.ai/subscribe';

  /// Where the user can see rate-limit usage (login-gated).
  static const String rateLimitsUrl = 'https://z.ai/manage-apikey/rate-limits';

  /// Public docs root (Mintlify).
  static const String docsUrl = 'https://docs.z.ai';

  /// Models landing page (describes each GLM model and pricing).
  static const String modelsUrl = 'https://z.ai/model-api';

  // ---- Default model selection -----------------------------------------

  /// Model the chat screen picks when the user has not chosen one yet.
  ///
  /// `glm-4.6` is a good general default — multi-modal, mature, reasonable
  /// cost ($0.6 / $2.2 per 1M tokens at time of writing).
  static const String defaultModel = 'glm-4.6';

  /// List of well-known model IDs that the user can pick from in the chat
  /// composer's model dropdown.
  ///
  /// This list is intentionally curated — z.ai exposes many more variants
  /// (e.g. `glm-4.5-air`, `glm-4.5-x`, `autoglm-phone-multilingual`) but the
  /// composer only shows the most common ones; an "advanced" picker could
  /// expose the full set later.
  static const List<String> knownModels = <String>[
    'glm-4.6',          // default general-purpose
    'glm-4.7',          // newer
    'glm-4.5',          // cheaper, 128K context
    'glm-4.5-flash',    // free tier
    'glm-4.7-flash',    // free tier, newer
    'glm-4.5-air',      // balanced
    'glm-4.6v',         // vision-capable
    'glm-4.6v-flash',   // vision-capable, free
    'glm-5.3',          // flagship (paid)
    'glm-5.2',          // flagship (paid)
    'glm-5.1',          // flagship (paid)
  ];

  // ---- Storage keys ----------------------------------------------------

  /// SharedPreferences key prefix used to namespace app-local values.
  static const String prefsPrefix = 'lagestroemia.';

  /// SharedPreferences key for the active locale (BCP-47 tag).
  static const String prefsKeyLocale = '${prefsPrefix}locale';

  /// SharedPreferences key for the active theme mode
  /// ('system', 'light', 'dark').
  static const String prefsKeyThemeMode = '${prefsPrefix}theme_mode';

  /// SharedPreferences key for the selected model id.
  static const String prefsKeyModel = '${prefsPrefix}model';

  /// SharedPreferences key for the API base URL (overrides the default).
  static const String prefsKeyApiBaseUrl = '${prefsPrefix}api_base_url';

  /// SecureStorage key for the API key (Bearer token).
  ///
  /// Stored separately from SharedPreferences so it is encrypted at rest by
  /// the OS keychain (Windows Credential Manager / libsecret on Linux /
  /// Android Keystore / browser storage on Web).
  static const String secureKeyApiKey = 'lagestroemia.api_key';

  /// SecureStorage key for the optional JWT signing secret.
  ///
  /// z.ai API keys have the form `<id>.<secret>`. The `secret` half can be
  /// used to sign short-lived JWTs for the optional JWT auth flow (see
  /// https://docs.z.ai/guides/develop/http/introduction). Storing it
  /// separately lets us offer "JWT mode" without breaking plain Bearer mode.
  static const String secureKeyJwtSecret = 'lagestroemia.jwt_secret';

  // ---- HTTP behaviour --------------------------------------------------

  /// Default request timeout for non-streaming HTTP calls.
  static const Duration defaultTimeout = Duration(seconds: 30);

  /// Maximum size of an attached file (50 MiB). Larger files must be
  /// uploaded via /paas/v4/files first and referenced by id.
  static const int maxInlineFileBytes = 50 * 1024 * 1024;
}
