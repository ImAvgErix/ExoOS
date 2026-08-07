#Requires -RunAsAdministrator
<#
.SYNOPSIS
  Pause Windows Update for the maximum consumer window (feature + quality).
  Prefer pause over permanently disabling wuauserv (recoverable, less broken).
#>
$ErrorActionPreference = 'SilentlyContinue'

$days = 35
$start = (Get-Date).ToUniversalTime()
$end = $start.AddDays($days)
# Windows UX Settings uses this round-trip format
$fmt = 'yyyy-MM-ddTHH:mm:ssZ'
$startS = $start.ToString($fmt)
$endS = $end.ToString($fmt)

$ux = 'HKLM:\SOFTWARE\Microsoft\WindowsUpdate\UX\Settings'
if (-not (Test-Path $ux)) { New-Item -Path $ux -Force | Out-Null }

# Pause quality + feature updates
Set-ItemProperty -Path $ux -Name 'PauseFeatureUpdatesStartTime' -Value $startS -Type String -Force
Set-ItemProperty -Path $ux -Name 'PauseFeatureUpdatesEndTime' -Value $endS -Type String -Force
Set-ItemProperty -Path $ux -Name 'PauseQualityUpdatesStartTime' -Value $startS -Type String -Force
Set-ItemProperty -Path $ux -Name 'PauseQualityUpdatesEndTime' -Value $endS -Type String -Force
Set-ItemProperty -Path $ux -Name 'PauseUpdatesExpiryTime' -Value $endS -Type String -Force
Set-ItemProperty -Path $ux -Name 'PauseUpdatesStartTime' -Value $startS -Type String -Force -ErrorAction SilentlyContinue

# Allow long pause UX (when supported)
Set-ItemProperty -Path $ux -Name 'FlightSettingsMaxPauseDays' -Value $days -Type DWord -Force -ErrorAction SilentlyContinue

# Soft defer policies (do not fully sever WU endpoints — resume still works)
$au = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU'
if (-not (Test-Path $au)) { New-Item -Path $au -Force | Out-Null }
# 2 = notify before download — paired with pause UI state
Set-ItemProperty -Path $au -Name 'NoAutoUpdate' -Value 1 -Type DWord -Force -ErrorAction SilentlyContinue
Set-ItemProperty -Path $au -Name 'AUOptions' -Value 2 -Type DWord -Force -ErrorAction SilentlyContinue

Write-Host "[Exo] Windows Update paused until $endS ($days days). Resume from Settings > Windows Update."
exit 0
