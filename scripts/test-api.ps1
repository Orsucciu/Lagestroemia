# Test the full chain with a 2-turn conversation.
# Usage:
#   .\scripts\test-api.ps1                              # tests 0.0.0.0:8081
#   .\scripts\test-api.ps1 -ServerHost 172.21.2.177     # tests a specific host
#   .\scripts\test-api.ps1 -ServerHost 127.0.0.1        # loopback
#   .\scripts\test-api.ps1 -ApiKey librevox-...         # pass the server API key
#
# Note: $Host is a built-in PowerShell read-only variable, so we use
# $ServerHost instead.
#
# If -ApiKey is not given, the script reads $env:LAGESTROEMIA_API_KEY.
# If neither is set, requests are sent without auth (fine since auth
# is disabled by default in native_host.py — see commit 6b0df24).

param(
    [string]$ServerHost = "0.0.0.0",
    [int]$Port = 8081,
    [string]$ApiKey = $env:LAGESTROEMIA_API_KEY,
    [switch]$SkipTurns
)

$ErrorActionPreference = "Stop"

function Write-Step($num, $msg) { Write-Host "`n$num. $msg" -ForegroundColor Cyan }
function Write-Ok($msg) { Write-Host "   OK $msg" -ForegroundColor Green }
function Write-Err($msg) { Write-Host "   X  $msg" -ForegroundColor Red }
function Write-Info($msg) { Write-Host "   i  $msg" -ForegroundColor Yellow }

$BaseUrl = "http://${ServerHost}:${Port}"
Write-Host "Testing against $BaseUrl" -ForegroundColor Cyan
if ($ApiKey) {
    $keyPreview = $ApiKey.Substring(0, [Math]::Min(8, $ApiKey.Length))
    Write-Host "Using API key from -ApiKey or env var (${keyPreview}...)" -ForegroundColor DarkGray
} else {
    Write-Host "No API key set — auth is disabled by default, so this is fine." -ForegroundColor DarkGray
}

function Get-AuthHeaders {
    if ($ApiKey) { return @{ "Authorization" = "Bearer $ApiKey" } }
    return @{}
}

function Send-ChatMessage {
    param([string]$Message, [int]$TimeoutSec = 60)
    $bodyJson = @{ model = "glm-4.7"; messages = @(@{ role = "user"; content = $Message }); stream = $true } | ConvertTo-Json -Depth 5 -Compress
    $tempFile = [System.IO.Path]::GetTempFileName()
    [System.IO.File]::WriteAllText($tempFile, $bodyJson, [System.Text.Encoding]::UTF8)
    try {
        $request = [System.Net.HttpWebRequest]::Create("$BaseUrl/v1/chat/completions")
        $request.Method = "POST"
        $request.ContentType = "application/json"
        if ($ApiKey) { $request.Headers["Authorization"] = "Bearer $ApiKey" }
        $request.Timeout = ($TimeoutSec * 1000)
        $bytes = [System.IO.File]::ReadAllBytes($tempFile)
        $request.ContentLength = $bytes.Length
        $stream = $request.GetRequestStream()
        $stream.Write($bytes, 0, $bytes.Length)
        $stream.Close()
        $response = $request.GetResponse()
        $reader = New-Object System.IO.StreamReader($response.GetResponseStream())
        $fullContent = ""
        while (-not $reader.EndOfStream) {
            $line = $reader.ReadLine()
            if ($line -match '^data: (.+)') {
                $data = $Matches[1]
                if ($data -eq '[DONE]') { break }
                try {
                    $chunk = $data | ConvertFrom-Json
                    if ($chunk.choices[0].delta.content) {
                        $fullContent += $chunk.choices[0].delta.content
                        Write-Host -NoNewline $chunk.choices[0].delta.content
                    }
                } catch {}
            }
        }
        $reader.Close()
        $response.Close()
        return $fullContent
    } catch [System.Net.WebException] {
        if ($_.Exception.Response) {
            $respStream = $_.Exception.Response.GetResponseStream()
            $sr = New-Object System.IO.StreamReader($respStream)
            Write-Err "HTTP $($_.Exception.Response.StatusCode): $($sr.ReadToEnd())"
        } else { Write-Err "Request failed: $($_.Exception.Message)" }
        return $null
    } catch {
        Write-Err "Unexpected: $($_.Exception.Message)"
        return $null
    } finally {
        Remove-Item $tempFile -ErrorAction SilentlyContinue
    }
}

# 1. Health
Write-Step "1" "Health check..."
try {
    $health = Invoke-RestMethod -Uri "$BaseUrl/health" -Method Get -TimeoutSec 5
    Write-Ok "ok: $($health.ok)"
    if (-not $health.extension_connected) { Write-Err "Extension not connected! Open chat.z.ai in the browser."; exit 1 }
    Write-Ok "extension_connected: True"
} catch {
    Write-Err "Cannot reach $BaseUrl/health — is the native host running? ($($_.Exception.Message))"
    exit 1
}

# 2. Models
Write-Step "2" "Models..."
try {
    $models = Invoke-RestMethod -Uri "$BaseUrl/v1/models" -Method Get -Headers (Get-AuthHeaders) -TimeoutSec 15
    Write-Ok "$($models.data.Count) models"
    if ($models.data.Count -gt 0) {
        Write-Info "First model: $($models.data[0].id)"
    }
} catch {
    if ($_.Exception.Response.StatusCode -eq 401) {
        Write-Err "401 — API key required. Pass -ApiKey <key> or set `$env:LAGESTROEMIA_API_KEY."
    } else {
        Write-Err "Failed: $($_.Exception.Message)"
    }
    exit 1
}

if ($SkipTurns) {
    Write-Host "`n-SkipTurns set — skipping conversation test." -ForegroundColor Cyan
    exit 0
}

# 3. Turn 1
Write-Step "3" "Turn 1: 'Say hello in French'"
Write-Info "Sending..."
$reply1 = Send-ChatMessage -Message "Say hello in French" -TimeoutSec 60
Write-Host ""
if ($reply1) { Write-Ok "Reply: $reply1" } else { Write-Err "No reply" }

# 4. Turn 2
Write-Step "4" "Turn 2: 'Now say goodbye in Spanish'"
Write-Info "Sending..."
$reply2 = Send-ChatMessage -Message "Now say goodbye in Spanish" -TimeoutSec 60
Write-Host ""
if ($reply2) { Write-Ok "Reply: $reply2" } else { Write-Err "No reply" }

# 5. Summary
Write-Host "`n=== Summary ===" -ForegroundColor Cyan
Write-Info "Turn 1: $(if ($reply1) { $reply1.Substring(0, [Math]::Min(100, $reply1.Length)) } else { '(none)' })"
Write-Info "Turn 2: $(if ($reply2) { $reply2.Substring(0, [Math]::Min(100, $reply2.Length)) } else { '(none)' })"
if ($reply1 -and $reply2) { Write-Ok "Multi-turn conversation works!" }
