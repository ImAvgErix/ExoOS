#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Downloads and installs the Exo privacy hosts file from the CDN.
.DESCRIPTION
    Fetches the hosts file from cdn.getnexus.cc and installs it to
    %SystemRoot%\System32\drivers\etc\hosts, blocking Microsoft telemetry,
    Watson diagnostics, Brave analytics and other tracking endpoints.

    The existing hosts file is backed up first. The DNS cache is flushed
    after install so blocked domains take effect immediately.
#>

$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

function Write-Step([string]$msg) { Write-Host "[Hosts] $msg" }

$hostsUrl   = 'https://cdn.getnexus.cc/Assets/hosts'
$targetHosts = "$env:SystemRoot\System32\drivers\etc\hosts"
$backupHosts = "$env:SystemRoot\System32\drivers\etc\hosts.Exo.bak"
$tempPath    = Join-Path $env:SystemRoot 'Temp\nexus_hosts'

try {
    # ── Download ──────────────────────────────────────────────────────────────────
    Write-Step "Downloading hosts file from CDN..."
    Invoke-WebRequest -Uri $hostsUrl -OutFile $tempPath -UseBasicParsing

    if (-not (Test-Path $tempPath)) {
        throw "Download completed but file was not found at: $tempPath"
    }
    Write-Step "Download complete."

    # ── Backup existing hosts file ────────────────────────────────────────────────
    if (Test-Path $targetHosts) {
        Write-Step "Backing up existing hosts file to hosts.Exo.bak..."
        Copy-Item -Path $targetHosts -Destination $backupHosts -Force
    }

    # ── Install ───────────────────────────────────────────────────────────────────
    Write-Step "Installing Exo privacy hosts file..."
    Copy-Item -Path $tempPath -Destination $targetHosts -Force
    Write-Step "Hosts file installed at: $targetHosts"

    # ── Flush DNS cache ───────────────────────────────────────────────────────────
    # In-memory operation — does not restart the adapter or affect active connections.
    Write-Step "Flushing DNS resolver cache..."
    Clear-DnsClientCache
    Write-Step "DNS cache flushed. Blocked domains are effective immediately."

    Write-Step "Privacy hosts file applied successfully."
}
catch {
    Write-Host "[Hosts] ERROR: $_" -ForegroundColor Red

    # If install failed mid-way and hosts file is gone, restore the backup
    if ((Test-Path $backupHosts) -and -not (Test-Path $targetHosts)) {
        Write-Host "[Hosts] Restoring backup..." -ForegroundColor Yellow
        Copy-Item -Path $backupHosts -Destination $targetHosts -Force
    }

    exit 1
}
finally {
    Remove-Item $tempPath -Force -ErrorAction SilentlyContinue
}
