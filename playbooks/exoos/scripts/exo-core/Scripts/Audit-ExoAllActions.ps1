#Requires -Version 5.1
# Full playbook audit: every action node classified against research DB.
# Not "trust blogs" — rules cite MS docs, Internals, or known-false cargo cult.
$ErrorActionPreference = 'Continue'
$PlaybookRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path
$OutDir = Join-Path $env:ProgramData 'ExoOS\audit'
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'

# =============================================================================
# KNOWLEDGE BASE — path patterns / exact keys → verdict + rationale + source
# Verdicts:
#   PASS_MS       — Microsoft documents this behavior/value
#   PASS_REAL     — Real mechanism, intentional Exo use
#   PASS_POLICY   — Valid policy/reg for privacy/debloat, expected side effects
#   TRADEOFF      — Real but costs battery/security/compat
#   THEATER       — Documented as unused / clamped / no effect
#   FAIL_HYPE     — Common tweak that is wrong or counterproductive
#   DANGER        — Breaks security/boot/anti-cheat likely
#   NOISE         — Shell cosmetics / file associations / branding, not FPS
#   REVIEW        — Needs case-by-case / OEM specific
#   UNKNOWN       — Not in DB yet
# =============================================================================
$Rules = @()

function Rule($Pattern, $Verdict, $Why, $Source, $ValueHint = $null) {
  $script:Rules += [pscustomobject]@{
    Pattern = $Pattern; Verdict = $Verdict; Why = $Why; Source = $Source; ValueHint = $ValueHint
  }
}

# --- MMCSS (MS Learn) ---
Rule 'Multimedia\\SystemProfile$' 'PASS_MS' 'MMCSS root profile' 'learn.microsoft.com MMCSS'
Rule 'Multimedia\\SystemProfile.*SystemResponsiveness' 'SPECIAL_SR' 'SystemResponsiveness clamp rules' 'learn.microsoft.com MMCSS'
Rule 'Multimedia\\SystemProfile.*NetworkThrottlingIndex' 'PASS_COMMON' 'Default 10; 0xFFFFFFFF disables multimedia net throttle' 'community+longstanding MMCSS'
Rule 'Multimedia\\SystemProfile\\Tasks\\Games.*Scheduling Category' 'PASS_MS' 'High/Medium/Low sets priority band' 'learn.microsoft.com MMCSS'
Rule 'Multimedia\\SystemProfile\\Tasks\\Games.*Priority' 'SPECIAL_PRIO' 'Under High, Priority always treated as 2' 'learn.microsoft.com MMCSS'
Rule 'Multimedia\\SystemProfile\\Tasks\\Games.*GPU Priority' 'THEATER' 'MS: GPU Priority is not yet used' 'learn.microsoft.com MMCSS'
Rule 'Multimedia\\SystemProfile\\Tasks\\Games.*SFIO Priority' 'THEATER' 'MS: SFIO Priority is not used' 'learn.microsoft.com MMCSS'
Rule 'Multimedia\\SystemProfile\\Tasks\\Games.*Clock Rate' 'THEATER' 'Clock rate guarantee removed Win7+' 'learn.microsoft.com MMCSS'
Rule 'Multimedia\\SystemProfile\\Tasks\\' 'PASS_MS' 'MMCSS task profile keys' 'learn.microsoft.com MMCSS'

# --- Scheduler ---
Rule 'PriorityControl.*Win32PrioritySeparation' 'TRADEOFF' 'Quantum/FG boost bitfield (Internals). Feel tradeoff not free FPS' 'Windows Internals'
Rule 'PriorityControl' 'REVIEW' 'Priority control knobs' 'Windows Internals'

# --- Timer / kernel ---
Rule 'Session Manager\\kernel.*GlobalTimerResolutionRequests' 'PASS_REAL' 'Win11 timer request semantics; 1 restores process timer raise' 'Win11 kernel change'
Rule 'Session Manager\\kernel.*DistributeTimers' 'PASS_REAL' 'Timer distribution across cores when present' 'kernel'
Rule 'Session Manager\\Memory Management.*DisablePagingExecutive' 'TRADEOFF' 'Keeps kernel in RAM; needs free RAM' 'common admin'
Rule 'Session Manager\\Memory Management.*LargeSystemCache' 'TRADEOFF' 'Server-oriented; 0 usual for desktop gaming' 'MS server vs desktop'
Rule 'Session Manager\\Memory Management.*FeatureSettingsOverride' 'TRADEOFF' 'Spectre/meltdown mitigation mask — security tradeoff' 'MS security advisory'
Rule 'Session Manager\\Memory Management\\PrefetchParameters' 'TRADEOFF' 'Prefetch/SysMain; SSD debate' 'admin'
Rule 'Session Manager\\Power.*HiberbootEnabled' 'PASS_REAL' 'Fast startup; 0 cleaner boots' 'MS power'

# --- Graphics ---
Rule 'GraphicsDrivers.*HwSchMode' 'PASS_REAL' 'HAGS; 2=enabled via real Windows setting' 'Windows Settings Graphics'
Rule 'GraphicsDrivers.*TdrDelay' 'TRADEOFF' 'TDR timeout; raise reduces false resets, hides hung GPU longer' 'WDDM TDR'
Rule 'GraphicsDrivers.*TdrLevel' 'DANGER' 'TdrLevel=0 disables TDR recovery — can hang display' 'WDDM'
Rule 'DirectX\\UserGpuPreferences.*DirectXUserGlobalSettings' 'PASS_REAL' 'VRROptimize/SwapEffectUpgrade Win11 windowed path' 'MS DirectX / Win11 gaming'
Rule 'GameConfigStore' 'PASS_REAL' 'FSO/FSE/GameDVR game path settings' 'Windows Gaming'
Rule 'GameDVR' 'PASS_POLICY' 'Capture/DVR policy' 'Windows Gaming'
Rule 'GameBar' 'PASS_POLICY' 'Game Mode / Game Bar' 'Windows Gaming'

# --- Power ---
Rule 'Control\\Power\\PowerThrottling' 'PASS_REAL' 'PowerThrottlingOff real EcoQoS path' 'MS power throttling'
Rule 'Control\\Power.*CsEnabled' 'PASS_REAL' 'Connected Standby desktop off' 'MS power'
Rule 'Control\\Power\\PowerSettings' 'PASS_REAL' 'Hidden power setting Attributes unlock' 'powercfg'
Rule 'HibernateEnabled' 'PASS_REAL' 'Hibernate enable flag' 'powercfg'

# --- Network ---
Rule 'Tcpip\\Parameters\\Interfaces.*TcpAckFrequency' 'PASS_REAL' 'Nagle-related; 1 = ACK more promptly' 'TCP/IP'
Rule 'Tcpip\\Parameters\\Interfaces.*TCPNoDelay' 'PASS_REAL' 'Disable Nagle algorithm' 'TCP/IP'
Rule 'Tcpip\\Parameters\\Interfaces.*TcpDelAckTicks' 'PASS_REAL' 'Delayed ACK ticks' 'TCP/IP'
Rule 'Tcpip\\Parameters.*DefaultTTL' 'REVIEW' 'TTL rarely affects gaming latency' 'TCP/IP'
Rule 'Tcpip\\Parameters.*TcpTimedWaitDelay' 'TRADEOFF' 'TIME_WAIT reuse; server-ish' 'TCP/IP'
Rule 'Tcpip\\Parameters.*MaxUserPort' 'TRADEOFF' 'Ephemeral port range' 'TCP/IP'
Rule 'Tcpip\\Parameters.*SynAttackProtect' 'PASS_REAL' 'SYN flood protection' 'TCP/IP security'
Rule 'Tcpip\\Parameters.*EnableWsd' 'REVIEW' 'Weak host / WSD related claims vary' 'TCP/IP'
Rule 'Tcpip\\Parameters.*Tcp1323Opts' 'TRADEOFF' 'Window scaling/timestamps options' 'RFC1323'
Rule 'DeliveryOptimization' 'PASS_POLICY' 'P2P update delivery' 'MS Delivery Optimization'
Rule 'Qos.*Do not use NLA' 'PASS_REAL' 'QoS non-best-effort limit policy' 'Group Policy QoS'
Rule 'Psched' 'REVIEW' 'Packet scheduler related' 'network'

# --- Input ---
Rule 'Control Panel\\Mouse.*MouseSpeed' 'PASS_REAL' '0 disables enhance pointer precision (accel)' 'MS mouse'
Rule 'Control Panel\\Mouse.*MouseThreshold' 'PASS_REAL' 'Accel thresholds with MouseSpeed' 'MS mouse'
Rule 'Control Panel\\Mouse' 'PASS_REAL' 'Mouse input' 'MS'
Rule 'Control Panel\\Desktop.*MenuShowDelay' 'PASS_REAL' 'UI snappiness' 'shell'
Rule 'Control Panel\\Desktop.*ForegroundLockTimeout' 'PASS_REAL' 'Focus steal prevention timeout' 'shell'
Rule 'Control Panel\\Accessibility' 'PASS_REAL' 'Sticky/Filter/Toggle keys traps' 'a11y'
Rule 'Control Panel\\Desktop.*HungAppTimeout' 'PASS_REAL' 'App hang UI timeout' 'shell'
Rule 'Control Panel\\Desktop.*AutoEndTasks' 'TRADEOFF' 'Auto-end hung apps' 'shell'
Rule 'WaitToKill' 'PASS_REAL' 'Shutdown kill timeouts' 'shell'

# --- Privacy / telemetry (policy-valid, not FPS magic) ---
Rule 'AdvertisingInfo' 'PASS_POLICY' 'Advertising ID' 'privacy policy'
Rule 'ActivityFeed|PublishUserActivities|UploadUserActivities' 'PASS_POLICY' 'Timeline/activity' 'privacy'
Rule 'TailoredExperiences' 'PASS_POLICY' 'Diagnostic tailored experiences' 'privacy'
Rule 'ContentDeliveryManager' 'PASS_POLICY' 'Suggestions/silent installs' 'privacy'
Rule 'CloudContent' 'PASS_POLICY' 'Consumer experiences policy' 'privacy'
Rule 'Diags?Track|Telemetry|AllowTelemetry' 'PASS_POLICY' 'Telemetry level' 'privacy'
Rule 'Windows Search.*AllowCortana' 'PASS_POLICY' 'Cortana policy' 'privacy'
Rule 'Windows Search.*DisableWebSearch' 'PASS_POLICY' 'Web search in Start' 'privacy'
Rule 'BingSearchEnabled' 'PASS_POLICY' 'Bing in search' 'privacy'
Rule 'BackgroundAccessApplications' 'PASS_POLICY' 'UWP background apps' 'privacy'
Rule 'PushNotifications.*ToastEnabled' 'PASS_POLICY' 'Toasts' 'privacy'
Rule 'InputPersonalization|TrainedDataStore|HarvestContacts' 'PASS_POLICY' 'Typing/inking data' 'privacy'
Rule 'Location|lfsvc|SensorPermission' 'PASS_POLICY' 'Location' 'privacy'
Rule 'AppPrivacy' 'PASS_POLICY' 'Capability privacy policies' 'privacy'
Rule 'Windows\\DataCollection' 'PASS_POLICY' 'Data collection policy' 'privacy'
Rule 'SQMClient' 'PASS_POLICY' 'Customer Experience Improvement' 'privacy'
Rule 'CEIP' 'PASS_POLICY' 'CEIP' 'privacy'

# --- Defender / security ---
Rule 'Windows Defender|Windows Defender Security Center|WdNisSvc|Sense|SecurityHealth' 'TRADEOFF' 'Defender strip — security vs FPS; anti-cheat sensitive' 'MS Defender'
Rule 'DeviceGuard|HypervisorEnforcedCodeIntegrity|LsaCfgFlags|Credential Guard' 'TRADEOFF' 'VBS/HVCI/Credential Guard — latency vs security' 'MS VBS'
Rule 'VulnerableDriverBlocklist' 'TRADEOFF' 'Driver blocklist security' 'MS'
Rule 'MitigationOptions|FeatureSettings' 'TRADEOFF' 'Exploit mitigations' 'MS security'

# --- Services noise ---
Rule 'services\\DiagTrack' 'PASS_POLICY' 'Telemetry service' 'privacy'
Rule 'services\\SysMain' 'TRADEOFF' 'Superfetch; extreme SSD gaming tradeoff' 'admin'
Rule 'services\\WSearch' 'TRADEOFF' 'Search indexer CPU/IO' 'admin'
Rule 'services\\Spooler' 'TRADEOFF' 'Print spooler; breaks printing' 'admin'
Rule 'services\\DoSvc' 'PASS_POLICY' 'Delivery Optimization' 'admin'
Rule 'services\\MapsBroker' 'PASS_POLICY' 'Maps' 'debloat'
Rule 'services\\Xbl|Xbox' 'TRADEOFF' 'Xbox services; needed for some Game Pass/overlay' 'gaming'
Rule 'services\\RemoteRegistry' 'PASS_POLICY' 'Remote registry security' 'security'
Rule 'services\\RemoteAccess|TermService|UmRdpService' 'PASS_POLICY' 'Remote access' 'security'
Rule 'services\\Fax' 'PASS_POLICY' 'Fax unused on gaming PC' 'debloat'
Rule 'services\\RetailDemo' 'PASS_POLICY' 'Retail demo' 'debloat'
Rule 'services\\WbioSrvc' 'TRADEOFF' 'Biometrics' 'debloat'
Rule 'services\\PhoneSvc' 'PASS_POLICY' 'Phone linkage' 'debloat'
Rule 'services\\TabletInputService' 'TRADEOFF' 'Touch keyboard / handwriting' 'debloat'
Rule 'services\\Themes' 'TRADEOFF' 'Themes service; can break personalization' 'debloat'
Rule 'services\\FontCache' 'TRADEOFF' 'Font cache; may slow first text render' 'debloat'
Rule 'services\\LanmanServer|LanmanWorkstation' 'DANGER' 'SMB client/server; breaks shares and some apps' 'network'
Rule 'services\\WlanSvc' 'TRADEOFF' 'WLAN; kill only if pure Ethernet always' 'network'
Rule 'services\\AudioSrv|Audiosrv|AudioEndpointBuilder' 'DANGER' 'Audio — do not disable for gaming' 'audio'
Rule 'services\\wuauserv|UsoSvc|WaaSMedicSvc' 'TRADEOFF' 'Windows Update stack; pause better than kill' 'WU'
Rule 'services\\BITS' 'TRADEOFF' 'Background transfer; used by Store/WU' 'WU'
Rule 'services\\DPS|WdiServiceHost|WdiSystemHost' 'TRADEOFF' 'Diagnostics' 'debloat'
Rule 'services\\TrkWks' 'PASS_POLICY' 'Distributed link tracking' 'debloat'
Rule 'services\\PcaSvc' 'TRADEOFF' 'Program Compatibility Assistant' 'debloat'
Rule 'services\\ShellHWDetection' 'TRADEOFF' 'AutoPlay hardware events' 'debloat'
Rule 'services\\stisvc|StiSvc' 'TRADEOFF' 'Still image / scanners' 'debloat'
Rule 'services\\icssvc' 'PASS_POLICY' 'Mobile hotspot' 'debloat'
Rule 'services\\FrameServer' 'TRADEOFF' 'Windows Camera Frame Server' 'debloat'
Rule 'services\\dmwappushservice' 'PASS_POLICY' 'WAP push telemetry-ish' 'privacy'
Rule 'services\\WerSvc' 'TRADEOFF' 'Error reporting' 'privacy'
Rule 'services\\wisvc' 'PASS_POLICY' 'Windows Insider service' 'debloat'
Rule 'services\\BcastDVR|CaptureService' 'PASS_POLICY' 'Game DVR capture services' 'gaming'
Rule 'services\\GraphicsPerfSvc' 'TRADEOFF' 'Graphics performance monitor' 'debloat'
Rule 'services\\DisplayEnhancementService' 'TRADEOFF' 'Display enhancement' 'debloat'
Rule 'services\\DusmSvc' 'PASS_POLICY' 'Data usage' 'debloat'
Rule 'services\\SEMgrSvc' 'PASS_POLICY' 'Payments/NFC' 'debloat'
Rule 'services\\CscService' 'PASS_POLICY' 'Offline files' 'debloat'
Rule 'services\\SharedAccess' 'TRADEOFF' 'ICS' 'network'
Rule 'services\\SSDPSRV|upnphost|fdPHost|FDResPub' 'TRADEOFF' 'Discovery/UPnP' 'network'
Rule 'services\\PrintNotify' 'TRADEOFF' 'Print notifications' 'debloat'
Rule 'services\\Spooler' 'TRADEOFF' 'Printing' 'debloat'
Rule 'services\\' 'REVIEW' 'Service start change — verify dependency' 'admin'

# --- Bloat appx / features ---
Rule 'appx|Appx|Microsoft\.|Clipchamp|Bing|Zune|People|YourPhone|GetHelp|MixedReality' 'PASS_POLICY' 'Appx remove debloat' 'debloat'
Rule 'feature\.disable|OptionalFeature|WindowsOptionalFeature' 'TRADEOFF' 'Optional feature disable' 'DISM'
Rule 'capability\.remove' 'TRADEOFF' 'Capability remove' 'DISM'

# --- Shell cosmetics (not FPS) ---
Rule 'HKCR\\' 'NOISE' 'File association / context menu — not FPS' 'shell'
Rule 'Explorer\\Advanced' 'PASS_POLICY' 'Explorer UX' 'shell'
Rule 'Explorer\\VisualEffects|WindowMetrics|MinAnimate|DragFullWindows' 'PASS_REAL' 'Visual effect snappiness' 'shell'
Rule 'Personalize|Themes\\Personalize|EnableTransparency' 'PASS_POLICY' 'Visual personalization' 'shell'
Rule 'Taskbar' 'PASS_POLICY' 'Taskbar UX' 'shell'
Rule 'Start_Track|ShowSyncProvider' 'PASS_POLICY' 'Start tracking' 'privacy'
Rule 'Feeds|NewsAndInterests|Widgets' 'PASS_POLICY' 'Widgets/news' 'privacy'
Rule 'Serialize.*StartupDelay' 'PASS_REAL' 'Startup delay' 'shell'
Rule 'AutoplayHandlers|NoDriveTypeAutoRun' 'PASS_POLICY' 'AutoPlay' 'shell'
Rule 'Windows Error Reporting' 'PASS_POLICY' 'WER UI' 'shell'
Rule 'CrashControl' 'TRADEOFF' 'Crash dump size' 'kernel'
Rule 'Desktop.*Wallpaper|WallPaper' 'NOISE' 'Wallpaper' 'cosmetic'
Rule 'ShellNew' 'NOISE' 'New-menu templates' 'shell'

# --- Edge / OneDrive / Copilot ---
Rule 'Microsoft\\Edge|MicrosoftEdge' 'PASS_POLICY' 'Edge policy strip' 'debloat'
Rule 'OneDrive' 'PASS_POLICY' 'OneDrive' 'debloat'
Rule 'Copilot|WindowsCopilot|TurnOffWindowsCopilot' 'PASS_POLICY' 'Copilot' 'debloat'
Rule 'AI\\|Windows AI|Recall' 'PASS_POLICY' 'AI features' 'debloat'

# --- NVIDIA ---
Rule 'NVIDIA Corporation' 'REVIEW' 'Vendor-specific; validate per driver' 'NVIDIA'
Rule 'nvlddmkm' 'REVIEW' 'NVIDIA kernel driver keys' 'NVIDIA'

# --- Storage / NTFS via registry analogs ---
Rule 'FileSystem.*NtfsDisableLastAccessUpdate' 'PASS_REAL' 'Last-access updates (fsutil equivalent)' 'NTFS'
Rule 'FileSystem.*NtfsMemoryUsage' 'PASS_REAL' 'NTFS metadata cache' 'NTFS'
Rule 'FileSystem.*DisableDeleteNotify' 'PASS_REAL' 'TRIM' 'storage'

# --- Boot / BCD related registry ---
Rule 'BCD|bootmgr|MemTest' 'REVIEW' 'Boot config related' 'BCD'

# --- Scheduled tasks (pattern on description/id) ---
Rule 'Application Experience|Compatibility Appraiser|ProgramDataUpdater' 'PASS_POLICY' 'Compat telemetry tasks' 'privacy'
Rule 'Customer Experience Improvement|Consolidator|UsbCeip|KernelCeip' 'PASS_POLICY' 'CEIP tasks' 'privacy'
Rule 'DiskDiagnostic' 'PASS_POLICY' 'Disk diagnostic data' 'privacy'
Rule 'Feedback\\Siuf|DmClient' 'PASS_POLICY' 'Feedback' 'privacy'
Rule 'Maps\\Maps' 'PASS_POLICY' 'Maps update tasks' 'debloat'
Rule 'Windows Error Reporting\\QueueReporting' 'PASS_POLICY' 'WER queue' 'privacy'
Rule 'FamilySafety' 'PASS_POLICY' 'Family safety' 'debloat'
Rule 'CloudExperienceHost' 'PASS_POLICY' 'Cloud experience' 'debloat'
Rule 'UpdateOrchestrator|WindowsUpdate' 'TRADEOFF' 'WU tasks; pause preferred over hard kill' 'WU'
Rule 'Xbl|Xbox' 'TRADEOFF' 'Xbox tasks' 'gaming'
Rule 'NVIDIA|NvTm|NvDriver' 'PASS_POLICY' 'NVIDIA telemetry tasks' 'vendor'

# --- Dangerous / known bad myths ---
Rule 'SystemResponsiveness' 'SPECIAL_SR' 'see value rules' 'MS MMCSS'
Rule 'Win32PrioritySeparation' 'TRADEOFF' 'see scheduler' 'Internals'
Rule 'SvcHostSplitDisable' 'TRADEOFF' 'Service host grouping; stability tradeoff' 'admin'
Rule 'EnablePrefetcher|EnableSuperfetch' 'TRADEOFF' 'Prefetch' 'admin'
Rule 'ClearPageFileAtShutdown' 'TRADEOFF' 'Security vs shutdown speed' 'security'
Rule 'DisableExceptionChainValidation|DisableHeapTerminator' 'DANGER' 'Weakens exploit protection' 'security'
Rule 'MoveImages|ASLR' 'DANGER' 'Disabling ASLR is security theater for FPS' 'security'
Rule 'TSX|Speculative' 'TRADEOFF' 'Speculative execution mitigations' 'security'

# --- Identity / cosmetic Exo branding ---
Rule 'SOFTWARE\\ExoOS|Exo OS|OEMInformation|RegisteredOwner' 'NOISE' 'Branding/marker' 'exo'
Rule 'RegisteredOrganization' 'NOISE' 'Branding' 'exo'

function Get-VerdictForAction {
  param($Type, $Path, $ValueName, $Value, $Service, $Extra)

  $blob = (@($Type, $Path, $ValueName, $Value, $Service, $Extra) -join ' | ')
  $pathName = "$Path\$ValueName"

  # Special: SystemResponsiveness value
  if ($ValueName -match 'SystemResponsiveness' -or $pathName -match 'SystemResponsiveness') {
    $n = $null
    try { $n = [int64]$Value } catch { }
    if ($null -ne $n) {
      if ($n -lt 10 -and $n -ge 0) {
        return [pscustomobject]@{ Verdict='FAIL_HYPE'; Why="SystemResponsiveness=$n clamps to 20 per MS (values <10). Use 10."; Source='learn.microsoft.com MMCSS'; Matched='SystemResponsiveness' }
      }
      if ($n -eq 100) {
        return [pscustomobject]@{ Verdict='TRADEOFF'; Why='100 disables MMCSS entirely'; Source='learn.microsoft.com MMCSS'; Matched='SystemResponsiveness' }
      }
      if ($n -eq 10) {
        return [pscustomobject]@{ Verdict='PASS_MS'; Why='10% low-priority reserve; min valid non-default'; Source='learn.microsoft.com MMCSS'; Matched='SystemResponsiveness' }
      }
      if ($n -eq 20) {
        return [pscustomobject]@{ Verdict='OK_STOCK'; Why='Default 20% reserve'; Source='learn.microsoft.com MMCSS'; Matched='SystemResponsiveness' }
      }
    }
  }

  # Special: Games Priority under High
  if ($Path -match 'Tasks\\Games' -and $ValueName -match '^Priority$') {
    $n = $null; try { $n = [int]$Value } catch {}
    if ($n -and $n -ne 2) {
      return [pscustomobject]@{ Verdict='THEATER'; Why="Priority=$n under Scheduling Category High is forced to 2 by MMCSS"; Source='learn.microsoft.com MMCSS'; Matched='Games Priority' }
    }
  }

  # Special: TdrLevel 0
  if ($ValueName -match 'TdrLevel') {
    $n = $null; try { $n = [int]$Value } catch {}
    if ($n -eq 0) {
      return [pscustomobject]@{ Verdict='DANGER'; Why='TdrLevel=0 disables GPU timeout detection'; Source='WDDM TDR'; Matched='TdrLevel' }
    }
  }

  # Special: NetworkThrottlingIndex
  if ($ValueName -match 'NetworkThrottlingIndex') {
    $n = $null
    try {
      if ($Value -match '4294967295|0x[fF]{8}|-1') { $n = [uint32]::MaxValue }
      else { $n = [uint64]$Value }
    } catch {}
    if ($n -eq [uint32]::MaxValue -or $Value -match 'ffffffff|4294967295') {
      return [pscustomobject]@{ Verdict='PASS_COMMON'; Why='0xFFFFFFFF disables MMCSS network throttle'; Source='MMCSS community+observed'; Matched='NetworkThrottlingIndex' }
    }
    if ($n -eq 10) {
      return [pscustomobject]@{ Verdict='OK_STOCK'; Why='Default throttle index 10'; Source='MMCSS'; Matched='NetworkThrottlingIndex' }
    }
  }

  # Type-level defaults
  if ($Type -eq 'note') {
    return [pscustomobject]@{ Verdict='NOISE'; Why='Documentation note only'; Source='playbook'; Matched='note' }
  }
  if ($Type -eq 'appx.remove') {
    return [pscustomobject]@{ Verdict='PASS_POLICY'; Why='Appx package remove (debloat)'; Source='Appx'; Matched='appx.remove' }
  }
  if ($Type -eq 'task.disable') {
    $t = "$Path $Value $Extra $Service"
    foreach ($r in $Rules) {
      if ($t -match $r.Pattern -and $r.Verdict -ne 'SPECIAL_SR' -and $r.Verdict -ne 'SPECIAL_PRIO') {
        return [pscustomobject]@{ Verdict=$r.Verdict; Why=$r.Why; Source=$r.Source; Matched=$r.Pattern }
      }
    }
    return [pscustomobject]@{ Verdict='PASS_POLICY'; Why='Scheduled task disable (debloat default)'; Source='Task Scheduler'; Matched='task.disable' }
  }
  if ($Type -eq 'service.set') {
    $s = if ($Service) { $Service } else { $Path }
    $blobSvc = "services\$s $Extra"
    foreach ($r in $Rules) {
      if ($blobSvc -match $r.Pattern -or $s -match $r.Pattern) {
        if ($r.Verdict -in @('SPECIAL_SR','SPECIAL_PRIO')) { continue }
        return [pscustomobject]@{ Verdict=$r.Verdict; Why="$($r.Why) (service $s)"; Source=$r.Source; Matched=$r.Pattern }
      }
    }
    return [pscustomobject]@{ Verdict='REVIEW'; Why="Service $s not in curated map — check dependencies"; Source='service map incomplete'; Matched='service.fallback' }
  }
  if ($Type -eq 'feature.disable' -or $Type -eq 'capability.remove') {
    return [pscustomobject]@{ Verdict='TRADEOFF'; Why='Optional Windows component removal'; Source='DISM'; Matched=$Type }
  }
  if ($Type -eq 'taskkill') {
    return [pscustomobject]@{ Verdict='TRADEOFF'; Why='Process kill at apply time'; Source='runtime'; Matched='taskkill' }
  }
  if ($Type -eq 'run') {
    $runBlob = "$Path $Value $Extra $ValueName"
    if ($runBlob -match 'bcdedit') {
      if ($runBlob -match 'hypervisorlaunchtype') {
        return [pscustomobject]@{ Verdict='TRADEOFF'; Why='Hypervisor off — VBS/HVCI/WSL2 impact'; Source='BCD'; Matched='bcdedit hypervisor' }
      }
      if ($runBlob -match 'useplatformtick|disabledynamictick|useplatformclock') {
        return [pscustomobject]@{ Verdict='REVIEW'; Why='Timer BCD stack; mixed evidence; measure'; Source='BCD/Blur Busters'; Matched='bcdedit timer' }
      }
      return [pscustomobject]@{ Verdict='REVIEW'; Why='BCD edit — boot impact'; Source='BCD'; Matched='bcdedit' }
    }
    if ($runBlob -match 'powercfg|Apply-ExoPowerPlan|Apply-ExoFullStack') {
      return [pscustomobject]@{ Verdict='PASS_REAL'; Why='Power plan / full stack orchestrator'; Source='powercfg'; Matched='power run' }
    }
    if ($runBlob -match 'Pause-WindowsUpdate|wuau') {
      return [pscustomobject]@{ Verdict='PASS_POLICY'; Why='WU pause (resumable) preferred over kill'; Source='WU'; Matched='wu pause' }
    }
    if ($runBlob -match 'fsutil') {
      return [pscustomobject]@{ Verdict='PASS_REAL'; Why='NTFS/fsutil behavior'; Source='fsutil'; Matched='fsutil' }
    }
    if ($runBlob -match 'netsh') {
      return [pscustomobject]@{ Verdict='PASS_REAL'; Why='TCP stack netsh'; Source='netsh'; Matched='netsh' }
    }
    if ($runBlob -match 'DisableVBS|Defender|DisableDefender') {
      return [pscustomobject]@{ Verdict='TRADEOFF'; Why='Security feature disable script'; Source='security'; Matched='security script' }
    }
    if ($runBlob -match 'Install-|winget|DirectX|VCRedist|DotNet') {
      return [pscustomobject]@{ Verdict='PASS_REAL'; Why='Gaming runtime dependency install'; Source='deps'; Matched='install' }
    }
    return [pscustomobject]@{ Verdict='REVIEW'; Why='Run action — inspect script/args'; Source='run'; Matched='run.fallback' }
  }
  if ($Type -eq 'registry.delete') {
    return [pscustomobject]@{ Verdict='REVIEW'; Why='Registry delete — verify key purpose'; Source='registry'; Matched='registry.delete' }
  }

  # registry.set path matching
  $search = "$Path\$ValueName"
  # Prefer longest/most specific rule by scanning all and picking best
  $best = $null
  $bestLen = -1
  foreach ($r in $Rules) {
    if ($r.Verdict -in @('SPECIAL_SR','SPECIAL_PRIO')) { continue }
    if ($search -match $r.Pattern -or $Path -match $r.Pattern -or $ValueName -match $r.Pattern) {
      $len = $r.Pattern.Length
      if ($len -gt $bestLen) {
        $bestLen = $len
        $best = $r
      }
    }
  }
  if ($best) {
    return [pscustomobject]@{ Verdict=$best.Verdict; Why=$best.Why; Source=$best.Source; Matched=$best.Pattern }
  }

  # Heuristic buckets for residual registry
  if ($Path -match 'HKCR|HKEY_CLASSES_ROOT') {
    return [pscustomobject]@{ Verdict='NOISE'; Why='HKCR shell/association'; Source='heuristic'; Matched='HKCR' }
  }
  if ($Path -match 'Policies\\') {
    return [pscustomobject]@{ Verdict='PASS_POLICY'; Why='Group Policy-style registry policy'; Source='heuristic'; Matched='Policies' }
  }
  if ($Path -match 'CurrentVersion\\Explorer|Start Menu|Taskband') {
    return [pscustomobject]@{ Verdict='PASS_POLICY'; Why='Shell/Explorer UX'; Source='heuristic'; Matched='Explorer' }
  }
  if ($Path -match 'Windows NT\\CurrentVersion\\Windows|Winlogon') {
    return [pscustomobject]@{ Verdict='REVIEW'; Why='Winlogon/session — careful'; Source='heuristic'; Matched='Winlogon' }
  }
  if ($Path -match 'Control\\Class\\\{4d36c|USB|HID|Keyboard|Mouse') {
    return [pscustomobject]@{ Verdict='REVIEW'; Why='Device class power/input — validate per hardware'; Source='heuristic'; Matched='device class' }
  }
  if ($Path -match 'Control\\Session Manager|Control\\FileSystem|Control\\Priority') {
    return [pscustomobject]@{ Verdict='REVIEW'; Why='Kernel/session manager residual'; Source='heuristic'; Matched='session residual' }
  }
  if ($Path -match 'Microsoft\\Windows\\CurrentVersion') {
    return [pscustomobject]@{ Verdict='REVIEW'; Why='Windows CurrentVersion residual policy/UX'; Source='heuristic'; Matched='CurrentVersion residual' }
  }

  return [pscustomobject]@{ Verdict='UNKNOWN'; Why='No rule or heuristic matched — needs manual research'; Source='none'; Matched='' }
}

# =============================================================================
# PARSE ALL YAML ACTIONS (structure-aware enough for our playbooks)
# =============================================================================
Write-Host "[Audit] Parsing playbook under $PlaybookRoot ..."
$actions = New-Object System.Collections.Generic.List[object]
$files = Get-ChildItem (Join-Path $PlaybookRoot 'actions') -Recurse -Include *.yml,*.yaml -File

foreach ($file in $files) {
  $rel = $file.FullName.Substring($PlaybookRoot.Length).TrimStart('\','/')
  $lines = Get-Content -LiteralPath $file.FullName
  $cur = $null
  $inActions = $false

  for ($i = 0; $i -lt $lines.Count; $i++) {
    $line = $lines[$i]
    if ($line -match '^\s*actions:\s*$') { $inActions = $true; continue }
    if (-not $inActions -and $line -match '^\s*-\s*type:\s*') { $inActions = $true }

    if ($line -match '^\s*-\s*type:\s*(\S+)\s*$') {
      if ($cur) { $actions.Add($cur) | Out-Null }
      $cur = [ordered]@{
        File = $rel; Line = $i + 1; Type = $Matches[1]
        Id = ''; Path = ''; ValueName = ''; ValueType = ''; Value = ''
        Service = ''; Start = ''; Description = ''; Args = ''; WhenOption = ''
        TaskName = ''; Package = ''; Feature = ''; Capability = ''
      }
      continue
    }
    if (-not $cur) { continue }

    if ($line -match '^\s+id:\s*[''"]?([^''"#]+?)[''"]?\s*(?:#.*)?$') { $cur.Id = $Matches[1].Trim(); continue }
    if ($line -match '^\s+path:\s*[''"]?(.*?)[''"]?\s*$') { $cur.Path = $Matches[1].Trim().Trim("'").Trim('"'); continue }
    if ($line -match '^\s+valueName:\s*[''"]?(.*?)[''"]?\s*$') { $cur.ValueName = $Matches[1].Trim().Trim("'").Trim('"'); continue }
    if ($line -match '^\s+valueType:\s*(\S+)\s*$') { $cur.ValueType = $Matches[1].Trim(); continue }
    if ($line -match '^\s+value:\s*[''"]?(.*?)[''"]?\s*$') { $cur.Value = $Matches[1].Trim().Trim("'").Trim('"'); continue }
    if ($line -match '^\s+service:\s*[''"]?(.*?)[''"]?\s*$') { $cur.Service = $Matches[1].Trim().Trim("'").Trim('"'); continue }
    if ($line -match '^\s+start:\s*(\S+)\s*$') { $cur.Start = $Matches[1].Trim(); continue }
    if ($line -match '^\s+description:\s*[''">]?\s*(.*)$') {
      $d = $Matches[1].Trim().Trim("'").Trim('"')
      if ($d -eq '>' -or $d -eq '|') {
        # folded scalar — grab next indented lines lightly
        $buf = @()
        while ($i + 1 -lt $lines.Count -and $lines[$i+1] -match '^\s{4,}') {
          $i++; $buf += $lines[$i].Trim()
        }
        $cur.Description = ($buf -join ' ')
      } else { $cur.Description = $d }
      continue
    }
    if ($line -match '^\s+args:\s*>?\s*(.*)$') {
      $a = $Matches[1].Trim()
      if ($a -eq '' -or $line -match 'args:\s*>') {
        $buf = @()
        while ($i + 1 -lt $lines.Count -and $lines[$i+1] -match '^\s{4,}') {
          $i++; $buf += $lines[$i].Trim()
        }
        $cur.Args = ($buf -join ' ')
      } else { $cur.Args = $a.Trim("'").Trim('"') }
      continue
    }
    if ($line -match '^\s+file:\s*[''"]?(.*?)[''"]?\s*$') { $cur.Path = $Matches[1].Trim().Trim("'").Trim('"'); continue }
    if ($line -match '^\s+whenOption:\s*(\S+)\s*$') { $cur.WhenOption = $Matches[1].Trim(); continue }
    if ($line -match '^\s+taskName:\s*[''"]?(.*?)[''"]?\s*$') { $cur.TaskName = $Matches[1].Trim().Trim("'").Trim('"'); continue }
    if ($line -match '^\s+taskPath:\s*[''"]?(.*?)[''"]?\s*$') { $cur.Path = $Matches[1].Trim().Trim("'").Trim('"'); continue }
    if ($line -match '^\s+package:\s*[''"]?(.*?)[''"]?\s*$') { $cur.Package = $Matches[1].Trim().Trim("'").Trim('"'); continue }
    if ($line -match '^\s+name:\s*[''"]?(.*?)[''"]?\s*$' -and $cur.Type -match 'feature|capability|appx|task') {
      $cur.Feature = $Matches[1].Trim().Trim("'").Trim('"'); continue
    }
  }
  if ($cur) { $actions.Add($cur) | Out-Null }
}

Write-Host "[Audit] Parsed $($actions.Count) actions from $($files.Count) files"
Write-Host "[Audit] Classifying..."

$classified = New-Object System.Collections.Generic.List[object]
$n = 0
foreach ($a in $actions) {
  $n++
  if ($n % 500 -eq 0) { Write-Host "  ... $n /$($actions.Count)" }
  $extra = @(
    $a.Description, $a.Args, $a.TaskName, $a.Package, $a.Feature, $a.Start, $a.WhenOption
  ) -join ' '
  $v = Get-VerdictForAction -Type $a.Type -Path $a.Path -ValueName $a.ValueName -Value $a.Value -Service $a.Service -Extra $extra
  $classified.Add([pscustomobject]@{
    File = $a.File
    Line = $a.Line
    Id = $a.Id
    Type = $a.Type
    Path = $a.Path
    ValueName = $a.ValueName
    Value = $a.Value
    Service = $a.Service
    Start = $a.Start
    WhenOption = $a.WhenOption
    TaskName = $a.TaskName
    Package = $a.Package
    Description = $a.Description
    Args = $a.Args
    Verdict = $v.Verdict
    Why = $v.Why
    Source = $v.Source
    MatchedRule = $v.Matched
    Fingerprint = ("{0}|{1}|{2}|{3}|{4}|{5}" -f $a.Type, $a.Path, $a.ValueName, $a.Value, $a.Service, $a.Start).ToLowerInvariant()
  }) | Out-Null
}

# Dedupe stats
$unique = $classified | Group-Object Fingerprint

# Summary
$byVerdict = $classified | Group-Object Verdict | Sort-Object Count -Descending
$byType = $classified | Group-Object Type | Sort-Object Count -Descending

$csvAll = Join-Path $OutDir "all-actions-$stamp.csv"
$csvUnique = Join-Path $OutDir "unique-tweaks-$stamp.csv"
$csvFail = Join-Path $OutDir "fail-theater-danger-$stamp.csv"
$csvUnknown = Join-Path $OutDir "unknown-$stamp.csv"
$summary = Join-Path $OutDir "SUMMARY-$stamp.txt"

$classified | Export-Csv -NoTypeInformation -Encoding UTF8 -Path $csvAll

# Unique fingerprints with worst verdict priority
$sev = @{
  DANGER=0; FAIL_HYPE=1; FAIL_YAML=2; THEATER=3; UNKNOWN=4; REVIEW=5; REVIEW_MEASURE=6
  TRADEOFF=7; PASS_POLICY=8; PASS_COMMON=9; PASS_REAL=10; PASS_MS=11; OK_STOCK=12; NOISE=13
}
$uniqueRows = foreach ($g in $unique) {
  $items = $g.Group
  $worst = $items | Sort-Object { if ($sev.ContainsKey($_.Verdict)) { $sev[$_.Verdict] } else { 50 } } | Select-Object -First 1
  [pscustomobject]@{
    Count = $g.Count
    Verdict = $worst.Verdict
    Why = $worst.Why
    Source = $worst.Source
    Type = $worst.Type
    Path = $worst.Path
    ValueName = $worst.ValueName
    Value = $worst.Value
    Service = $worst.Service
    Start = $worst.Start
    ExampleFile = $worst.File
    ExampleId = $worst.Id
    Fingerprint = $g.Name
  }
}
$uniqueRows | Sort-Object @{e={ if ($sev.ContainsKey($_.Verdict)) { $sev[$_.Verdict] } else { 50 } }}, Count -Descending |
  Export-Csv -NoTypeInformation -Encoding UTF8 -Path $csvUnique

$classified | Where-Object { $_.Verdict -match 'FAIL|THEATER|DANGER' } |
  Export-Csv -NoTypeInformation -Encoding UTF8 -Path $csvFail
$classified | Where-Object { $_.Verdict -eq 'UNKNOWN' } |
  Export-Csv -NoTypeInformation -Encoding UTF8 -Path $csvUnknown

# UNKNOWN path frequency for research queue
$unkPaths = $classified | Where-Object Verdict -eq 'UNKNOWN' |
  Group-Object { "$($_.Path) :: $($_.ValueName)" } | Sort-Object Count -Descending

$sb = New-Object System.Text.StringBuilder
[void]$sb.AppendLine("Exo FULL ACTION AUDIT  $stamp")
[void]$sb.AppendLine("Playbook: $PlaybookRoot")
[void]$sb.AppendLine("Total actions parsed: $($classified.Count)")
[void]$sb.AppendLine("Unique fingerprints:  $($unique.Count)")
[void]$sb.AppendLine("Knowledge rules:      $($Rules.Count)")
[void]$sb.AppendLine('')
[void]$sb.AppendLine('=== BY VERDICT (all action nodes) ===')
foreach ($g in $byVerdict) {
  $pct = [math]::Round(100.0 * $g.Count / [math]::Max(1,$classified.Count), 1)
  [void]$sb.AppendLine(('{0,-16} {1,6}  {2,5}%' -f $g.Name, $g.Count, $pct))
}
[void]$sb.AppendLine('')
[void]$sb.AppendLine('=== BY TYPE ===')
foreach ($g in $byType) { [void]$sb.AppendLine(('{0,-20} {1,6}' -f $g.Name, $g.Count)) }
[void]$sb.AppendLine('')
[void]$sb.AppendLine('=== FAIL / THEATER / DANGER (unique) ===')
$badU = $uniqueRows | Where-Object { $_.Verdict -match 'FAIL|THEATER|DANGER' } | Sort-Object Verdict, Count -Descending
foreach ($b in $badU | Select-Object -First 80) {
  [void]$sb.AppendLine("[$($b.Verdict)] x$($b.Count) $($b.Path) | $($b.ValueName)=$($b.Value) :: $($b.Why)")
}
[void]$sb.AppendLine('')
[void]$sb.AppendLine("=== UNKNOWN top paths (research queue, $($unkPaths.Count) distinct) ===")
foreach ($u in $unkPaths | Select-Object -First 100) {
  [void]$sb.AppendLine("x$($u.Count)  $($u.Name)")
}
[void]$sb.AppendLine('')
[void]$sb.AppendLine('=== COVERAGE ===')
$known = ($classified | Where-Object { $_.Verdict -ne 'UNKNOWN' }).Count
$unk = ($classified | Where-Object { $_.Verdict -eq 'UNKNOWN' }).Count
[void]$sb.AppendLine("Classified (non-UNKNOWN): $known / $($classified.Count) ($([math]::Round(100*$known/$classified.Count,1))%)")
[void]$sb.AppendLine("UNKNOWN residual:         $unk")
[void]$sb.AppendLine('')
[void]$sb.AppendLine("CSV all:     $csvAll")
[void]$sb.AppendLine("CSV unique:  $csvUnique")
[void]$sb.AppendLine("CSV bad:     $csvFail")
[void]$sb.AppendLine("CSV unknown: $csvUnknown")

$txt = $sb.ToString()
$txt | Set-Content -Path $summary -Encoding UTF8
Write-Host $txt
Write-Host "[Audit] Done."
# Also copy stable names
Copy-Item $csvAll (Join-Path $OutDir 'all-actions-latest.csv') -Force
Copy-Item $csvUnique (Join-Path $OutDir 'unique-tweaks-latest.csv') -Force
Copy-Item $csvFail (Join-Path $OutDir 'fail-theater-danger-latest.csv') -Force
Copy-Item $csvUnknown (Join-Path $OutDir 'unknown-latest.csv') -Force
Copy-Item $summary (Join-Path $OutDir 'SUMMARY-latest.txt') -Force
exit 0
