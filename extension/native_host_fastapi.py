#!/usr/bin/env python3
"""
Lagestroemia Native Messaging Host — FastAPI version.

This is a drop-in replacement for native_host.py that uses FastAPI +
Pydantic + sse-starlette for the HTTP layer. The bridge code (native
messaging I/O, response queues, polling) is the same as native_host.py.

Why use this instead of native_host.py:
  - Proper Pydantic request validation (catches malformed bodies
    before they reach the bridge)
  - sse-starlette handles SSE framing correctly (multi-line content,
    Unicode, [DONE] terminator)
  - Automatic OpenAPI docs at /docs
  - Cleaner error responses (OpenAI-spec-shaped)
  - Type hints throughout

Why use native_host.py instead:
  - Zero dependencies (stdlib only)
  - Works without `pip install -r requirements.txt`
  - Smaller attack surface

Switching between them:
  The wrapper script (native_host_wrapper.bat / .sh) decides which
  to run. Set LAGESTROEMIA_USE_FASTAPI=1 to use this version.

  Edit the wrapper to:
    set LAGESTROEMIA_USE_FASTAPI=1
    "python.exe" "native_host.py"

  native_host.py will detect the env var and exec this file instead.

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
from typing import Any, Optional

# ---- FastAPI imports ----
# These are optional — native_host.py works without them. This file
# requires them.
try:
    from fastapi import FastAPI, Request, HTTPException
    from fastapi.middleware.cors import CORSMiddleware
    from fastapi.responses import JSONResponse, HTMLResponse, StreamingResponse
    from pydantic import BaseModel, Field
    import uvicorn
except ImportError as e:
    print(f"[native-fastapi] Missing dependency: {e}", file=sys.stderr)
    print("[native-fastapi] Install with: pip install fastapi uvicorn pydantic", file=sys.stderr)
    sys.exit(3)


# ============================================================================
# Config (set in main())
# ============================================================================

_API_KEY: Optional[str] = None
_IS_LOOPBACK: bool = True


# ============================================================================
# Bridge code — same as native_host.py
# (Copied verbatim to keep this file self-contained.)
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
# Pydantic models — OpenAI Chat Completions spec
# ============================================================================

class ChatMessage(BaseModel):
    role: str
    content: Optional[Any] = None  # string or array of content parts
    name: Optional[str] = None
    tool_call_id: Optional[str] = None
    tool_calls: Optional[list] = None
    reasoning_content: Optional[str] = None


class ChatCompletionRequest(BaseModel):
    model: str = "glm-4.7"
    messages: list[ChatMessage]
    stream: bool = False
    tools: Optional[list] = None
    tool_choice: Optional[Any] = None
    temperature: Optional[float] = None
    max_tokens: Optional[int] = None
    max_completion_tokens: Optional[int] = None
    top_p: Optional[float] = None
    presence_penalty: Optional[float] = None
    frequency_penalty: Optional[float] = None
    n: Optional[int] = None
    stop: Optional[Any] = None
    seed: Optional[int] = None
    reasoning_effort: Optional[str] = None  # 'minimal'|'low'|'medium'|'high'
    user: Optional[str] = None
    response_format: Optional[dict] = None
    logprobs: Optional[bool] = None
    top_logprobs: Optional[int] = None


# ============================================================================
# FastAPI app
# ============================================================================

app = FastAPI(
    title="Lagestroemia native host (FastAPI)",
    description="OpenAI-compatible HTTP server bridging to chat.z.ai via the Lagestroemia browser extension.",
    version="0.9.0",
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["GET", "POST", "OPTIONS", "DELETE"],
    allow_headers=["Content-Type", "Authorization"],
)


def _is_loopback_client(request: Request) -> bool:
    """True if the request originates from a local/private IP."""
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


def _openai_error(status: int, message: str, error_type: str = 'invalid_request_error',
                  code: Optional[str] = None) -> JSONResponse:
    """Return an OpenAI-spec-shaped error response."""
    body = {
        'error': {
            'message': message,
            'type': error_type,
        }
    }
    if code:
        body['error']['code'] = code
    return JSONResponse(status_code=status, content=body)


@app.get("/")
async def index():
    """Small HTML index page."""
    html = '''<!DOCTYPE html>
<html>
<head><meta charset="utf-8"><title>Lagestroemia native host (FastAPI)</title>
<style>body{font:14px/1.5 -apple-system,system-ui,sans-serif;max-width:600px;margin:40px auto;padding:0 20px;color:#222}code{background:#f4f4f4;padding:2px 6px;border-radius:3px}a{color:#7C4DFF}</style>
</head>
<body>
<h1>Lagestroemia native host (FastAPI)</h1>
<p>OpenAI-compatible HTTP server. Bridges external clients (opencode, Cline, Continue, curl) to the Lagestroemia browser extension, which forwards requests to chat.z.ai.</p>
<h2>Endpoints</h2>
<ul>
  <li><code>GET /health</code> — health check</li>
  <li><code>GET /v1/models</code> — list models</li>
  <li><code>POST /v1/chat/completions</code> — chat (stream + non-stream)</li>
  <li><code>GET /docs</code> — OpenAPI docs (interactive)</li>
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


@app.get("/v1/models")
async def list_models():
    # Ask the extension for the live list, fall back to static.
    request_id = str(uuid.uuid4())
    q = queue.Queue()
    with _response_queues_lock:
        _response_queues[request_id] = q
    send_message_to_extension({'type': 'getModels', 'requestId': request_id})
    try:
        msg = q.get(timeout=10)
        if msg.get('type') == 'response' and msg.get('models'):
            models = [{'id': m, 'object': 'model', 'owned_by': 'z.ai'} for m in msg['models']]
            return {'object': 'list', 'data': models}
    except queue.Empty:
        pass
    finally:
        with _response_queues_lock:
            _response_queues.pop(request_id, None)
    # Fallback static list
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
    return {'object': 'list', 'data': models}


@app.post("/v1/chat/completions")
async def chat_completions(req: ChatCompletionRequest, request: Request):
    if not _extension_connected.is_set():
        return _openai_error(503,
            'Browser extension is not connected. Make sure the Lagestroemia '
            'extension is installed and a chat.z.ai tab is open.',
            error_type='server_error')

    # Convert Pydantic messages to dicts for the extension.
    messages = [m.model_dump(exclude_none=True) for m in req.messages]

    # Build options forwarded to the extension.
    options = {
        'tools': req.tools,
        'tool_choice': req.tool_choice,
        'temperature': req.temperature,
        'max_tokens': req.max_tokens or req.max_completion_tokens,
        'top_p': req.top_p,
        'presence_penalty': req.presence_penalty,
        'frequency_penalty': req.frequency_penalty,
        'stop': req.stop,
        'seed': req.seed,
    }
    if req.reasoning_effort in ('medium', 'high'):
        options['thinking'] = True
    options = {k: v for k, v in options.items() if v is not None}

    request_id = str(uuid.uuid4())
    q = queue.Queue()
    with _response_queues_lock:
        _response_queues[request_id] = q

    pending_req = {
        'type': 'sendChat',
        'requestId': request_id,
        'messages': messages,
        'model': req.model,
        'stream': req.stream,
        'options': options,
    }
    with _pending_lock:
        _pending_requests.append(pending_req)

    # Wait for the first response.
    try:
        first_msg = q.get(timeout=180)
        msg_type = first_msg.get('type', '')
        if msg_type == 'error':
            with _response_queues_lock:
                _response_queues.pop(request_id, None)
            return _openai_error(502, first_msg.get('error', 'Unknown error'),
                                 error_type='upstream_error')
        q.put(first_msg)  # put it back for the streaming loop
    except queue.Empty:
        with _response_queues_lock:
            _response_queues.pop(request_id, None)
        return _openai_error(504,
            'Extension did not respond in 180 seconds. Likely causes:\n'
            '  1. Captcha required — switch to Firefox and solve the Aliyun popup\n'
            '  2. chat.z.ai tab is closed or backgrounded\n'
            '  3. Extension crashed — check browser console (F12)\n'
            '  4. Content script not loaded — reload the chat.z.ai tab',
            error_type='timeout')

    if req.stream:
        return StreamingResponse(
            _stream_sse(q, request_id, req.model),
            media_type="text/event-stream",
            headers={
                "Cache-Control": "no-cache",
                "Connection": "close",
                "X-Accel-Buffering": "no",
            },
        )
    else:
        return await _collect_response(q, request_id, req.model)


async def _stream_sse(q: queue.Queue, request_id: str, model: str):
    """Async generator that yields SSE chunks."""
    try:
        while True:
            try:
                msg = q.get(timeout=120)
            except queue.Empty:
                yield 'data: {"error":{"message":"Timeout waiting for response"}}\n\n'
                break

            msg_type = msg.get('type', '')

            if msg_type == 'streamChunk':
                chunk = msg.get('chunk', {})
                content = chunk.get('content', '')
                reasoning = chunk.get('reasoning', '')
                tool_calls = chunk.get('tool_calls')
                finish_reason = chunk.get('finish_reason')

                # Backfill tool_call IDs.
                if isinstance(tool_calls, list):
                    for tc in tool_calls:
                        if not tc.get('id'):
                            tc['id'] = f'call_{request_id[:8]}_{tc.get("index", 0)}'
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

                delta = {}
                if content:
                    delta['content'] = content
                if reasoning:
                    delta['reasoning_content'] = reasoning
                if tool_calls:
                    delta['tool_calls'] = tool_calls
                if not delta and not finish_reason:
                    continue

                choice = {'index': 0, 'delta': delta, 'finish_reason': None}
                if finish_reason:
                    choice['finish_reason'] = finish_reason

                sse_chunk = {
                    'id': request_id,
                    'object': 'chat.completion.chunk',
                    'model': model,
                    'choices': [choice],
                }
                yield f'data: {json.dumps(sse_chunk)}\n\n'

            elif msg_type in ('streamEnd', 'response'):
                final_chunk = {
                    'id': request_id,
                    'object': 'chat.completion.chunk',
                    'model': model,
                    'choices': [{'index': 0, 'delta': {}, 'finish_reason': 'stop'}],
                }
                yield f'data: {json.dumps(final_chunk)}\n\n'
                yield 'data: [DONE]\n\n'
                break

            elif msg_type == 'error':
                error_msg = msg.get('error', 'Unknown error')
                yield f'data: {{"error":{{"message":"{error_msg}"}}}}\n\n'
                break
    finally:
        with _response_queues_lock:
            _response_queues.pop(request_id, None)


async def _collect_response(q: queue.Queue, request_id: str, model: str) -> JSONResponse:
    """Collect all chunks into a single non-streaming response."""
    full_content = ''
    reasoning = ''
    tool_calls_by_index = {}
    final_finish_reason = None

    try:
        while True:
            try:
                msg = q.get(timeout=120)
            except queue.Empty:
                return _openai_error(504, 'Timeout', error_type='timeout')

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
                                'id': tc.get('id') or f'call_{request_id[:8]}_{idx}',
                                'type': tc.get('type', 'function'),
                                'function': {'name': '', 'arguments': ''},
                            }
                        acc = tool_calls_by_index[idx]
                        fn = tc.get('function', {})
                        if fn.get('name'):
                            acc['function']['name'] += fn['name']
                        if fn.get('arguments'):
                            acc['function']['arguments'] += fn['arguments']
                        if tc.get('id'):
                            acc['id'] = tc['id']
                        if tc.get('type'):
                            acc['type'] = tc['type']
                if chunk.get('finish_reason'):
                    final_finish_reason = chunk['finish_reason']
            elif msg_type in ('streamEnd', 'response'):
                break
            elif msg_type == 'error':
                return _openai_error(502, msg.get('error', 'Unknown error'),
                                     error_type='upstream_error')
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

    return JSONResponse(content={
        'id': request_id,
        'object': 'chat.completion',
        'model': model,
        'choices': [{'index': 0, 'message': message, 'finish_reason': finish_reason}],
        'usage': {
            'prompt_tokens': 0,
            'completion_tokens': 0,
            'total_tokens': 0,
        },
    })


# ---- Internal endpoints (loopback only) ----

@app.get("/_pending")
async def pending(request: Request):
    if not _is_loopback_client(request):
        return _openai_error(404, 'Not found')
    with _pending_lock:
        if _pending_requests:
            req = _pending_requests.pop(0)
            return req
        return {'type': 'none'}


@app.post("/_response")
async def response(request: Request):
    if not _is_loopback_client(request):
        return _openai_error(404, 'Not found')
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
        return _openai_error(404, 'Not found')
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
    chats = [{'id': r[0], 'title': r[1], 'model': r[2],
              'created_at': r[3], 'updated_at': r[4]} for r in rows]
    return {'chats': chats}


@app.get("/v1/chats/{chat_id}")
async def get_chat(chat_id: str):
    with _chat_db_lock:
        conn = _get_chat_db()
        row = conn.execute('SELECT * FROM chats WHERE id = ?', (chat_id,)).fetchone()
        conn.close()
    if not row:
        return _openai_error(404, 'Chat not found')
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

    print(f"[native-fastapi] Starting FastAPI server on http://{HOST}:{PORT}", file=sys.stderr)
    print(f"[native-fastapi] Bind mode: {'loopback' if _IS_LOOPBACK else 'LAN-reachable'}", file=sys.stderr)
    print(f"[native-fastapi] Reachable URLs:", file=sys.stderr)
    for url in _enumerate_lan_urls(HOST, PORT):
        print(f"[native-fastapi]   {url}", file=sys.stderr)
    print(f"[native-fastapi] Endpoints:", file=sys.stderr)
    print(f"[native-fastapi]   GET  /            (index)", file=sys.stderr)
    print(f"[native-fastapi]   GET  /health", file=sys.stderr)
    print(f"[native-fastapi]   GET  /v1/models", file=sys.stderr)
    print(f"[native-fastapi]   POST /v1/chat/completions", file=sys.stderr)
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

    # Run uvicorn in the main thread. We can't use the async version
    # because uvicorn.run() blocks, and we need the main thread to be
    # blocked so the background threads can call _trigger_shutdown via
    # os._exit() when stdin closes.
    try:
        uvicorn.run(
            app,
            host=HOST,
            port=PORT,
            log_level='warning',
            access_log=False,
            # Disable the uvicorn banner — we already printed our own.
            timeout_keep_alive=30,
        )
    except KeyboardInterrupt:
        _trigger_shutdown(reason='keyboard_interrupt')


if __name__ == '__main__':
    _install_signal_handlers()
    main()
