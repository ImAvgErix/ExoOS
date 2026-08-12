#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Installs the bundled Exo privacy hosts file (offline — no CDN).
#>
$ErrorActionPreference = 'Stop'

function Write-Step([string]$msg) { Write-Host "[Hosts] $msg" }

$candidates = @(
    (Join-Path $PSScriptRoot '..\..\..\assets\hosts'),
    (Join-Path $PSScriptRoot '..\..\..\..\assets\hosts')
)
$bundled = $candidates | Where-Object { Test-Path $_ } | Select-Object -First 1

$targetHosts = "$env:SystemRoot\System32\drivers\etc\hosts"
$backupHosts = "$env:SystemRoot\System32\drivers\etc\hosts.Exo.bak"

try {
    if (-not $bundled) {
        throw "Bundled hosts file missing (looked under playbook assets/hosts)"
    }
    Write-Step "Using bundled Exo hosts (offline): $bundled"

    if (Test-Path $targetHosts) {
        Write-Step "Backing up existing hosts to hosts.Exo.bak"
        Copy-Item -Path $targetHosts -Destination $backupHosts -Force
    }

    Copy-Item -Path $bundled -Destination $targetHosts -Force
    Write-Step "Installed $targetHosts"
    Clear-DnsClientCache
    Write-Step "DNS cache flushed"
}
catch {
    Write-Host "[Hosts] ERROR: $_" -ForegroundColor Red
    if ((Test-Path $backupHosts) -and -not (Test-Path $targetHosts)) {
        Copy-Item -Path $backupHosts -Destination $targetHosts -Force
    }
    exit 1
}
