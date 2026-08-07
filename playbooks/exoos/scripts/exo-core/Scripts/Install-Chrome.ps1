#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Silently installs Google Chrome (standalone / offline installer).
.DESCRIPTION
    Downloads Google's enterprise standalone MSI and installs Chrome
    silently system-wide via msiexec.  Unlike the mini-installer stub,
    the standalone MSI is a single process so -Wait works correctly and
    there is no race condition with a spawned child installer.
    An internet connection is required to fetch the installer.
    Cleans up its own temp directory on exit.
#>

$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

# Standalone 64-bit MSI — single-process, no child spawning
$downloadUrl = 'https://dl.google.com/dl/chrome/install/googlechromestandaloneenterprise64.msi'
$tempDir     = Join-Path $env:TEMP 'ExoChrome'
$installer   = Join-Path $tempDir  'chrome_standalone_x64.msi'

function Write-Step([string]$msg) { Write-Host "[Chrome] $msg" }

try {
    # ── Prepare isolated temp directory ───────────────────────────────────────
    if (Test-Path $tempDir) { Remove-Item $tempDir -Recurse -Force -ErrorAction SilentlyContinue }
    New-Item $tempDir -ItemType Directory -Force | Out-Null

    # ── Download ──────────────────────────────────────────────────────────────
    Write-Step "Downloading Chrome standalone MSI..."
    Invoke-WebRequest -Uri $downloadUrl -OutFile $installer -UseBasicParsing

    if (-not (Test-Path $installer)) {
        throw "Download failed -- installer not found at: $installer"
    }
    Write-Step "Download complete ($('{0:N1}' -f ((Get-Item $installer).Length / 1MB)) MB)"

    # ── Install ───────────────────────────────────────────────────────────────
    # msiexec flags:
    #   /i       — install
    #   /quiet   — no UI
    #   /norestart — suppress automatic reboot
    Write-Step "Installing Chrome silently..."
    $proc = Start-Process -FilePath 'msiexec.exe' `
                          -ArgumentList @('/i', "`"$installer`"", '/quiet', '/norestart') `
                          -Wait -PassThru

    switch ($proc.ExitCode) {
        0    { Write-Step "Google Chrome installed successfully." }
        3010 { Write-Step "Google Chrome installed successfully (reboot pending)." }
        1638 { Write-Step "Google Chrome skipped (a newer version is already installed)." }
        default { throw "msiexec exited with code $($proc.ExitCode)" }
    }
}
catch {
    Write-Host "[Chrome] ERROR: $_" -ForegroundColor Red
    exit 1
}
finally {
    if (Test-Path $tempDir) {
        Remove-Item $tempDir -Recurse -Force -ErrorAction SilentlyContinue
    }
    Write-Step "Temp files removed."
}