#Requires -RunAsAdministrator
# Exo Full OS depth stack (not just CPU/power).
# Layers: kernel/timer, MMCSS, scheduler priority, input, GPU/DX, network,
# storage, NVIDIA (if present), background services/tasks, power handoff.
# Modes:
#   default / -Shared  = safe for Balanced + Privacy + Extreme
#   -Extreme           = Maximum FPS extras (sysresp 0, win32 0x26, prefetch off, NIC)
#   -SkipPower         = do not re-run Apply-ExoPowerPlan.ps1
param(
  [switch]$Extreme,
  [switch]$Shared,
  [switch]$SkipPower
)
$ErrorActionPreference = 'SilentlyContinue'
if ($Shared -and -not $Extreme) { $Extreme = $false }

$LogDir = Join-Path $env:ProgramData 'ExoOS'
New-Item -ItemType Directory -Force -Path $LogDir | Out-Null
$Log = Join-Path $LogDir 'full-stack.log'

function Write-Exo([string]$m) {
  $line = "[{0}] {1}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $m
  Write-Host "[Exo FullOS] $m"
  Add-Content -Path $Log -Value $line
}

function Set-RegDword([string]$Path, [string]$Name, $Value) {
  if (-not (Test-Path $Path)) { New-Item -Path $Path -Force | Out-Null }
  # Use reg.exe for large DWORD values (0xffffffff) — PowerShell can corrupt unsigned max
  $hk = $Path -replace '^HKLM:\\', 'HKLM\' -replace '^HKCU:\\', 'HKCU\' -replace '^HKCR:\\', 'HKCR\' -replace '^HKU:\\', 'HKU\'
  $num = [uint32]([decimal]$Value)
  & reg.exe add $hk /v $Name /t REG_DWORD /d $num /f | Out-Null
}
function Set-RegString([string]$Path, [string]$Name, [string]$Value) {
  if (-not (Test-Path $Path)) { New-Item -Path $Path -Force | Out-Null }
  New-ItemProperty -Path $Path -Name $Name -PropertyType String -Value $Value -Force | Out-Null
}
function Set-ServiceSafe([string]$Name, [string]$StartType, [switch]$Stop) {
  $svc = Get-Service -Name $Name -EA SilentlyContinue
  if (-not $svc) { return }
  $map = @{ Boot = 0; System = 1; Automatic = 2; Manual = 3; Disabled = 4 }
  $startCode = $map[$StartType]
  try {
    Set-Service -Name $Name -StartupType $StartType -EA Stop
  } catch {
    # Protected services (DoSvc etc.): write Start via registry + sc.exe
    try {
      if ($null -ne $startCode) {
        & reg.exe add "HKLM\SYSTEM\CurrentControlSet\Services\$Name" /v Start /t REG_DWORD /d $startCode /f | Out-Null
        $scType = switch ($StartType) { 'Automatic' { 'auto' } 'Manual' { 'demand' } 'Disabled' { 'disabled' } default { 'demand' } }
        & sc.exe config $Name start= $scType | Out-Null
      }
    } catch { }
  }
  if ($Stop -and $svc.Status -eq 'Running') {
    try { Stop-Service -Name $Name -Force -EA Stop } catch {
      & sc.exe stop $Name | Out-Null
    }
  }
  $after = Get-Service -Name $Name -EA SilentlyContinue
  Write-Exo ("service $Name -> $StartType (now $($after.StartType)/$($after.Status))")
}

Write-Exo "==== START FullOS Extreme=$Extreme ===="

# ---------------------------------------------------------------------------
# 1) Kernel / timer / power throttle
# ---------------------------------------------------------------------------
Set-RegDword 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\kernel' 'GlobalTimerResolutionRequests' 1
# Prefer distributing timer IRQs across cores when present (Win10 1809+)
Set-RegDword 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\kernel' 'DistributeTimers' 1
Set-RegDword 'HKLM:\SYSTEM\CurrentControlSet\Control\Power\PowerThrottling' 'PowerThrottlingOff' 1
Set-RegDword 'HKLM:\SYSTEM\CurrentControlSet\Control\Power' 'CsEnabled' 0
Set-RegDword 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Power' 'HiberbootEnabled' 0
Write-Exo 'kernel: GlobalTimerResolutionRequests=1, DistributeTimers=1, PowerThrottlingOff, CsEnabled=0, Hiberboot off'

# ---------------------------------------------------------------------------
# 2) MMCSS — verified against Microsoft docs, not optimizer blogs
# https://learn.microsoft.com/windows/win32/procthread/multimedia-class-scheduler-service
# - SystemResponsiveness: % for low-priority; <10 or >100 => clamp 20; 100 disables MMCSS
# - Scheduling Category High: Priority is ALWAYS treated as 2
# - GPU Priority: "This priority is not yet used"
# - SFIO Priority: "This value is not used"
# - Clock Rate guarantee removed since Windows 7
# Meaningful Games change: Scheduling Category = High (priority band).
# ---------------------------------------------------------------------------
$games = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile\Tasks\Games'
Set-RegString $games 'Scheduling Category' 'High'
Set-RegString $games 'Background Only' 'False'
Set-RegDword $games 'Affinity' 0
# Keep stock-ish Priority (MS forces 2 under High anyway). Do not set theater GPU/SFIO.

$mm = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile'
Set-RegDword $mm 'NetworkThrottlingIndex' 4294967295
# MS docs (MMCSS): SystemResponsiveness = % CPU reserved for low-priority tasks.
# Values not divisible by 10 round down. Values <10 or >100 clamp to 20 (default).
# So 0 is NOT "max gaming" — it falls back to 20. Minimum meaningful gaming value is 10.
# https://learn.microsoft.com/windows/win32/procthread/multimedia-class-scheduler-service
Set-RegDword $mm 'SystemResponsiveness' 10
Write-Exo 'MMCSS: NetworkThrottlingIndex=max, SystemResponsiveness=10 (MS: <10 clamps to 20)'

# ---------------------------------------------------------------------------
# 3) Scheduler priority separation
# ---------------------------------------------------------------------------
# 0x26 = 38 = short quantum, variable, high foreground boost
# Shared keeps a milder 0x24 (36) so desktop still snappy without extreme quantum
if ($Extreme) {
  Set-RegDword 'HKLM:\SYSTEM\CurrentControlSet\Control\PriorityControl' 'Win32PrioritySeparation' 38
  Write-Exo 'Win32PrioritySeparation=38 (0x26 extreme foreground)'
} else {
  Set-RegDword 'HKLM:\SYSTEM\CurrentControlSet\Control\PriorityControl' 'Win32PrioritySeparation' 36
  Write-Exo 'Win32PrioritySeparation=36 (0x24 shared foreground)'
}

# ---------------------------------------------------------------------------
# 4) Memory / storage
# ---------------------------------------------------------------------------
Set-RegDword 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management' 'DisablePagingExecutive' 1
Set-RegDword 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management' 'LargeSystemCache' 0
if ($Extreme) {
  Set-RegDword 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management\PrefetchParameters' 'EnablePrefetcher' 0
  Set-RegDword 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management\PrefetchParameters' 'EnableSuperfetch' 0
  Write-Exo 'prefetch/superfetch off (extreme, SSD gaming)'
} else {
  # SSD-friendly: boot+app prefetch only (3) is stock; leave unless extreme
  Write-Exo 'prefetch left stock (shared)'
}
try {
  fsutil behavior set DisableLastAccess 1 | Out-Null
  fsutil behavior set EncryptPagingFile 0 | Out-Null
  # MemoryUsage 1 doubles NTFS metadata cache — good for gaming + many small files
  fsutil behavior set MemoryUsage 1 | Out-Null
  fsutil behavior set DisableDeleteNotify 0 | Out-Null
  Write-Exo 'NTFS: DisableLastAccess, MemoryUsage=1, TRIM on'
} catch { Write-Exo "fsutil: $($_.Exception.Message)" }

# ---------------------------------------------------------------------------
# 5) GPU / DirectX / FSO borderless-first
# ---------------------------------------------------------------------------
# HAGS on for shared+extreme (user can flip off if rare driver bug)
Set-RegDword 'HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers' 'HwSchMode' 2
# TDR: give GPU longer before reset (stock 2s is harsh under heavy shader compile)
Set-RegDword 'HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers' 'TdrDelay' 10
Set-RegDword 'HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers' 'TdrDdiDelay' 10

Set-RegDword 'HKCU:\System\GameConfigStore' 'GameDVR_Enabled' 0
Set-RegDword 'HKCU:\System\GameConfigStore' 'GameDVR_FSEBehavior' 0
Set-RegDword 'HKCU:\System\GameConfigStore' 'GameDVR_FSEBehaviorMode' 0
Set-RegDword 'HKCU:\System\GameConfigStore' 'GameDVR_HonorUserFSEBehaviorMode' 0
Set-RegDword 'HKCU:\System\GameConfigStore' 'GameDVR_DXGIHonorFSEWindowsCompatible' 0
Set-RegDword 'HKCU:\System\GameConfigStore' 'GameDVR_EFSEFeatureFlags' 0
Set-RegDword 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\GameDVR' 'AllowGameDVR' 0
Set-RegDword 'HKCU:\Software\Microsoft\Windows\CurrentVersion\GameDVR' 'AppCaptureEnabled' 0
Set-RegDword 'HKCU:\Software\Microsoft\Windows\CurrentVersion\GameDVR' 'HistoricalCaptureEnabled' 0
Set-RegDword 'HKCU:\Software\Microsoft\GameBar' 'AutoGameModeEnabled' 1
Set-RegDword 'HKCU:\Software\Microsoft\GameBar' 'AllowAutoGameMode' 1
Set-RegDword 'HKCU:\Software\Microsoft\GameBar' 'UseNexusForGameBarEnabled' 0

# Windowed/borderless present path (Win11+) — free 1% lows for many titles
$dx = 'HKCU:\Software\Microsoft\DirectX\UserGpuPreferences'
if (-not (Test-Path $dx)) { New-Item $dx -Force | Out-Null }
Set-RegString $dx 'DirectXUserGlobalSettings' 'VRROptimizeEnable=1;SwapEffectUpgradeEnable=1;'
Write-Exo 'GPU: HAGS=2, TDR=10, GameDVR off, Game Mode on, SwapEffect+VRR upgrade'

# ---------------------------------------------------------------------------
# 6) Input
# ---------------------------------------------------------------------------
Set-RegString 'HKCU:\Control Panel\Mouse' 'MouseSpeed' '0'
Set-RegString 'HKCU:\Control Panel\Mouse' 'MouseThreshold1' '0'
Set-RegString 'HKCU:\Control Panel\Mouse' 'MouseThreshold2' '0'
Set-RegString 'HKCU:\Control Panel\Mouse' 'MouseHoverTime' '10'
Set-RegString 'HKCU:\Control Panel\Desktop' 'MenuShowDelay' '0'
Set-RegDword 'HKCU:\Control Panel\Desktop' 'ForegroundLockTimeout' 0
Set-RegString 'HKCU:\Control Panel\Desktop' 'AutoEndTasks' '1'
Set-RegString 'HKCU:\Control Panel\Desktop' 'HungAppTimeout' '1000'
Set-RegString 'HKCU:\Control Panel\Desktop' 'WaitToKillAppTimeout' '2000'
Set-RegString 'HKLM:\SYSTEM\CurrentControlSet\Control' 'WaitToKillServiceTimeout' '2000'
# Sticky/Filter/Toggle keys off (shift spam during games)
Set-RegString 'HKCU:\Control Panel\Accessibility\StickyKeys' 'Flags' '506'
Set-RegString 'HKCU:\Control Panel\Accessibility\ToggleKeys' 'Flags' '58'
Set-RegString 'HKCU:\Control Panel\Accessibility\Keyboard Response' 'Flags' '122'
Set-RegString 'HKCU:\Control Panel\Accessibility\MouseKeys' 'Flags' '0'
Write-Exo 'input: 1:1 mouse, no sticky keys, snappy kill timeouts'

# ---------------------------------------------------------------------------
# 7) Network — Nagle off, throttle already off, TCP gaming-ish
# ---------------------------------------------------------------------------
$ifRoot = 'HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters\Interfaces'
Get-ChildItem $ifRoot -EA SilentlyContinue | ForEach-Object {
  $p = $_.PSPath
  $ip = Get-ItemProperty $p -EA SilentlyContinue
  # Only touch adapters that have (or had) an address binding
  if ($ip.IPAddress -or $ip.DhcpIPAddress -or $ip.DhcpServer) {
    Set-RegDword $p 'TcpAckFrequency' 1
    Set-RegDword $p 'TCPNoDelay' 1
    Set-RegDword $p 'TcpDelAckTicks' 0
  }
}
Set-RegDword 'HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters' 'DefaultTTL' 64
Set-RegDword 'HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters' 'TcpTimedWaitDelay' 30
Set-RegDword 'HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters' 'MaxUserPort' 65534
Set-RegDword 'HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters' 'TcpMaxDataRetransmissions' 5
# Disable Windows Scaling Heuristics (can clamp RWIN badly)
try { netsh int tcp set heuristics disabled | Out-Null } catch { }
try { netsh int tcp set global autotuninglevel=normal | Out-Null } catch { }
try { netsh int tcp set global rss=enabled | Out-Null } catch { }
try { netsh int tcp set global ecncapability=disabled | Out-Null } catch { }
try { netsh int tcp set global timestamps=disabled | Out-Null } catch { }
# Fast open is fine; RSC can add latency on some NICs for competitive — extreme only
if ($Extreme) {
  try { netsh int tcp set global rsc=disabled | Out-Null } catch { }
  # Prefer BBR2 when OS supports it (Win11 22H2+), else leave CUBIC
  try {
    $tpl = netsh int tcp show supplemental | Out-String
    netsh int tcp set supplemental template=internet congestionprovider=bbr2 2>$null | Out-Null
    Write-Exo 'TCP: tried BBR2 congestion (falls back if unsupported)'
  } catch { Write-Exo 'TCP: BBR2 not available, keeping provider' }
}
Write-Exo 'network: Nagle off (AckFreq/NoDelay), heuristics off, RSS on'

# NIC power / interrupt moderation (best-effort; names vary by driver)
Get-NetAdapter -Physical -EA SilentlyContinue | Where-Object Status -eq 'Up' | ForEach-Object {
  $n = $_.Name
  foreach ($prop in @(
      @{Name='*EEE*'; Value='0'},
      @{Name='*Energy*Efficient*'; Value='0'},
      @{Name='*Green*'; Value='0'},
      @{Name='*Power*Saving*'; Value='0'},
      @{Name='*Selective*Suspend*'; Value='0'},
      @{Name='*Idle*'; Value='0'},
      @{Name='Interrupt Moderation'; Value='Disabled'},
      @{Name='*Flow*Control*'; Value='Disabled'}
    )) {
    try {
      Set-NetAdapterAdvancedProperty -Name $n -DisplayName $prop.Name -DisplayValue $prop.Value -EA Stop
    } catch {
      try { Set-NetAdapterAdvancedProperty -Name $n -RegistryKeyword $prop.Name -RegistryValue $prop.Value -EA SilentlyContinue } catch { }
    }
  }
  Write-Exo "NIC tune attempt: $n"
}

# ---------------------------------------------------------------------------
# 8) NVIDIA extras (if present)
# ---------------------------------------------------------------------------
if (Test-Path 'HKLM:\SOFTWARE\NVIDIA Corporation') {
  Set-RegDword 'HKLM:\SOFTWARE\NVIDIA Corporation\Global\FTS' 'EnableRID73779' 1  # pre-rendered frames path hints
  Set-RegDword 'HKLM:\SOFTWARE\NVIDIA Corporation\Global\NVTweak' 'AnselEnable' 0
  Set-RegDword 'HKLM:\SOFTWARE\NVIDIA Corporation\Global\NVTweak' 'EnableAnsel' 0
  # Silence telemetry tasks if present
  foreach ($tn in @('NvTmRep_CrashReport1_{B2FE1952-0186-46C3-BAEC-A80AA35AC5B8}',
                    'NvTmRep_CrashReport2_{B2FE1952-0186-46C3-BAEC-A80AA35AC5B8}',
                    'NvTmRep_CrashReport3_{B2FE1952-0186-46C3-BAEC-A80AA35AC5B8}',
                    'NvTmRep_CrashReport4_{B2FE1952-0186-46C3-BAEC-A80AA35AC5B8}',
                    'NvDriverUpdateCheckDaily_{B2FE1952-0186-46C3-BAEC-A80AA35AC5B8}',
                    'NVIDIA GeForce Experience SelfUpdate_{B2FE1952-0186-46C3-BAEC-A80AA35AC5B8}',
                    'NvNodeLauncher_{B2FE1952-0186-46C3-BAEC-A80AA35AC5B8}')) {
    try { Disable-ScheduledTask -TaskName $tn -EA Stop | Out-Null } catch { }
  }
  Write-Exo 'NVIDIA: Ansel off, telemetry tasks best-effort disable'
}

# ---------------------------------------------------------------------------
# 9) Background services (shared quiet — not nuclear)
# ---------------------------------------------------------------------------
# Telemetry / bloat always quiet
Set-ServiceSafe 'DiagTrack' Disabled -Stop
Set-ServiceSafe 'dmwappushservice' Disabled -Stop
Set-ServiceSafe 'RetailDemo' Disabled -Stop
Set-ServiceSafe 'MapsBroker' Disabled -Stop
Set-ServiceSafe 'WbioSrvc' Manual -Stop
Set-ServiceSafe 'PhoneSvc' Manual -Stop
Set-ServiceSafe 'TabletInputService' Manual -Stop
Set-ServiceSafe 'DoSvc' Manual -Stop
Set-ServiceSafe 'PcaSvc' Manual -Stop
Set-ServiceSafe 'wisvc' Disabled -Stop
Set-ServiceSafe 'RemoteRegistry' Disabled -Stop
Set-ServiceSafe 'RemoteAccess' Disabled -Stop
Set-ServiceSafe 'TrkWks' Manual -Stop
Set-ServiceSafe 'CscService' Disabled -Stop
Set-ServiceSafe 'SEMgrSvc' Manual -Stop
Set-ServiceSafe 'icssvc' Disabled -Stop
Set-ServiceSafe 'FrameServer' Manual -Stop
Set-ServiceSafe 'WerSvc' Manual -Stop
Set-ServiceSafe 'DusmSvc' Manual -Stop  # data usage

if ($Extreme) {
  # Search indexing + SysMain cost RAM/IO on gaming desktops
  Set-ServiceSafe 'WSearch' Disabled -Stop
  Set-ServiceSafe 'SysMain' Disabled -Stop
  Set-ServiceSafe 'Spooler' Disabled -Stop
  Set-ServiceSafe 'Fax' Disabled -Stop
  Set-ServiceSafe 'PrintNotify' Manual -Stop
  Set-ServiceSafe 'XblAuthManager' Manual -Stop
  Set-ServiceSafe 'XblGameSave' Manual -Stop
  Set-ServiceSafe 'XboxGipSvc' Manual -Stop
  Set-ServiceSafe 'XboxNetApiSvc' Manual -Stop
  Set-ServiceSafe 'BcastDVRUserService' Manual -Stop
  Set-ServiceSafe 'CaptureService' Manual -Stop
  Set-ServiceSafe 'GraphicsPerfSvc' Manual -Stop
  Set-ServiceSafe 'DisplayEnhancementService' Manual -Stop
  Write-Exo 'extreme services: WSearch/SysMain/Spooler off'
} else {
  # Shared: don't kill search/sysmain — just calm Delivery Optimization
  Set-ServiceSafe 'WSearch' Manual
  Write-Exo 'shared services: WSearch manual (not killed)'
}

# ---------------------------------------------------------------------------
# 10) Scheduled tasks (telemetry / CEIP / maps / feedback)
# ---------------------------------------------------------------------------
$tasks = @(
  '\Microsoft\Windows\Application Experience\Microsoft Compatibility Appraiser',
  '\Microsoft\Windows\Application Experience\ProgramDataUpdater',
  '\Microsoft\Windows\Application Experience\StartupAppTask',
  '\Microsoft\Windows\Customer Experience Improvement Program\Consolidator',
  '\Microsoft\Windows\Customer Experience Improvement Program\UsbCeip',
  '\Microsoft\Windows\DiskDiagnostic\Microsoft-Windows-DiskDiagnosticDataCollector',
  '\Microsoft\Windows\Feedback\Siuf\DmClient',
  '\Microsoft\Windows\Feedback\Siuf\DmClientOnScenarioDownload',
  '\Microsoft\Windows\Maps\MapsToastTask',
  '\Microsoft\Windows\Maps\MapsUpdateTask',
  '\Microsoft\Windows\Windows Error Reporting\QueueReporting',
  '\Microsoft\Windows\CloudExperienceHost\CreateObjectTask',
  '\Microsoft\Windows\Shell\FamilySafetyMonitor',
  '\Microsoft\Windows\Shell\FamilySafetyRefreshTask',
  '\Microsoft\Windows\Autochk\Proxy',
  '\Microsoft\Windows\PI\Sqm-Tasks',
  '\Microsoft\Windows\NetTrace\GatherNetworkInfo',
  '\Microsoft\Windows\AppID\SmartScreenSpecific'
)
foreach ($t in $tasks) {
  try {
    $name = Split-Path $t -Leaf
    $path = (Split-Path $t -Parent) + '\'
    Disable-ScheduledTask -TaskName $name -TaskPath $path -EA Stop | Out-Null
    Write-Exo "task off: $t"
  } catch { }
}

# ---------------------------------------------------------------------------
# 11) Privacy / shell noise (light — full strip is elsewhere)
# ---------------------------------------------------------------------------
Set-RegDword 'HKCU:\Software\Microsoft\Windows\CurrentVersion\AdvertisingInfo' 'Enabled' 0
Set-RegDword 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\AdvertisingInfo' 'Enabled' 0
Set-RegDword 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\System' 'EnableActivityFeed' 0
Set-RegDword 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\System' 'PublishUserActivities' 0
Set-RegDword 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\System' 'UploadUserActivities' 0
Set-RegDword 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Privacy' 'TailoredExperiencesWithDiagnosticDataEnabled' 0
Set-RegDword 'HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager' 'SystemPaneSuggestionsEnabled' 0
Set-RegDword 'HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager' 'SoftLandingEnabled' 0
Set-RegDword 'HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager' 'SilentInstalledAppsEnabled' 0
Set-RegDword 'HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager' 'SubscribedContent-338389Enabled' 0
Set-RegDword 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' 'ShowSyncProviderNotifications' 0
Set-RegDword 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' 'TaskbarDa' 0
Set-RegDword 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Search' 'BingSearchEnabled' 0
Set-RegDword 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Search' 'SearchboxTaskbarMode' 0
Set-RegDword 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search' 'AllowCortana' 0
Set-RegDword 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search' 'DisableWebSearch' 1
Set-RegDword 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent' 'DisableWindowsConsumerFeatures' 1
Set-RegDword 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent' 'DisableSoftLanding' 1
Set-RegDword 'HKCU:\Software\Microsoft\Windows\CurrentVersion\BackgroundAccessApplications' 'GlobalUserDisabled' 1
Set-RegDword 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DeliveryOptimization' 'DODownloadMode' 0
Set-RegDword 'HKCU:\Software\Microsoft\Windows\CurrentVersion\PushNotifications' 'ToastEnabled' 0
Write-Exo 'privacy/shell: ads/activity/websearch/consumer features quiet'

# Visuals snappy
Set-RegString 'HKCU:\Control Panel\Desktop\WindowMetrics' 'MinAnimate' '0'
Set-RegDword 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects' 'VisualFXSetting' 2
Set-RegDword 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' 'TaskbarAnimations' 0
Set-RegDword 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' 'ListviewAlphaSelect' 0
Set-RegDword 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' 'ListviewShadow' 0
Set-RegString 'HKCU:\Control Panel\Desktop' 'DragFullWindows' '0'

# ---------------------------------------------------------------------------
# 12) BCD / VBS reinforce (extreme). Shared only ensures hypervisor off is left alone.
# ---------------------------------------------------------------------------
if ($Extreme) {
  try { bcdedit /set useplatformtick yes | Out-Null } catch { }
  try { bcdedit /set disabledynamictick yes | Out-Null } catch { }
  try { bcdedit /set useplatformclock false | Out-Null } catch { }
  try { bcdedit /set hypervisorlaunchtype off | Out-Null } catch { }
  # Soft VBS disable via policy (full DisableVBS script is separate extreme pack)
  Set-RegDword 'HKLM:\SYSTEM\CurrentControlSet\Control\DeviceGuard' 'EnableVirtualizationBasedSecurity' 0
  Set-RegDword 'HKLM:\SYSTEM\CurrentControlSet\Control\DeviceGuard' 'RequirePlatformSecurityFeatures' 0
  Set-RegDword 'HKLM:\SYSTEM\CurrentControlSet\Control\DeviceGuard\Scenarios\HypervisorEnforcedCodeIntegrity' 'Enabled' 0
  Set-RegDword 'HKLM:\SYSTEM\CurrentControlSet\Control\Lsa' 'LsaCfgFlags' 0
  Write-Exo 'extreme BCD+VBS policy reinforced (reboot may still be required for VBS Running clear)'
}

# ---------------------------------------------------------------------------
# 13) Power plan handoff (platform-specific AM4/AM5/Intel lives here)
# ---------------------------------------------------------------------------
if (-not $SkipPower) {
  $powerScript = Join-Path $PSScriptRoot 'Apply-ExoPowerPlan.ps1'
  if (Test-Path $powerScript) {
    Write-Exo 'invoking Apply-ExoPowerPlan.ps1'
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $powerScript
  } else {
    Write-Exo "power script missing: $powerScript"
  }
}

# ---------------------------------------------------------------------------
# 14) Marker
# ---------------------------------------------------------------------------
$mark = 'HKLM:\SOFTWARE\ExoOS'
if (-not (Test-Path $mark)) { New-Item $mark -Force | Out-Null }
Set-ItemProperty $mark -Name FullStackApplied -Value 1 -Type DWord -Force
Set-ItemProperty $mark -Name FullStackVersion -Value '1.7.0' -Force
Set-ItemProperty $mark -Name FullStackExtreme -Value ([int][bool]$Extreme) -Type DWord -Force
Set-ItemProperty $mark -Name FullStackUtc -Value ((Get-Date).ToUniversalTime().ToString('o')) -Force
Set-ItemProperty $mark -Name Version -Value '1.7.0' -Force

Write-Exo "==== DONE FullOS Extreme=$Extreme (reboot recommended for VBS/BCD/HAGS if first time) ===="
exit 0
