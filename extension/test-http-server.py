#!/usr/bin/env python3
"""Test the native_host.py HTTP server in isolation.

Starts the server without the extension connection, then sends
test requests to verify the endpoints work."""

import subprocess
import time
import urllib.request
import json
import sys
import os

def test_server():
    # Start the server in a subprocess (it will fail to connect to
    # the extension, but the HTTP server still starts).
    proc = subprocess.Popen(
        [sys.executable, 'native_host.py'],
        stdin=subprocess.PIPE,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        cwd=os.path.dirname(os.path.abspath(__file__)),
    )

    # Send a fake "connected" message so the server thinks the extension
    # is connected.
    import struct
    msg = json.dumps({"type": "connected"}).encode('utf-8')
    proc.stdin.write(struct.pack('<I', len(msg)))
    proc.stdin.write(msg)
    proc.stdin.flush()

    # Give the server time to start.
    time.sleep(2)

    results = []

    # Test 1: Health endpoint
    try:
        resp = urllib.request.urlopen('http://127.0.0.1:8081/health', timeout=5)
        data = json.loads(resp.read())
        assert data['ok'] == True
        assert data['extension_connected'] == True
        results.append(('Health endpoint', True, str(data)))
    except Exception as e:
        results.append(('Health endpoint', False, str(e)))

    # Test 2: Models endpoint
    try:
        resp = urllib.request.urlopen('http://127.0.0.1:8081/v1/models', timeout=5)
        data = json.loads(resp.read())
        assert data['object'] == 'list'
        assert len(data['data']) > 0
        assert data['data'][0]['id'] == 'glm-4.7'
        results.append(('Models endpoint', True, f'{len(data["data"])} models'))
    except Exception as e:
        results.append(('Models endpoint', False, str(e)))

    # Test 3: Chat endpoint (without extension, should get 503)
    try:
        req_data = json.dumps({
            'model': 'glm-4.7',
            'messages': [{'role': 'user', 'content': 'test'}],
        }).encode('utf-8')
        req = urllib.request.Request(
            'http://127.0.0.1:8081/v1/chat/completions',
            data=req_data,
            headers={'Content-Type': 'application/json'},
        )
        try:
            resp = urllib.request.urlopen(req, timeout=5)
            results.append(('Chat (no ext)', False, 'Should have failed'))
        except urllib.error.HTTPError as e:
            data = json.loads(e.read())
            assert e.code == 503
            assert 'not connected' in data['error']['message'].lower()
            results.append(('Chat (no ext → 503)', True, f'HTTP {e.code}'))
    except Exception as e:
        results.append(('Chat (no ext → 503)', False, str(e)))

    # Clean up
    proc.terminate()
    proc.wait()

    # Print results
    print('\n=== HTTP Server Tests ===')
    all_passed = True
    for name, passed, detail in results:
        status = '✅' if passed else '❌'
        print(f'  {status} {name}: {detail}')
        if not passed:
            all_passed = False

    print(f'\n{"✅ All HTTP server tests passed!" if all_passed else "❌ Some tests failed!"}')
    return all_passed

if __name__ == '__main__':
    success = test_server()
    sys.exit(0 if success else 1)
