// z.ai API client.
//
// Supports two distinct backends:
//
// 1. **api.z.ai** (OpenAI-compatible, used in API-key mode).
//    - Base URL: https://api.z.ai/api/paas/v4
//    - Auth: `Authorization: Bearer <api_key>`
//    - Chat completions: POST /chat/completions
//    - SSE: standard OpenAI shape, `data: { ... }\n\n` then `data: [DONE]`
//    - File upload: POST /files (multipart)
//
// 2. **chat.z.ai** (open-webui-style, used in guest mode).
//    - Base URL: https://chat.z.ai/api
//    - Auth: `Authorization: Bearer <guest_jwt>` + `X-FE-Version` header
//    - Chat completions: POST /v2/chat/completions
//    - SSE: wrapped shape, `data: {"type":"chat:completion","data":{...}}\n\n`
//      then `data: [DONE]`. The actual content delta is at
//      `data.choices[0].delta.content`.
//    - Requires `captcha_verify_param` in the body for the first chat in a
//      session (provided by the in-app Aliyun captcha widget).
//    - File upload: not supported in guest mode.
//
// The client is intentionally thin — it knows about HTTP and the wire
// format, and nothing else. Domain logic lives in providers /
// repositories.

import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:logging/logging.dart';

import '../../core/config/app_config.dart';
import '../../core/result/result.dart';
import '../models/models.dart';

/// Which backend the client is talking to.
enum ApiBackend {
  /// api.z.ai (OpenAI-compatible, API-key mode).
  apiZai,

  /// chat.z.ai (open-webui, guest mode).
  chatZai,
}

/// A parsed chunk from the streaming chat completions endpoint.
class ChatStreamChunk {
  const ChatStreamChunk({
    this.contentDelta,
    this.reasoningDelta,
    this.finishReason,
    this.usage,
    this.error,
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

  /// Set on a chunk that carries an error (chat.z.ai surfaces errors inline
  /// via `data.error`).
  final ApiError? error;

  bool get isDone => finishReason != null || error != null;
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
    required String bearerToken,
    String? apiBaseUrl,
    ApiBackend backend = ApiBackend.apiZai,
    Dio? dio,
    String? captchaVerifyParam,
  })  : _token = bearerToken,
        _backend = backend,
        _apiBaseUrl = apiBaseUrl ??
            (backend == ApiBackend.chatZai
                ? AppConfig.chatZaiApiBaseUrl
                : AppConfig.defaultApiBaseUrl),
        _captchaVerifyParam = captchaVerifyParam,
        _dio = dio ?? Dio() {
    _dio.options
      ..baseUrl = _apiBaseUrl
      ..connectTimeout = AppConfig.defaultTimeout
      ..receiveTimeout = AppConfig.defaultTimeout * 2
      ..headers = <String, Object?>{
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $_token',
        // Hint z.ai to send back English error messages. The body content
        // itself follows the user's input language.
        'Accept-Language': 'en-US,en',
        if (backend == ApiBackend.chatZai) ...<String, Object?>{
          'X-FE-Version': AppConfig.chatZaiFeVersion,
          'Origin': 'https://chat.z.ai',
          'Referer': 'https://chat.z.ai/',
          'User-Agent':
              'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0.0.0 Safari/537.36',
        },
      };
  }

  final String _token;
  final ApiBackend _backend;
  final String _apiBaseUrl;
  final String? _captchaVerifyParam;
  final Dio _dio;
  static final Logger _log = Logger('lagestroemia.api');

  /// Returns the configured base URL (no trailing slash).
  String get apiBaseUrl => _apiBaseUrl;

  /// Returns the active backend.
  ApiBackend get backend => _backend;

  /// Returns the chat completions path for the active backend.
  String get _chatCompletionsPath => _backend == ApiBackend.chatZai
      ? AppConfig.chatZaiChatCompletionsPath
      : AppConfig.chatCompletionsPath;

  /// Updates the captcha token (called by the in-app captcha widget when
  /// the user solves it).
  void setCaptchaVerifyParam(String? param) {
    // We can't mutate `_captchaVerifyParam` (final) — re-create the client
    // via the provider when needed. For simplicity, we expose this method
    // and the provider invalidates the apiClientProvider when it changes.
    // (Implementation: nothing here — the caller re-creates the client.)
  }

  /// Sends a non-streaming chat completion request.
  ///
  /// [messages] is the OpenAI-shaped list of message objects. [model]
  /// defaults to [AppConfig.defaultModel]. Other optional fields are
  /// forwarded as-is.
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
    final body = _buildBody(
      messages: messages,
      model: model,
      temperature: temperature,
      maxTokens: maxTokens,
      stop: stop,
      tools: tools,
      thinking: thinking,
      reasoningEffort: reasoningEffort,
      responseFormat: responseFormat,
      requestId: requestId,
      userId: userId,
      doSample: doSample,
      stream: false,
    );

    try {
      final response = await _dio.post<dynamic>(
        _chatCompletionsPath,
        data: jsonEncode(body),
      );
      final data = response.data;
      final map = data is String
          ? jsonDecode(data) as Map<String, Object?>
          : data as Map<String, Object?>;
      return Ok(_parseAssistantResponse(map, _backend));
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
    CancelToken? cancelToken,
  }) async* {
    final body = _buildBody(
      messages: messages,
      model: model,
      temperature: temperature,
      maxTokens: maxTokens,
      stop: stop,
      tools: tools,
      thinking: thinking,
      reasoningEffort: reasoningEffort,
      responseFormat: responseFormat,
      requestId: requestId,
      userId: userId,
      doSample: doSample,
      stream: true,
    );

    Response<ResponseBody> response;
    try {
      response = await _dio.post<ResponseBody>(
        _chatCompletionsPath,
        data: jsonEncode(body),
        cancelToken: cancelToken,
        options: Options(
          responseType: ResponseType.stream,
          headers: <String, Object?>{
            'Accept': 'text/event-stream',
          },
        ),
      );
    } on DioException catch (e) {
      if (e.type == DioExceptionType.cancel) {
        // Cancelled by the user — yield a special chunk so the consumer can
        // stop cleanly.
        yield const ChatStreamChunk(finishReason: 'cancelled');
        return;
      }
      _log.warning('chatCompletionStream failed: $e');
      final apiError = _dioErrorToApiError(e);
      yield ChatStreamChunk(error: apiError);
      return;
    }

    final stream =
        response.data?.stream ?? const Stream<List<int>>.empty();
    final decoded = _utf8Decode(stream);
    await for (final event in _sseEvents(decoded)) {
      if (event == '[DONE]') {
        return;
      }
      final map = jsonDecode(event) as Map<String, Object?>;

      // chat.z.ai wraps the payload in {"type": "chat:completion", "data": {...}}
      final payload = _backend == ApiBackend.chatZai
          ? _unwrapChatZai(map)
          : map;

      if (payload == null) continue;

      // Inline error in chat.z.ai stream.
      final inlineError = payload['error'];
      if (inlineError is Map<Object?, Object?>) {
        final rawCode = inlineError['code'];
        final code = rawCode is num
            ? rawCode.toInt()
            : rawCode is String
                ? int.tryParse(rawCode)
                : null;
        // The chat.z.ai captcha-required error has error_code
        // `FRONTEND_CAPTCHA_REQUIRED` (a string), not a numeric code.
        final errorCodeString = inlineError['error_code'] as String?;
        final isCaptchaRequired =
            errorCodeString == 'FRONTEND_CAPTCHA_REQUIRED' ||
                (inlineError['captcha_error_type'] != null);
        final detail =
            (inlineError['detail'] as String?) ?? 'Unknown error';
        // 426 = outdated client; treat as a soft error.
        yield ChatStreamChunk(
          error: ApiError(
            message: isCaptchaRequired
                ? 'Captcha required. Please solve the captcha to continue.'
                : detail,
            code: code?.toString() ?? errorCodeString,
            kind: isCaptchaRequired
                ? ApiErrorKind.badRequest
                : code == 426
                    ? ApiErrorKind.badRequest
                    : code == 401
                        ? ApiErrorKind.auth
                        : ApiErrorKind.unknown,
          ),
        );
        return;
      }

      final choices = payload['choices'] as List<Object?>?;
      if (choices == null || choices.isEmpty) {
        // Sometimes chat.z.ai sends usage-only chunks. Skip.
        final usage = payload['usage'];
        if (usage is Map<Object?, Object?>?) {
          yield ChatStreamChunk(usage: usage?.cast<String, Object?>());
        }
        continue;
      }
      final choice = choices.first as Map<String, Object?>;
      final delta =
          (choice['delta'] as Map<Object?, Object?>?)?.cast<String, Object?>();
      final finish = choice['finish_reason'] as String?;
      final usage = payload['usage'] as Map<Object?, Object?>?;
      yield ChatStreamChunk(
        contentDelta: delta?['content'] as String?,
        reasoningDelta: delta?['reasoning_content'] as String?,
        finishReason: finish,
        usage: usage?.cast<String, Object?>(),
      );
    }
  }

  /// Uploads a file to z.ai's file storage and returns the file id.
  /// Only supported in API-key mode (api.z.ai).
  Future<Result<RemoteFile, ApiError>> uploadFile({
    required String filename,
    required String mimeType,
    required List<int> bytes,
    required String purpose,
  }) async {
    if (_backend == ApiBackend.chatZai) {
      return Err<RemoteFile, ApiError>(ApiError(
        message: 'File upload is not supported in guest mode. Sign in with '
            'an API key to use file uploads.',
        kind: ApiErrorKind.unknown,
      ));
    }
    final form = FormData.fromMap(<String, Object?>{
      'purpose': purpose,
      'file': MultipartFile.fromBytes(bytes,
          filename: filename, contentType: DioMediaType.parse(mimeType)),
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

  /// Fetches the model list from the active backend.
  ///
  /// For api.z.ai this returns the documented model list (statically
  /// declared in [AppConfig.knownModels] — the docs don't expose a list
  /// endpoint).
  /// For chat.z.ai this calls `GET /models` and returns the actual list
  /// returned by the backend.
  Future<List<String>> listModels() async {
    if (_backend == ApiBackend.apiZai) {
      return const <String>[...AppConfig.knownModels];
    }
    try {
      final response = await _dio.get<dynamic>(AppConfig.chatZaiModelsPath);
      final data = response.data;
      final m = data is String
          ? jsonDecode(data) as Map<String, Object?>
          : data as Map<String, Object?>;
      final list = (m['data'] as List<Object?>?) ?? const <Object?>[];
      return list
          .map((e) => ((e as Map<Object?, Object?>)['id'] as String?) ?? '')
          .where((s) => s.isNotEmpty)
          .toList(growable: false);
    } catch (e) {
      _log.warning('listModels failed: $e');
      return const <String>[...AppConfig.chatZaiKnownModels];
    }
  }

  // ---- body builder ----------------------------------------------------

  Map<String, Object?> _buildBody({
    required List<Map<String, Object?>> messages,
    required String? model,
    required double? temperature,
    required int? maxTokens,
    required List<String>? stop,
    required Map<String, Object?>? tools,
    required Map<String, Object?>? thinking,
    required String? reasoningEffort,
    required Map<String, Object?>? responseFormat,
    required String? requestId,
    required String? userId,
    required bool? doSample,
    required bool stream,
  }) {
    final defaultModel = _backend == ApiBackend.chatZai
        ? AppConfig.defaultGuestModel
        : AppConfig.defaultModel;
    final body = <String, Object?>{
      'model': model ?? defaultModel,
      'messages': messages,
      'stream': stream,
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
    if (_backend == ApiBackend.chatZai && _captchaVerifyParam != null) {
      body['captcha_verify_param'] = _captchaVerifyParam;
    }
    return body;
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

/// Unwraps the chat.z.ai `{"type": "chat:completion", "data": {...}}`
/// envelope. Returns null if the envelope is malformed.
Map<String, Object?>? _unwrapChatZai(Map<String, Object?> map) {
  // The streaming format is `{"data": {"data": {...}}, "type": "chat:completion"}`
  // for content, or `{"data": {...}, "type": ...}` for control events.
  final type = map['type'] as String?;
  if (type != 'chat:completion') {
    // Other event types (e.g. `chat:completion:start`) — skip.
    return null;
  }
  final data = map['data'];
  if (data is! Map<Object?, Object?>) return null;
  // Some chunks have an extra nested `data` wrapper (the actual OpenAI
  // payload sits inside `data.data`).
  final innerData = data['data'];
  if (innerData is Map<Object?, Object?>) {
    return Map<String, Object?>.from(innerData);
  }
  return Map<String, Object?>.from(data);
}

/// Parses the JSON body of a non-streaming chat completion response.
AssistantResponse _parseAssistantResponse(
    Map<String, Object?> map, ApiBackend backend) {
  // chat.z.ai wraps the payload.
  final payload = backend == ApiBackend.chatZai
      ? (_unwrapChatZai(map) ?? const {})
      : map;

  final choices = payload['choices'] as List<Object?>? ?? const [];
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
  final message =
      (choice['message'] as Map<Object?, Object?>).cast<String, Object?>();
  final content = (message['content'] as String?) ?? '';
  final reasoning = message['reasoning_content'] as String?;
  final rawToolCalls = message['tool_calls'] as List<Object?>?;
  final toolCalls = rawToolCalls
      ?.map((e) => (e as Map<Object?, Object?>).cast<String, Object?>())
      .toList(growable: false);
  final usageMap =
      (payload['usage'] as Map<Object?, Object?>?)?.cast<String, Object?>();
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
  final message =
      (errorBody?['message'] as String?) ?? e.message ?? 'Network error';
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
  //
  // We use a manual decoder here because `bytes.transform(utf8.decoder)`
  // has a type mismatch on some Dart SDKs (the StreamTransformer type
  // variables don't unify cleanly with `Stream<List<int>>` from Dio).
  return _Utf8StreamDecoder().bind(bytes);
}

class _Utf8StreamDecoder extends StreamTransformerBase<List<int>, String> {
  final Converter<List<int>, String> _converter = utf8.decoder;

  @override
  Stream<String> bind(Stream<List<int>> stream) {
    return Stream<String>.eventTransformed(
      stream,
      (EventSink<String> sink) => _ConverterSink(_converter, sink),
    );
  }
}

class _ConverterSink implements EventSink<List<int>> {
  _ConverterSink(this.converter, this.sink);
  final Converter<List<int>, String> converter;
  final EventSink<String> sink;
  final _buffer = <int>[];

  @override
  void add(List<int> event) {
    _buffer.addAll(event);
    // Try to decode as much as we can safely — only flush complete
    // UTF-8 sequences. For simplicity, decode the whole buffer on each
    // chunk (small per-chunk size means this is fine).
    try {
      final decoded = utf8.decode(_buffer);
      sink.add(decoded);
      _buffer.clear();
    } catch (_) {
      // Incomplete UTF-8 sequence; wait for next chunk.
    }
  }

  @override
  void addError(Object error, [StackTrace? stackTrace]) =>
      sink.addError(error, stackTrace);

  @override
  void close() {
    if (_buffer.isNotEmpty) {
      try {
        sink.add(utf8.decode(_buffer));
      } catch (_) {}
    }
    sink.close();
  }
}

/// Splits a stream of UTF-8 text into SSE event payloads.
Stream<String> _sseEvents(Stream<String> text) async* {
  final buffer = StringBuffer();
  await for (final chunk in text) {
    buffer.write(chunk);
    while (true) {
      final s = buffer.toString();
      final idx = s.indexOf('\n\n');
      if (idx == -1) break;
      final event = s.substring(0, idx);
      buffer.clear();
      buffer.write(s.substring(idx + 2));
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
