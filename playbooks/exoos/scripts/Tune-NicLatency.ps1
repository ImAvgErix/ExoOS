# ExoOS — NIC latency / bandwidth pack (Nexus/FSOS-X-class, declarative)
# Nagle + interrupt moderation off + EEE/green/flow-control off; keep checksum/LSO for throughput.
$ErrorActionPreference = 'SilentlyContinue'
$Extreme = ($env:EXO_EXTREME -eq '1') -or ($args -contains '-Extreme')

Write-Host 'Exo NIC latency tune'

# Per-interface Nagle
$base = 'HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters\Interfaces'
Get-ChildItem $base | ForEach-Object {
  $p = $_.PSPath
  $ip = (Get-ItemProperty -Path $p -Name IPAddress -EA SilentlyContinue).IPAddress
  $dip = (Get-ItemProperty -Path $p -Name DhcpIPAddress -EA SilentlyContinue).DhcpIPAddress
  if (-not $ip -and -not $dip) { return }
  New-ItemProperty -Path $p -Name TcpAckFrequency -PropertyType DWord -Value 1 -Force | Out-Null
  New-ItemProperty -Path $p -Name TCPNoDelay -PropertyType DWord -Value 1 -Force | Out-Null
  New-ItemProperty -Path $p -Name TcpDelAckTicks -PropertyType DWord -Value 0 -Force | Out-Null
}

# Global TCP
try { netsh int tcp set heuristics disabled | Out-Null } catch {}
try { netsh int tcp set global autotuninglevel=normal | Out-Null } catch {}
try { netsh int tcp set global rss=enabled | Out-Null } catch {}
try { netsh int tcp set global ecncapability=disabled | Out-Null } catch {}
try { netsh int tcp set global timestamps=disabled | Out-Null } catch {}
if ($Extreme) {
  try { netsh int tcp set global rsc=disabled | Out-Null } catch {}
  try { netsh int tcp set supplemental template=internet congestionprovider=bbr2 2>$null | Out-Null } catch {}
}

# Adapter advanced properties (names vary by driver)
Get-NetAdapter -Physical -EA SilentlyContinue | Where-Object { $_.Status -eq 'Up' } | ForEach-Object {
  $n = $_.Name
  foreach ($prop in @(
      @{Name='*EEE*'; Value='0'},
      @{Name='*Energy*Efficient*'; Value='0'},
      @{Name='*Green*'; Value='0'},
      @{Name='*Power*Saving*'; Value='0'},
      @{Name='*Selective*Suspend*'; Value='0'},
      @{Name='Interrupt Moderation'; Value='Disabled'},
      @{Name='*Interrupt*Moderation*'; Value='Disabled'},
      @{Name='*Flow*Control*'; Value='Disabled'}
    )) {
    try {
      Set-NetAdapterAdvancedProperty -Name $n -DisplayName $prop.Name -DisplayValue $prop.Value -EA Stop
    } catch {
      try { Set-NetAdapterAdvancedProperty -Name $n -RegistryKeyword $prop.Name -RegistryValue $prop.Value -EA SilentlyContinue } catch {}
    }
  }
  Write-Host "NIC tune: $n"
}

exit 0
