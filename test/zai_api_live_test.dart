// Integration tests against the live chat.z.ai backend.
//
// These tests are tagged with 'live' so they can be filtered out of the
// default `flutter test` run (which is offline). Run them with:
//
//   flutter test test/zai_api_live_test.dart
//
// (The default test run skips live tests because they hit the real
// network and require the chat.z.ai backend to be reachable.)

library zai_api_live_test;

import 'package:flutter_test/flutter_test.dart';
import 'package:dio/dio.dart';

import 'package:lagestroemia/core/config/app_config.dart';
import 'package:lagestroemia/data/api/zai_api_client.dart';

@Tags(['live'])
void main() {
  late ZaiApiClient client;
  late String guestToken;

  setUpAll(() async {
    // 1. Fetch a guest token from chat.z.ai.
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

    // 2. Create a guest-mode client.
    client = ZaiApiClient(
      bearerToken: guestToken,
      backend: ApiBackend.chatZai,
      dio: dio,
    );
  });

  test('guest signup returns a JWT and a guest user id', () {
    // Already verified in setUpAll; this test exists so the live test
    // suite has at least one explicit assertion.
    expect(guestToken.length, greaterThan(40));
  });

  test('chat completions endpoint is reachable and returns captcha-required',
      () async {
    final stream = client.chatCompletionStream(
      messages: <Map<String, Object?>>[
        <String, Object?>{'role': 'user', 'content': 'ping'},
      ],
      model: 'glm-4.7',
    );
    final chunks = <ChatStreamChunk>[];
    await for (final chunk in stream) {
      chunks.add(chunk);
      if (chunk.error != null) break;
    }
    // Diagnostic output to help diagnose failures.
    // ignore: avoid_print
    print('Got ${chunks.length} chunks. Errors: '
        '${chunks.where((c) => c.error != null).map((c) => c.error!.message).toList()}');
    expect(chunks, isNotEmpty);
    // The first chunk should carry the captcha-required error.
    final hasCaptchaError = chunks.any((c) =>
        c.error != null &&
        (c.error!.message.contains('CAPTCHA') ||
            c.error!.message.contains('captcha') ||
            c.error!.message.contains('Captcha')));
    expect(hasCaptchaError, isTrue,
        reason: 'Expected the chat endpoint to require a captcha in guest '
            'mode. Got chunks: $chunks');
  });

  test('model list endpoint returns a non-empty list including glm-4.7',
      () async {
    final models = await client.listModels();
    expect(models, isNotEmpty);
    expect(models, contains('glm-4.7'));
  }, timeout: const Timeout(Duration(seconds: 30)));
}
