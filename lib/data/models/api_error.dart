part of 'models.dart';

/// Error surfaced by the z.ai API. The shape mirrors the documented
/// response body `{"error": {"code": "1214", "message": "..."}}`, but we
/// also keep a generic `message` field for transport-level failures (DNS,
/// timeout, malformed SSE chunk).
@immutable
class ApiError {
  const ApiError({
    required this.message,
    this.code,
    this.httpStatus,
    this.kind = ApiErrorKind.unknown,
    this.cause,
  });

  /// Human-readable message suitable to show in a snackbar.
  final String message;

  /// z.ai business error code (e.g. `1214`). Null for transport errors.
  final String? code;

  /// HTTP status code (e.g. 401). Null for non-HTTP errors.
  final int? httpStatus;

  /// Coarse classification used by the UI to pick the right message.
  final ApiErrorKind kind;

  /// Underlying error, if any. Used for diagnostics, not for display.
  final Object? cause;

  /// Convenience: returns a [Result] carrying this error.
  Result<T, ApiError> errResult<T>() => Err<T, ApiError>(this);

  @override
  String toString() {
    final parts = <String>[];
    if (code != null) parts.add('code=$code');
    if (httpStatus != null) parts.add('http=$httpStatus');
    if (parts.isNotEmpty) return 'ApiError(${parts.join(' ')}): $message';
    return 'ApiError: $message';
  }
}

enum ApiErrorKind {
  auth,
  rateLimit,
  quota,
  badRequest,
  notFound,
  server,
  network,
  parse,
  cancelled,
  /// The model the user picked is not available to them. chat.z.ai
  /// returns this for guest users trying to use flagship models like
  /// glm-5.3 / glm-5.2 / GLM-5-Turbo (HTTP 403 with message "Model
  /// not available for current user level").
  modelNotAllowed,
  unknown;

  static ApiErrorKind fromHttpStatus(int? status) {
    if (status == null) return ApiErrorKind.network;
    if (status == 401) return ApiErrorKind.auth;
    // 403 stays `auth` for the OpenAI-compatible api.z.ai backend (where
    // it means the API key is invalid/revoked), but on chat.z.ai it
    // can also mean "this model is restricted to higher-tier users".
    // The chat_state.dart code inspects the message text to upgrade a
    // 403 to modelNotAllowed.
    if (status == 403) return ApiErrorKind.auth;
    if (status == 404) return ApiErrorKind.notFound;
    if (status == 429) return ApiErrorKind.rateLimit;
    if (status >= 400 && status < 500) return ApiErrorKind.badRequest;
    if (status >= 500) return ApiErrorKind.server;
    return ApiErrorKind.unknown;
  }

  static ApiErrorKind fromBusinessCode(String code) {
    switch (code) {
      case '1000':
      case '1001':
      case '1003':
        return ApiErrorKind.auth;
      case '1113':
      case '1302':
      case '1308':
      case '1310':
      case '1311':
      case '1313':
      case '1316':
      case '1317':
      case '1318':
      case '1319':
      case '1320':
      case '1321':
        return ApiErrorKind.quota;
      case '1210':
      case '1211':
      case '1213':
      case '1214':
      case '1261':
        return ApiErrorKind.badRequest;
      default:
        return ApiErrorKind.unknown;
    }
  }
}
