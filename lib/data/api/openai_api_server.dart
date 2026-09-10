// OpenAI-compatible local HTTP server.
//
// Spins up a tiny HTTP server (via `dart:io`'s `HttpServer`) that other
// OpenAI-speaking clients (curl, Cline, Continue, LibreChat, the OpenAI
// Python/Node SDKs, etc.) can hit to use z.ai through Lagestroemia.
//
// The server listens on `127.0.0.1` (loopback only — never 0.0.0.0) on
// the port the user picks in Settings. Endpoints:
//
//   GET  /v1/models
//        → forwards to z.ai's model list. Returns the OpenAI shape:
//          {"object":"list","data":[{"id":"glm-4.7","object":"model",
//          "created":..., "owned_by":"z.ai"}, ...]}
//
//   POST /v1/chat/completions
//        → forwards to z.ai. Body is the OpenAI-shaped payload
//          (model, messages, stream, temperature, max_tokens, tools, etc.).
//          If `stream: true`, the response is SSE-flushed in real time
//          (text/event-stream chunks for each delta). Otherwise the
//          response is a single JSON object.
//
//   GET  /v1/health
//        → returns {"ok":true,"version":"<appVersion>"} so callers can
//          probe the server without sending a chat request.
//
//   GET  /            → returns a small HTML page describing the server.
//
// Auth: the server is loopback-only (no remote access). It still
// expects callers to pass an `Authorization: Bearer` header that
// matches the API key configured in Settings (the user's z.ai API key
// OR a separate "server API key" that the user sets). If the user
// leaves the server API key empty, no auth is required (loopback only).
//
// This file uses `dart:io` directly so it only runs on native targets
// (Linux, Windows, Android). On Web we cannot open a TCP listener —
// the Settings UI will show "Not available on Web".

import 'dart:async';
import 'dart:convert';
import 'dart:io'
    show
        ContentType,
        HttpHeaders,
        HttpStatus,
        HttpRequest,
        HttpResponse,
        HttpServer,
        InternetAddress;

import 'package:dio/dio.dart';
import 'package:logging/logging.dart';

import '../../core/config/app_config.dart';

/// Configuration for the OpenAI-compatible server.
class OpenAiServerConfig {
  const OpenAiServerConfig({
    this.enabled = false,
    this.port = 8081,
    this.serverApiKey = '',
    this.allowCors = true,
  });

  /// Whether the server is running. Persists across app restarts.
  final bool enabled;

  /// TCP port to listen on. Default: 8081 (out of the way of common
  /// dev servers like 8080, 3000, 5000).
  final int port;

  /// Optional server-side API key. If non-empty, the caller must pass
  /// `Authorization: Bearer <serverApiKey>` to access any endpoint. If
  /// empty, no auth is required (loopback-only).
  final String serverApiKey;

  /// If true, sends `Access-Control-Allow-Origin: *` on responses so
  /// browser-based clients can call the server. Default: true (since
  /// the server is loopback-only, CORS is safe).
  final bool allowCors;

  OpenAiServerConfig copyWith({
    bool? enabled,
    int? port,
    String? serverApiKey,
    bool? allowCors,
  }) {
    return OpenAiServerConfig(
      enabled: enabled ?? this.enabled,
      port: port ?? this.port,
      serverApiKey: serverApiKey ?? this.serverApiKey,
      allowCors: allowCors ?? this.allowCors,
    );
  }
}

/// The running state of the server, exposed to the UI.
class OpenAiServerStatus {
  const OpenAiServerStatus({
    this.running = false,
    this.port,
    this.url,
    this.error,
  });

  final bool running;
  final int? port;
  final String? url;
  final String? error;
}

/// The OpenAI-compatible server.
///
/// Use [start] to bind and [stop] to release. After [start], callers
/// can hit `http://127.0.0.1:<port>/v1/chat/completions` etc.
///
/// The server forwards to z.ai using the supplied [bearerToken]. The
/// caller is responsible for keeping the token fresh (e.g. calling
/// `signZaiJwt` per-request in JWT mode, or just passing the raw
/// API key / guest token).
class OpenAiApiServer {
  OpenAiApiServer({required this.bearerTokenProvider})
      : _config = const OpenAiServerConfig();

  /// Function that returns the current Bearer token to forward to z.ai.
  /// Called once per incoming request so the token is always fresh
  /// (handles JWT refresh, account switching, guest token rotation).
  final String? Function() bearerTokenProvider;

  static final Logger _log = Logger('lagestroemia.server');

  OpenAiServerConfig _config;
  HttpServer? _server;
  StreamSubscription? _subscription;

  /// Returns the current config (for the UI to display).
  OpenAiServerConfig get config => _config;

  /// Returns the current running status (for the UI).
  OpenAiServerStatus get status {
    final server = _server;
    if (server == null) {
      return const OpenAiServerStatus();
    }
    final port = server.port;
    return OpenAiServerStatus(
      running: true,
      port: port,
      url: 'http://127.0.0.1:$port',
    );
  }

  /// Starts the server. Returns the running status on success, an
  /// error message on failure.
  Future<OpenAiServerStatus> start(OpenAiServerConfig config) async {
    if (_server != null) {
      await stop();
    }
    _config = config;
    try {
      final server = await HttpServer.bind(
        InternetAddress.loopbackIPv4,
        config.port,
      );
      _server = server;
      _log.info('OpenAI-compat server listening on 127.0.0.1:${server.port}');
      _subscription = server.listen(_handleRequest);
      return OpenAiServerStatus(
        running: true,
        port: server.port,
        url: 'http://127.0.0.1:${server.port}',
      );
    } catch (e) {
      _log.warning('Failed to start OpenAI-compat server: $e');
      return OpenAiServerStatus(error: e.toString());
    }
  }

  /// Stops the server. Safe to call when not running.
  Future<void> stop() async {
    final sub = _subscription;
    if (sub != null) {
      await sub.cancel();
      _subscription = null;
    }
    final server = _server;
    if (server != null) {
      await server.close(force: true);
      _server = null;
    }
    _log.info('OpenAI-compat server stopped');
  }

  // ---- request handling --------------------------------------------------

  void _handleRequest(HttpRequest request) {
    try {
      _addCorsHeaders(request.response);
      final path = request.uri.path;
      final method = request.method;
      _log.fine('$method $path');

      // CORS preflight
      if (method == 'OPTIONS') {
        request.response.statusCode = HttpStatus.noContent;
        request.response.close();
        return;
      }

      // Auth check (unless serverApiKey is empty)
      if (_config.serverApiKey.isNotEmpty) {
        final authHeader = request.headers.value(HttpHeaders.authorizationHeader);
        final expected = 'Bearer ${_config.serverApiKey}';
        if (authHeader != expected) {
          _sendJson(request.response, statusCode: 401, body: <String, Object?>{
            'error': <String, String>{
              'message': 'Invalid API key. Expected Authorization: Bearer '
                  '<serverApiKey>.',
              'type': 'invalid_request_error',
              'code': 'invalid_api_key',
            },
          });
          return;
        }
      }

      if (path == '/' && method == 'GET') {
        _handleIndex(request);
        return;
      }
      if (path == '/v1/health' && method == 'GET') {
        _handleHealth(request);
        return;
      }
      if (path == '/v1/models' && method == 'GET') {
        _handleListModels(request);
        return;
      }
      if (path == '/v1/chat/completions' && method == 'POST') {
        _handleChatCompletions(request);
        return;
      }
      // 404
      _sendJson(request.response, statusCode: 404, body: <String, Object?>{
        'error': <String, String>{
          'message': 'Unknown route: $method $path',
          'type': 'invalid_request_error',
        },
      });
    } catch (e, st) {
      _log.warning('Request handler crashed: $e\n$st');
      try {
        _sendJson(request.response, statusCode: 500, body: <String, Object?>{
          'error': <String, String>{
            'message': 'Internal server error: $e',
            'type': 'server_error',
          },
        });
      } catch (_) {
        // Response may already be closed; nothing more we can do.
      }
    }
  }

  void _addCorsHeaders(HttpResponse response) {
    if (!_config.allowCors) return;
    response.headers.set(HttpHeaders.accessControlAllowOriginHeader, '*');
    response.headers.set(
        HttpHeaders.accessControlAllowMethodsHeader, 'GET, POST, OPTIONS');
    response.headers.set(HttpHeaders.accessControlAllowHeadersHeader,
        'Authorization, Content-Type, Accept');
  }

  void _handleIndex(HttpRequest request) {
    request.response.headers.contentType = ContentType.html;
    final port = _server?.port ?? _config.port;
    request.response.write('''
<!DOCTYPE html>
<html>
<head><meta charset="utf-8"><title>Lagestroemia OpenAI-compat server</title>
<style>body{font:14px/1.5 -apple-system,system-ui,sans-serif;max-width:600px;margin:40px auto;padding:0 20px;color:#222}code{background:#f4f4f4;padding:2px 6px;border-radius:3px}a{color:#7C4DFF}</style>
</head>
<body>
<h1>Lagestroemia OpenAI-compat server</h1>
<p>Listening on <code>http://127.0.0.1:$port</code>. Loopback only — other
machines on the network cannot reach it.</p>
<h2>Endpoints</h2>
<ul>
  <li><code>GET /v1/health</code> — returns <code>{"ok":true,"version":"..."}</code></li>
  <li><code>GET /v1/models</code> — list of available z.ai models</li>
  <li><code>POST /v1/chat/completions</code> — OpenAI-shaped chat
      completions (stream and non-stream)</li>
</ul>
<h2>Quick test</h2>
<pre>curl http://127.0.0.1:$port/v1/chat/completions \\
  -H "Content-Type: application/json" \\
  ${_config.serverApiKey.isNotEmpty ? '-H "Authorization: Bearer &lt;your-server-api-key&gt" \\\n  ' : ''}-d '{
    "model": "glm-4.7",
    "messages": [{"role":"user","content":"Say hello in 5 words"}],
    "stream": false
  }'</pre>
<p>For streaming, set <code>"stream": true</code>. The server forwards the
SSE response byte-for-byte from z.ai.</p>
<p><a href="https://docs.z.ai">z.ai docs</a> · <a href="https://github.com/Orsucciu/Lagestroemia">Source</a></p>
</body>
</html>
''');
    request.response.close();
  }

  void _handleHealth(HttpRequest request) {
    _sendJson(request.response, body: <String, Object?>{
      'ok': true,
      'version': AppConfig.appVersion,
      'port': _server?.port,
    });
  }

  Future<void> _handleListModels(HttpRequest request) async {
    final token = bearerTokenProvider();
    if (token == null || token.isEmpty) {
      _sendJson(request.response, statusCode: 401, body: <String, Object?>{
        'error': <String, String>{
          'message': 'No z.ai auth token available. Sign in to Lagestroemia '
              'first.',
          'type': 'server_error',
        },
      });
      return;
    }
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    // Use the same model list the app shows. The chat.z.ai backend exposes
    // /api/models, but to keep this server simple we return the curated
    // list from AppConfig for the active backend.
    final models = _isGuestToken(token)
        ? AppConfig.chatZaiKnownModels
        : AppConfig.knownModels;
    final data = <Map<String, Object?>>[
      for (final id in models)
        <String, Object?>{
          'id': id,
          'object': 'model',
          'created': now,
          'owned_by': 'z.ai',
        },
    ];
    _sendJson(request.response, body: <String, Object?>{
      'object': 'list',
      'data': data,
    });
  }

  Future<void> _handleChatCompletions(HttpRequest request) async {
    // Read the request body.
    final bodyBytes = await _readBody(request);
    Map<String, Object?> body;
    try {
      body = jsonDecode(utf8.decode(bodyBytes)) as Map<String, Object?>;
    } catch (e) {
      _sendJson(request.response, statusCode: 400, body: <String, Object?>{
        'error': <String, String>{
          'message': 'Invalid JSON body: $e',
          'type': 'invalid_request_error',
        },
      });
      return;
    }

    final token = bearerTokenProvider();
    if (token == null || token.isEmpty) {
      _sendJson(request.response, statusCode: 401, body: <String, Object?>{
        'error': <String, String>{
          'message': 'No z.ai auth token available. Sign in to Lagestroemia '
              'first.',
          'type': 'server_error',
        },
      });
      return;
    }

    final isGuest = _isGuestToken(token);
    final baseUrl = isGuest
        ? AppConfig.chatZaiApiBaseUrl
        : AppConfig.defaultApiBaseUrl;
    final model = body['model'] as String?;
    final path = isGuest
        ? (AppConfig.isChatZaiAgentModel(model ?? AppConfig.defaultGuestModel)
            ? AppConfig.chatZaiAgentChatCompletionsPath
            : AppConfig.chatZaiChatCompletionsPath)
        : AppConfig.chatCompletionsPath;
    final isStream = body['stream'] == true;

    // Build outgoing headers (matching what ZaiApiClient sends).
    final headers = <String, Object?>{
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $token',
      'Accept-Language': 'en-US,en',
      if (isGuest) ...<String, Object?>{
        'X-FE-Version': AppConfig.chatZaiFeVersion,
        'Origin': 'https://chat.z.ai',
        'Referer': 'https://chat.z.ai/',
        'User-Agent':
            'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0.0.0 Safari/537.36',
      },
    };

    final dio = Dio();
    try {
      if (isStream) {
        // Forward as SSE — stream the response back to the client
        // chunk-by-chunk.
        request.response.headers.contentType =
            ContentType.parse('text/event-stream');
        request.response.headers.set(HttpHeaders.cacheControlHeader, 'no-cache');
        request.response.headers.set(HttpHeaders.connectionHeader, 'keep-alive');
        final response = await dio.post<ResponseBody>(
          '$baseUrl$path',
          data: jsonEncode(body),
          options: Options(
            responseType: ResponseType.stream,
            headers: headers,
          ),
        );
        final stream = response.data?.stream ??
            const Stream<List<int>>.empty();
        await for (final chunk in stream) {
          request.response.add(chunk);
          await request.response.flush();
        }
        await request.response.close();
      } else {
        // Non-streaming — buffer the full response.
        final response = await dio.post<dynamic>(
          '$baseUrl$path',
          data: jsonEncode(body),
          options: Options(headers: headers),
        );
        final data = response.data;
        // For chat.z.ai (guest), unwrap the envelope
        // {"type":"chat:completion","data":{...}} → use data.data
        if (isGuest) {
          final outer =
              data is String ? jsonDecode(data) : data as Map<String, Object?>;
          final type = outer['type'] as String?;
          if (type == 'chat:completion') {
            final innerData = outer['data'];
            if (innerData is Map<String, Object?>) {
              // The inner 'data' is the actual OpenAI-shaped payload
              final payload = innerData['data'];
              if (payload is Map<String, Object?>) {
                _sendJson(request.response, body: payload);
                return;
              }
              // Or the inner 'data' IS the payload
              _sendJson(request.response, body: innerData);
              return;
            }
          }
          // Fallback: pass the whole response through unchanged.
          _sendJson(request.response, body: outer);
          return;
        }
        // For api.z.ai (paid): pass through unchanged.
        final result = data is String
            ? jsonDecode(data) as Map<String, Object?>
            : data as Map<String, Object?>;
        _sendJson(request.response, body: result);
      }
    } on DioException catch (e) {
      _log.warning('Upstream call failed: $e');
      final status = e.response?.statusCode ?? 500;
      Map<String, Object?> errorBody;
      final data = e.response?.data;
      if (data is Map<String, Object?> &&
          data['error'] is Map<String, Object?>) {
        errorBody = data;
      } else if (data is String) {
        try {
          errorBody = jsonDecode(data) as Map<String, Object?>;
        } catch (_) {
          errorBody = <String, Object?>{
            'error': <String, String>{
              'message': data,
              'type': 'upstream_error',
            },
          };
        }
      } else {
        errorBody = <String, Object?>{
          'error': <String, String>{
            'message': e.message ?? 'Upstream error',
            'type': 'upstream_error',
          },
        };
      }
      _sendJson(request.response, statusCode: status, body: errorBody);
    } catch (e) {
      _log.warning('Chat completions handler crashed: $e');
      _sendJson(request.response, statusCode: 500, body: <String, Object?>{
        'error': <String, String>{
          'message': 'Internal server error: $e',
          'type': 'server_error',
        },
      });
    } finally {
      dio.close();
    }
  }

  // ---- helpers -----------------------------------------------------------

  /// Heuristic: z.ai guest JWTs are ES256-signed (header alg=ES256), so
  /// the JWT starts with `eyJhbGciOiJFUzI1NiIs...`. z.ai API keys are
  /// typically `<hex>.<secret>` and not JWTs at all.
  ///
  /// If the token looks like a JWT (starts with `eyJ`), assume guest.
  /// Otherwise assume API-key mode.
  bool _isGuestToken(String token) {
    return token.startsWith('eyJ');
  }

  Future<List<int>> _readBody(HttpRequest request) async {
    final completer = Completer<List<int>>();
    final buffer = <int>[];
    request.listen(
      buffer.addAll,
      onDone: () => completer.complete(buffer),
      onError: (Object e) => completer.completeError(e),
    );
    return completer.future;
  }

  void _sendJson(
    HttpResponse response, {
    int statusCode = 200,
    required Map<String, Object?> body,
  }) {
    response.statusCode = statusCode;
    response.headers.contentType = ContentType.json;
    response.write(jsonEncode(body));
    response.close();
  }
}
