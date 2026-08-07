#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Sets DNS servers to Google Public DNS (8.8.8.8 / 8.8.4.4) on all active physical adapters.
.DESCRIPTION
    Google Public DNS is one of the most reliable and globally distributed public resolvers.
    It offers strong uptime, supports DNSSEC validation, and is well-suited for general use.

    Changes take effect immediately — no adapter restart required.
    The DNS cache is flushed so cached entries from the previous server are evicted.
#>

$ErrorActionPreference = 'Stop'

function Write-Step([string]$msg) { Write-Host "[DNS] $msg" }

try {
    $primary   = '8.8.8.8'
    $secondary = '8.8.4.4'

    # Target all active, physical (non-virtual, non-loopback) adapters
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

    # Flush the DNS resolver cache — evicts stale entries from the old server.
    # This is an in-memory operation; it does NOT restart the adapter or disrupt connections.
    Write-Step "Flushing DNS resolver cache..."
    Clear-DnsClientCache
    Write-Step "DNS cache flushed."

    Write-Step "Google Public DNS applied successfully ($primary / $secondary)."
}
catch {
    Write-Host "[DNS] ERROR: $_" -ForegroundColor Red
    exit 1
}
