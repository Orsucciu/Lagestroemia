// Unit tests for the z.ai JWT signing helper.
//
// Verifies that our hand-rolled HS256 implementation produces a valid
// JWT shape with the correct header / payload fields that the z.ai
// API expects.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:lagestroemia/core/auth/zai_jwt.dart';

void main() {
  group('ZaiApiKeyParts', () {
    test('isCompositeKey returns true for id.secret shape', () {
      expect(ZaiApiKeyParts.isCompositeKey('abc.def'), isTrue);
      expect(ZaiApiKeyParts.isCompositeKey('1234567890.abcdef'), isTrue);
    });

    test('isCompositeKey returns false for non-composite keys', () {
      expect(ZaiApiKeyParts.isCompositeKey(''), isFalse);
      expect(ZaiApiKeyParts.isCompositeKey('noDot'), isFalse);
      expect(ZaiApiKeyParts.isCompositeKey('.startsWithDot'), isFalse);
      expect(ZaiApiKeyParts.isCompositeKey('endsWithDot.'), isFalse);
    });

    test('tryParse returns parts for composite keys', () {
      final parts = ZaiApiKeyParts.tryParse('abc.def');
      expect(parts, isNotNull);
      expect(parts!.id, 'abc');
      expect(parts.secret, 'def');
    });

    test('tryParse returns null for non-composite keys', () {
      expect(ZaiApiKeyParts.tryParse('noDot'), isNull);
      expect(ZaiApiKeyParts.tryParse(''), isNull);
    });
  });

  group('signZaiJwt', () {
    test('produces a valid JWT shape (three dot-separated base64url parts)',
        () {
      final parts = ZaiApiKeyParts(id: 'testid', secret: 'testsecret');
      final jwt = signZaiJwt(
        parts: parts,
        now: DateTime.utc(2025, 1, 1, 0, 0, 0),
      );
      final segments = jwt.split('.');
      expect(segments.length, 3);
      // Each segment should be base64url-safe (no padding, no `+`, no `/`).
      for (final s in segments) {
        expect(s, isNot(contains('=')));
        expect(s, isNot(contains('+')));
        expect(s, isNot(contains('/')));
      }
    });

    test('header decodes to {"alg":"HS256","sign_type":"SIGN","typ":"JWT"}',
        () {
      final parts = ZaiApiKeyParts(id: 'testid', secret: 'testsecret');
      final jwt = signZaiJwt(
        parts: parts,
        now: DateTime.utc(2025, 1, 1, 0, 0, 0),
      );
      final headerB64 = jwt.split('.').first;
      final padded = headerB64 + '=' * ((4 - headerB64.length % 4) % 4);
      final headerJson = utf8.decode(base64Url.decode(padded));
      final decoded = jsonDecode(headerJson) as Map<String, Object?>;
      expect(decoded['alg'], 'HS256');
      expect(decoded['sign_type'], 'SIGN');
      expect(decoded['typ'], 'JWT');
    });

    test('payload decodes to {api_key, exp, timestamp} with ms timestamps',
        () {
      final parts = ZaiApiKeyParts(id: 'myid', secret: 'mysecret');
      final fixedNow = DateTime.utc(2025, 1, 1, 0, 0, 0);
      final jwt = signZaiJwt(
        parts: parts,
        now: fixedNow,
      );
      final payloadB64 = jwt.split('.').skip(1).first;
      final padded = payloadB64 + '=' * ((4 - payloadB64.length % 4) % 4);
      final payloadJson = utf8.decode(base64Url.decode(padded));
      final decoded = jsonDecode(payloadJson) as Map<String, Object?>;
      final expectedTs = fixedNow.millisecondsSinceEpoch;
      final expectedExp = expectedTs + 60 * 60 * 1000; // 1 hour default
      expect(decoded['api_key'], 'myid');
      expect(decoded['timestamp'], expectedTs);
      expect(decoded['exp'], expectedExp);
    });

    test('signing is deterministic for the same input', () {
      final parts = ZaiApiKeyParts(id: 'myid', secret: 'mysecret');
      final fixedNow = DateTime.utc(2025, 1, 1, 0, 0, 0);
      final jwt1 = signZaiJwt(parts: parts, now: fixedNow);
      final jwt2 = signZaiJwt(parts: parts, now: fixedNow);
      expect(jwt1, jwt2);
    });

    test('signing changes with the secret', () {
      final p1 = ZaiApiKeyParts(id: 'myid', secret: 'secret1');
      final p2 = ZaiApiKeyParts(id: 'myid', secret: 'secret2');
      final fixedNow = DateTime.utc(2025, 1, 1, 0, 0, 0);
      final jwt1 = signZaiJwt(parts: p1, now: fixedNow);
      final jwt2 = signZaiJwt(parts: p2, now: fixedNow);
      // Header + payload are the same; only the signature differs.
      expect(jwt1.split('.').sublist(0, 2).join('.'),
          jwt2.split('.').sublist(0, 2).join('.'));
      expect(jwt1.split('.').last, isNot(jwt2.split('.').last));
    });

    test('validity period affects exp', () {
      final parts = ZaiApiKeyParts(id: 'myid', secret: 'mysecret');
      final fixedNow = DateTime.utc(2025, 1, 1, 0, 0, 0);
      final jwt1h = signZaiJwt(parts: parts, now: fixedNow);
      final jwt5m = signZaiJwt(
        parts: parts,
        now: fixedNow,
        validity: const Duration(minutes: 5),
      );
      final exp1h = _extractExp(jwt1h);
      final exp5m = _extractExp(jwt5m);
      expect(exp1h - exp5m, 55 * 60 * 1000); // 55 minutes in ms
    });

    // Cross-check against a reference token produced by Python's
    // PyJWT library (HS256, the exact same header/payload/secret). If
    // this test fails, our hand-rolled JWT does not match the spec.
    test('matches Python PyJWT reference output byte-for-byte', () {
      final parts = ZaiApiKeyParts(id: 'testid', secret: 'testsecret');
      final jwt = signZaiJwt(
        parts: parts,
        now: DateTime.utc(2025, 1, 1, 0, 0, 0),
      );
      // Generated with:
      //   python -c "import jwt; print(jwt.encode(
      //     {'api_key':'testid','exp':1735693200000,'timestamp':1735689600000},
      //     'testsecret', algorithm='HS256',
      //     headers={'alg':'HS256','sign_type':'SIGN'}))"
      const expected =
          'eyJhbGciOiJIUzI1NiIsInNpZ25fdHlwZSI6IlNJR04iLCJ0eXAiOiJKV1QifQ'
          '.eyJhcGlfa2V5IjoidGVzdGlkIiwiZXhwIjoxNzM1NjkzMjAwMDAwLCJ0aW1l'
          'c3RhbXAiOjE3MzU2ODk2MDAwMDB9.Sn_GgYe5VQf6Vl2zKKv_J477yAs-smpB'
          '3s5wJA3x79w';
      expect(jwt, expected);
    });
  });
}

int _extractExp(String jwt) {
  final payloadB64 = jwt.split('.').skip(1).first;
  // base64Url.decode requires padding; add it.
  final padded = payloadB64 + '=' * ((4 - payloadB64.length % 4) % 4);
  final payloadJson = utf8.decode(base64Url.decode(padded));
  final decoded = jsonDecode(payloadJson) as Map<String, Object?>;
  return decoded['exp']! as int;
}
