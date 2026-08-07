# ExoOS - disable Nagle on all IPv4 interfaces (Exo)
$ErrorActionPreference = 'SilentlyContinue'
$base = 'HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters\Interfaces'
Get-ChildItem $base | ForEach-Object {
    $p = $_.PSPath
    # Only touch keys that look like real NICs (have DhcpIPAddress or IPAddress)
    $ip = (Get-ItemProperty -Path $p -Name IPAddress -ErrorAction SilentlyContinue).IPAddress
    $dip = (Get-ItemProperty -Path $p -Name DhcpIPAddress -ErrorAction SilentlyContinue).DhcpIPAddress
    if (-not $ip -and -not $dip) { return }
    New-ItemProperty -Path $p -Name TcpAckFrequency -PropertyType DWord -Value 1 -Force | Out-Null
    New-ItemProperty -Path $p -Name TCPNoDelay -PropertyType DWord -Value 1 -Force | Out-Null
    New-ItemProperty -Path $p -Name TcpDelAckTicks -PropertyType DWord -Value 0 -Force | Out-Null
}
exit 0
