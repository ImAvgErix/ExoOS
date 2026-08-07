#Requires -RunAsAdministrator
<#
.SYNOPSIS
  Disable noisy Task Scheduler entries by folder/pattern (best-effort).
  Does not touch critical system paths (UpdateOrchestrator full wipe is opt-in elsewhere).
#>
$ErrorActionPreference = 'SilentlyContinue'

$patterns = @(
  'Compat', 'CEIP', 'Customer Experience', 'Feedback', 'Siuf', 'Maps',
  'CloudExperience', 'FamilySafety', 'XblGameSave', 'OfficeTelemetry',
  'RetailDemo', 'Flighting', 'DeviceDirectory', 'PushToInstall',
  'SpeechModel', 'Location', 'NetTrace', 'HelloFace', 'Work Folders',
  'SettingSync', 'DiskDiagnostic', 'DiskFootprint', 'Power Efficiency',
  'MemoryDiagnostic', 'Application Experience', 'ProgramDataUpdater'
)

$safeRoots = @(
  '\Microsoft\Windows\',
  '\Microsoft\Office\',
  '\Microsoft\XblGameSave\'
)

$disabled = 0
$tasks = Get-ScheduledTask -ErrorAction SilentlyContinue
foreach ($t in $tasks) {
  $path = $t.TaskPath
  $name = $t.TaskName
  $full = "$path$name"
  $underSafe = $false
  foreach ($r in $safeRoots) {
    if ($path.StartsWith($r, [StringComparison]::OrdinalIgnoreCase)) { $underSafe = $true; break }
  }
  if (-not $underSafe) { continue }

  # Never disable BitLocker unlock / recovery-critical or time if not matching noise
  if ($name -match 'BitLocker|Bde|Recovery|Defrag' -and $full -notmatch 'ScheduledDefrag|ProactiveScan') {
    continue
  }

  $hit = $false
  foreach ($p in $patterns) {
    if ($full -match [regex]::Escape($p) -or $path -match $p -or $name -match $p) { $hit = $true; break }
  }
  if (-not $hit) { continue }

  if ($t.State -eq 'Disabled') { continue }
  try {
    Disable-ScheduledTask -TaskPath $path -TaskName $name -ErrorAction Stop | Out-Null
    $disabled++
  } catch {
    try {
      schtasks.exe /Change /TN "$path$name" /Disable | Out-Null
      $disabled++
    } catch { }
  }
}

Write-Host "[Exo] Task library sweep disabled ~$disabled tasks"
