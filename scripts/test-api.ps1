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
    [switch]$SkipTurns,
    [switch]$NoColor
)

$ErrorActionPreference = "Stop"

function Write-Step($num, $msg) { if (-not $NoColor) { Write-Host "`n$num. $msg" -ForegroundColor Cyan } else { Write-Host "`n$num. $msg" } }
function Write-Ok($msg) { if (-not $NoColor) { Write-Host "   OK $msg" -ForegroundColor Green } else { Write-Host "   OK $msg" } }
function Write-Err($msg) { if (-not $NoColor) { Write-Host "   X  $msg" -ForegroundColor Red } else { Write-Host "   X  $msg" } }
function Write-Info($msg) { if (-not $NoColor) { Write-Host "   i  $msg" -ForegroundColor Yellow } else { Write-Host "   i  $msg" } }

# Dark gray for thinking — visible but visually distinct from the answer.
function Write-Thinking($msg) { if (-not $NoColor) { Write-Host -NoNewline $msg -ForegroundColor DarkGray } else { Write-Host -NoNewline $msg } }
# White (default) for the answer.
function Write-Answer($msg) { Write-Host -NoNewline $msg }

$BaseUrl = "http://${ServerHost}:${Port}"
Write-Host "Testing against $BaseUrl" -ForegroundColor $(if ($NoColor) { 'White' } else { 'Cyan' })
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
    param([string]$Message, [int]$TimeoutSec = 120)

    # Request thinking explicitly via the body. The native host
    # forwards 'reasoning_effort' and translates it to the extension's
    # 'thinking' flag. chat.z.ai's UI shows a "Thought Process"
    # section when this is enabled.
    $bodyObj = @{
        model = "glm-4.7"
        messages = @(@{ role = "user"; content = $Message })
        stream = $true
        reasoning_effort = "high"
    }
    $bodyJson = $bodyObj | ConvertTo-Json -Depth 5 -Compress
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
        $fullReasoning = ""
        $inThinkingSection = $false
        $inAnswerSection = $false
        $chunkCount = 0
        $reasoningChunkCount = 0
        $contentChunkCount = 0

        while (-not $reader.EndOfStream) {
            $line = $reader.ReadLine()
            if ($line -match '^data: (.+)') {
                $data = $Matches[1]
                if ($data -eq '[DONE]') { break }
                try {
                    $chunk = $data | ConvertFrom-Json
                    $delta = $chunk.choices[0].delta
                    $chunkCount++

                    # Reasoning content (thinking).
                    if ($delta.reasoning_content) {
                        if (-not $inThinkingSection) {
                            $inThinkingSection = $true
                            Write-Host ""
                            Write-Host "   --- Thinking ---" -ForegroundColor $(if ($NoColor) { 'White' } else { 'DarkGray' })
                            Write-Host "   " -NoNewline -ForegroundColor $(if ($NoColor) { 'White' } else { 'DarkGray' })
                        }
                        $fullReasoning += $delta.reasoning_content
                        Write-Thinking $delta.reasoning_content
                        $reasoningChunkCount++
                    }

                    # Regular content (answer).
                    if ($delta.content) {
                        if ($inThinkingSection -and -not $inAnswerSection) {
                            $inAnswerSection = $true
                            Write-Host ""
                            Write-Host "   --- Answer ---" -ForegroundColor $(if ($NoColor) { 'White' } else { 'Green' })
                            Write-Host "   " -NoNewline
                        }
                        $fullContent += $delta.content
                        Write-Answer $delta.content
                        $contentChunkCount++
                    }
                } catch {}
            }
        }
        $reader.Close()
        $response.Close()
        Write-Host ""  # newline after the streamed output

        return @{
            Content = $fullContent
            Reasoning = $fullReasoning
            ChunkCount = $chunkCount
            ReasoningChunkCount = $reasoningChunkCount
            ContentChunkCount = $contentChunkCount
        }
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

# 3. Turn 1 — a question that benefits from thinking
Write-Step "3" "Turn 1: 'Explain quantum entanglement in 2 sentences.'"
Write-Info "Sending (reasoning_effort=high)..."
$reply1 = Send-ChatMessage -Message "Explain quantum entanglement in 2 sentences." -TimeoutSec 120
Write-Host ""
if ($reply1) {
    Write-Ok "Total chunks: $($reply1.ChunkCount) (reasoning: $($reply1.ReasoningChunkCount), content: $($reply1.ContentChunkCount))"
    if ($reply1.Reasoning) {
        Write-Ok "Reasoning captured ($($reply1.Reasoning.Length) chars)"
    } else {
        Write-Info "No reasoning captured — model may not have produced thinking for this prompt"
    }
    if ($reply1.Content) {
        Write-Ok "Content captured ($($reply1.Content.Length) chars)"
    } else {
        Write-Err "No content captured"
    }
} else {
    Write-Err "No reply"
}

# 4. Turn 2 — a follow-up that requires the context from turn 1
Write-Step "4" "Turn 2: 'Now explain it like I'm 5.'"
Write-Info "Sending (reasoning_effort=high)..."
$reply2 = Send-ChatMessage -Message "Now explain it like I'm 5." -TimeoutSec 120
Write-Host ""
if ($reply2) {
    Write-Ok "Total chunks: $($reply2.ChunkCount) (reasoning: $($reply2.ReasoningChunkCount), content: $($reply2.ContentChunkCount))"
    if ($reply2.Reasoning) {
        Write-Ok "Reasoning captured ($($reply2.Reasoning.Length) chars)"
    } else {
        Write-Info "No reasoning captured — model may not have produced thinking for this prompt"
    }
    if ($reply2.Content) {
        Write-Ok "Content captured ($($reply2.Content.Length) chars)"
    } else {
        Write-Err "No content captured"
    }
} else {
    Write-Err "No reply"
}

# 5. Summary
Write-Host "`n=== Summary ===" -ForegroundColor Cyan
if ($reply1 -and $reply2) {
    Write-Ok "Both turns returned responses."
    Write-Host ""
    Write-Host "Turn 1 thinking (first 200 chars):" -ForegroundColor $(if ($NoColor) { 'White' } else { 'DarkGray' })
    if ($reply1.Reasoning) {
        Write-Host "   $($reply1.Reasoning.Substring(0, [Math]::Min(200, $reply1.Reasoning.Length)))" -ForegroundColor $(if ($NoColor) { 'White' } else { 'DarkGray' })
    } else {
        Write-Info "   (none)"
    }
    Write-Host ""
    Write-Host "Turn 1 answer (first 200 chars):" -ForegroundColor Green
    if ($reply1.Content) {
        Write-Host "   $($reply1.Content.Substring(0, [Math]::Min(200, $reply1.Content.Length)))" -ForegroundColor Green
    } else {
        Write-Err "   (none)"
    }
    Write-Host ""
    Write-Host "Turn 2 thinking (first 200 chars):" -ForegroundColor $(if ($NoColor) { 'White' } else { 'DarkGray' })
    if ($reply2.Reasoning) {
        Write-Host "   $($reply2.Reasoning.Substring(0, [Math]::Min(200, $reply2.Reasoning.Length)))" -ForegroundColor $(if ($NoColor) { 'White' } else { 'DarkGray' })
    } else {
        Write-Info "   (none)"
    }
    Write-Host ""
    Write-Host "Turn 2 answer (first 200 chars):" -ForegroundColor Green
    if ($reply2.Content) {
        Write-Host "   $($reply2.Content.Substring(0, [Math]::Min(200, $reply2.Content.Length)))" -ForegroundColor Green
    } else {
        Write-Err "   (none)"
    }
    Write-Host ""
    if ($reply1.Reasoning -and $reply2.Reasoning) {
        Write-Ok "Thinking captured on BOTH turns — reasoning_content is working!"
    } elseif ($reply1.Reasoning -or $reply2.Reasoning) {
        Write-Info "Thinking captured on at least one turn — partial success."
    } else {
        Write-Err "No thinking captured on either turn. Check that the model has 'Deep Think' enabled in chat.z.ai, or that reasoning_effort=high is being honored."
    }
}
