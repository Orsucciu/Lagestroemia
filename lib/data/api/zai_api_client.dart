// z.ai API client.
//
// Wraps the OpenAI-compatible `/paas/v4/chat/completions` endpoint with:
//  - streaming (SSE parser),
//  - plain (non-streaming) calls,
//  - file uploads via `/paas/v4/files`,
//  - structured error handling via [ApiError].
//
// The client is intentionally thin — it knows about HTTP and the wire format,
// and nothing else. Domain logic lives in providers / repositories.

import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:logging/logging.dart';

import '../../core/config/app_config.dart';
import '../../core/result/result.dart';
import '../models/models.dart';

/// A parsed chunk from the streaming chat completions endpoint.
class ChatStreamChunk {
  const ChatStreamChunk({
    this.contentDelta,
    this.reasoningDelta,
    this.finishReason,
    this.usage,
  });

  /// Incremental text appended to `choices[0].delta.content`. May be null
  /// (e.g. when only reasoning is being streamed).
  final String? contentDelta;

  /// Incremental reasoning content (GLM-4.6+).
  final String? reasoningDelta;

  /// Set on the last chunk before `[DONE]`.
  final String? finishReason;

  /// Set on the last chunk: token usage breakdown.
  final Map<String, Object?>? usage;

  bool get isDone => finishReason != null;
}

/// Token usage breakdown from the chat completions endpoint.
class ChatUsage {
  const ChatUsage({
    required this.promptTokens,
    required this.completionTokens,
    required this.totalTokens,
  });

  final int promptTokens;
  final int completionTokens;
  final int totalTokens;

  factory ChatUsage.fromMap(Map<String, Object?> m) {
    return ChatUsage(
      promptTokens: (m['prompt_tokens'] as num?)?.toInt() ?? 0,
      completionTokens: (m['completion_tokens'] as num?)?.toInt() ?? 0,
      totalTokens: (m['total_tokens'] as num?)?.toInt() ?? 0,
    );
  }
}

/// High-level z.ai API client.
///
/// Construct once per app run and keep it for the lifetime of the app.
class ZaiApiClient {
  ZaiApiClient({
    required String apiKey,
    String? apiBaseUrl,
    Dio? dio,
  })  : _apiKey = apiKey,
        _apiBaseUrl = (apiBaseUrl ?? AppConfig.defaultApiBaseUrl),
        _dio = dio ?? Dio() {
    _dio.options
      ..baseUrl = _apiBaseUrl
      ..connectTimeout = AppConfig.defaultTimeout
      ..receiveTimeout = AppConfig.defaultTimeout * 2
      ..headers = <String, Object?>{
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $_apiKey',
        // Hint z.ai to send back English error messages. The body content
        // itself follows the user's input language.
        'Accept-Language': 'en-US,en',
      };
  }

  final String _apiKey;
  final String _apiBaseUrl;
  final Dio _dio;
  static final Logger _log = Logger('lagestroemia.api');

  /// Returns the configured base URL (no trailing slash). Useful for
  /// displaying in the Settings screen.
  String get apiBaseUrl => _apiBaseUrl;

  /// Sends a non-streaming chat completion request.
  ///
  /// [messages] is the OpenAI-shaped list of message objects. [model]
  /// defaults to [AppConfig.defaultModel]. Other optional fields are
  /// forwarded as-is.
  ///
  /// Returns the assistant message content (`choices[0].message.content`)
  /// plus optional reasoning + tool_calls.
  Future<Result<AssistantResponse, ApiError>> chatCompletion({
    required List<Map<String, Object?>> messages,
    String? model,
    double? temperature,
    int? maxTokens,
    List<String>? stop,
    Map<String, Object?>? tools,
    Map<String, Object?>? thinking,
    String? reasoningEffort,
    Map<String, Object?>? responseFormat,
    String? requestId,
    String? userId,
    bool? doSample,
  }) async {
    final body = <String, Object?>{
      'model': model ?? AppConfig.defaultModel,
      'messages': messages,
      'stream': false,
      if (temperature != null) 'temperature': temperature,
      if (maxTokens != null) 'max_tokens': maxTokens,
      if (stop != null) 'stop': stop,
      if (tools != null) 'tools': tools,
      if (thinking != null) 'thinking': thinking,
      if (reasoningEffort != null) 'reasoning_effort': reasoningEffort,
      if (responseFormat != null) 'response_format': responseFormat,
      if (requestId != null) 'request_id': requestId,
      if (userId != null) 'user_id': userId,
      if (doSample != null) 'do_sample': doSample,
    };

    try {
      final response = await _dio.post<dynamic>(
        AppConfig.chatCompletionsPath,
        data: jsonEncode(body),
      );
      final data = response.data;
      final map = data is String ? jsonDecode(data) as Map<String, Object?> : data as Map<String, Object?>;
      return Ok(_parseAssistantResponse(map));
    } on DioException catch (e) {
      return _dioErrorToApiError(e).errResult();
    }
  }

  /// Sends a streaming chat completion request.
  ///
  /// Yields [ChatStreamChunk]s as they arrive over the SSE connection. The
  /// stream closes after the `[DONE]` sentinel.
  Stream<ChatStreamChunk> chatCompletionStream({
    required List<Map<String, Object?>> messages,
    String? model,
    double? temperature,
    int? maxTokens,
    List<String>? stop,
    Map<String, Object?>? tools,
    Map<String, Object?>? thinking,
    String? reasoningEffort,
    Map<String, Object?>? responseFormat,
    String? requestId,
    String? userId,
    bool? doSample,
  }) async* {
    final body = <String, Object?>{
      'model': model ?? AppConfig.defaultModel,
      'messages': messages,
      'stream': true,
      if (temperature != null) 'temperature': temperature,
      if (maxTokens != null) 'max_tokens': maxTokens,
      if (stop != null) 'stop': stop,
      if (tools != null) 'tools': tools,
      if (thinking != null) 'thinking': thinking,
      if (reasoningEffort != null) 'reasoning_effort': reasoningEffort,
      if (responseFormat != null) 'response_format': responseFormat,
      if (requestId != null) 'request_id': requestId,
      if (userId != null) 'user_id': userId,
      if (doSample != null) 'do_sample': doSample,
    };

    Response<ResponseBody> response;
    try {
      response = await _dio.post<ResponseBody>(
        AppConfig.chatCompletionsPath,
        data: jsonEncode(body),
        options: Options(
          responseType: ResponseType.stream,
          headers: <String, Object?>{
            'Accept': 'text/event-stream',
          },
        ),
      );
    } on DioException catch (e) {
      _log.warning('chatCompletionStream failed: $e');
      final apiError = _dioErrorToApiError(e);
      yield ChatStreamChunk(
        finishReason: 'error',
        usage: <String, Object?>{
          'error': apiError.message,
          'code': apiError.code,
        },
      );
      return;
    }

    final stream = response.data?.stream ??
        const Stream<List<int>>.empty();
    // Convert the byte stream into a stream of decoded SSE events.
    final decoded = _utf8Decode(stream);
    await for (final event in _sseEvents(decoded)) {
      if (event == '[DONE]') {
        return;
      }
      final map = jsonDecode(event) as Map<String, Object?>;
      final choices = map['choices'] as List<Object?>?;
      if (choices == null || choices.isEmpty) {
        // Edge case: an early chunk with no choice. Skip.
        continue;
      }
      final choice = choices.first as Map<String, Object?>;
      final delta = (choice['delta'] as Map<Object?, Object?>?)?.cast<String, Object?>();
      final finish = choice['finish_reason'] as String?;
      final usage = map['usage'] as Map<Object?, Object?>?;
      yield ChatStreamChunk(
        contentDelta: delta?['content'] as String?,
        reasoningDelta: delta?['reasoning_content'] as String?,
        finishReason: finish,
        usage: usage?.cast<String, Object?>(),
      );
    }
  }

  /// Uploads a file to z.ai's file storage and returns the file id.
  ///
  /// [purpose] must be `'user_data'` (glossary) or `'agent'` (RAG / chat
  /// references). See https://docs.z.ai/api-reference/files/upload-a-file.
  Future<Result<RemoteFile, ApiError>> uploadFile({
    required String filename,
    required String mimeType,
    required List<int> bytes,
    required String purpose,
  }) async {
    final form = FormData.fromMap(<String, Object?>{
      'purpose': purpose,
      'file': MultipartFile.fromBytes(bytes, filename: filename,
          contentType: DioMediaType.parse(mimeType)),
    });
    try {
      final response = await _dio.post<dynamic>(
        AppConfig.filesPath,
        data: form,
        options: Options(
          headers: <String, Object?>{
            'Content-Type': 'multipart/form-data',
          },
        ),
      );
      final data = response.data;
      final m = data is String
          ? jsonDecode(data) as Map<String, Object?>
          : data as Map<String, Object?>;
      return Ok(RemoteFile(
        id: m['id']! as String,
        filename: m['filename']! as String,
        bytes: (m['bytes'] as num?)?.toInt() ?? bytes.length,
        purpose: m['purpose']! as String,
        createdAt: DateTime.now().toUtc(),
      ));
    } on DioException catch (e) {
      return _dioErrorToApiError(e).errResult();
    }
  }
}

/// Response from a non-streaming chat completion request.
class AssistantResponse {
  const AssistantResponse({
    required this.content,
    this.reasoning,
    this.toolCalls,
    required this.usage,
    required this.finishReason,
  });

  final String content;
  final String? reasoning;
  final List<Map<String, Object?>>? toolCalls;
  final ChatUsage usage;
  final String finishReason;
}

/// Metadata for a file uploaded to z.ai's file storage.
class RemoteFile {
  const RemoteFile({
    required this.id,
    required this.filename,
    required this.bytes,
    required this.purpose,
    required this.createdAt,
  });

  final String id;
  final String filename;
  final int bytes;
  final String purpose;
  final DateTime createdAt;
}

// ---- helpers --------------------------------------------------------------

/// Parses the JSON body of a non-streaming chat completion response.
AssistantResponse _parseAssistantResponse(Map<String, Object?> map) {
  final choices = map['choices'] as List<Object?>? ?? const [];
  if (choices.isEmpty) {
    return const AssistantResponse(
      content: '',
      usage: ChatUsage(
        promptTokens: 0,
        completionTokens: 0,
        totalTokens: 0,
      ),
      finishReason: 'stop',
    );
  }
  final choice = choices.first as Map<String, Object?>;
  final message = (choice['message'] as Map<Object?, Object?>).cast<String, Object?>();
  final content = (message['content'] as String?) ?? '';
  final reasoning = message['reasoning_content'] as String?;
  final rawToolCalls = message['tool_calls'] as List<Object?>?;
  final toolCalls = rawToolCalls
      ?.map((e) => (e as Map<Object?, Object?>).cast<String, Object?>())
      .toList(growable: false);
  final usageMap = (map['usage'] as Map<Object?, Object?>?)?.cast<String, Object?>();
  final usage = ChatUsage.fromMap(usageMap ?? const {});
  final finishReason = (choice['finish_reason'] as String?) ?? 'stop';
  return AssistantResponse(
    content: content,
    reasoning: reasoning,
    toolCalls: toolCalls,
    usage: usage,
    finishReason: finishReason,
  );
}

ApiError _dioErrorToApiError(DioException e) {
  // z.ai error body: {"error":{"code":"1214","message":"..."}}
  final data = e.response?.data;
  Map<String, Object?>? errorBody;
  if (data is Map<String, Object?>) {
    errorBody = data['error'] as Map<String, Object?>?;
  } else if (data is String) {
    try {
      final decoded = jsonDecode(data) as Map<String, Object?>;
      errorBody = decoded['error'] as Map<String, Object?>?;
    } catch (_) {/* not JSON */}
  }
  final code = errorBody?['code'] as String?;
  final message = (errorBody?['message'] as String?) ?? e.message ?? 'Network error';
  final httpStatus = e.response?.statusCode;
  ApiErrorKind kind;
  if (code != null) {
    kind = ApiErrorKind.fromBusinessCode(code);
  } else {
    kind = ApiErrorKind.fromHttpStatus(httpStatus);
  }
  if (e.type == DioExceptionType.connectionTimeout ||
      e.type == DioExceptionType.receiveTimeout ||
      e.type == DioExceptionType.connectionError) {
    kind = ApiErrorKind.network;
  }
  if (e.type == DioExceptionType.cancel) {
    kind = ApiErrorKind.cancelled;
  }
  return ApiError(
    message: message,
    code: code,
    httpStatus: httpStatus,
    kind: kind,
    cause: e,
  );
}

Stream<String> _utf8Decode(Stream<List<int>> bytes) {
  // Glue consecutive byte arrays and decode using utf8 decoder so that
  // multi-byte chars split across chunks are not corrupted.
  return bytes.transform(utf8.decoder);
}

/// Splits a stream of UTF-8 text into SSE event payloads.
///
/// SSE format: events are separated by a blank line. Each event may have
/// one or more lines starting with `data: `. We concatenate the data
/// lines of a single event into one string. We only care about `data:`
/// events (z.ai does not emit `event:` typed messages for chat
/// completions). The sentinel `data: [DONE]` is yielded as the literal
/// string `[DONE]`.
Stream<String> _sseEvents(Stream<String> text) async* {
  final buffer = StringBuffer();
  await for (final chunk in text) {
    buffer.write(chunk);
    // Find every complete event (ending with `\n\n`).
    while (true) {
      final s = buffer.toString();
      final idx = s.indexOf('\n\n');
      if (idx == -1) break;
      final event = s.substring(0, idx);
      buffer.clear();
      buffer.write(s.substring(idx + 2));
      // Parse the event's data lines.
      final dataLines = <String>[];
      for (final line in event.split('\n')) {
        if (line.startsWith('data:')) {
          dataLines.add(line.substring(5).trimLeft());
        } else if (line.startsWith(':')) {
          // comment, ignore
        } else if (line.startsWith('event:') ||
            line.startsWith('id:') ||
            line.startsWith('retry:')) {
          // we don't use these
        }
      }
      if (dataLines.isEmpty) continue;
      yield dataLines.join('\n');
    }
  }
}
