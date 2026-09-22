# Register the Lagestroemia native messaging host on Windows.
#
# Usage:
#   .\scripts\install-native.ps1 -Browser chrome -ExtensionId <id>
#   .\scripts\install-native.ps1 -Browser edge   -ExtensionId <id>
#   .\scripts\install-native.ps1 -Browser firefox
#
# For Chrome/Edge, find the extension ID on chrome://extensions after
# loading the unpacked extension. For Firefox, the ID is in the manifest.

param(
    [Parameter(Mandatory=$true)]
    [string]$Browser,

    [string]$ExtensionId
)

$ErrorActionPreference = "Stop"

$ExtDir = Resolve-Path "$PSScriptRoot\..\extension"
$NativeHostPath = Join-Path $ExtDir "native_host.py"
$PythonExe = (Get-Command python -ErrorAction SilentlyContinue).Source
if (-not $PythonExe) {
    $PythonExe = (Get-Command python3 -ErrorAction SilentlyContinue).Source
}
if (-not $PythonExe) {
    Write-Error "Python not found. Install Python 3 and add it to your PATH."
    exit 1
}

# Create a wrapper batch script.
# The wrapper sets env vars that native_host.py reads on startup.
# Uncomment + edit to enable LAN/remote access:
#   set LAGESTROEMIA_HOST=0.0.0.0   binds to all IPv4 interfaces
#   set LAGESTROEMIA_API_KEY=...    REQUIRED when host is non-loopback
$WrapperBat = Join-Path $ExtDir "native_host_wrapper.bat"
@"
@echo off
REM Lagestroemia native host wrapper.
REM
REM To enable LAN/remote access (opencode on another machine, etc.):
REM   1. Uncomment the LAGESTROEMIA_HOST line below and set it to 0.0.0.0
REM      (or a specific IP like 192.168.1.50).
REM   2. Uncomment LAGESTROEMIA_API_KEY and set it to a secret string.
REM      The server REFUSES to bind non-loopback without a key.
REM   3. Reload the browser extension.
REM set LAGESTROEMIA_HOST=0.0.0.0
REM set LAGESTROEMIA_API_KEY=change-me
"$PythonExe" "$NativeHostPath"
"@ | Set-Content $WrapperBat -Encoding ASCII

# For Firefox, use the extension ID from the manifest.
if ($Browser -eq "firefox") {
    $ExtensionId = "lagestroemia@orsucciu.github.io"
}

# For Chrome/Edge, ask for the extension ID if not provided.
if ($Browser -ne "firefox" -and -not $ExtensionId) {
    Write-Host ""
    Write-Host "To find the extension ID:" -ForegroundColor Cyan
    Write-Host "  1. Open chrome://extensions (or edge://extensions)"
    Write-Host "  2. Enable Developer mode"
    Write-Host "  3. Load the extension\ directory"
    Write-Host "  4. Copy the ID (a 32-char string like abcdefghijklmnopqrstuvwxyz123456)"
    Write-Host ""
    $ExtensionId = Read-Host "Paste the extension ID"
}

if (-not $ExtensionId) {
    Write-Error "Extension ID is required for $Browser"
    exit 1
}

# Build the manifest.
$ManifestPath = Join-Path $ExtDir "lagestroemia_native_manifest.json"

if ($Browser -eq "firefox") {
    $Manifest = @{
        name = "lagestroemia"
        description = "Lagestroemia local proxy server for chat.z.ai"
        path = $WrapperBat
        type = "stdio"
        allowed_extensions = @($ExtensionId)
    } | ConvertTo-Json -Depth 5
} else {
    $Manifest = @{
        name = "lagestroemia"
        description = "Lagestroemia local proxy server for chat.z.ai"
        path = $WrapperBat
        type = "stdio"
        allowed_origins = @("chrome-extension://$ExtensionId/")
    } | ConvertTo-Json -Depth 5
}

# Write manifest without BOM (Chrome/Edge reject JSON with BOM).
[System.IO.File]::WriteAllText($ManifestPath, $Manifest, [System.Text.UTF8Encoding]::new($false))

# Determine the registry key.
switch ($Browser) {
    "chrome" {
        $RegKey = "HKCU:\Software\Google\Chrome\NativeMessagingHosts\lagestroemia"
    }
    "edge" {
        $RegKey = "HKCU:\Software\Microsoft\Edge\NativeMessagingHosts\lagestroemia"
    }
    "firefox" {
        $RegKey = "HKCU:\Software\Mozilla\NativeMessagingHosts\lagestroemia"
    }
    default {
        Write-Error "Unknown browser: $Browser (use chrome, edge, or firefox)"
        exit 1
    }
}

# Create the registry key and set the default value to the manifest path.
if (-not (Test-Path $RegKey)) {
    New-Item -Path $RegKey -Force | Out-Null
}
Set-ItemProperty -Path $RegKey -Name "(Default)" -Value $ManifestPath

Write-Host ""
Write-Host "✅ Native messaging host registered for $Browser" -ForegroundColor Green
Write-Host "   Manifest: $ManifestPath"
Write-Host "   Wrapper:  $WrapperBat"
Write-Host "   Registry: $RegKey"
Write-Host "   Extension ID: $ExtensionId"
Write-Host ""
Write-Host "The local HTTP server will start automatically when the extension"
Write-Host "connects. By default it listens on http://127.0.0.1:8081 (loopback only)."
Write-Host ""
Write-Host "To enable LAN/remote access (opencode on another machine):" -ForegroundColor Cyan
Write-Host "  1. Edit: $WrapperBat"
Write-Host "  2. Uncomment: set LAGESTROEMIA_HOST=0.0.0.0"
Write-Host "  3. Uncomment: set LAGESTROEMIA_API_KEY=<your-secret>"
Write-Host "  4. Reload the extension."
Write-Host ""
Write-Host "After reloading the extension, check:" -ForegroundColor Cyan
Write-Host "  curl http://127.0.0.1:8081/health"
Write-Host ""
Write-Host "You should see a 🌺 badge on chat.z.ai saying 'Server on :8081'" -ForegroundColor Cyan
