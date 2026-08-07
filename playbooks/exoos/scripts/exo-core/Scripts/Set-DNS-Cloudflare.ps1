#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Sets DNS servers to Cloudflare (1.1.1.1 / 1.0.0.1) on all active physical adapters.
.DESCRIPTION
    Cloudflare DNS is one of the fastest and most privacy-respecting public resolvers.
    It does not log or sell your query data and supports DNSSEC.

    Changes take effect immediately — no adapter restart required.
    The DNS cache is flushed so cached entries from the previous server are evicted.
#>

$ErrorActionPreference = 'Stop'

function Write-Step([string]$msg) { Write-Host "[DNS] $msg" }

try {
    $primary   = '1.1.1.1'
    $secondary = '1.0.0.1'

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

    Write-Step "Cloudflare DNS applied successfully ($primary / $secondary)."
}
catch {
    Write-Host "[DNS] ERROR: $_" -ForegroundColor Red
    exit 1
}
