# ExoOS — keep process count low after reboot (StartupApproved / Run / Edge update)
$ErrorActionPreference = 'SilentlyContinue'
Write-Host 'Exo startup permanence'

# Disable common startup-approved entries that relaunch bloat
$approved = @(
  'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run',
  'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run32',
  'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run',
  'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run32'
)
$killNames = @(
  'OneDrive', 'Microsoft Edge*', 'Teams*', 'Skype*', 'Discord Update*',
  'Steam*', 'EpicGames*', 'Adobe*', 'iTunes*', 'Spotify*', 'CCleaner*',
  'Office*', 'Microsoft.*Update*', 'SecurityHealth*'
)
foreach ($root in $approved) {
  if (-not (Test-Path $root)) { continue }
  Get-Item -Path $root -EA SilentlyContinue | ForEach-Object {
    $_.Property | ForEach-Object {
      $name = $_
      foreach ($pat in $killNames) {
        if ($name -like $pat) {
          # 12-byte disabled blob (binary) — last-known StartupApproved disabled marker
          $disabled = [byte[]](0x03,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00)
          New-ItemProperty -Path $root -Name $name -PropertyType Binary -Value $disabled -Force | Out-Null
          Write-Host "StartupApproved disable: $name"
        }
      }
    }
  }
}

# Remove noisy Run keys (not gaming launchers the user may want)
$runKeys = @(
  'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run',
  'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run',
  'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Run'
)
$removeExact = @(
  'OneDrive', 'MicrosoftEdgeAutoLaunch*', 'Teams', 'com.squirrel.Teams.Teams',
  'Skype for Desktop', 'AdobeAAMUpdater*', 'AdobeGCInvoker*', 'CCleaner*',
  'Google Update*', 'Microsoft.Windows.ShellExperience*'
)
foreach ($rk in $runKeys) {
  if (-not (Test-Path $rk)) { continue }
  Get-Item -Path $rk -EA SilentlyContinue | ForEach-Object {
    $_.Property | ForEach-Object {
      $name = $_
      foreach ($pat in $removeExact) {
        if ($name -like $pat) {
          Remove-ItemProperty -Path $rk -Name $name -Force -EA SilentlyContinue
          Write-Host "Run key removed: $name"
        }
      }
    }
  }
}

# Edge update tasks
foreach ($tn in @(
    '\MicrosoftEdgeUpdateTaskMachineCore*',
    '\MicrosoftEdgeUpdateTaskMachineUA*',
    '\Microsoft\EdgeUpdate\*'
  )) {
  try { Get-ScheduledTask -TaskPath '\' -EA SilentlyContinue | Where-Object { $_.TaskName -like 'MicrosoftEdgeUpdate*' } | Disable-ScheduledTask -EA SilentlyContinue | Out-Null } catch {}
}

Write-Host 'Startup permanence done'
exit 0
