#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Sets DNS servers to Quad9 (9.9.9.9 / 149.112.112.112) on all active physical adapters.
.DESCRIPTION
    Quad9 is a non-profit, security-focused public DNS resolver that blocks access to
    known malicious domains using threat intelligence from 19+ sources. It does not
    log personally identifiable information and is DNSSEC-enabled.

    Changes take effect immediately — no adapter restart required.
    The DNS cache is flushed so cached entries from the previous server are evicted.
#>

$ErrorActionPreference = 'Stop'

function Write-Step([string]$msg) { Write-Host "[DNS] $msg" }

try {
    $primary   = '9.9.9.9'
    $secondary = '149.112.112.112'

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

    Write-Step "Quad9 DNS applied successfully ($primary / $secondary)."
}
catch {
    Write-Host "[DNS] ERROR: $_" -ForegroundColor Red
    exit 1
}
