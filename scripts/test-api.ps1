# Test the Lagestroemia local API server.
# Usage: .\scripts\test-api.ps1
#
# Sends a chat completion request to localhost:8081 and prints
# the streaming response. No curl quoting issues — uses PowerShell's
# Invoke-RestMethod which handles JSON natively.

$ErrorActionPreference = "Stop"

Write-Host "1. Health check..." -ForegroundColor Cyan
$health = Invoke-RestMethod -Uri "http://127.0.0.1:8081/health" -Method Get
Write-Host "   ok: $($health.ok)" -ForegroundColor Green
Write-Host "   extension_connected: $($health.extension_connected)" -ForegroundColor Green

if (-not $health.extension_connected) {
    Write-Host ""
    Write-Host "ERROR: Extension is not connected!" -ForegroundColor Red
    Write-Host "Make sure:" -ForegroundColor Yellow
    Write-Host "  1. The extension is loaded in Edge"
    Write-Host "  2. You reloaded it after running install-native.ps1"
    Write-Host "  3. A chat.z.ai tab is open"
    Write-Host "  4. The badge on chat.z.ai is green"
    exit 1
}

Write-Host ""
Write-Host "2. Models..." -ForegroundColor Cyan
$models = Invoke-RestMethod -Uri "http://127.0.0.1:8081/v1/models" -Method Get
Write-Host "   $($models.data.Count) models available" -ForegroundColor Green
$models.data | ForEach-Object { Write-Host "   - $($_.id)" }

Write-Host ""
Write-Host "3. Chat (non-streaming)..." -ForegroundColor Cyan

$body = @{
    model = "glm-4.7"
    messages = @(
        @{
            role = "user"
            content = "Say hello in one sentence."
        }
    )
    stream = $false
} | ConvertTo-Json -Depth 5

try {
    $response = Invoke-RestMethod -Uri "http://127.0.0.1:8081/v1/chat/completions" `
        -Method Post `
        -ContentType "application/json" `
        -Body $body `
        -TimeoutSec 120

    Write-Host "   Response:" -ForegroundColor Green
    Write-Host "   $($response.choices[0].message.content)" -ForegroundColor White
} catch {
    Write-Host "   Error: $($_.Exception.Message)" -ForegroundColor Red
    if ($_.ErrorDetails.Message) {
        Write-Host "   Details: $($_.ErrorDetails.Message)" -ForegroundColor Yellow
    }
}

Write-Host ""
Write-Host "4. Chat (streaming)..." -ForegroundColor Cyan

$body = @{
    model = "glm-4.7"
    messages = @(
        @{
            role = "user"
            content = "Count from 1 to 5."
        }
    )
    stream = $true
} | ConvertTo-Json -Depth 5

try {
    $request = [System.Net.HttpWebRequest]::Create("http://127.0.0.1:8081/v1/chat/completions")
    $request.Method = "POST"
    $request.ContentType = "application/json"
    $request.Timeout = 120000
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($body)
    $request.ContentLength = $bytes.Length
    $stream = $request.GetRequestStream()
    $stream.Write($bytes, 0, $bytes.Length)
    $stream.Close()

    $response = $request.GetResponse()
    $reader = New-Object System.IO.StreamReader($response.GetResponseStream())
    Write-Host "   Streaming response:" -ForegroundColor Green
    while (-not $reader.EndOfStream) {
        $line = $reader.ReadLine()
        if ($line -match '^data: (.+)') {
            $data = $Matches[1]
            if ($data -eq '[DONE]') {
                Write-Host "" -ForegroundColor Green
                Write-Host "   [DONE]" -ForegroundColor Green
                break
            }
            try {
                $chunk = $data | ConvertFrom-Json
                if ($chunk.choices[0].delta.content) {
                    Write-Host -NoNewline $chunk.choices[0].delta.content
                }
            } catch {}
        }
    }
    $reader.Close()
    $response.Close()
} catch {
    Write-Host "   Error: $($_.Exception.Message)" -ForegroundColor Red
}
