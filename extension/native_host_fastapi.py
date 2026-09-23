#!/usr/bin/env python3
"""
Lagestroemia Native Messaging Host — FastAPI version using
fastapi-openai-compat.

This is a drop-in replacement for native_host.py that uses the
`fastapi-openai-compat` library (https://github.com/deepset-ai/fastapi-openai-compat)
for the OpenAI-compatible HTTP layer. The library handles:
  - SSE streaming (proper framing, [DONE] terminator)
  - Tool calls (streaming + non-streaming)
  - Reasoning content (DeepSeek convention: delta.reasoning_content)
  - Forward compatibility (dict-based types, accepts new OpenAI fields)
  - OpenAI-spec-shaped error responses
  - Automatic OpenAPI docs at /docs

We only need to provide:
  - list_models(): return the available model IDs
  - run_completion(): bridge the request to the browser extension,
    yield chunks as they come back

The bridge code (native messaging I/O, response queues, polling,
watchdog, stale-instance killing) is the same as native_host.py.

Switching between versions:
  Set LAGESTROEMIA_USE_FASTAPI=1 in the wrapper to use this version.
  native_host.py detects the env var and execs this file.

Usage:
  python native_host_fastapi.py [--port 8081] [--host 0.0.0.0]
                                 [--api-key <key>] [--kill-all]
"""

import argparse
import json
import os
import queue
import signal
import socket
import sqlite3
import struct
import subprocess
import sys
import threading
import time
import uuid
from collections.abc import Generator
from typing import Optional

# ---- FastAPI + fastapi-openai-compat imports ----
try:
    from fastapi import FastAPI, Request
    from fastapi.middleware.cors import CORSMiddleware
    from fastapi.responses import JSONResponse, HTMLResponse
    from fastapi_openai_compat import (
        create_chat_completion_router,
        create_models_router,
        CompletionResult,
        MessageParam,
    )
    import uvicorn
except ImportError as e:
    print(f"[native-fastapi] Missing dependency: {e}", file=sys.stderr)
    print("[native-fastapi] Install with: pip install -r extension/requirements.txt", file=sys.stderr)
    sys.exit(3)


# ============================================================================
# Config
# ============================================================================

_API_KEY: Optional[str] = None
_IS_LOOPBACK: bool = True


# ============================================================================
# Bridge code — same as native_host.py
# ============================================================================

_stdout_lock = threading.Lock()
_extension_connected = threading.Event()
_outgoing_queue: queue.Queue = queue.Queue()

_response_queues: dict = {}
_response_queues_lock = threading.Lock()

_pending_requests: list = []
_pending_lock = threading.Lock()


def send_message_to_extension(msg: dict) -> None:
    _outgoing_queue.put(msg)


def _sender_thread():
    while True:
        try:
            msg = _outgoing_queue.get()
            if msg is None:
                break
            data = json.dumps(msg).encode('utf-8')
            with _stdout_lock:
                sys.stdout.buffer.write(struct.pack('<I', len(data)))
                sys.stdout.buffer.write(data)
                sys.stdout.buffer.flush()
        except Exception as e:
            print(f"[native-fastapi] Failed to send to extension: {e}", file=sys.stderr)


def stdin_reader_thread():
    while True:
        try:
            raw_length = sys.stdin.buffer.read(4)
            if len(raw_length) < 4:
                print("[native-fastapi] stdin closed — shutting down", file=sys.stderr)
                _trigger_shutdown(reason='stdin_closed')
                break
            length = struct.unpack('<I', raw_length)[0]
            if length == 0:
                continue
            data = sys.stdin.buffer.read(length)
            if len(data) < length:
                print("[native-fastapi] stdin truncated — shutting down", file=sys.stderr)
                _trigger_shutdown(reason='stdin_truncated')
                break

            msg = json.loads(data.decode('utf-8'))
            msg_type = msg.get('type', '')

            if msg_type == 'connected':
                _extension_connected.set()
                print("[native-fastapi] Extension connected", file=sys.stderr)
            elif msg_type == 'ping':
                pass
            elif msg_type in ('response', 'streamChunk', 'streamEnd', 'error'):
                request_id = msg.get('requestId', '')
                with _response_queues_lock:
                    q = _response_queues.get(request_id)
                if q:
                    q.put(msg)
        except json.JSONDecodeError:
            continue
        except Exception as e:
            print(f"[native-fastapi] stdin reader: {e}", file=sys.stderr)
            time.sleep(1)


# ---- Shutdown machinery ----

_shutdown_lock = threading.Lock()
_shutdown_triggered = False
_SHUTDOWN_TIMEOUT_SECONDS = 60


def _trigger_shutdown(reason: str = 'unknown') -> None:
    global _shutdown_triggered
    with _shutdown_lock:
        if _shutdown_triggered:
            return
        _shutdown_triggered = True
    print(f"[native-fastapi] Shutting down (reason: {reason})", file=sys.stderr)
    try:
        sys.stderr.flush()
    except Exception:
        pass
    time.sleep(0.1)
    os._exit(0)


def _watchdog_thread():
    startup = time.time()
    while True:
        time.sleep(5)
        if not _extension_connected.is_set():
            if time.time() - startup > _SHUTDOWN_TIMEOUT_SECONDS:
                _trigger_shutdown(reason='extension_never_connected')
                return


# ---- Stale-instance killing ----

def _is_loopback_host(host: str) -> bool:
    h = host.strip().lower()
    if h in ('localhost', '::1'):
        return True
    if h.startswith('127.'):
        return True
    return False


def _find_other_native_host_pids() -> list:
    own_pid = os.getpid()
    pids = []
    if sys.platform.startswith('win'):
        ps_cmd = (
            "$ErrorActionPreference='SilentlyContinue'; "
            "Get-CimInstance Win32_Process -Filter \"CommandLine LIKE '%native_host%'\" | "
            f"Where-Object {{ $_.ProcessId -ne {own_pid} }} | "
            "ForEach-Object { Write-Output $_.ProcessId }"
        )
        try:
            result = subprocess.run(
                ['powershell', '-NoProfile', '-Command', ps_cmd],
                capture_output=True, text=True, timeout=10,
            )
            for line in result.stdout.strip().split('\n'):
                line = line.strip()
                if line.isdigit():
                    pids.append(int(line))
        except Exception as e:
            print(f"[native-fastapi] PowerShell enum failed: {e}", file=sys.stderr)
    else:
        try:
            result = subprocess.run(
                ['pgrep', '-f', 'native_host'], capture_output=True, text=True, timeout=5,
            )
            for line in result.stdout.strip().split('\n'):
                line = line.strip()
                if line.isdigit():
                    pid = int(line)
                    if pid != own_pid:
                        pids.append(pid)
        except FileNotFoundError:
            try:
                result = subprocess.run(
                    ['ps', '-eo', 'pid=,command='], capture_output=True, text=True, timeout=5,
                )
                for line in result.stdout.split('\n'):
                    line = line.strip()
                    if 'native_host' in line:
                        parts = line.split(None, 1)
                        if parts and parts[0].isdigit():
                            pid = int(parts[0])
                            if pid != own_pid:
                                pids.append(pid)
            except Exception as e:
                print(f"[native-fastapi] ps enum failed: {e}", file=sys.stderr)
        except Exception as e:
            print(f"[native-fastapi] pgrep enum failed: {e}", file=sys.stderr)
    return pids


def _kill_pid(pid: int) -> bool:
    try:
        if sys.platform.startswith('win'):
            subprocess.run(
                ['taskkill', '/PID', str(pid), '/F'],
                timeout=5, check=False, capture_output=True,
            )
        else:
            os.kill(pid, signal.SIGTERM)
        return True
    except Exception as e:
        print(f"[native-fastapi] Failed to kill PID {pid}: {e}", file=sys.stderr)
        return False


def _kill_existing_native_hosts(verbose: bool = True) -> int:
    pids = _find_other_native_host_pids()
    if not pids:
        if verbose:
            print("[native-fastapi] No stale instances found.", file=sys.stderr)
        return 0
    if verbose:
        print(f"[native-fastapi] Found {len(pids)} stale instance(s): PIDs {pids}", file=sys.stderr)
    killed = 0
    for pid in pids:
        if _kill_pid(pid):
            killed += 1
            if verbose:
                print(f"[native-fastapi] Killed stale instance PID {pid}", file=sys.stderr)
    if killed > 0:
        time.sleep(0.5)
    return killed


def _enumerate_lan_urls(host: str, port: int) -> list:
    if host in ('0.0.0.0', '::'):
        urls = []
        try:
            for info in socket.getaddrinfo(None, port, socket.AF_INET,
                                           socket.SOCK_STREAM, 0, socket.AI_PASSIVE):
                addr = info[4][0]
                urls.append(f'http://{addr}:{port}')
            seen = set()
            unique = []
            for u in urls:
                if u not in seen:
                    seen.add(u)
                    unique.append(u)
            return unique or [f'http://0.0.0.0:{port}']
        except Exception:
            return [f'http://0.0.0.0:{port}']
    return [f'http://{host}:{port}']


# ---- Local chat storage (SQLite) — same as native_host.py ----

_chat_db_path = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'chats.db')
_chat_db_lock = threading.Lock()


def _get_chat_db():
    conn = sqlite3.connect(_chat_db_path, check_same_thread=False)
    conn.execute('''
        CREATE TABLE IF NOT EXISTS chats (
            id TEXT PRIMARY KEY,
            title TEXT NOT NULL,
            model TEXT,
            messages TEXT NOT NULL,
            created_at INTEGER NOT NULL,
            updated_at INTEGER NOT NULL
        )
    ''')
    conn.commit()
    return conn


# ============================================================================
# Bridge: extension → run_completion
# ============================================================================

def _send_chat_to_extension(messages: list, model: str, body: dict) -> queue.Queue:
    """Put a chat request in the pending list for the extension to poll.
    Returns the response queue the caller should read from."""
    request_id = str(uuid.uuid4())
    q = queue.Queue()
    with _response_queues_lock:
        _response_queues[request_id] = q

    # Build options forwarded to the extension.
    options = {
        'tools': body.get('tools'),
        'tool_choice': body.get('tool_choice'),
        'temperature': body.get('temperature'),
        'max_tokens': body.get('max_tokens') or body.get('max_completion_tokens'),
        'top_p': body.get('top_p'),
        'presence_penalty': body.get('presence_penalty'),
        'frequency_penalty': body.get('frequency_penalty'),
        'stop': body.get('stop'),
        'seed': body.get('seed'),
    }
    # Translate OpenAI's reasoning_effort to our thinking flag.
    reasoning_effort = body.get('reasoning_effort')
    if reasoning_effort in ('medium', 'high'):
        options['thinking'] = True
    options = {k: v for k, v in options.items() if v is not None}

    stream = body.get('stream', False)
    pending_req = {
        'type': 'sendChat',
        'requestId': request_id,
        'messages': messages,
        'model': model,
        'stream': stream,
        'options': options,
    }
    with _pending_lock:
        _pending_requests.append(pending_req)

    return q, request_id


class BridgeChunk:
    """Duck-typed chunk object that fastapi-openai-compat recognizes.

    The library checks for attributes:
      - .content  → str, emitted as delta.content
      - .reasoning → object with .reasoning_text, emitted as delta.reasoning_content
      - .tool_calls → list, emitted as delta.tool_calls
      - .finish_reason → str, set on the choice

    We set whichever fields are present in the extension's chunk.
    """
    def __init__(self, chunk_data: dict):
        self.content = chunk_data.get('content') or None
        if not self.content:
            self.content = None
        reasoning = chunk_data.get('reasoning')
        if reasoning:
            self.reasoning = type('R', (), {'reasoning_text': reasoning})()
        else:
            self.reasoning = None
        self.tool_calls = chunk_data.get('tool_calls')
        # Backfill tool_call IDs.
        if isinstance(self.tool_calls, list):
            for tc in self.tool_calls:
                if not tc.get('id'):
                    tc['id'] = f'call_{uuid.uuid4().hex[:8]}_{tc.get("index", 0)}'
                if not tc.get('type'):
                    tc['type'] = 'function'
                fn = tc.get('function')
                if not isinstance(fn, dict):
                    tc['function'] = {'name': '', 'arguments': ''}
                else:
                    if not fn.get('name'):
                        fn['name'] = ''
                    if not fn.get('arguments'):
                        fn['arguments'] = ''
        self.finish_reason = chunk_data.get('finish_reason')


# ============================================================================
# fastapi-openai-compat callbacks
# ============================================================================

def list_models() -> list:
    """Return the available model IDs. Asks the extension for the live
    list, falls back to static."""
    request_id = str(uuid.uuid4())
    q = queue.Queue()
    with _response_queues_lock:
        _response_queues[request_id] = q
    send_message_to_extension({'type': 'getModels', 'requestId': request_id})
    try:
        msg = q.get(timeout=10)
        if msg.get('type') == 'response' and msg.get('models'):
            return msg['models']
    except queue.Empty:
        pass
    finally:
        with _response_queues_lock:
            _response_queues.pop(request_id, None)
    # Fallback static list
    return ['glm-4.7', 'x-preview-l', 'glm-5.3', 'glm-5.2', 'glm-4.6v',
            'GLM-4.1V-Thinking-FlashX', 'deep-research', 'zero']


def run_completion(model: str, messages: list, body: dict) -> CompletionResult:
    """Bridge the request to the extension.

    For non-streaming: collect all chunks, return a ChatCompletion.
    For streaming: yield BridgeChunk objects, the library handles SSE.

    Note: this is a sync callable. The library runs it in a thread pool
    so it doesn't block the async event loop. We block on q.get() which
    is fine — the thread pool thread can wait.
    """
    if not _extension_connected.is_set():
        raise RuntimeError(
            'Browser extension is not connected. Make sure the Lagestroemia '
            'extension is installed and a chat.z.ai tab is open.'
        )

    # Convert messages to plain dicts for the extension.
    msg_dicts = []
    for m in messages:
        if isinstance(m, dict):
            msg_dicts.append(m)
        else:
            msg_dicts.append(m)

    q, request_id = _send_chat_to_extension(msg_dicts, model, body)
    stream = body.get('stream', False)

    if stream:
        # Return a generator. The library wraps each yielded BridgeChunk
        # as a chat.completion.chunk SSE message.
        def stream_generator() -> Generator:
            try:
                while True:
                    try:
                        msg = q.get(timeout=180)
                    except queue.Empty:
                        # Yield an error chunk — the library will surface it.
                        raise RuntimeError('Extension did not respond in 180 seconds')

                    msg_type = msg.get('type', '')
                    if msg_type == 'streamChunk':
                        chunk = msg.get('chunk', {})
                        # Skip empty chunks (no content, no reasoning, no tool_calls, no finish_reason).
                        if not any([chunk.get('content'), chunk.get('reasoning'),
                                    chunk.get('tool_calls'), chunk.get('finish_reason')]):
                            continue
                        yield BridgeChunk(chunk)
                    elif msg_type in ('streamEnd', 'response'):
                        return
                    elif msg_type == 'error':
                        raise RuntimeError(msg.get('error', 'Unknown error'))
            finally:
                with _response_queues_lock:
                    _response_queues.pop(request_id, None)

        return stream_generator()
    else:
        # Non-streaming: collect all chunks into a single response.
        from fastapi_openai_compat import ChatCompletion, Choice, Message
        import time as _time

        full_content = ''
        reasoning = ''
        tool_calls_by_index = {}
        final_finish_reason = None

        try:
            while True:
                try:
                    msg = q.get(timeout=180)
                except queue.Empty:
                    raise RuntimeError('Extension did not respond in 180 seconds')

                msg_type = msg.get('type', '')
                if msg_type == 'streamChunk':
                    chunk = msg.get('chunk', {})
                    full_content += chunk.get('content', '')
                    reasoning += chunk.get('reasoning', '')
                    tcs = chunk.get('tool_calls')
                    if isinstance(tcs, list):
                        for tc in tcs:
                            idx = tc.get('index', 0)
                            if idx not in tool_calls_by_index:
                                tool_calls_by_index[idx] = {
                                    'index': idx,
                                    'id': tc.get('id') or f'call_{uuid.uuid4().hex[:8]}_{idx}',
                                    'type': tc.get('type', 'function'),
                                    'function': {'name': '', 'arguments': ''},
                                }
                            acc = tool_calls_by_index[idx]
                            fn = tc.get('function', {})
                            if fn.get('name'):
                                acc['function']['name'] += fn['name']
                            if fn.get('arguments'):
                                acc['function']['arguments'] += fn['arguments']
                    if chunk.get('finish_reason'):
                        final_finish_reason = chunk['finish_reason']
                elif msg_type in ('streamEnd', 'response'):
                    break
                elif msg_type == 'error':
                    raise RuntimeError(msg.get('error', 'Unknown error'))
        finally:
            with _response_queues_lock:
                _response_queues.pop(request_id, None)

        message = {'role': 'assistant'}
        if tool_calls_by_index:
            message['content'] = None
            message['tool_calls'] = [tool_calls_by_index[i] for i in sorted(tool_calls_by_index)]
        else:
            message['content'] = full_content
        if reasoning:
            message['reasoning_content'] = reasoning

        finish_reason = final_finish_reason or ('tool_calls' if tool_calls_by_index else 'stop')

        return ChatCompletion(
            id=f'chatcmpl-{uuid.uuid4().hex[:24]}',
            object='chat.completion',
            created=int(_time.time()),
            model=model,
            choices=[Choice(
                index=0,
                message=Message(**message),
                finish_reason=finish_reason,
            )],
            usage={'prompt_tokens': 0, 'completion_tokens': 0, 'total_tokens': 0},
        )


# ============================================================================
# FastAPI app
# ============================================================================

app = FastAPI(
    title="Lagestroemia native host (FastAPI + fastapi-openai-compat)",
    description="OpenAI-compatible HTTP server bridging to chat.z.ai via the Lagestroemia browser extension.",
    version="0.10.0",
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["GET", "POST", "OPTIONS", "DELETE"],
    allow_headers=["Content-Type", "Authorization"],
)

# Register the OpenAI-compatible routers from fastapi-openai-compat.
# These handle /v1/chat/completions and /v1/models with full OpenAI spec
# compliance — SSE streaming, tool calls, reasoning content, etc.
chat_router = create_chat_completion_router(
    list_models=list_models,
    run_completion=run_completion,
)
app.include_router(chat_router)

models_router = create_models_router(list_models=list_models)
app.include_router(models_router)


def _is_loopback_client(request: Request) -> bool:
    client_ip = request.client.host if request.client else '127.0.0.1'
    if client_ip in ('127.0.0.1', '::1', 'localhost'):
        return True
    try:
        parts = [int(p) for p in client_ip.split('.')]
        if len(parts) == 4:
            a, b, _, _ = parts
            if a == 10: return True
            if a == 172 and 16 <= b <= 31: return True
            if a == 192 and b == 168: return True
            if a == 169 and b == 254: return True
    except (ValueError, IndexError):
        pass
    if client_ip.startswith(('fc', 'fd', 'fe80')):
        return True
    return False


@app.get("/")
async def index():
    html = '''<!DOCTYPE html>
<html>
<head><meta charset="utf-8"><title>Lagestroemia native host</title>
<style>body{font:14px/1.5 -apple-system,system-ui,sans-serif;max-width:600px;margin:40px auto;padding:0 20px;color:#222}code{background:#f4f4f4;padding:2px 6px;border-radius:3px}a{color:#7C4DFF}</style>
</head>
<body>
<h1>Lagestroemia native host</h1>
<p>OpenAI-compatible HTTP server powered by
<a href="https://github.com/deepset-ai/fastapi-openai-compat">fastapi-openai-compat</a>.
Bridges external clients (opencode, Cline, Continue, curl) to the Lagestroemia
browser extension, which forwards requests to chat.z.ai.</p>
<h2>Endpoints</h2>
<ul>
  <li><code>GET /health</code> — health check</li>
  <li><code>GET /v1/models</code> — list models (from fastapi-openai-compat)</li>
  <li><code>POST /v1/chat/completions</code> — chat (stream + non-stream, tools, reasoning)</li>
  <li><code>GET /docs</code> — interactive OpenAPI docs</li>
</ul>
<h2>Quick test</h2>
<pre>curl http://127.0.0.1:8081/health
curl http://127.0.0.1:8081/v1/models
curl http://127.0.0.1:8081/v1/chat/completions \\
  -H "Content-Type: application/json" \\
  -d '{"model":"glm-4.7","messages":[{"role":"user","content":"hi"}],"stream":false}'</pre>
</body>
</html>'''
    return HTMLResponse(content=html)


@app.get("/health")
async def health():
    return {"ok": True, "extension_connected": _extension_connected.is_set()}


# ---- Internal endpoints (loopback only) ----
# These are NOT part of the OpenAI spec — they're the bridge between
# the native host and the browser extension. The extension polls
# /_pending for chat requests and POSTs responses to /_response.

from fastapi import HTTPException


@app.get("/_pending")
async def pending(request: Request):
    if not _is_loopback_client(request):
        raise HTTPException(status_code=404, detail="Not found")
    with _pending_lock:
        if _pending_requests:
            return _pending_requests.pop(0)
        return {'type': 'none'}


@app.post("/_response")
async def response(request: Request):
    if not _is_loopback_client(request):
        raise HTTPException(status_code=404, detail="Not found")
    body = await request.json()
    request_id = body.get('requestId', '')
    with _response_queues_lock:
        q = _response_queues.get(request_id)
    if q:
        q.put(body)
    return {'ok': True}


@app.get("/_debug")
async def debug(request: Request):
    if not _is_loopback_client(request):
        raise HTTPException(status_code=404, detail="Not found")
    with _pending_lock:
        pending_count = len(_pending_requests)
    with _response_queues_lock:
        queue_ids = list(_response_queues.keys())
    return {
        'extension_connected': _extension_connected.is_set(),
        'pending_requests': pending_count,
        'active_queues': queue_ids,
        'api_key_set': bool(_API_KEY),
        'is_loopback_bind': _IS_LOOPBACK,
        'http_layer': 'fastapi-openai-compat',
    }


# ---- Local chat storage endpoints ----

@app.get("/v1/chats")
async def list_chats():
    with _chat_db_lock:
        conn = _get_chat_db()
        rows = conn.execute(
            'SELECT id, title, model, created_at, updated_at FROM chats ORDER BY updated_at DESC'
        ).fetchall()
        conn.close()
    return {'chats': [{'id': r[0], 'title': r[1], 'model': r[2],
                       'created_at': r[3], 'updated_at': r[4]} for r in rows]}


@app.get("/v1/chats/{chat_id}")
async def get_chat(chat_id: str):
    with _chat_db_lock:
        conn = _get_chat_db()
        row = conn.execute('SELECT * FROM chats WHERE id = ?', (chat_id,)).fetchone()
        conn.close()
    if not row:
        raise HTTPException(status_code=404, detail="Chat not found")
    return {
        'id': row[0], 'title': row[1], 'model': row[2],
        'messages': json.loads(row[3]),
        'created_at': row[4], 'updated_at': row[5],
    }


@app.post("/v1/chats")
async def save_chat(request: Request):
    body = await request.json()
    chat_id = body.get('id') or str(uuid.uuid4())
    title = body.get('title', 'Untitled')
    model = body.get('model', '')
    messages = body.get('messages', [])
    now = int(time.time())
    with _chat_db_lock:
        conn = _get_chat_db()
        conn.execute('''
            INSERT OR REPLACE INTO chats (id, title, model, messages, created_at, updated_at)
            VALUES (?, ?, ?, ?, ?, ?)
        ''', (chat_id, title, model, json.dumps(messages), now, now))
        conn.commit()
        conn.close()
    return {'ok': True, 'id': chat_id}


@app.delete("/v1/chats/{chat_id}")
async def delete_chat(chat_id: str):
    with _chat_db_lock:
        conn = _get_chat_db()
        conn.execute('DELETE FROM chats WHERE id = ?', (chat_id,))
        conn.commit()
        conn.close()
    return {'ok': True}


# ============================================================================
# Main
# ============================================================================

def _install_signal_handlers():
    if sys.platform.startswith('win'):
        return
    def _handler(signum, frame):
        _trigger_shutdown(reason=f'signal_{signum}')
    signal.signal(signal.SIGTERM, _handler)
    signal.signal(signal.SIGINT, _handler)


def main():
    parser = argparse.ArgumentParser(description='Lagestroemia native host (FastAPI)')
    parser.add_argument('--port', type=int, default=None, help='Port (default: 8081)')
    parser.add_argument('--host', type=str, default='0.0.0.0',
                        help='Bind address (default: 0.0.0.0)')
    parser.add_argument('--api-key', type=str, default=None, help='Server API key (currently ignored, auth disabled)')
    parser.add_argument('--kill-all', action='store_true', help='Kill stale instances and exit')
    parser.add_argument('--no-kill-existing', action='store_true', help='Do NOT kill stale instances')
    args, _ = parser.parse_known_args()

    if args.kill_all:
        killed = _kill_existing_native_hosts(verbose=True)
        print(f"[native-fastapi] Killed {killed} stale instance(s).", file=sys.stderr)
        sys.exit(0)

    global _API_KEY, _IS_LOOPBACK

    PORT = args.port or int(os.environ.get('LAGESTROEMIA_PORT', '8081'))
    HOST = args.host or os.environ.get('LAGESTROEMIA_HOST', '0.0.0.0')
    _API_KEY = args.api_key or os.environ.get('LAGESTROEMIA_API_KEY', None)
    _IS_LOOPBACK = _is_loopback_host(HOST)

    if not _IS_LOOPBACK:
        print(f"[native-fastapi] WARNING: binding to '{HOST}' with auth DISABLED.", file=sys.stderr)

    if not args.no_kill_existing:
        killed = _kill_existing_native_hosts(verbose=True)
        if killed > 0:
            print(f"[native-fastapi] Killed {killed} stale instance(s).", file=sys.stderr)

    print(f"[native-fastapi] Starting FastAPI server (fastapi-openai-compat) on http://{HOST}:{PORT}", file=sys.stderr)
    print(f"[native-fastapi] HTTP layer: fastapi-openai-compat (https://github.com/deepset-ai/fastapi-openai-compat)", file=sys.stderr)
    print(f"[native-fastapi] Bind mode: {'loopback' if _IS_LOOPBACK else 'LAN-reachable'}", file=sys.stderr)
    print(f"[native-fastapi] Reachable URLs:", file=sys.stderr)
    for url in _enumerate_lan_urls(HOST, PORT):
        print(f"[native-fastapi]   {url}", file=sys.stderr)
    print(f"[native-fastapi] Endpoints:", file=sys.stderr)
    print(f"[native-fastapi]   GET  /            (index)", file=sys.stderr)
    print(f"[native-fastapi]   GET  /health", file=sys.stderr)
    print(f"[native-fastapi]   GET  /v1/models   (fastapi-openai-compat)", file=sys.stderr)
    print(f"[native-fastapi]   POST /v1/chat/completions  (fastapi-openai-compat)", file=sys.stderr)
    print(f"[native-fastapi]   GET  /docs         (OpenAPI docs)", file=sys.stderr)
    print(f"[native-fastapi]   GET  /_pending     (internal, loopback only)", file=sys.stderr)
    print(f"[native-fastapi]   POST /_response    (internal, loopback only)", file=sys.stderr)
    print(f"[native-fastapi]   GET  /_debug       (internal, loopback only)", file=sys.stderr)

    # Start background threads.
    sender = threading.Thread(target=_sender_thread, daemon=True)
    sender.start()
    stdin_thread = threading.Thread(target=stdin_reader_thread, daemon=True)
    stdin_thread.start()
    watchdog = threading.Thread(target=_watchdog_thread, daemon=True)
    watchdog.start()

    _extension_connected.set()
    send_message_to_extension({'type': 'nativeReady', 'port': PORT})

    try:
        uvicorn.run(
            app,
            host=HOST,
            port=PORT,
            log_level='warning',
            access_log=False,
            timeout_keep_alive=30,
        )
    except KeyboardInterrupt:
        _trigger_shutdown(reason='keyboard_interrupt')


if __name__ == '__main__':
    _install_signal_handlers()
    main()
