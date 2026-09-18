# Test the full chain: HTTP -> native -> background -> content -> chat.z.ai
# Usage: .\scripts\test-api.ps1
#
# This script tests each step of the chain and prints diagnostics
# so you can see exactly where it gets stuck.

$ErrorActionPreference = "Stop"

function Write-Step($num, $msg) {
    Write-Host "`n$num. $msg" -ForegroundColor Cyan
}

function Write-Ok($msg) {
    Write-Host "   ✅ $msg" -ForegroundColor Green
}

function Write-Err($msg) {
    Write-Host "   ❌ $msg" -ForegroundColor Red
}

function Write-Info($msg) {
    Write-Host "   ℹ $msg" -ForegroundColor Yellow
}

# 1. Health
Write-Step "1" "Health check..."
$health = Invoke-RestMethod -Uri "http://127.0.0.1:8081/health" -Method Get -TimeoutSec 5
Write-Ok "ok: $($health.ok)"
if ($health.extension_connected) {
    Write-Ok "extension_connected: True"
} else {
    Write-Err "extension_connected: False"
    Write-Host "   Kill Python, reload extension, try again." -ForegroundColor Yellow
    exit 1
}

# 2. Models
Write-Step "2" "Models..."
$models = Invoke-RestMethod -Uri "http://127.0.0.1:8081/v1/models" -Method Get -TimeoutSec 15
Write-Ok "$($models.data.Count) models"

# 3. Chat (streaming, with timeout)
Write-Step "3" "Chat (streaming, 30s timeout)..."
Write-Info "Sending 'Say hello in French' to x-preview-l..."
Write-Info "If this hangs, the captcha may be blocking. Check chat.z.ai tab."

# Write the JSON body to a temp file to avoid PowerShell escaping hell.
$bodyJson = @{
    model = "x-preview-l"
    messages = @(@{ role = "user"; content = "Say hello in French" })
    stream = $true
} | ConvertTo-Json -Depth 5 -Compress

$tempFile = [System.IO.Path]::GetTempFileName()
[System.IO.File]::WriteAllText($tempFile, $bodyJson, [System.Text.Encoding]::UTF8)

Write-Info "Body: $bodyJson"

try {
    $request = [System.Net.HttpWebRequest]::Create("http://127.0.0.1:8081/v1/chat/completions")
    $request.Method = "POST"
    $request.ContentType = "application/json"
    $request.Timeout = 30000
    $bytes = [System.IO.File]::ReadAllBytes($tempFile)
    $request.ContentLength = $bytes.Length
    $stream = $request.GetRequestStream()
    $stream.Write($bytes, 0, $bytes.Length)
    $stream.Close()

    Write-Info "Waiting for response (check chat.z.ai tab for captcha)..."

    $response = $request.GetResponse()
    $reader = New-Object System.IO.StreamReader($response.GetResponseStream())

    $fullContent = ""
    $lineNum = 0
    while (-not $reader.EndOfStream) {
        $line = $reader.ReadLine()
        $lineNum++
        if ($line -match '^data: (.+)') {
            $data = $Matches[1]
            if ($data -eq '[DONE]') {
                Write-Ok "[DONE] — stream complete"
                break
            }
            try {
                $chunk = $data | ConvertFrom-Json
                if ($chunk.error) {
                    Write-Err "Error: $($chunk.error.message)"
                    break
                }
                if ($chunk.choices[0].delta.content) {
                    $fullContent += $chunk.choices[0].delta.content
                    Write-Host -NoNewline $chunk.choices[0].delta.content
                }
            } catch {
                Write-Info "Parse error on line ${lineNum}: ${data}"
            }
        }
    }
    $reader.Close()
    $response.Close()

    if ($fullContent) {
        Write-Host ""
        Write-Ok "Got response: $fullContent"
    } else {
        Write-Err "No content received (captcha may have blocked the request)"
        Write-Info "Check the chat.z.ai tab — is there a captcha overlay?"
        Write-Info "Check the background script console for errors."
    }
} catch [System.Net.WebException] {
    if ($_.Exception.Response) {
        $respStream = $_.Exception.Response.GetResponseStream()
        $sr = New-Object System.IO.StreamReader($respStream)
        $errBody = $sr.ReadToEnd()
        Write-Err "HTTP $($_.Exception.Response.StatusCode): $errBody"
    } else {
        Write-Err "Request failed: $($_.Exception.Message)"
    }
} catch {
    Write-Err "Unexpected error: $($_.Exception.Message)"
} finally {
    Remove-Item $tempFile -ErrorAction SilentlyContinue
}

Write-Host ""
Write-Host "=== Diagnostics ===" -ForegroundColor Cyan
Write-Info "If step 3 hung or failed, check these:"
Write-Info "1. Is a chat.z.ai tab open and active?"
Write-Info "2. Is there a captcha overlay on chat.z.ai? Solve it."
Write-Info "3. Open edge://extensions → click 'service worker' under Lagestroemia"
Write-Info "   Look for [bg] log lines showing the message flow."
Write-Info "4. Open F12 on chat.z.ai → Console tab"
Write-Info "   Look for [content] log lines showing the fetch request."
