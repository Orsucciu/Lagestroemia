// Live integration test for the OpenAI-compatible local server.
//
// Starts the server on a random free port, hits each endpoint with
// curl/Dio, and verifies the responses. The test uses a fake bearer
// token provider that returns a real guest JWT fetched from
// chat.z.ai (so the upstream calls actually work end-to-end).
//
// Run:
//   /home/z/my-project/scripts/env.sh flutter test \
//     test/openai_api_server_live_test.dart

library openai_api_server_live_test;

import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:lagestroemia/core/config/app_config.dart';
import 'package:lagestroemia/data/api/openai_api_server.dart';

void main() {
  OpenAiApiServer? server;
  int port = 0;
  String? guestToken;

  setUpAll(() async {
    // 1. Fetch a guest token from chat.z.ai (real network call).
    final dio = Dio();
    final response = await dio.get<dynamic>(
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
    guestToken = m['token'] as String;
    expect(guestToken, isNotEmpty,
        reason: 'Guest signup should return a non-empty JWT');

    // 2. Bind the server to port 0 (the OS assigns a free port).
    server = OpenAiApiServer(
      bearerTokenProvider: () => guestToken,
    );
    final status = await server!.start(const OpenAiServerConfig(port: 0));
    expect(status.running, isTrue, reason: 'Server should start');
    expect(status.port, greaterThan(0));
    port = status.port!;
  });

  tearDownAll(() async {
    await server?.stop();
  });

  group('OpenAI-compat server (live)', () {
    test('GET / returns an HTML page', () async {
      final dio = Dio();
      final response = await dio.get<dynamic>('http://127.0.0.1:$port/');
      expect(response.statusCode, 200);
      expect(response.headers.value('content-type'), contains('text/html'));
      final body = response.data.toString();
      expect(body, contains('Lagestroemia OpenAI-compat server'));
    });

    test('GET /v1/health returns {"ok":true,"version":"...","port":<int>}',
        () async {
      final dio = Dio();
      final response = await dio.get<dynamic>('http://127.0.0.1:$port/v1/health');
      expect(response.statusCode, 200);
      final m = response.data as Map<String, Object?>;
      expect(m['ok'], isTrue);
      expect(m['version'], AppConfig.appVersion);
      expect(m['port'], port);
    });

    test('GET /v1/models returns the OpenAI list shape', () async {
      final dio = Dio();
      final response =
          await dio.get<dynamic>('http://127.0.0.1:$port/v1/models');
      expect(response.statusCode, 200);
      final m = response.data as Map<String, Object?>;
      expect(m['object'], 'list');
      final data = m['data'] as List<Object?>;
      expect(data, isNotEmpty);
      // chat.z.ai guest token → should return chatZaiKnownModels list
      // (which includes glm-4.7).
      final ids = data
          .map((e) => (e as Map<String, Object?>)['id'] as String)
          .toList();
      expect(ids, contains('glm-4.7'));
      // Each model entry should be the OpenAI shape.
      final first = data.first as Map<String, Object?>;
      expect(first['object'], 'model');
      expect(first['owned_by'], 'z.ai');
    });

    test('POST /v1/chat/completions (non-stream) forwards to z.ai and '
        'returns the captcha-required error in the OpenAI error shape',
        () async {
      final dio = Dio();
      final response = await dio.post<dynamic>(
        'http://127.0.0.1:$port/v1/chat/completions',
        data: <String, Object?>{
          'model': 'glm-4.7',
          'messages': <Map<String, Object?>>[
            <String, Object?>{'role': 'user', 'content': 'ping'},
          ],
          'stream': false,
        },
        options: Options(
          headers: <String, Object?>{'Content-Type': 'application/json'},
          // Accept any 5xx too — the server may return 500 when the
          // upstream rejects.
          validateStatus: (status) => status != null && status < 600,
        ),
      );
      final body = response.data;
      final bodyStr = body is String ? body : jsonEncode(body);
      // The captcha-required error from chat.z.ai comes back as a 200 OK
      // with the SSE envelope {"data":{"data":{"done":true,
      // "error":{"captcha_error_type":"missing_param",...}}},...}.
      // Our server should unwrap that and forward the inner `data` or
      // error object. Either way, the body should mention captcha.
      expect(
        bodyStr.toLowerCase(),
        contains('captcha'),
        reason: 'Expected the server to forward the captcha-required '
            'error. Status: ${response.statusCode}. Got: $bodyStr',
      );
    });

    test('POST /v1/chat/completions with invalid JSON returns a 400',
        () async {
      final dio = Dio();
      final response = await dio.post<dynamic>(
        'http://127.0.0.1:$port/v1/chat/completions',
        data: 'not valid json',
        options: Options(
          headers: <String, Object?>{'Content-Type': 'application/json'},
          validateStatus: (status) => status != null && status < 500,
        ),
      );
      expect(response.statusCode, 400);
      final m = response.data as Map<String, Object?>;
      expect((m['error'] as Map<String, Object?>)['type'],
          'invalid_request_error');
    });

    test('GET /unknown-route returns 404', () async {
      final dio = Dio();
      final response = await dio.get<dynamic>(
        'http://127.0.0.1:$port/this-does-not-exist',
        options: Options(
          validateStatus: (status) => status != null && status < 500,
        ),
      );
      expect(response.statusCode, 404);
      final m = response.data as Map<String, Object?>;
      expect((m['error'] as Map<String, Object?>)['type'],
          'invalid_request_error');
    });

    test('server API key auth rejects callers without a matching key',
        () async {
      // Start a second server with a server-API-key set.
      final secureServer = OpenAiApiServer(
        bearerTokenProvider: () => guestToken,
      );
      final status = await secureServer.start(
        const OpenAiServerConfig(port: 0, serverApiKey: 'test-secret-key'),
      );
      expect(status.running, isTrue);
      final securePort = status.port!;

      // Without the right key → 401.
      final dio = Dio();
      final noAuth = await dio.get<dynamic>(
        'http://127.0.0.1:$securePort/v1/health',
        options: Options(
          validateStatus: (status) => status != null && status < 500,
        ),
      );
      expect(noAuth.statusCode, 401);

      // With the right key → 200.
      final withAuth = await dio.get<dynamic>(
        'http://127.0.0.1:$securePort/v1/health',
        options: Options(
          headers: <String, Object?>{
            'Authorization': 'Bearer test-secret-key',
          },
          validateStatus: (status) => status != null && status < 500,
        ),
      );
      expect(withAuth.statusCode, 200);

      await secureServer.stop();
    });
  });
}
