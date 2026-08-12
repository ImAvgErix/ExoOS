#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Sets DNS on all active physical adapters (Cloudflare, Google, or Quad9).
#>
param(
    [Parameter(Mandatory = $true, Position = 0)]
    [ValidateSet('Cloudflare', 'Google', 'Quad9')]
    [string]$Provider
)

$ErrorActionPreference = 'Stop'

$servers = @{
    Cloudflare = @{ Primary = '1.1.1.1'; Secondary = '1.0.0.1'; Label = 'Cloudflare DNS' }
    Google     = @{ Primary = '8.8.8.8'; Secondary = '8.8.4.4'; Label = 'Google Public DNS' }
    Quad9      = @{ Primary = '9.9.9.9'; Secondary = '149.112.112.112'; Label = 'Quad9 DNS' }
}[$Provider]

$primary = $servers.Primary
$secondary = $servers.Secondary

function Write-Step([string]$msg) { Write-Host "[DNS] $msg" }

try {
    $adapters = Get-NetAdapter |
        Where-Object { $_.Status -eq 'Up' -and $_.InterfaceDescription -notmatch 'Virtual|Loopback|Teredo|ISATAP|6to4' }

    if (-not $adapters) {
        Write-Step "No active physical adapters found. DNS settings unchanged."
        exit 0
    }

    foreach ($adapter in $adapters) {
        Write-Step "Configuring '$($adapter.Name)' ($($adapter.InterfaceDescription))..."
        try {
            Set-DnsClientServerAddress -InterfaceIndex $adapter.InterfaceIndex `
                                       -ServerAddresses @($primary, $secondary) `
                                       -ErrorAction Stop
            Write-Step "  -> Set: $primary, $secondary"
        }
        catch {
            Write-Host "[DNS] WARNING: Could not set DNS on '$($adapter.Name)': $_" -ForegroundColor Yellow
        }
    }

    Write-Step "Flushing DNS resolver cache..."
    Clear-DnsClientCache
    Write-Step "$($servers.Label) applied ($primary / $secondary)."
}
catch {
    Write-Host "[DNS] ERROR: $_" -ForegroundColor Red
    exit 1
}
