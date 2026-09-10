// Unit tests for the ZaiApiClient's chat-completions path selection.
//
// These don't hit the network — they only verify that
// `chatCompletionsPathFor(model, agentMode)` returns the right URL
// for each combination of backend + model + agent-mode flag.

import 'package:flutter_test/flutter_test.dart';
import 'package:dio/dio.dart';

import 'package:lagestroemia/core/config/app_config.dart';
import 'package:lagestroemia/data/api/zai_api_client.dart';

void main() {
  group('chatCompletionsPathFor (chat.z.ai backend)', () {
    late ZaiApiClient client;

    setUp(() {
      client = ZaiApiClient(
        bearerToken: 'fake-guest-token',
        backend: ApiBackend.chatZai,
        dio: Dio(),
      );
    });

    test('regular endpoint when agentMode is false (even for agent-capable model)',
        () {
      // `x-preview-l` is in chatZaiAgentCapableModels, but agentMode=false
      // so the regular endpoint should be used.
      expect(
        client.chatCompletionsPathFor(model: 'x-preview-l', agentMode: false),
        AppConfig.chatZaiChatCompletionsPath,
      );
    });

    test('agent endpoint when agentMode is true and model is agent-capable', () {
      expect(
        client.chatCompletionsPathFor(model: 'x-preview-l', agentMode: true),
        AppConfig.chatZaiAgentChatCompletionsPath,
      );
    });

    test('regular endpoint when agentMode is true but model is NOT agent-capable',
        () {
      // `glm-4.7` is a regular chat model — agentMode=true has no effect.
      expect(
        client.chatCompletionsPathFor(model: 'glm-4.7', agentMode: true),
        AppConfig.chatZaiChatCompletionsPath,
      );
    });

    test('falls back to default guest model when model is null', () {
      // AppConfig.defaultGuestModel is 'glm-4.7' which is NOT agent-capable.
      // So agentMode=true should still return the regular path.
      expect(
        client.chatCompletionsPathFor(model: null, agentMode: true),
        AppConfig.chatZaiChatCompletionsPath,
      );
    });
  });

  group('chatCompletionsPathFor (api.z.ai backend)', () {
    late ZaiApiClient client;

    setUp(() {
      client = ZaiApiClient(
        bearerToken: 'fake-api-key',
        backend: ApiBackend.apiZai,
        dio: Dio(),
      );
    });

    test('always uses the OpenAI-compatible chat path (agentMode is ignored)', () {
      // On api.z.ai, the public agent API has a different shape; callers
      // should use agentRequest(). The chat completions path is always
      // the regular one regardless of agentMode.
      expect(
        client.chatCompletionsPathFor(model: 'glm-4.6', agentMode: false),
        AppConfig.chatCompletionsPath,
      );
      expect(
        client.chatCompletionsPathFor(model: 'glm-4.6', agentMode: true),
        AppConfig.chatCompletionsPath,
      );
    });
  });

  group('AppConfig deep-think-capable model lists', () {
    test('chatZai deep-think models include the reasoning-capable ones', () {
      expect(AppConfig.isChatZaiDeepThinkModel('glm-4.7'), isTrue);
      expect(AppConfig.isChatZaiDeepThinkModel('glm-5.3'), isTrue);
      expect(AppConfig.isChatZaiDeepThinkModel('deep-research'), isTrue);
      // Vision-only or flash models not in the deep-think list.
      expect(AppConfig.isChatZaiDeepThinkModel('glm-4.6v'), isFalse);
    });

    test('apiZai deep-think models include the mainline GLM models', () {
      expect(AppConfig.isApiZaiDeepThinkModel('glm-4.6'), isTrue);
      expect(AppConfig.isApiZaiDeepThinkModel('glm-5.3'), isTrue);
      // Flash / vision models not in the list.
      expect(AppConfig.isApiZaiDeepThinkModel('glm-4.5-flash'), isFalse);
      expect(AppConfig.isApiZaiDeepThinkModel('glm-4.6v'), isFalse);
    });

    test('chatZai agent-capable models are still recognized', () {
      // Sanity-check that we didn't break the existing agent list.
      expect(AppConfig.isChatZaiAgentModel('x-preview-l'), isTrue);
      expect(AppConfig.isChatZaiAgentModel('deep-research'), isTrue);
      expect(AppConfig.isChatZaiAgentModel('glm-4.7'), isFalse);
    });
  });
}
