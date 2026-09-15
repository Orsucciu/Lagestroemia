// chat.z.ai request signature — reverse-engineered from the chat.z.ai
// web bundle (prod-fe-1.1.95).
//
// Every POST to /api/v2/chat/completions requires an `X-Signature`
// header (HMAC-SHA256, 64 hex chars). Without it, chat.z.ai rejects the
// request even if the captcha_verify_param is valid.
//
// Algorithm (from the bundle's `sne()` function):
//   1. sortedPayload = entries of {timestamp, requestId, user_id}
//                       sorted by key, joined by ","
//                      → "requestId,<uuid>,timestamp,<ms>,user_id,<uid>"
//   2. p = base64(utf8(promptText))
//   3. h = sortedPayload + "|" + p + "|" + timestamp
//   4. m = floor(timestamp_ms / 300000)  // 5-minute window
//   5. derivedKey = HMAC_SHA256(SECRET_KEY, str(m)) → hex
//   6. signature = HMAC_SHA256(derivedKey_as_utf8, h) → hex
//
// The SECRET_KEY is hardcoded in the bundle (obfuscated via RC4 + array
// rotation). Decoded value: "key-@@@@)))()((9))-xxxx&&&%%%%%"

import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:uuid/uuid.dart';

/// The hardcoded secret key extracted from the chat.z.ai JS bundle.
const _kSecretKey = 'key-@@@@)))()((9))-xxxx&&&%%%%%';

const _uuid = Uuid();

/// Builds the signed request metadata for a chat.z.ai chat completions
/// request. Returns the sorted payload, URL query params, timestamp,
/// and request id — all of which are needed to compute the signature
/// and build the final URL.
ChatZaiRequestMeta buildChatZaiRequestMeta({
  required String? userId,
  required String? token,
}) {
  final timestamp = DateTime.now().millisecondsSinceEpoch.toString();
  final requestId = _uuid.v4();

  // Build the sorted payload: entries of {timestamp, requestId, user_id}
  // sorted alphabetically by key, then joined by ",".
  // Key order after sorting: requestId < timestamp < user_id
  final entries = <MapEntry<String, String>>[
    MapEntry('timestamp', timestamp),
    MapEntry('requestId', requestId),
    MapEntry('user_id', userId ?? ''),
  ]..sort((a, b) => a.key.compareTo(b.key));
  // join(",") on [[k,v],[k,v]] → "k,v,k,v"
  final sortedPayload = entries
      .map((e) => '${e.key},${e.value}')
      .join(',');

  // Build the URL query params. Only timestamp, requestId, user_id
  // are part of the signed payload. The rest are browser-fingerprint
  // fields for bot-detection/analytics — values can be faked.
  final urlParams = <String, String>{
    'timestamp': timestamp,
    'requestId': requestId,
    'user_id': userId ?? '',
    'version': '0.0.1',
    'platform': 'web',
    if (token != null && token.isNotEmpty) 'token': token,
    'user_agent': 'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 '
        '(KHTML, like Gecko) Chrome/130.0.0.0 Safari/537.36',
    'language': 'en-US',
    'languages': 'en-US,en',
    'timezone': 'UTC',
    'cookie_enabled': 'true',
    'screen_width': '1920',
    'screen_height': '1080',
    'screen_resolution': '1920x1080',
    'viewport_height': '900',
    'viewport_width': '1440',
    'viewport_size': '1440x900',
    'color_depth': '24',
    'pixel_ratio': '1',
    'current_url': 'https://chat.z.ai/',
    'pathname': '/',
    'search': '',
    'hash': '',
    'host': 'chat.z.ai',
    'hostname': 'chat.z.ai',
    'protocol': 'https:',
    'referrer': '',
    'title': 'Z.ai',
    'timezone_offset': '0',
    'local_time': DateTime.now().toIso8601String(),
    'utc_time': DateTime.now().toUtc().toIso8601String(),
    'is_mobile': 'false',
    'is_touch': 'false',
    'max_touch_points': '0',
    'browser_name': 'Chrome',
    'os_name': 'Linux',
  };

  return ChatZaiRequestMeta(
    timestamp: timestamp,
    requestId: requestId,
    sortedPayload: sortedPayload,
    urlParams: urlParams,
  );
}

/// Computes the X-Signature header value for a chat.z.ai chat request.
///
/// [sortedPayload] comes from [buildChatZaiRequestMeta].
/// [promptText] is the user's prompt (the `signature_prompt` body field).
/// [timestamp] comes from [buildChatZaiRequestMeta].
String computeChatZaiSignature({
  required String sortedPayload,
  required String promptText,
  required String timestamp,
}) {
  // 1. base64-encode the UTF-8 bytes of the prompt.
  final p = base64Encode(utf8.encode(promptText));

  // 2. canonical string: sortedPayload | base64(prompt) | timestamp
  final h = '$sortedPayload|$p|$timestamp';

  // 3. 5-minute time window index
  final tsNum = int.parse(timestamp);
  final m = tsNum ~/ 300000; // 5 * 60 * 1000

  // 4. derived key = HMAC_SHA256(SECRET_KEY, str(m)) → 64-char hex
  final derivedKey = Hmac(sha256, utf8.encode(_kSecretKey))
      .convert(utf8.encode(m.toString()))
      .toString();

  // 5. signature = HMAC_SHA256(derivedKey_as_utf8, canonicalString) → hex
  final signature = Hmac(sha256, utf8.encode(derivedKey))
      .convert(utf8.encode(h))
      .toString();

  return signature;
}

/// Generates a random device id matching the format chat.z.ai expects:
/// `uid_` followed by 7 random alphanumeric characters. Persist this
/// across app launches (store in SharedPreferences).
String generateDeviceId() {
  const chars =
      'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789';
  final now = DateTime.now().microsecondsSinceEpoch;
  final buf = StringBuffer('uid_');
  for (var i = 0; i < 7; i++) {
    buf.write(chars[(now + i * 7919) % chars.length]);
  }
  return buf.toString();
}

/// Request metadata built by [buildChatZaiRequestMeta] and consumed by
/// [computeChatZaiSignature] and the URL builder.
class ChatZaiRequestMeta {
  const ChatZaiRequestMeta({
    required this.timestamp,
    required this.requestId,
    required this.sortedPayload,
    required this.urlParams,
  });

  final String timestamp;
  final String requestId;
  final String sortedPayload;
  final Map<String, String> urlParams;
}
