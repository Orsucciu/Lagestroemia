#!/usr/bin/env python3
"""
Lagestroemia Native Messaging Host — local OpenAI-compatible proxy.

This script runs as a Native Messaging host for the browser extension.
It starts an HTTP server on localhost:8081 that exposes an
OpenAI-compatible API. External apps (opencode, curl, etc.) connect
to this server. The server relays requests to the browser extension
via stdin/stdout (Native Messaging protocol), which forwards them to
the content script running inside chat.z.ai.

Architecture:
    opencode → HTTP :8081 → this script → stdin/stdout → extension
                                                         ↓
                                                    content.js
                                                         ↓
                                                    fetch() to chat.z.ai
                                                    (same-origin, no CORS)

Installation:
    See install.sh (Linux/macOS) or install.ps1 (Windows) to register
    this script as a Native Messaging host.

Usage (after installation):
    # From any external app:
    curl http://localhost:8081/v1/chat/completions \\
      -H "Content-Type: application/json" \\
      -d '{"model":"glm-4.7","messages":[{"role":"user","content":"hello"}],"stream":true}'

    # Or with opencode / any OpenAI-compatible client:
    OPENAI_API_BASE=http://localhost:8081/v1 opencode
"""

import json
import struct
import sys
import threading
import time
import http.server
import socketserver
import queue
from typing import Optional

# ---- Native Messaging I/O ----
# The browser communicates with this script via stdin (4-byte length
# prefix + JSON) and stdout (same format). We read messages from stdin
# in a background thread and send messages to stdout (thread-safe via
# a lock).

_stdout_lock = threading.Lock()
_extension_connected = threading.Event()

# Queue for messages to send to the extension. A dedicated sender thread
# reads from this queue and writes to stdout. This is critical on Windows
# where writing to stdout from multiple threads (HTTP handler threads)
# can fail silently — the native messaging pipe requires all writes to
# come from a single thread.
_outgoing_queue = queue.Queue()


def send_message_to_extension(msg: dict) -> None:
    """Put a message in the outgoing queue. The sender thread will
    write it to stdout."""
    _outgoing_queue.put(msg)


def _sender_thread():
    """Dedicated thread that reads from the outgoing queue and writes
    to stdout. This ensures all stdout writes come from a single thread,
    which is required for native messaging on Windows."""
    while True:
        try:
            msg = _outgoing_queue.get()
            if msg is None:
                # Sentinel — exit.
                break
            data = json.dumps(msg).encode('utf-8')
            with _stdout_lock:
                sys.stdout.buffer.write(struct.pack('<I', len(data)))
                sys.stdout.buffer.write(data)
                sys.stdout.buffer.flush()
            print(f"[native] Sent to extension: {msg.get('type', '?')} ({len(data)} bytes)", file=sys.stderr)
        except Exception as e:
            print(f"[native] Failed to send to extension: {e}", file=sys.stderr)
_response_queues: dict[str, queue.Queue] = {}
_response_queues_lock = threading.Lock()

# Pending requests for the extension to pick up via HTTP polling.
# When an HTTP chat request comes in, it's put here. The extension
# polls GET /_pending to get it, processes it, and POSTs responses
# to /_response.
_pending_requests: list[dict] = []
_pending_lock = threading.Lock()


def read_message_from_extension() -> Optional[dict]:
    """Read a JSON message from the browser extension via stdin."""
    raw_length = sys.stdin.buffer.read(4)
    if len(raw_length) < 4:
        return None
    length = struct.unpack('<I', raw_length)[0]
    if length == 0:
        return None
    data = sys.stdin.buffer.read(length)
    return json.loads(data.decode('utf-8'))


def stdin_reader_thread():
    """Background thread that reads messages from the extension.
    Uses a timeout on stdin so it doesn't block forever on Windows
    when running standalone (without a browser)."""
    import select
    while True:
        try:
            # On Windows, select() doesn't work on stdin. We use a
            # short read timeout via threading instead — if no data
            # arrives in 5 seconds, just loop and try again. This
            # keeps the thread alive without blocking forever.
            raw_length = sys.stdin.buffer.read(4)
            if len(raw_length) < 4:
                # stdin closed (EOF) — extension disconnected.
                print("[native] stdin closed, exiting", file=sys.stderr)
                break
            length = struct.unpack('<I', raw_length)[0]
            if length == 0:
                continue
            data = sys.stdin.buffer.read(length)
            if len(data) < length:
                break

            msg = json.loads(data.decode('utf-8'))
            msg_type = msg.get('type', '')

            if msg_type == 'connected':
                _extension_connected.set()
                print("[native] Extension connected", file=sys.stderr)

            elif msg_type == 'ping':
                # Keepalive ping from the service worker. Just ignore.
                pass

            elif msg_type == 'response':
                request_id = msg.get('requestId', '')
                with _response_queues_lock:
                    q = _response_queues.get(request_id)
                if q:
                    q.put(msg)

            elif msg_type == 'streamChunk':
                request_id = msg.get('requestId', '')
                with _response_queues_lock:
                    q = _response_queues.get(request_id)
                if q:
                    q.put(msg)

            elif msg_type == 'streamEnd':
                request_id = msg.get('requestId', '')
                with _response_queues_lock:
                    q = _response_queues.get(request_id)
                if q:
                    q.put(msg)

            elif msg_type == 'error':
                request_id = msg.get('requestId', '')
                with _response_queues_lock:
                    q = _response_queues.get(request_id)
                if q:
                    q.put(msg)

        except json.JSONDecodeError:
            continue
        except Exception as e:
            # On Windows, reading from stdin when it's a pipe can
            # raise various errors. Just log and keep going.
            print(f"[native] stdin reader: {e}", file=sys.stderr)
            time.sleep(1)


def send_request_to_extension(request_id: str, messages: list, model: str,
                               stream: bool, options: dict = None) -> queue.Queue:
    """Send a chat request to the extension and return the response queue."""
    q = queue.Queue()
    with _response_queues_lock:
        _response_queues[request_id] = q

    msg = {
        'type': 'sendChat',
        'requestId': request_id,
        'messages': messages,
        'model': model,
        'stream': stream,
        'options': options or {},
    }
    print(f"[native] Sending sendChat to extension: requestId={request_id}, "
          f"model={model}, messages={len(messages)}", file=sys.stderr)
    send_message_to_extension(msg)
    print(f"[native] sendChat sent ({len(json.dumps(msg).encode())} bytes)", file=sys.stderr)
    return q


# ---- HTTP Server (OpenAI-compatible API) ----

class ChatHandler(http.server.BaseHTTPRequestHandler):
    """HTTP handler that exposes an OpenAI-compatible API."""

    def log_message(self, format, *args):
        # Log to stderr so it doesn't interfere with stdout (which is
        # used for Native Messaging).
        print(f"[http] {self.address_string()} - {format % args}", file=sys.stderr)

    def do_GET(self):
        if self.path == '/v1/models':
            self._handle_models()
        elif self.path == '/health':
            self._send_json(200, {'ok': True, 'extension_connected': _extension_connected.is_set()})
        elif self.path == '/_pending':
            self._handle_pending()
        elif self.path == '/_debug':
            self._handle_debug()
        else:
            self._send_json(404, {'error': {'message': 'Not found'}})

    def do_POST(self):
        if self.path == '/v1/chat/completions':
            self._handle_chat()
        elif self.path == '/_response':
            self._handle_response()
        else:
            self._send_json(404, {'error': {'message': 'Not found'}})

    def _send_json(self, status, body):
        data = json.dumps(body).encode('utf-8')
        self.send_response(status)
        self.send_header('Content-Type', 'application/json')
        self.send_header('Content-Length', str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def _handle_models(self):
        """Return the model list. Asks the extension for the live list
        from chat.z.ai's DOM. Falls back to a static list if the
        extension doesn't respond."""
        import uuid
        request_id = str(uuid.uuid4())
        q = queue.Queue()
        with _response_queues_lock:
            _response_queues[request_id] = q

        # Ask the extension for the model list.
        send_message_to_extension({
            'type': 'getModels',
            'requestId': request_id,
        })

        # Wait up to 10 seconds for the response.
        try:
            msg = q.get(timeout=10)
            if msg.get('type') == 'response' and msg.get('models'):
                models = [{'id': m, 'object': 'model', 'owned_by': 'z.ai'}
                          for m in msg['models']]
                self._send_json(200, {'object': 'list', 'data': models})
                return
        except queue.Empty:
            pass
        finally:
            with _response_queues_lock:
                _response_queues.pop(request_id, None)

        # Fallback: static list.
        models = [
            {'id': 'glm-4.7', 'object': 'model', 'owned_by': 'z.ai'},
            {'id': 'x-preview-l', 'object': 'model', 'owned_by': 'z.ai'},
            {'id': 'glm-5.3', 'object': 'model', 'owned_by': 'z.ai'},
            {'id': 'glm-5.2', 'object': 'model', 'owned_by': 'z.ai'},
            {'id': 'glm-4.6v', 'object': 'model', 'owned_by': 'z.ai'},
            {'id': 'GLM-4.1V-Thinking-FlashX', 'object': 'model', 'owned_by': 'z.ai'},
            {'id': 'deep-research', 'object': 'model', 'owned_by': 'z.ai'},
            {'id': 'zero', 'object': 'model', 'owned_by': 'z.ai'},
        ]
        self._send_json(200, {'object': 'list', 'data': models})

    def _handle_chat(self):
        """Handle POST /v1/chat/completions — the main chat endpoint."""
        # Check if the extension is connected.
        if not _extension_connected.is_set():
            self._send_json(503, {
                'error': {
                    'message': 'Browser extension is not connected. '
                               'Make sure the Lagestroemia extension is installed '
                               'and a chat.z.ai tab is open.',
                    'type': 'server_error',
                }
            })
            return

        # Read the request body.
        content_length = int(self.headers.get('Content-Length', 0))
        body = self.rfile.read(content_length)
        try:
            req = json.loads(body)
        except json.JSONDecodeError:
            self._send_json(400, {'error': {'message': 'Invalid JSON: ' + body.decode('utf-8', errors='replace')[:200]}})
            return

        messages = req.get('messages', [])
        model = req.get('model', 'glm-4.7')
        stream = req.get('stream', False)

        # Generate a unique request ID.
        import uuid
        request_id = str(uuid.uuid4())

        # Create a response queue for this request.
        q = queue.Queue()
        with _response_queues_lock:
            _response_queues[request_id] = q

        # Put the request in the pending list for the extension to poll.
        pending_req = {
            'type': 'sendChat',
            'requestId': request_id,
            'messages': messages,
            'model': model,
            'stream': stream,
            'options': {},
        }
        with _pending_lock:
            _pending_requests.append(pending_req)

        # Wait for the first response (chunk, complete, or error).
        try:
            first_msg = q.get(timeout=30)
            msg_type = first_msg.get('type', '')
            if msg_type == 'error':
                err = first_msg.get('error', 'Unknown error')
                self._send_json(502, {'error': {'message': err}})
                with _response_queues_lock:
                    _response_queues.pop(request_id, None)
                return
            # Got a response — put it back and continue with streaming.
            q.put(first_msg)
        except queue.Empty:
            with _response_queues_lock:
                _response_queues.pop(request_id, None)
            self._send_json(504, {
                'error': {
                    'message': 'Extension did not respond in 30 seconds. '
                               'Make sure a chat.z.ai tab is open and the '
                               'captcha has been solved.',
                    'type': 'timeout',
                }
            })
            return

        if stream:
            self._handle_streaming_response(q, request_id, model)
        else:
            self._handle_non_streaming_response(q, request_id, model)

    def _handle_streaming_response(self, q: queue.Queue, request_id: str, model: str):
        """Stream SSE chunks back to the HTTP client."""
        self.send_response(200)
        self.send_header('Content-Type', 'text/event-stream')
        self.send_header('Cache-Control', 'no-cache')
        self.send_header('Connection', 'keep-alive')
        self.end_headers()

        try:
            while True:
                # Wait for the next message from the extension.
                try:
                    msg = q.get(timeout=120)  # 2-minute timeout
                except queue.Empty:
                    # Timeout — send an error event.
                    self.wfile.write(b'data: {"error":{"message":"Timeout waiting for response"}}\n\n')
                    self.wfile.flush()
                    break

                msg_type = msg.get('type', '')

                if msg_type == 'streamChunk':
                    chunk = msg.get('chunk', {})
                    content = chunk.get('content', '')
                    reasoning = chunk.get('reasoning', '')

                    # Build an OpenAI-compatible SSE chunk.
                    sse_chunk = {
                        'id': request_id,
                        'object': 'chat.completion.chunk',
                        'model': model,
                        'choices': [{
                            'index': 0,
                            'delta': {'content': content} if content else {},
                            'finish_reason': None,
                        }],
                    }
                    self.wfile.write(f'data: {json.dumps(sse_chunk)}\n\n'.encode())
                    self.wfile.flush()

                elif msg_type == 'streamEnd' or msg_type == 'response':
                    # Stream complete — send the final chunk with finish_reason.
                    final_chunk = {
                        'id': request_id,
                        'object': 'chat.completion.chunk',
                        'model': model,
                        'choices': [{
                            'index': 0,
                            'delta': {},
                            'finish_reason': 'stop',
                        }],
                    }
                    self.wfile.write(f'data: {json.dumps(final_chunk)}\n\n'.encode())
                    self.wfile.write(b'data: [DONE]\n\n')
                    self.wfile.flush()
                    break

                elif msg_type == 'error':
                    error_msg = msg.get('error', 'Unknown error')
                    self.wfile.write(f'data: {{"error":{{"message":"{error_msg}"}}}}\n\n'.encode())
                    self.wfile.flush()
                    break

        except BrokenPipeError:
            # Client disconnected.
            pass
        finally:
            # Clean up the response queue.
            with _response_queues_lock:
                _response_queues.pop(request_id, None)

    def _handle_non_streaming_response(self, q: queue.Queue, request_id: str, model: str):
        """Collect all chunks and return a single JSON response."""
        full_content = ''
        reasoning = ''

        try:
            while True:
                try:
                    msg = q.get(timeout=120)
                except queue.Empty:
                    self._send_json(504, {'error': {'message': 'Timeout'}})
                    return

                msg_type = msg.get('type', '')

                if msg_type == 'streamChunk':
                    chunk = msg.get('chunk', {})
                    full_content += chunk.get('content', '')
                    reasoning += chunk.get('reasoning', '')

                elif msg_type == 'streamEnd' or msg_type == 'response':
                    break

                elif msg_type == 'error':
                    self._send_json(502, {'error': {'message': msg.get('error', 'Unknown error')}})
                    return

        finally:
            with _response_queues_lock:
                _response_queues.pop(request_id, None)

        response = {
            'id': request_id,
            'object': 'chat.completion',
            'model': model,
            'choices': [{
                'index': 0,
                'message': {
                    'role': 'assistant',
                    'content': full_content,
                },
                'finish_reason': 'stop',
            }],
            'usage': {
                'prompt_tokens': 0,
                'completion_tokens': 0,
                'total_tokens': 0,
            },
        }
        self._send_json(200, response)

    def _handle_pending(self):
        """GET /_pending — returns the next pending request for the
        extension to process. The extension polls this endpoint."""
        with _pending_lock:
            if _pending_requests:
                req = _pending_requests.pop(0)
                self._send_json(200, req)
            else:
                self._send_json(200, {'type': 'none'})

    def _handle_response(self):
        """POST /_response — receives a response chunk from the extension.
        Body: {"requestId": "XXX", "type": "streamChunk|streamEnd|error",
               "chunk": {"content": "...", "reasoning": "..."},
               "error": "message"}"""
        content_length = int(self.headers.get('Content-Length', 0))
        body = self.rfile.read(content_length)
        try:
            msg = json.loads(body)
        except json.JSONDecodeError:
            self._send_json(400, {'error': 'Invalid JSON'})
            return

        request_id = msg.get('requestId', '')
        msg_type = msg.get('type', '')

        with _response_queues_lock:
            q = _response_queues.get(request_id)
        if q:
            q.put(msg)
            self._send_json(200, {'ok': True})
        else:
            self._send_json(404, {'error': 'Unknown requestId'})

    def _handle_debug(self):
        """GET /_debug — returns internal state for debugging."""
        with _pending_lock:
            pending_count = len(_pending_requests)
        with _response_queues_lock:
            queue_ids = list(_response_queues.keys())
        self._send_json(200, {
            'extension_connected': _extension_connected.is_set(),
            'pending_requests': pending_count,
            'active_queues': queue_ids,
            'pending_details': list(_pending_requests) if pending_count > 0 else [],
        })


class ThreadedHTTPServer(socketserver.ThreadingMixIn, http.server.HTTPServer):
    """Multi-threaded HTTP server so we can handle multiple concurrent requests."""
    daemon_threads = True
    allow_reuse_address = True


# ---- Main ----

def main():
    PORT = 8081

    # Start the HTTP server FIRST (before the stdin reader). This
    # ensures the server is immediately available even if the stdin
    # reader blocks (which it does on Windows when run standalone).
    try:
        server = ThreadedHTTPServer(('127.0.0.1', PORT), ChatHandler)
    except OSError as e:
        # Port already in use — another instance is running.
        print(f"[native] Port {PORT} already in use ({e}). "
              f"Another instance may be running.", file=sys.stderr)
        print("[native] Exiting. Close the other instance first.", file=sys.stderr)
        sys.exit(1)

    print(f"[native] HTTP server listening on http://127.0.0.1:{PORT}", file=sys.stderr)
    print(f"[native] OpenAI-compatible API:", file=sys.stderr)
    print(f"[native]   GET  /v1/models", file=sys.stderr)
    print(f"[native]   POST /v1/chat/completions", file=sys.stderr)
    print(f"[native]   GET  /health", file=sys.stderr)

    # Start the sender thread (writes to stdout from a single thread).
    sender = threading.Thread(target=_sender_thread, daemon=True)
    sender.start()

    # Start the stdin reader thread (reads messages from the extension).
    stdin_thread = threading.Thread(target=stdin_reader_thread, daemon=True)
    stdin_thread.start()

    # Signal to the extension that we're ready. If we can send via
    # stdout, the extension IS connected (the browser launched us).
    _extension_connected.set()
    send_message_to_extension({'type': 'nativeReady', 'port': PORT})

    # Also start a polling endpoint so the extension can poll for
    # pending requests (bypasses native messaging stdout which is
    # broken on Windows for multi-threaded writes).
    # Flow:
    #   1. HTTP POST /v1/chat/completions → puts request in _pending_requests
    #   2. Extension polls GET /_pending → gets the request
    #   3. Extension types into chat.z.ai, watches DOM
    #   4. Extension POST /_response → sends chunks back
    #   5. HTTP handler reads chunks from the response queue → streams SSE

    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("[native] Shutting down", file=sys.stderr)
        server.shutdown()


if __name__ == '__main__':
    main()
