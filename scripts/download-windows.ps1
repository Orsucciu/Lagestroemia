# Download the latest Lagestroemia Windows build from GitHub Releases.
#
# Usage (in PowerShell):
#   .\scripts\download-windows.ps1
#
# Or from cmd:
#   powershell -ExecutionPolicy Bypass -File scripts\download-windows.ps1
#
# Downloads lagestroemia-windows-x64.zip, extracts it to .\lagestroemia\,
# and prints the path to the exe.

param(
    [string]$OutputDir = "lagestroemia"
)

$ErrorActionPreference = "Stop"

$Repo = "Orsucciu/Lagestroemia"
$ReleaseTag = "latest"
$AssetName = "lagestroemia-windows-x64.zip"
$ApiUrl = "https://api.github.com/repos/$Repo/releases/tags/$ReleaseTag"

Write-Host "Fetching release info from $ApiUrl..." -ForegroundColor Cyan

# Fetch the release info to get the asset download URL.
$Release = Invoke-RestMethod -Uri $ApiUrl -Headers @{
    "User-Agent" = "lagestroemia-download-script"
}

# Find the Windows asset.
$Asset = $Release.assets | Where-Object { $_.name -eq $AssetName } | Select-Object -First 1
if (-not $Asset) {
    Write-Error "Asset '$AssetName' not found in release '$ReleaseTag'."
    Write-Host "Available assets:" -ForegroundColor Yellow
    $Release.assets | ForEach-Object { Write-Host "  $($_.name)" }
    exit 1
}

Write-Host "Found: $($Asset.name) ($([math]::Round($Asset.size / 1MB, 1)) MB)" -ForegroundColor Green

# Download the zip.
$ZipPath = "$AssetName"
$DownloadUrl = $Asset.browser_download_url
Write-Host "Downloading from $DownloadUrl..." -ForegroundColor Cyan

# GitHub releases redirect to a CDN, so we need -MaximumRedirection.
Invoke-WebRequest -Uri $DownloadUrl -OutFile $ZipPath -UseBasicParsing -MaximumRedirection 10

Write-Host "Downloaded to $ZipPath" -ForegroundColor Green

# Extract.
if (Test-Path $OutputDir) {
    Write-Host "Removing existing $OutputDir directory..." -ForegroundColor Yellow
    Remove-Item -Recurse -Force $OutputDir
}

Write-Host "Extracting to $OutputDir..." -ForegroundColor Cyan
Expand-Archive -Path $ZipPath -DestinationPath $OutputDir -Force

# Find the exe.
$Exe = Get-ChildItem -Path $OutputDir -Filter "lagestroemia.exe" -Recurse | Select-Object -First 1
if ($Exe) {
    Write-Host ""
    Write-Host "=== Done! ===" -ForegroundColor Green
    Write-Host "Run the app with:" -ForegroundColor Green
    Write-Host "  & '$($Exe.FullName)'" -ForegroundColor White
    Write-Host ""
    Write-Host "Or double-click: $($Exe.FullName)" -ForegroundColor Gray
} else {
    Write-Host "Extraction complete, but lagestroemia.exe was not found." -ForegroundColor Yellow
    Write-Host "Check the contents of $OutputDir" -ForegroundColor Gray
}
