# Register the Lagestroemia native messaging host on Windows.
#
# Usage (in PowerShell as administrator):
#   .\scripts\install-native.ps1
#
# Or from cmd:
#   powershell -ExecutionPolicy Bypass -File scripts\install-native.ps1

param(
    [string]$Browser = "chrome"
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

# Create a wrapper batch script (Chrome on Windows needs an .exe or .bat).
$WrapperBat = Join-Path $ExtDir "native_host_wrapper.bat"
@"
@echo off
"$PythonExe" "$NativeHostPath"
"@ | Set-Content $WrapperBat -Encoding ASCII

# The native messaging host manifest.
$Manifest = @{
    name = "lagestroemia"
    description = "Lagestroemia local proxy server for chat.z.ai"
    path = $WrapperBat
    type = "stdio"
    allowed_extensions = @("lagestroemia@orsucciu.github.io")
} | ConvertTo-Json -Depth 5

# Determine the registry key based on the browser.
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
$ManifestFile = Join-Path $ExtDir "lagestroemia_native_manifest.json"
$Manifest | Set-Content $ManifestFile -Encoding UTF8

if (-not (Test-Path $RegKey)) {
    New-Item -Path $RegKey -Force | Out-Null
}
Set-ItemProperty -Path $RegKey -Name "(Default)" -Value $ManifestFile

Write-Host "✅ Native messaging host registered for $Browser" -ForegroundColor Green
Write-Host "   Manifest: $ManifestFile"
Write-Host "   Wrapper:  $WrapperBat"
Write-Host "   Registry: $RegKey"
Write-Host ""
Write-Host "The local HTTP server will start automatically when the extension"
Write-Host "connects. It listens on http://127.0.0.1:8081"
Write-Host ""
Write-Host "Test with:"
Write-Host "  curl http://127.0.0.1:8081/health"
Write-Host "  curl http://127.0.0.1:8081/v1/models"
