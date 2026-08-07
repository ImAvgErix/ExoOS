#Requires -RunAsAdministrator
<#
.SYNOPSIS
  Installs Riot Client (used by Valorant, League, TFT).
.DESCRIPTION
  Winget only ships region-specific League installers. We download the official
  Valorant/live channel installer, which installs the shared Riot Client.
#>
$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

function Write-Step([string]$msg) { Write-Host "[Riot] $msg" }

# Already present?
$paths = @(
    "$env:ProgramFiles\Riot Games\Riot Client\RiotClientServices.exe",
    "${env:ProgramFiles(x86)}\Riot Games\Riot Client\RiotClientServices.exe",
    "$env:LOCALAPPDATA\Riot Games\Riot Client\RiotClientServices.exe"
)
if ($paths | Where-Object { Test-Path $_ }) {
    Write-Step "Riot Client already installed — skip."
    exit 0
}

$tempDir = Join-Path $env:TEMP 'ExoRiot'
$installer = Join-Path $tempDir 'RiotClientInstaller.exe'
# Official live channel installer (installs Riot Client)
$url = 'https://valorant.secure.dyn.riotcdn.net/channels/public/x/installer/current/live.live.na.exe'

try {
    if (Test-Path $tempDir) { Remove-Item $tempDir -Recurse -Force -ErrorAction SilentlyContinue }
    New-Item $tempDir -ItemType Directory -Force | Out-Null

    Write-Step "Downloading Riot Client installer..."
    Invoke-WebRequest -Uri $url -OutFile $installer -UseBasicParsing
    if (-not (Test-Path $installer)) { throw "Download failed" }

    Write-Step "Starting installer (may show a brief UI)..."
    # Product installers accept --skip-to-install on recent builds
    $proc = Start-Process -FilePath $installer -ArgumentList '--skip-to-install' -Wait -PassThru
    if ($proc.ExitCode -ne 0 -and $proc.ExitCode -ne $null) {
        Write-Step "Retry without flags..."
        $proc = Start-Process -FilePath $installer -Wait -PassThru
    }
    Write-Step "Installer finished (exit $($proc.ExitCode))."
    exit 0
}
catch {
    Write-Host "[Riot] ERROR: $_" -ForegroundColor Red
    exit 1
}
finally {
    if (Test-Path $tempDir) {
        Remove-Item $tempDir -Recurse -Force -ErrorAction SilentlyContinue
    }
}
