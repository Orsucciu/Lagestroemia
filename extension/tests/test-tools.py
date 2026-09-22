#!/usr/bin/env python3
"""
Unit tests for the OpenAI-compat translation layer in native_host.py.

Verifies that:
  1. Streaming SSE chunks have the correct OpenAI shape.
  2. tool_calls are forwarded with backfilled IDs.
  3. reasoning_content is forwarded as delta.reasoning_content.
  4. Non-streaming response accumulates tool_calls correctly (by index).
  5. Auth + loopback gating work as expected.

This test does NOT hit chat.z.ai — it simulates the extension by
posting to /_response directly. Run with:

    python3 -m pytest extension/tests/test-tools.py -v
  or
    python3 extension/tests/test-tools.py

The test starts native_host.py in-process on a random port with a
known API key, then drives it via urllib.
"""
import json
import os
import sys
import threading
import time
import urllib.request
import urllib.error
from io import BytesIO

# Make native_host importable.
HERE = os.path.dirname(os.path.abspath(__file__))
EXT_DIR = os.path.dirname(HERE)
sys.path.insert(0, EXT_DIR)

# Set config BEFORE importing native_host (the module reads these at
# import time via main(), but we'll set them via the module's globals
# after import for the test).
os.environ['LAGESTROEMIA_HOST'] = '127.0.0.1'
os.environ['LAGESTROEMIA_PORT'] = '0'  # 0 = OS picks a free port
os.environ['LAGESTROEMIA_API_KEY'] = 'test-secret-key'

import native_host  # noqa: E402

# Silence the per-request log_message so test output is readable.
native_host.ChatHandler.log_message = lambda self, fmt, *args: None


def _start_server():
    """Start the native_host HTTP server in a background thread.
    Returns (server, port)."""
    # Use ThreadedHTTPServer (same as production) so /_pending can be
    # served concurrently with a blocking /v1/chat/completions call.
    server = native_host.ThreadedHTTPServer(('127.0.0.1', 0),
                                             native_host.ChatHandler)
    port = server.server_address[1]
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    return server, port


def _set_extension_connected(state: bool):
    """Flip the global _extension_connected event so _handle_chat thinks
    the extension is ready."""
    if state:
        native_host._extension_connected.set()
    else:
        native_host._extension_connected.clear()


def _post_response(port, request_id, msg_type, payload):
    """Simulate the extension posting a chunk to /_response."""
    body = json.dumps({
        'requestId': request_id,
        'type': msg_type,
        **payload,
    }).encode('utf-8')
    req = urllib.request.Request(
        f'http://127.0.0.1:{port}/_response',
        data=body,
        headers={'Content-Type': 'application/json'},
        method='POST',
    )
    urllib.request.urlopen(req, timeout=2).read()


def _post_chat(port, body, api_key='test-secret-key', stream=True):
    """POST /v1/chat/completions. Returns (status, headers, body)."""
    headers = {'Content-Type': 'application/json'}
    if api_key:
        headers['Authorization'] = f'Bearer {api_key}'
    req = urllib.request.Request(
        f'http://127.0.0.1:{port}/v1/chat/completions',
        data=json.dumps(body).encode('utf-8'),
        headers=headers,
        method='POST',
    )
    try:
        resp = urllib.request.urlopen(req, timeout=10)
        return resp.status, dict(resp.headers), resp.read().decode('utf-8')
    except urllib.error.HTTPError as e:
        return e.code, dict(e.headers), e.read().decode('utf-8')


def _consume_pending(port, timeout=5) -> dict:
    """Poll /_pending until a request appears (or timeout).
    The extension does this in a 500ms loop; for tests we poll faster."""
    deadline = time.time() + timeout
    while time.time() < deadline:
        req = urllib.request.Request(f'http://127.0.0.1:{port}/_pending')
        data = json.loads(urllib.request.urlopen(req, timeout=2).read())
        if data.get('type') and data['type'] != 'none':
            return data
        time.sleep(0.05)
    raise TimeoutError(f'no pending request after {timeout}s')


def _drive_response(port, request_id, chunks):
    """Push a sequence of streamChunks followed by streamEnd. Mimics
    what the extension does when chat.z.ai streams a response."""
    for chunk in chunks:
        _post_response(port, request_id, 'streamChunk', {'chunk': chunk})
    _post_response(port, request_id, 'streamEnd', {})


def test_auth_disabled_by_default():
    """Auth is currently disabled — even with an API key configured,
    requests without a key are accepted. This test documents the
    current behavior so future changes are intentional.

    To re-enable auth, edit _check_auth() in native_host.py and
    uncomment the strict-auth block. Then update this test to expect
    401 again.
    """
    server, port = _start_server()
    try:
        native_host._API_KEY = 'test-secret-key'
        status, _, body = _post_chat(port, {
            'model': 'glm-4.7',
            'messages': [{'role': 'user', 'content': 'hi'}],
        }, api_key=None)
        # Auth no longer blocks — request proceeds to the next check
        # (extension connected), which fails with 503 because no
        # extension is connected in the test environment.
        assert status == 503, f'expected 503 (no extension), got {status}: {body}'
        assert 'not connected' in body.lower()
    finally:
        server.shutdown()


def test_auth_accepts_correct_key():
    """With the right API key, the request proceeds (will then fail with
    503 because extension isn't connected)."""
    server, port = _start_server()
    try:
        native_host._API_KEY = 'test-secret-key'
        native_host._extension_connected.clear()
        status, _, body = _post_chat(port, {
            'model': 'glm-4.7',
            'messages': [{'role': 'user', 'content': 'hi'}],
        }, api_key='test-secret-key')
        assert status == 503, f'expected 503 (no extension), got {status}: {body}'
        assert 'not connected' in body.lower()
    finally:
        server.shutdown()


def test_health_is_public():
    """/health works without auth."""
    server, port = _start_server()
    try:
        native_host._API_KEY = 'test-secret-key'
        req = urllib.request.Request(f'http://127.0.0.1:{port}/health')
        resp = urllib.request.urlopen(req, timeout=2)
        data = json.loads(resp.read())
        assert data['ok'] is True
        assert 'extension_connected' in data
    finally:
        server.shutdown()


def test_streaming_forwards_content_and_reasoning():
    """A streamChunk with content + reasoning produces an OpenAI SSE
    chunk with delta.content and delta.reasoning_content."""
    server, port = _start_server()
    try:
        native_host._API_KEY = 'test-secret-key'
        _set_extension_connected(True)

        # Kick off the request in a thread (it blocks waiting for the
        # extension to respond).
        result = {}
        def call():
            result['status'], result['headers'], result['body'] = _post_chat(port, {
                'model': 'glm-4.7',
                'messages': [{'role': 'user', 'content': 'hi'}],
                'stream': True,
            })
        t = threading.Thread(target=call)
        t.start()

        # Grab the pending request and drive a response.
        pending = _consume_pending(port)
        request_id = pending['requestId']
        _drive_response(port, request_id, [
            {'content': 'Hello', 'reasoning': 'thinking...'},
            {'content': ' world', 'reasoning': 'more thinking'},
        ])

        t.join(timeout=5)
        assert result['status'] == 200, f"got {result['status']}: {result['body']}"

        # Parse the SSE body.
        chunks = []
        for line in result['body'].split('\n'):
            if line.startswith('data: '):
                data = line[6:]
                if data == '[DONE]':
                    break
                chunks.append(json.loads(data))

        # Should have: 2 content chunks, 1 final chunk.
        assert len(chunks) >= 2, f'expected >=2 chunks, got {len(chunks)}: {chunks}'

        # First chunk: content='Hello', reasoning='thinking...'
        c1 = chunks[0]
        assert c1['object'] == 'chat.completion.chunk'
        assert c1['model'] == 'glm-4.7'
        delta1 = c1['choices'][0]['delta']
        assert delta1['content'] == 'Hello'
        assert delta1['reasoning_content'] == 'thinking...'

        # Second chunk: content=' world', reasoning='more thinking'
        c2 = chunks[1]
        delta2 = c2['choices'][0]['delta']
        assert delta2['content'] == ' world'
        assert delta2['reasoning_content'] == 'more thinking'

        # Last chunk: finish_reason='stop'
        last = chunks[-1]
        assert last['choices'][0]['finish_reason'] == 'stop'
    finally:
        server.shutdown()


def test_streaming_forwards_tool_calls_with_backfilled_id():
    """A streamChunk with tool_calls produces an OpenAI SSE chunk with
    delta.tool_calls. If chat.z.ai omitted the id, we backfill one."""
    server, port = _start_server()
    try:
        native_host._API_KEY = 'test-secret-key'
        _set_extension_connected(True)

        result = {}
        def call():
            result['status'], result['headers'], result['body'] = _post_chat(port, {
                'model': 'glm-4.7',
                'messages': [{'role': 'user', 'content': 'list files'}],
                'tools': [{
                    'type': 'function',
                    'function': {
                        'name': 'list_files',
                        'description': 'List files in the current directory',
                        'parameters': {'type': 'object', 'properties': {}},
                    },
                }],
                'stream': True,
            })
        t = threading.Thread(target=call)
        t.start()

        pending = _consume_pending(port)
        request_id = pending['requestId']

        # Simulate chat.z.ai emitting a tool_call WITHOUT an id.
        _drive_response(port, request_id, [
            {
                'tool_calls': [{
                    'index': 0,
                    # no 'id'
                    'type': 'function',
                    'function': {'name': 'list_files', 'arguments': '{"path": "."}'},
                }],
                'finish_reason': 'tool_calls',
            },
        ])

        t.join(timeout=5)
        assert result['status'] == 200

        chunks = []
        for line in result['body'].split('\n'):
            if line.startswith('data: '):
                data = line[6:]
                if data == '[DONE]':
                    break
                chunks.append(json.loads(data))

        # Find the chunk with tool_calls.
        tc_chunk = None
        for c in chunks:
            if c['choices'][0]['delta'].get('tool_calls'):
                tc_chunk = c
                break
        assert tc_chunk is not None, f'no chunk with tool_calls in {chunks}'

        tc = tc_chunk['choices'][0]['delta']['tool_calls'][0]
        assert tc['function']['name'] == 'list_files'
        assert tc['function']['arguments'] == '{"path": "."}'
        # ID was backfilled.
        assert tc['id'].startswith('call_'), f"expected backfilled id, got {tc.get('id')}"
        assert tc['type'] == 'function'

        # finish_reason should be 'tool_calls' on that chunk OR on the final.
        finish_reasons = [c['choices'][0].get('finish_reason') for c in chunks]
        assert 'tool_calls' in finish_reasons, f'expected tool_calls finish_reason in {finish_reasons}'
    finally:
        server.shutdown()


def test_non_streaming_accumulates_tool_calls():
    """Non-streaming response accumulates tool_call argument fragments
    across chunks (merging by index) and emits a single tool_calls
    array in the final message."""
    server, port = _start_server()
    try:
        native_host._API_KEY = 'test-secret-key'
        _set_extension_connected(True)

        result = {}
        def call():
            result['status'], result['headers'], result['body'] = _post_chat(port, {
                'model': 'glm-4.7',
                'messages': [{'role': 'user', 'content': 'list files'}],
                'tools': [{'type': 'function', 'function': {
                    'name': 'list_files',
                    'parameters': {'type': 'object', 'properties': {}},
                }}],
                'stream': False,
            })
        t = threading.Thread(target=call)
        t.start()

        pending = _consume_pending(port)
        request_id = pending['requestId']

        # Simulate the OpenAI streaming pattern: first chunk has name,
        # subsequent chunks have argument fragments.
        _drive_response(port, request_id, [
            {'tool_calls': [{'index': 0, 'function': {'name': 'list_files'}}]},
            {'tool_calls': [{'index': 0, 'function': {'arguments': '{"path'}}]},
            {'tool_calls': [{'index': 0, 'function': {'arguments': '": "."}'}}]},
            {'finish_reason': 'tool_calls'},
        ])

        t.join(timeout=5)
        assert result['status'] == 200, f"got {result['status']}: {result['body']}"

        resp = json.loads(result['body'])
        assert resp['object'] == 'chat.completion'
        choice = resp['choices'][0]
        assert choice['finish_reason'] == 'tool_calls'
        msg = choice['message']
        assert msg['role'] == 'assistant'
        # content should be null when tool_calls present.
        assert msg['content'] is None
        assert len(msg['tool_calls']) == 1
        tc = msg['tool_calls'][0]
        assert tc['function']['name'] == 'list_files'
        # Arguments were accumulated across 3 chunks.
        assert tc['function']['arguments'] == '{"path": "."}'
        assert tc['id'].startswith('call_')
        assert tc['type'] == 'function'
    finally:
        server.shutdown()


def test_request_forwards_tools_to_extension():
    """When the caller sends tools/temperature/etc, they're forwarded
    to the extension via the pending request's options field."""
    server, port = _start_server()
    try:
        native_host._API_KEY = 'test-secret-key'
        _set_extension_connected(True)

        result = {}
        def call():
            result['status'], result['headers'], result['body'] = _post_chat(port, {
                'model': 'glm-4.7',
                'messages': [{'role': 'user', 'content': 'hi'}],
                'tools': [{'type': 'function', 'function': {
                    'name': 'foo', 'parameters': {},
                }}],
                'temperature': 0.7,
                'max_tokens': 100,
                'reasoning_effort': 'high',
                'stream': True,
            })
        t = threading.Thread(target=call)
        t.start()

        pending = _consume_pending(port)
        # Cancel the request so the call thread doesn't hang.
        _post_response(port, pending['requestId'], 'error', {'error': 'test-cancel'})

        # Verify forwarded options.
        opts = pending.get('options', {})
        assert opts.get('tools') is not None
        assert opts['tools'][0]['function']['name'] == 'foo'
        assert opts.get('temperature') == 0.7
        assert opts.get('max_tokens') == 100
        # reasoning_effort='high' should translate to thinking=True
        assert opts.get('thinking') is True

        t.join(timeout=5)
    finally:
        server.shutdown()


def test_internal_endpoints_loopback_only():
    """When bound to 0.0.0.0, /_pending and /_response should be
    unreachable from non-loopback clients. This test only verifies
    the loopback path works (since we can't easily simulate a remote
    client in a unit test)."""
    server, port = _start_server()
    try:
        native_host._API_KEY = None  # no auth required
        # /_pending should work from loopback.
        req = urllib.request.Request(f'http://127.0.0.1:{port}/_pending')
        resp = urllib.request.urlopen(req, timeout=2)
        data = json.loads(resp.read())
        # Should return {'type': 'none'} when no pending requests.
        assert data.get('type') in ('none', None)
    finally:
        server.shutdown()


def main():
    """Run all tests (no pytest needed)."""
    tests = [
        test_auth_disabled_by_default,
        test_auth_accepts_correct_key,
        test_health_is_public,
        test_streaming_forwards_content_and_reasoning,
        test_streaming_forwards_tool_calls_with_backfilled_id,
        test_non_streaming_accumulates_tool_calls,
        test_request_forwards_tools_to_extension,
        test_internal_endpoints_loopback_only,
    ]
    passed = 0
    failed = 0
    for test in tests:
        try:
            test()
            print(f'  ✅ {test.__name__}')
            passed += 1
        except Exception as e:
            import traceback
            print(f'  ❌ {test.__name__}: {e}')
            traceback.print_exc()
            failed += 1
    print(f'\n{passed}/{passed + failed} tests passed')
    sys.exit(0 if failed == 0 else 1)


if __name__ == '__main__':
    main()
