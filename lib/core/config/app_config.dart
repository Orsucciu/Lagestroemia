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

  /// Default z.ai API base URL (OpenAI-compatible endpoint). Used in
  /// API-key mode.
  ///
  /// Source: https://docs.z.ai/openapi.json — server root is
  /// `https://api.z.ai/api` and chat completions live under `/paas/v4`.
  static const String defaultApiBaseUrl = 'https://api.z.ai/api/paas/v4';

  /// chat.z.ai base URL — used in guest mode (the open-webui-style internal
  /// API that the website itself uses).
  ///
  /// The website silently signs up a guest user via
  /// `GET /v1/auths/` (returns a guest JWT) and then posts to
  /// `POST /v2/chat/completions` with that JWT. The endpoint requires the
  /// user to solve an Aliyun captcha per session before chat is allowed.
  static const String chatZaiApiBaseUrl = 'https://chat.z.ai/api';

  /// Front-end version sent in `X-FE-Version` header for chat.z.ai calls.
  /// This is the version the website itself sends (matches the JS bundle
  /// at https://z-cdn.chatglm.cn/z-ai/frontend/prod-fe-1.1.93/...).
  static const String chatZaiFeVersion = 'prod-fe-1.1.93';

  // ---- Chat completion paths (per mode) --------------------------------

  /// Path appended to [defaultApiBaseUrl] for chat completions
  /// (OpenAI-compatible, used in API-key mode).
  static const String chatCompletionsPath = '/chat/completions';

  /// Path appended to [chatZaiApiBaseUrl] for chat completions
  /// (open-webui-style, used in guest mode). The response is wrapped:
  /// `data: {"type":"chat:completion","data":{...}}` and `[DONE]`.
  static const String chatZaiChatCompletionsPath = '/v2/chat/completions';

  /// Path appended to [chatZaiApiBaseUrl] for anonymous guest signup.
  /// `GET /v1/auths/` returns a guest user with a JWT.
  static const String chatZaiGuestAuthPath = '/v1/auths/';

  /// Path appended to [chatZaiApiBaseUrl] for listing models.
  static const String chatZaiModelsPath = '/models';

  // ---- z.ai API key mode paths (api.z.ai) ------------------------------

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
  /// `glm-4.6` is a good general default for api.z.ai (paid) mode.
  static const String defaultModel = 'glm-4.6';

  /// Default model for guest mode (chat.z.ai). The website exposes a
  /// different model list — see [chatZaiKnownModels].
  static const String defaultGuestModel = 'glm-4.7';

  /// Models available on api.z.ai (API-key mode). Curated subset of the
  /// documented OpenAPI list.
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

  /// Models available on chat.z.ai (guest mode), as returned by
  /// `GET /api/models`. Sampled from a live response on 2026-09-09.
  ///
  /// Some IDs are non-obvious (`x-preview-l`, `0727-106B-API`) — these are
  /// the actual strings the website sends in the chat completions body.
  static const List<String> chatZaiKnownModels = <String>[
    'glm-4.7',                      // GLM-4.7
    'glm-4.6v',                      // GLM-4.6V (vision)
    'glm-5.3',                       // GLM-5.3
    'glm-5.2',                       // GLM-5.2
    'GLM-5-Turbo',                   // GLM-5-Turbo
    'GLM-5v-Turbo',                  // GLM-5V-Turbo (vision)
    '0727-106B-API',                 // GLM-4.5-Air
    '0727-360B-API',                 // GLM-4.5
    'x-preview-l',                   // GLM-5.3-Flash (preview)
    'deep-research',                 // Z1-Rumination
    'zero',                          // Z1-32B
  ];

  // ---- Aliyun captcha (used in guest mode before the first chat) ------

  /// Aliyun captcha SDK URL. Loaded lazily into the in-app webview that
  /// renders the captcha widget.
  static const String aliyunCaptchaSdkUrl =
      'https://o.alicdn.com/captcha-frontend/aliyunCaptcha/AliyunCaptcha.js';

  /// Aliyun captcha region (Singapore datacenter, matches what the website
  /// sends).
  static const String aliyunCaptchaRegion = 'sgp';

  /// Aliyun captcha prefix.
  static const String aliyunCaptchaPrefix = 'no8xfe';

  /// Aliyun captcha scene id for chat.z.ai.
  static const String aliyunCaptchaSceneIdChatZai = 'didk33e0';

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
