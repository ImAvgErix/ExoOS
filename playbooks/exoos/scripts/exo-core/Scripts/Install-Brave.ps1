#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Silently installs the Brave Browser (standalone / offline installer).
.DESCRIPTION
    Downloads BraveBrowserStandaloneSetup.exe from Brave's official CDN and
    runs it silently.  Unlike BraveBrowserSetup.exe (the online stub), the
    standalone build is a single self-contained process — -Wait works correctly
    and there is no race condition with a spawned child installer.
    An internet connection is required to fetch the installer.
    Cleans up its own temp directory on exit.
#>

$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

# Standalone (offline) installer — single-process, no child spawning
$downloadUrl = 'https://brave-browser-downloads.s3.brave.com/latest/BraveBrowserStandaloneSetup.exe'
$tempDir     = Join-Path $env:TEMP 'ExoBrave'
$installer   = Join-Path $tempDir  'BraveBrowserStandaloneSetup.exe'

function Write-Step([string]$msg) { Write-Host "[Brave] $msg" }

try {
    # ── Prepare isolated temp directory ──────────────────────────────────────
    if (Test-Path $tempDir) { Remove-Item $tempDir -Recurse -Force -ErrorAction SilentlyContinue }
    New-Item $tempDir -ItemType Directory -Force | Out-Null

    # ── Download ──────────────────────────────────────────────────────────────
    Write-Step "Downloading Brave standalone installer..."
    Invoke-WebRequest -Uri $downloadUrl -OutFile $installer -UseBasicParsing

    if (-not (Test-Path $installer)) {
        throw "Download failed -- installer not found at: $installer"
    }
    Write-Step "Download complete ($('{0:N1}' -f ((Get-Item $installer).Length / 1MB)) MB)"

    # ── Install ───────────────────────────────────────────────────────────────
    # Chromium installer flags:
    #   /silent  — no UI
    #   /install — required alongside /silent
    Write-Step "Installing Brave silently..."
    $proc = Start-Process -FilePath $installer `
                          -ArgumentList @('/silent', '/install') `
                          -Wait -PassThru

    switch ($proc.ExitCode) {
        0    { Write-Step "Brave Browser installed successfully." }
        3010 { Write-Step "Brave Browser installed successfully (reboot pending)." }
        19   { Write-Step "Brave Browser skipped (already up to date)." }
        default { throw "Brave installer exited with code $($proc.ExitCode)" }
    }
}
catch {
    Write-Host "[Brave] ERROR: $_" -ForegroundColor Red
    exit 1
}
finally {
    if (Test-Path $tempDir) {
        Remove-Item $tempDir -Recurse -Force -ErrorAction SilentlyContinue
    }
    Write-Step "Temp files removed."
}