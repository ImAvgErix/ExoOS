# ExoOS — USB hub + HID mouse/keyboard power management off (latency / wake)
$ErrorActionPreference = 'SilentlyContinue'
Write-Host 'Exo USB/HID power tune'

# Global USB selective suspend via powercfg (reinforces polish)
try { powercfg /SETACVALUEINDEX SCHEME_CURRENT 2a737441-1930-4402-8d77-b2bebba308a3 48e6b7a6-50f5-4782-a5d4-53bb8f07e226 0 | Out-Null } catch {}
try { powercfg /SETDCVALUEINDEX SCHEME_CURRENT 2a737441-1930-4402-8d77-b2bebba308a3 48e6b7a6-50f5-4782-a5d4-53bb8f07e226 0 | Out-Null } catch {}
try { powercfg /SETACTIVE SCHEME_CURRENT | Out-Null } catch {}

# Device-instance: Enhanced Power Management + DeviceIdle for USB + HID
$enum = 'HKLM:\SYSTEM\CurrentControlSet\Enum'
$targets = @(
  'USB\*',
  'HID\*'
)
Get-ChildItem $enum -EA SilentlyContinue | Where-Object {
  $_.PSChildName -match '^(USB|HID|USBSTOR)$'
} | ForEach-Object {
  Get-ChildItem $_.PSPath -Recurse -EA SilentlyContinue | Where-Object {
    $_.PSChildName -eq 'Device Parameters'
  } | ForEach-Object {
    $p = $_.PSPath
    New-ItemProperty -Path $p -Name EnhancedPowerManagementEnabled -PropertyType DWord -Value 0 -Force -EA SilentlyContinue | Out-Null
    New-ItemProperty -Path $p -Name AllowIdleIrpInD3 -PropertyType DWord -Value 0 -Force -EA SilentlyContinue | Out-Null
    New-ItemProperty -Path $p -Name DeviceIdleEnabled -PropertyType DWord -Value 0 -Force -EA SilentlyContinue | Out-Null
    New-ItemProperty -Path $p -Name SelectiveSuspendOn -PropertyType DWord -Value 0 -Force -EA SilentlyContinue | Out-Null
    New-ItemProperty -Path $p -Name SelectiveSuspendEnabled -PropertyType DWord -Value 0 -Force -EA SilentlyContinue | Out-Null
  }
}

Write-Host 'USB/HID: selective suspend / enhanced power management cleared (best-effort)'
exit 0
