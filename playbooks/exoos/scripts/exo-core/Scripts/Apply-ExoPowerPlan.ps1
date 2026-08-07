#Requires -RunAsAdministrator
# Exo platform power stack:
# - Unlock every hidden PowerSettings entry Windows hides from the UI
# - Detect AM4 Zen2/3 vs AM5 Zen4/5 vs APU/Strix vs Intel classic vs 12+ hybrid
# - Import matching .pow, then slam platform-specific indices (GUID + alias)
# Validated against live powercfg /qh on Win11 + Ryzen 5000 / hybrid-capable SKUs
$ErrorActionPreference = 'SilentlyContinue'

$PlaybookRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path
$PowerDir = Join-Path $PlaybookRoot 'assets\power'
$Log = Join-Path $env:ProgramData 'ExoOS\power-plan.log'
New-Item -ItemType Directory -Force -Path (Split-Path $Log) | Out-Null

function Write-Exo([string]$m) {
  $line = "[{0}] {1}" -f (Get-Date -Format 'HH:mm:ss'), $m
  Write-Host "[Exo Power] $m"
  Add-Content -Path $Log -Value $line
}

# ---------------------------------------------------------------------------
# Unlock hidden power options (registry Attributes + powercfg -ATTRIB_HIDE)
# ---------------------------------------------------------------------------
function Unlock-AllPowerSettings {
  # Connected Standby off (desktop)
  Set-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Power' -Name 'CsEnabled' -Value 0 -Type DWord -Force

  $root = 'HKLM:\SYSTEM\CurrentControlSet\Control\Power\PowerSettings'
  $n = 0
  Get-ChildItem $root -Recurse -EA SilentlyContinue | ForEach-Object {
    $p = $_.PSPath
    if ($p -match 'DefaultPowerSchemeValues|\\255$') { return }
    try {
      Set-ItemProperty -LiteralPath $p -Name 'Attributes' -Value 2 -Type DWord -Force
      $n++
    } catch { }
  }

  # Unhide by walking every setting GUID under every subgroup via powercfg
  $qh = powercfg /qh SCHEME_CURRENT 2>$null | Out-String
  $sub = $null
  foreach ($line in ($qh -split "`r?`n")) {
    if ($line -match 'Subgroup GUID:\s*([0-9a-fA-F-]{36})') { $sub = $Matches[1]; continue }
    if ($sub -and $line -match 'Power Setting GUID:\s*([0-9a-fA-F-]{36})') {
      powercfg -attributes $sub $Matches[1] -ATTRIB_HIDE 2>$null | Out-Null
    }
  }
  Write-Exo "Unlocked power settings (Attributes touch ~$n keys + full -ATTRIB_HIDE pass)"
}

# ---------------------------------------------------------------------------
# Detect platform (AM4/AM5/APU/Intel gen)
# ---------------------------------------------------------------------------
function Get-ExoCpuProfile {
  $cpu = Get-CimInstance Win32_Processor | Select-Object -First 1
  $name = [string]$cpu.Name
  $manu = [string]$cpu.Manufacturer
  $cores = [int]$cpu.NumberOfCores
  $threads = [int]$cpu.NumberOfLogicalProcessors

  $p = [ordered]@{
    Name     = $name.Trim()
    Vendor   = 'Other'
    Platform = 'Generic'  # AM4 | AM5 | Strix | TRX | IntelClassic | IntelHybrid
    Gen      = 0
    Series   = 0
    Hybrid   = $false
    MultiCcd = $false
    X3D      = ($name -match 'X3D')
    Cores    = $cores
    Threads  = $threads
    PowFile  = 'Exo-Primary.pow'
    Label    = 'Exo Extreme'
    Guid     = 'a1111111-e80e-4e0e-a111-0e0e0e0e0e03'
  }

  if ($manu -match 'AMD' -or $name -match 'AMD|Ryzen|Threadripper|EPYC|Athlon') {
    $p.Vendor = 'AMD'
    $p.PowFile = 'Exo-AMD.pow'
    $p.Guid = 'a1111111-e80e-4e0e-a111-0e0e0e0e0e01'

    # Multi-CCD desktop: 12+ cores typical (5900X/5950X/7900/7950/9900/9950)
    if ($cores -ge 12 -and $name -notmatch 'Threadripper|EPYC') { $p.MultiCcd = $true }

    if ($name -match 'Threadripper') {
      $p.Platform = 'TRX'; $p.Label = 'Exo Extreme (AMD TR)'; $p.MultiCcd = $true
    }
    elseif ($name -match 'Ryzen\s*AI|Strix|Hawk Point|Phoenix') {
      $p.Platform = 'Strix'; $p.Hybrid = $true; $p.Gen = 4
      $p.Label = 'Exo Extreme (AMD APU Strix/Phoenix)'
    }
    elseif ($name -match '(\d{4,5})') {
      $series = [int]$Matches[1]
      $p.Series = $series
      if ($series -ge 9000 -and $series -lt 10000) {
        $p.Platform = 'AM5'; $p.Gen = 5
        $p.Label = if ($p.X3D) { 'Exo Extreme (AM5 Zen5 X3D)' } else { 'Exo Extreme (AM5 Zen5)' }
      }
      elseif ($series -ge 8000 -and $series -lt 9000) {
        $p.Platform = 'AM5'; $p.Gen = 4
        if ($name -match 'G\b|GE\b') {
          $p.Hybrid = $true; $p.Label = 'Exo Extreme (AM5 APU)'
        } else {
          $p.Label = if ($p.X3D) { 'Exo Extreme (AM5 Zen4 X3D)' } else { 'Exo Extreme (AM5 Zen4)' }
        }
      }
      elseif ($series -ge 7000 -and $series -lt 8000) {
        $p.Platform = 'AM5'; $p.Gen = 4
        $p.Label = if ($p.X3D) { 'Exo Extreme (AM5 Zen4 X3D)' } else { 'Exo Extreme (AM5 Zen4)' }
      }
      elseif ($series -ge 5000 -and $series -lt 6000) {
        $p.Platform = 'AM4'; $p.Gen = 3
        $p.Label = if ($p.X3D) { 'Exo Extreme (AM4 Zen3 X3D)' } else { 'Exo Extreme (AM4 Zen3)' }
      }
      elseif ($series -ge 4000 -and $series -lt 5000) {
        $p.Platform = 'AM4'; $p.Gen = 2; $p.Hybrid = $true
        $p.Label = 'Exo Extreme (AM4 Renoir/Cezanne APU)'
      }
      elseif ($series -ge 3000 -and $series -lt 4000) {
        $p.Platform = 'AM4'; $p.Gen = 2
        $p.Label = 'Exo Extreme (AM4 Zen2)'
      }
      elseif ($series -ge 2000 -and $series -lt 3000) {
        $p.Platform = 'AM4'; $p.Gen = 1; $p.Label = 'Exo Extreme (AM4 Zen+)'
      }
      else {
        $p.Platform = 'AM4'; $p.Gen = 1; $p.Label = 'Exo Extreme (AMD)'
      }
    }
    else {
      $p.Platform = 'AM4'; $p.Label = 'Exo Extreme (AMD)'
    }
  }
  elseif ($manu -match 'Intel' -or $name -match 'Intel|Core\(TM\)|Xeon') {
    $p.Vendor = 'Intel'
    $p.Guid = 'a1111111-e80e-4e0e-a111-0e0e0e0e0e02'
    $p.PowFile = 'Exo-LowLatency.pow'

    if ($name -match 'Ultra\s*[579]\s*2\d{2}|Ultra\s*9\s*2') {
      $p.Platform = 'IntelHybrid'; $p.Gen = 15; $p.Hybrid = $true
      $p.Label = 'Exo Extreme (Intel Arrow Lake)'
      $p.PowFile = 'Exo-Competitive.pow'
    }
    elseif ($name -match 'Ultra|Meteor') {
      $p.Platform = 'IntelHybrid'; $p.Gen = 14; $p.Hybrid = $true
      $p.Label = 'Exo Extreme (Intel Ultra/Meteor)'
      $p.PowFile = 'Exo-Competitive.pow'
    }
    elseif ($name -match 'i[3579]-(\d{1,2})\d{3}') {
      $gen = [int]$Matches[1]
      $p.Gen = $gen
      if ($gen -ge 12) {
        $p.Platform = 'IntelHybrid'; $p.Hybrid = $true
        $p.Label = "Exo Extreme (Intel ${gen}th hybrid)"
        $p.PowFile = 'Exo-Competitive.pow'
      }
      else {
        $p.Platform = 'IntelClassic'
        $p.Label = "Exo Extreme (Intel ${gen}th)"
      }
    }
    else {
      $p.Platform = 'IntelClassic'
      $p.Label = 'Exo Extreme (Intel)'
    }
  }

  return [pscustomobject]$p
}

function S([string]$scheme, [string]$aliasOrGuid, [string]$setting, [string]$val) {
  # Try alias form first, then raw GUIDs if caller passed them as setting-only under SUB_PROCESSOR
  powercfg /setacvalueindex $scheme $aliasOrGuid $setting $val 2>$null | Out-Null
  powercfg /setdcvalueindex $scheme $aliasOrGuid $setting $val 2>$null | Out-Null
}

function Apply-BaseLatency([string]$g) {
  # Min/max processor state
  S $g SUB_PROCESSOR PROCTHROTTLEMIN 100
  S $g SUB_PROCESSOR PROCTHROTTLEMAX 100
  # Unpark all cores (class 0)
  S $g SUB_PROCESSOR CPMINCORES 100
  S $g SUB_PROCESSOR CPMAXCORES 100
  # Class 1 unpark (hybrid / efficiency class) - safe if absent
  S $g SUB_PROCESSOR CPMINCORES1 100
  S $g SUB_PROCESSOR CPMAXCORES1 100

  # Boost
  S $g SUB_PROCESSOR PERFBOOSTMODE 2      # Aggressive
  S $g SUB_PROCESSOR PERFBOOSTPOL 100
  S $g SUB_PROCESSOR PERFDUTYCYCLING 0

  # Ramp aggressiveness (percent thresholds)
  S $g SUB_PROCESSOR PERFINCTHRESHOLD 30
  S $g SUB_PROCESSOR PERFDECTHRESHOLD 10
  S $g SUB_PROCESSOR PERFINCPOL 2          # Ideal / rocket
  S $g SUB_PROCESSOR PERFDECPOL 1
  S $g SUB_PROCESSOR PERFCHECK 15

  # Latency sensitivity path (multimedia/game)
  S $g SUB_PROCESSOR LATENCYHINTPERF 99
  S $g SUB_PROCESSOR LATENCYHINTUNPARK 100
  S $g SUB_PROCESSOR LATENCYHINTUNPARK1 100
  S $g SUB_PROCESSOR LATENCYHINTEPP 0
  S $g SUB_PROCESSOR LATENCYHINTEPP1 0

  # Parking concurrency / distribution - keep cores available
  S $g SUB_PROCESSOR CPCONCURRENCY 97
  S $g SUB_PROCESSOR CPDISTRIBUTION 90
  S $g SUB_PROCESSOR CPINCREASETIME 1
  S $g SUB_PROCESSOR CPPERF 0

  # Resource priority high
  S $g SUB_PROCESSOR RESOURCEPRIORITY 100
  S $g SUB_PROCESSOR RESOURCEPRIORITY1 100

  # Disk / USB / PCIe / sleep
  powercfg /setacvalueindex $g SUB_DISK DISKIDLE 0 | Out-Null
  powercfg /setacvalueindex $g 2a737441-1930-4402-8d77-b2bebba308a3 48e6b7a6-50f5-4782-a5d4-53bb8f07e226 0 | Out-Null
  powercfg /setacvalueindex $g SUB_PCIEXPRESS ASPM 0 | Out-Null
  powercfg /setacvalueindex $g SUB_SLEEP HYBRIDSLEEP 0 | Out-Null
  powercfg /setacvalueindex $g SUB_SLEEP STANDBYIDLE 0 | Out-Null
  powercfg /change monitor-timeout-ac 0 | Out-Null
  powercfg /change standby-timeout-ac 0 | Out-Null
  powercfg /change hibernate-timeout-ac 0 | Out-Null
  powercfg /h off | Out-Null
}

function Apply-AmdSingleCcd([string]$g, [int]$zen, [bool]$x3d) {
  # Single-CCD AM4/AM5 (5600X, 5800X3D, 7800X3D, 9800X3D): unpark everything, CPPC-friendly
  # Do NOT disable C-states entirely - Ryzen boost uses idle residency
  S $g SUB_PROCESSOR IDLEDISABLE 0
  S $g SUB_PROCESSOR PERFAUTONOMOUS 1
  S $g SUB_PROCESSOR PERFDUTYCYCLING 0
  S $g SUB_PROCESSOR PERFEPP 0
  S $g SUB_PROCESSOR PERFBOOSTMODE 2
  S $g SUB_PROCESSOR PERFBOOSTPOL 100
  # Zen2 slightly softer down-ramp (stutter)
  if ($zen -le 2) { S $g SUB_PROCESSOR PERFDECTHRESHOLD 20 }
  if ($zen -ge 5) { S $g SUB_PROCESSOR PERFINCTHRESHOLD 25 }
  if ($x3d) {
    # X3D: keep boost but avoid frying - still unparked for gaming
    S $g SUB_PROCESSOR PERFEPP 0
    Write-Exo "AMD single-CCD X3D Zen$zen profile"
  }
  else {
    Write-Exo "AMD single-CCD Zen$zen profile (e.g. 5600X)"
  }
}

function Apply-AmdMultiCcd([string]$g, [int]$zen, [bool]$x3d) {
  # Dual-CCD (5950X, 7950X, 9950X3D): for pure gaming some park CCD1;
  # Exo default = unpark all (max FPS multi-thread + no surprise parking stutter).
  # Prefer performant scheduling; user can tighten with Process Lasso if needed.
  S $g SUB_PROCESSOR IDLEDISABLE 0
  S $g SUB_PROCESSOR PERFAUTONOMOUS 1
  S $g SUB_PROCESSOR PERFDUTYCYCLING 0
  S $g SUB_PROCESSOR PERFEPP 0
  S $g SUB_PROCESSOR PERFBOOSTMODE 2
  S $g SUB_PROCESSOR PERFBOOSTPOL 100
  S $g SUB_PROCESSOR SCHEDPOLICY 2
  S $g SUB_PROCESSOR SHORTSCHEDPOLICY 2
  S $g SUB_PROCESSOR HETEROPOLICY 4
  # Keep both CCDs available
  S $g SUB_PROCESSOR CPMINCORES 100
  S $g SUB_PROCESSOR CPMAXCORES 100
  if ($x3d) {
    # Dual-CCD X3D: still unpark; preferred cores handled by chipset CPPC preferred cores in BIOS
    Write-Exo "AMD multi-CCD X3D Zen$zen profile (unparked; prefer BIOS CPPC Preferred Cores)"
  }
  else {
    Write-Exo "AMD multi-CCD Zen$zen profile (unparked all CCDs)"
  }
}

function Apply-AmdApu([string]$g) {
  S $g SUB_PROCESSOR IDLEDISABLE 0
  S $g SUB_PROCESSOR PERFAUTONOMOUS 1
  S $g SUB_PROCESSOR PERFDUTYCYCLING 0
  S $g SUB_PROCESSOR PERFEPP 20
  S $g SUB_PROCESSOR PERFBOOSTMODE 2
  S $g SUB_PROCESSOR CPMINCORES 100
  Write-Exo "AMD APU profile (slight EPP for iGPU thermals)"
}

function Apply-IntelClassic([string]$g, [int]$gen) {
  S $g SUB_PROCESSOR IDLEDISABLE 0
  S $g SUB_PROCESSOR PERFAUTONOMOUS 1
  S $g SUB_PROCESSOR PERFDUTYCYCLING 0
  S $g SUB_PROCESSOR PERFEPP 0
  S $g SUB_PROCESSOR PERFBOOSTMODE 2
  S $g SUB_PROCESSOR PERFBOOSTPOL 100
  S $g SUB_PROCESSOR CPMINCORES 100
  Write-Exo "Intel classic gen~$gen profile"
}

function Apply-IntelHybrid([string]$g, [int]$gen) {
  # Prefer P-cores for short/long threads; unpark both classes
  S $g SUB_PROCESSOR IDLEDISABLE 0
  S $g SUB_PROCESSOR PERFAUTONOMOUS 1
  S $g SUB_PROCESSOR PERFDUTYCYCLING 0
  S $g SUB_PROCESSOR PERFEPP 0
  S $g SUB_PROCESSOR PERFEPP1 0
  S $g SUB_PROCESSOR PERFBOOSTMODE 2
  S $g SUB_PROCESSOR PERFBOOSTPOL 100
  S $g SUB_PROCESSOR CPMINCORES 100
  S $g SUB_PROCESSOR CPMAXCORES 100
  S $g SUB_PROCESSOR CPMINCORES1 100
  S $g SUB_PROCESSOR CPMAXCORES1 100
  S $g SUB_PROCESSOR SCHEDPOLICY 2
  S $g SUB_PROCESSOR SHORTSCHEDPOLICY 2
  S $g SUB_PROCESSOR HETEROCLASS0 0
  S $g SUB_PROCESSOR HETEROCLASS1 0
  S $g SUB_PROCESSOR HETEROPOLICY 4
  S $g SUB_PROCESSOR HETEROCLASS1INITIALPERF 100
  S $g SUB_PROCESSOR LATENCYHINTUNPARK1 100
  S $g SUB_PROCESSOR PERFINCTHRESHOLD1 30
  S $g SUB_PROCESSOR PERFDECTHRESHOLD1 10
  Write-Exo "Intel hybrid gen~$gen (P+E) profile"
}

# --- main ---
Unlock-AllPowerSettings
# Ensure Ultimate Performance template exists
powercfg -duplicatescheme e9a42b02-d5df-448d-aa00-03f14749eb61 2>$null | Out-Null

$profile = Get-ExoCpuProfile
Write-Exo ("CPU: " + $profile.Name)
Write-Exo ("Platform=" + $profile.Platform + " Gen=" + $profile.Gen + " Hybrid=" + $profile.Hybrid + " MultiCcd=" + $profile.MultiCcd + " X3D=" + $profile.X3D)

$pow = Join-Path $PowerDir $profile.PowFile
if (-not (Test-Path $pow)) {
  foreach ($fb in @('Exo-AMD.pow', 'Exo-Gaming.pow', 'Exo-Performance.pow', 'Exo-Primary.pow', 'Exo-Competitive.pow', 'Exo-LowLatency.pow')) {
    $c = Join-Path $PowerDir $fb
    if (Test-Path $c) { $pow = $c; break }
  }
}

$guid = $profile.Guid
powercfg -delete $guid 2>$null | Out-Null

if (Test-Path $pow) {
  $imp = Start-Process powercfg.exe -ArgumentList @('-import', $pow, $guid) -Wait -PassThru -WindowStyle Hidden
  Write-Exo ("Import " + (Split-Path $pow -Leaf) + " exit=" + $imp.ExitCode)
}
else {
  # Fall back: Ultimate Performance if present, else High Performance
  $dup = powercfg -duplicatescheme e9a42b02-d5df-448d-aa00-03f14749eb61 2>$null
  if (-not $dup) { powercfg -duplicatescheme 8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c $guid | Out-Null }
  Write-Exo "No .pow - used Ultimate/High Performance duplicate"
}

$desc = $profile.Platform + " | " + $profile.Name
powercfg -changename $guid $profile.Label $desc | Out-Null
powercfg -setactive $guid | Out-Null

Apply-BaseLatency $guid

switch ($profile.Platform) {
  'AM4' {
    if ($profile.MultiCcd) { Apply-AmdMultiCcd $guid $profile.Gen $profile.X3D }
    else { Apply-AmdSingleCcd $guid $profile.Gen $profile.X3D }
  }
  'AM5' {
    if ($profile.MultiCcd) { Apply-AmdMultiCcd $guid $profile.Gen $profile.X3D }
    else { Apply-AmdSingleCcd $guid $profile.Gen $profile.X3D }
  }
  'Strix' { Apply-AmdApu $guid }
  'TRX' { Apply-AmdMultiCcd $guid 4 $profile.X3D }
  'IntelClassic' { Apply-IntelClassic $guid $profile.Gen }
  'IntelHybrid' { Apply-IntelHybrid $guid $profile.Gen }
  default {
    S $guid SUB_PROCESSOR PERFDUTYCYCLING 0
    Write-Exo "Generic profile only"
  }
}

powercfg -setactive $guid | Out-Null

# Persist active scheme marker for Exo
$mark = 'HKLM:\SOFTWARE\ExoOS'
if (-not (Test-Path $mark)) { New-Item $mark -Force | Out-Null }
Set-ItemProperty $mark -Name PowerPlanGuid -Value $guid -Force
Set-ItemProperty $mark -Name PowerPlanLabel -Value $profile.Label -Force
Set-ItemProperty $mark -Name PowerPlanPlatform -Value $profile.Platform -Force
Set-ItemProperty $mark -Name PowerPlanCpu -Value $profile.Name -Force

Write-Exo ("ACTIVE " + (powercfg /getactivescheme))
Write-Exo ("DONE plan=" + $profile.Label + " file=" + (Split-Path $pow -Leaf))
exit 0
