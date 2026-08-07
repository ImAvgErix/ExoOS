#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Silently installs 7-Zip.
.DESCRIPTION
    Downloads the 7-Zip installer (.exe) from the Exo content CDN and installs it
    silently with no UI and no desktop shortcut.
    Cleans up temp files on exit.
#>

$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$cdnUrl    = 'https://cdn.getnexus.cc/Assets/7z-x64.exe'
$tempDir   = Join-Path $env:TEMP '7Zip'
$installer = Join-Path $tempDir  '7zip_installer.exe'

function Write-Step([string]$msg) { Write-Host "[7-Zip] $msg" }

try {
    # Prepare temp directory
    if (Test-Path $tempDir) { Remove-Item $tempDir -Recurse -Force }
    New-Item $tempDir -ItemType Directory -Force | Out-Null

    # Download
    Write-Step "Downloading 7-Zip installer..."
    Invoke-WebRequest -Uri $cdnUrl -OutFile $installer -UseBasicParsing

    if (-not (Test-Path $installer)) {
        throw "Download failed -- installer not found at: $installer"
    }
    Write-Step "Download complete ($( '{0:N1}' -f ((Get-Item $installer).Length / 1MB) ) MB)"

    # Install
    # 7-Zip's NSIS-based EXE installer accepts /S for fully silent install.
    # It does not create a desktop shortcut by default.
    Write-Step "Installing 7-Zip silently..."
    $proc = Start-Process -FilePath $installer -ArgumentList '/S' -Wait -PassThru

    switch ($proc.ExitCode) {
        0       { Write-Step "7-Zip installed successfully." }
        default { throw "Installer exited with code $($proc.ExitCode)" }
    }
}
catch {
    Write-Host "[7-Zip] ERROR: $_" -ForegroundColor Red
    exit 1
}
finally {
    if (Test-Path $tempDir) {
        Remove-Item $tempDir -Recurse -Force -ErrorAction SilentlyContinue
    }
    Write-Step "Temp files removed."
}
