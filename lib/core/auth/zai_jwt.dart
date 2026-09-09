// JWT signing for z.ai API keys in form `<id>.<secret>`.
//
// z.ai supports an optional JWT-based authentication flow for higher
// security: instead of sending the raw API key as `Bearer`, sign a
// short-lived JWT using the secret half of the key. The token is
// valid for `exp_seconds` (default 1 hour).
//
// Spec (from https://docs.z.ai/guides/develop/http/introduction):
//
// ```python
// id, secret = apikey.split(".")
// payload = {
//   "api_key": id,
//   "exp": int(round(time.time() * 1000)) + exp_seconds * 1000,
//   "timestamp": int(round(time.time() * 1000)),
// }
// return jwt.encode(payload, secret, algorithm="HS256",
//   headers={"alg": "HS256", "sign_type": "SIGN"})
// ```
//
// We implement HS256 manually using `package:crypto`'s `Hmac` so we
// don't pull in a heavyweight JWT library. The output is the standard
// JWT `header.payload.signature` triple base64url-encoded.

import 'dart:convert';

import 'package:crypto/crypto.dart';

/// A pair of (id, secret) extracted from a z.ai API key.
class ZaiApiKeyParts {
  const ZaiApiKeyParts({required this.id, required this.secret});

  /// The id half (before the dot).
  final String id;

  /// The secret half (after the dot). Used as the HS256 signing key.
  final String secret;

  /// True if [raw] looks like a z.ai API key (contains a dot and both
  /// halves are non-empty).
  static bool isCompositeKey(String raw) {
    final idx = raw.indexOf('.');
    if (idx <= 0 || idx >= raw.length - 1) return false;
    return true;
  }

  /// Splits a raw key into id + secret. Returns null if [raw] is not in
  /// the `<id>.<secret>` shape.
  static ZaiApiKeyParts? tryParse(String raw) {
    final idx = raw.indexOf('.');
    if (idx <= 0 || idx >= raw.length - 1) return null;
    return ZaiApiKeyParts(
      id: raw.substring(0, idx),
      secret: raw.substring(idx + 1),
    );
  }
}

/// Signs a short-lived z.ai JWT for the given composite API key.
///
/// Returns the standard JWT string `header.payload.signature`
/// (base64url-encoded, no padding) suitable for use as the `Bearer`
/// token in chat completion requests.
///
/// [validity] defaults to 1 hour. z.ai accepts up to 24 hours.
String signZaiJwt({
  required ZaiApiKeyParts parts,
  Duration validity = const Duration(hours: 1),
  DateTime? now,
}) {
  final timestamp = (now ?? DateTime.now()).toUtc();
  final timestampMs = timestamp.millisecondsSinceEpoch;
  final expMs = timestampMs + validity.inMilliseconds;

  // JWT header. z.ai requires the `sign_type: SIGN` extra header.
  final header = <String, String>{
    'alg': 'HS256',
    'sign_type': 'SIGN',
    'typ': 'JWT',
  };

  // JWT payload. z.ai uses milliseconds (not seconds) for `exp` and
  // `timestamp`.
  final payload = <String, Object>{
    'api_key': parts.id,
    'exp': expMs,
    'timestamp': timestampMs,
  };

  final headerB64 = _b64UrlNoPad(utf8.encode(jsonEncode(header)));
  final payloadB64 = _b64UrlNoPad(utf8.encode(jsonEncode(payload)));
  final signingInput = '$headerB64.$payloadB64';

  final hmac = Hmac(sha256, utf8.encode(parts.secret));
  final digest = hmac.convert(utf8.encode(signingInput));
  final signatureB64 = _b64UrlNoPad(digest.bytes);

  return '$signingInput.$signatureB64';
}

String _b64UrlNoPad(List<int> bytes) {
  final encoded = base64Url.encode(bytes);
  return encoded.replaceAll('=', '');
}
