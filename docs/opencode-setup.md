# Using Lagestroemia with opencode

This guide covers the three common setups:

1. **Same machine** — opencode runs on the same OS as the browser
2. **WSL2** — browser on Windows, opencode in WSL2 (same physical machine, different network namespace)
3. **LAN** — opencode on a different machine entirely

All three require the [browser extension](../extension/README.md) to be installed and a chat.z.ai tab to be open.

---

## 1. Same machine (simplest)

opencode and Firefox/Chrome run on the same OS. The native host's default loopback bind works.

1. Install the native host: `scripts/install-native.sh firefox` (or `chrome`/`edge`, or `install-native.ps1` on Windows).
2. Load the extension and open https://chat.z.ai — solve the captcha once via the side panel.
3. Verify the server is up:
   ```bash
   curl http://127.0.0.1:8081/health
   # → {"ok": true, "extension_connected": true}
   ```
4. Add to `~/.config/opencode/opencode.json`:
   ```json
   {
     "$schema": "https://opencode.ai/config.json",
     "provider": {
       "lagestroemia": {
         "npm": "@ai-sdk/openai-compatible",
         "name": "Lagestroemia (z.ai)",
         "options": { "baseURL": "http://127.0.0.1:8081/v1" },
         "models": {
           "glm-4.7": { "name": "GLM-4.7" },
           "glm-4.6": { "name": "GLM-4.6" }
         }
       }
     }
   }
   ```
5. Run: `opencode --model lagestroemia/glm-4.7`

No API key needed — loopback binds don't require auth.

---

## 2. WSL2 (browser on Windows, opencode in WSL2)

WSL2 runs in a lightweight VM with its own network namespace. `127.0.0.1` on Windows is **not** reachable from inside WSL2 — you need to bind to `0.0.0.0` and use the Windows host IP.

### 2.1. Update the native host code on Windows

If you cloned Lagestroemia before the LAN-access work landed, update:

```powershell
cd C:\path\to\Lagestroemia
git fetch origin
git checkout browser-extension
git pull
```

The `install-native.ps1` script only writes the wrapper and registry entry once — it doesn't copy `native_host.py` anywhere. The wrapper references the script at its cloned path, so a `git pull` is enough. No need to re-run `install-native.ps1` unless you switched browsers or want to regenerate the wrapper.

### 2.2. Enable LAN binding in the wrapper

Open `extension/native_host_wrapper.bat` in a text editor. Uncomment and set the two env vars:

```bat
@echo off
REM Lagestroemia native host wrapper.
set LAGESTROEMIA_HOST=0.0.0.0
set LAGESTROEMIA_API_KEY=librevox-rotate-me
"C:\Python313\python.exe" "C:\path\to\Lagestroemia\extension\native_host.py"
```

Pick a real secret — anyone on your LAN can reach the server now.

### 2.3. Open the Windows firewall

In an **admin** PowerShell:

```powershell
New-NetFirewallRule -DisplayName "Lagestroemia" `
  -Direction Inbound -LocalPort 8081 -Protocol TCP -Action Allow
```

### 2.4. Reload the extension

Firefox: `about:debugging` → This Firefox → Lagestroemia → **Reload**.
Chrome/Edge: `chrome://extensions` → click the reload arrow on Lagestroemia.

The native host process is killed and re-spawned when the extension reloads. Watch the chat.z.ai tab — the 🌺 badge should reappear within a few seconds.

### 2.5. Find the Windows host IP from WSL2

Inside WSL, run:

```bash
# Method 1: the default route's gateway is the Windows host
ip route show default | awk '{print $3}'

# Method 2: DNS resolver is the Windows host
cat /etc/resolv.conf | grep nameserver | awk '{print $2}'
```

Both should return the same IP, typically `172.x.x.1` (the vEthernet (WSL) adapter on Windows). Save it as a variable:

```bash
WINHOST=$(ip route show default | awk '{print $3}')
```

### 2.6. Verify from WSL

```bash
# Health (no auth needed):
curl http://$WINHOST:8081/health

# Auth required for everything else:
curl http://$WINHOST:8081/v1/models \
  -H "Authorization: Bearer librevox-rotate-me"
```

### 2.7. Point opencode at it

`~/.config/opencode/opencode.json` inside WSL:

```json
{
  "$schema": "https://opencode.ai/config.json",
  "provider": {
    "lagestroemia": {
      "npm": "@ai-sdk/openai-compatible",
      "name": "Lagestroemia (z.ai)",
      "options": {
        "baseURL": "http://172.x.x.1:8081/v1"
      },
      "apiKey": "librevox-rotate-me",
      "models": {
        "glm-4.7": { "name": "GLM-4.7" },
        "glm-4.6": { "name": "GLM-4.6" }
      }
    }
  }
}
```

Replace `172.x.x.1` with the actual IP from step 2.5.

Run:

```bash
opencode --model lagestroemia/glm-4.7
```

### WSL2 mirrored networking (alternative)

If you're on Windows 11 22H2+ and have WSL2 mirrored networking enabled in `%USERPROFILE%\.wslconfig`:

```ini
[wsl2]
networkingMode=mirrored
```

…then `localhost` from WSL forwards to Windows, and you can skip the LAN bind entirely. Use `http://127.0.0.1:8081/v1` from WSL just like in the same-machine setup. The downside: mirrored mode has its own quirks (some VPNs break, port forwarding behaves differently), so don't enable it just for this.

### Common WSL2 gotchas

- **`172.21.x.x` vs `172.x.x.1`**: `172.21.x.x` is often the WSL VM's own IP. `172.x.x.1` (the gateway) is the Windows host. curl the gateway, not the WSL IP.
- **IP changes on reboot**: WSL2 IPs are DHCP-ish. The Windows host IP is fairly stable but can change after reboots or `wsl --shutdown`. Use the `ip route` lookup in your shell rc if you want it automated.
- **`Connection refused` after a Windows reboot**: The native host only runs while Firefox/Chrome is open with the extension loaded. Open the browser first.

---

## 3. LAN (opencode on a different machine)

Same as WSL2 but with a real LAN IP instead of the vEthernet one.

### 3.1. On the host (where the browser runs)

1. Update code: `git pull` on the `browser-extension` branch.
2. Edit `extension/native_host_wrapper.bat` (or `.sh`):
   ```bash
   export LAGESTROEMIA_HOST=0.0.0.0
   export LAGESTROEMIA_API_KEY=<shared-secret>
   ```
3. Open the firewall:
   - **Windows**: `New-NetFirewallRule -DisplayName "Lagestroemia" -Direction Inbound -LocalPort 8081 -Protocol TCP -Action Allow`
   - **Linux**: `sudo ufw allow 8081/tcp`
4. Reload the extension in the browser.
5. Find the LAN IP: `ipconfig` (Windows) or `ip addr` (Linux). Look for the `192.168.x.x` or `10.x.x.x` address.

### 3.2. On the client (where opencode runs)

`~/.config/opencode/opencode.json`:

```json
{
  "provider": {
    "lagestroemia": {
      "npm": "@ai-sdk/openai-compatible",
      "options": { "baseURL": "http://192.168.1.50:8081/v1" },
      "apiKey": "<shared-secret>",
      "models": {
        "glm-4.7": { "name": "GLM-4.7" }
      }
    }
  }
}
```

### Security model

- Loopback binds (`127.0.0.1`) require no API key.
- Non-loopback binds (`0.0.0.0` or any specific IP) **require** an API key. The server refuses to start otherwise.
- Internal endpoints (`/_pending`, `/_response`, `/_debug`) are loopback-only — they return 404 to non-loopback callers. This prevents remote clients from reading pending user messages or injecting fake responses, even when the server is bound to `0.0.0.0`.
- The API key is sent via `Authorization: Bearer <key>`. Use HTTPS (a reverse proxy) if you're sending it over an untrusted network.

---

## Reinstalling / updating the native host

### When to re-run `install-native.sh` / `install-native.ps1`

- **First install** — yes, run it.
- **After `git pull` on the same branch** — no, just reload the extension. The wrapper references `native_host.py` at its cloned path, so updating the file is enough.
- **Switching browsers** (e.g. Chrome → Firefox) — yes, re-run with the new browser argument.
- **Switching branches** — no, just reload. The wrapper doesn't care which branch is checked out.
- **Want to regenerate the wrapper with the latest env-var comments** — yes, re-run.

### Updating the code

```bash
cd /path/to/Lagestroemia
git fetch origin
git checkout browser-extension   # if not already on it
git pull
```

Then **reload the extension** in the browser to kill the old `native_host.py` process and start the new one:

- Firefox: `about:debugging` → This Firefox → Lagestroemia → Reload
- Chrome/Edge: `chrome://extensions` → reload arrow on Lagestroemia

### Verifying the update took effect

After reload, hit `/health` and check the response headers. The new code sends `Access-Control-Allow-Headers: Content-Type, Authorization` (the old code only sent `Content-Type`):

```bash
curl -v http://127.0.0.1:8081/health 2>&1 | grep -i allow-headers
# Should show: Access-Control-Allow-Headers: Content-Type, Authorization
```

If you see only `Content-Type`, the old `native_host.py` is still running — reload the extension harder (close and reopen the browser tab too).

---

## Verifying it works end-to-end

```bash
# 1. Health (no auth needed even with API key set):
curl http://127.0.0.1:8081/health
# → {"ok": true, "extension_connected": true}

# 2. Models (auth required if API key set):
curl http://127.0.0.1:8081/v1/models \
  -H "Authorization: Bearer <your-key>"
# → {"object":"list","data":[{"id":"glm-4.7",...}]}

# 3. Plain chat (non-streaming):
curl http://127.0.0.1:8081/v1/chat/completions \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer <your-key>" \
  -d '{
    "model": "glm-4.7",
    "messages": [{"role":"user","content":"Say hi in 5 words"}],
    "stream": false
  }'

# 4. Tools (function calling):
curl http://127.0.0.1:8081/v1/chat/completions \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer <your-key>" \
  -d '{
    "model": "glm-4.7",
    "messages": [{"role":"user","content":"What is 2+2?"}],
    "tools": [{
      "type": "function",
      "function": {
        "name": "calc",
        "description": "Perform arithmetic",
        "parameters": {
          "type": "object",
          "properties": {"expr": {"type": "string"}},
          "required": ["expr"]
        }
      }
    }],
    "stream": true
  }'
```

If all four work, opencode will work. If any fail, check the `[native]` and `[content]` logs in the browser's developer tools console (for the chat.z.ai tab) and the native host's stderr (visible in `about:debugging` → Inspect for Firefox, or `chrome://extensions` → Service Worker for Chrome).

---

## Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| `curl /health` returns `extension_connected: false` | chat.z.ai tab closed or extension not loaded | Open chat.z.ai, reload extension |
| `Connection refused` on `127.0.0.1:8081` from same machine | Native host not running | Reload extension; check `about:debugging` for errors |
| `Connection refused` on the LAN IP from another machine | Server bound to `127.0.0.1` only, or firewall blocking | Set `LAGESTROEMIA_HOST=0.0.0.0` in wrapper, reload extension, open firewall |
| `Connection refused` on `172.x.x.1` from WSL2 | Same as above, or you're curling the WSL IP instead of the Windows host IP | Use `ip route show default \| awk '{print $3}'` to find the Windows host IP |
| opencode hangs on first request | Captcha not yet solved | Send a message via the side panel first to trigger the captcha |
| opencode gets 503 "extension not connected" | Native host didn't start | Re-run `install-native.sh` / `.ps1`, reload extension, check stderr |
| opencode gets 504 timeout | Captcha solve took >30s, or chat.z.ai tab crashed | Reload chat.z.ai tab, retry |
| opencode gets 401 invalid_api_key | API key mismatch | Set `LAGESTROEMIA_API_KEY` in wrapper, match in opencode config |
| Tool calls don't work | Old extension version | `git pull` on `browser-extension`, reload extension |
| `Access-Control-Allow-Headers: Content-Type` (no `Authorization`) | Old `native_host.py` still running | `git pull`, reload extension harder (close chat.z.ai tab too) |
| LAN caller gets 404 on `/_pending` | That's correct — internal endpoints are loopback-only | Use `/v1/chat/completions`, not `/_pending` |

---

## Quick reinstall cheat sheet

**On Windows, after `git pull`:**

```powershell
# 1. Update code
cd C:\path\to\Lagestroemia
git checkout browser-extension
git pull

# 2. Edit the wrapper to enable LAN bind
notepad extension\native_host_wrapper.bat
# Uncomment and set:
#   set LAGESTROEMIA_HOST=0.0.0.0
#   set LAGESTROEMIA_API_KEY=<your-secret>

# 3. Open firewall (admin PowerShell)
New-NetFirewallRule -DisplayName "Lagestroemia" -Direction Inbound -LocalPort 8081 -Protocol TCP -Action Allow

# 4. Reload the extension in Firefox/Chrome
```

**In WSL:**

```bash
# 5. Find the Windows host IP
WINHOST=$(ip route show default | awk '{print $3}')
echo $WINHOST

# 6. Verify
curl http://$WINHOST:8081/health
curl http://$WINHOST:8081/v1/models -H "Authorization: Bearer <your-secret>"

# 7. Point opencode at it
mkdir -p ~/.config/opencode
cat > ~/.config/opencode/opencode.json <<EOF
{
  "\$schema": "https://opencode.ai/config.json",
  "provider": {
    "lagestroemia": {
      "npm": "@ai-sdk/openai-compatible",
      "name": "Lagestroemia (z.ai)",
      "options": { "baseURL": "http://$WINHOST:8081/v1" },
      "apiKey": "<your-secret>",
      "models": {
        "glm-4.7": { "name": "GLM-4.7" }
      }
    }
  }
}
EOF

# 8. Run
opencode --model lagestroemia/glm-4.7
```
