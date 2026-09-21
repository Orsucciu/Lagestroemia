# Test the full chain with a 2-turn conversation.
# Usage: .\scripts\test-api.ps1

$ErrorActionPreference = "Stop"

function Write-Step($num, $msg) { Write-Host "`n$num. $msg" -ForegroundColor Cyan }
function Write-Ok($msg) { Write-Host "   OK $msg" -ForegroundColor Green }
function Write-Err($msg) { Write-Host "   X  $msg" -ForegroundColor Red }
function Write-Info($msg) { Write-Host "   i  $msg" -ForegroundColor Yellow }

function Send-ChatMessage {
    param([string]$Message, [int]$TimeoutSec = 60)
    $bodyJson = @{ model = "x-preview-l"; messages = @(@{ role = "user"; content = $Message }); stream = $true } | ConvertTo-Json -Depth 5 -Compress
    $tempFile = [System.IO.Path]::GetTempFileName()
    [System.IO.File]::WriteAllText($tempFile, $bodyJson, [System.Text.Encoding]::UTF8)
    try {
        $request = [System.Net.HttpWebRequest]::Create("http://127.0.0.1:8081/v1/chat/completions")
        $request.Method = "POST"
        $request.ContentType = "application/json"
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
$health = Invoke-RestMethod -Uri "http://127.0.0.1:8081/health" -Method Get -TimeoutSec 5
Write-Ok "ok: $($health.ok)"
if (-not $health.extension_connected) { Write-Err "Not connected!"; exit 1 }
Write-Ok "extension_connected: True"

# 2. Models
Write-Step "2" "Models..."
$models = Invoke-RestMethod -Uri "http://127.0.0.1:8081/v1/models" -Method Get -TimeoutSec 15
Write-Ok "$($models.data.Count) models"

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
