#!/usr/bin/env python3
"""Full Exo playbook audit: classify every action against research DB."""
from __future__ import annotations
import csv, os, re, sys
from collections import Counter, defaultdict
from datetime import datetime
from pathlib import Path

PLAYBOOK = Path(__file__).resolve().parents[3]
ACTIONS = PLAYBOOK / "actions"
OUT = Path(os.environ.get("PROGRAMDATA", "C:/ProgramData")) / "ExoOS" / "audit"
OUT.mkdir(parents=True, exist_ok=True)
STAMP = datetime.now().strftime("%Y%m%d-%H%M%S")

# path-pattern rules: (regex, verdict, why, source)
RULES: list[tuple[str, str, str, str]] = [
    (r"Multimedia\\SystemProfile.*SystemResponsiveness", "SPECIAL_SR", "MS clamp rules", "learn.microsoft.com MMCSS"),
    (r"Multimedia\\SystemProfile.*NetworkThrottlingIndex", "PASS_COMMON", "Default 10; FFFFFFFF disables", "MMCSS"),
    (r"Multimedia\\SystemProfile\\Tasks\\Games.*Scheduling Category", "PASS_MS", "High/Medium/Low sets priority band", "learn.microsoft.com MMCSS"),
    (r"Multimedia\\SystemProfile\\Tasks\\Games.*Priority", "SPECIAL_PRIO", "Under High Priority forced to 2", "learn.microsoft.com MMCSS"),
    (r"Multimedia\\SystemProfile\\Tasks\\Games.*GPU Priority", "THEATER", "MS: GPU Priority not yet used", "learn.microsoft.com MMCSS"),
    (r"Multimedia\\SystemProfile\\Tasks\\Games.*SFIO Priority", "THEATER", "MS: SFIO Priority not used", "learn.microsoft.com MMCSS"),
    (r"Multimedia\\SystemProfile\\Tasks\\Games.*Clock Rate", "THEATER", "Clock rate guarantee removed Win7+", "learn.microsoft.com MMCSS"),
    (r"Multimedia\\SystemProfile\\Tasks\\", "PASS_MS", "MMCSS task profile", "learn.microsoft.com MMCSS"),
    (r"Multimedia\\SystemProfile", "PASS_MS", "MMCSS root", "learn.microsoft.com MMCSS"),
    (r"PriorityControl.*Win32PrioritySeparation", "TRADEOFF", "Quantum/FG boost bitfield", "Windows Internals"),
    (r"Session Manager\\kernel.*GlobalTimerResolutionRequests", "PASS_REAL", "Win11 timer request restore", "Win11 kernel"),
    (r"Session Manager\\kernel.*DistributeTimers", "PASS_REAL", "Timer IRQ distribution", "kernel"),
    (r"Session Manager\\Memory Management.*DisablePagingExecutive", "TRADEOFF", "Kernel locked in RAM", "admin"),
    (r"Session Manager\\Memory Management.*LargeSystemCache", "TRADEOFF", "Server vs desktop cache", "MS"),
    (r"Session Manager\\Memory Management.*FeatureSettingsOverride", "TRADEOFF", "Mitigation mask", "MS security"),
    (r"Session Manager\\Memory Management\\PrefetchParameters", "TRADEOFF", "Prefetch/SysMain", "admin"),
    (r"Session Manager\\Power.*HiberbootEnabled", "PASS_REAL", "Fast startup", "MS power"),
    (r"GraphicsDrivers.*HwSchMode", "PASS_REAL", "HAGS", "Windows Graphics"),
    (r"GraphicsDrivers.*TdrDelay", "TRADEOFF", "TDR timeout", "WDDM"),
    (r"GraphicsDrivers.*TdrLevel", "DANGER", "TdrLevel 0 disables recovery", "WDDM"),
    (r"DirectX\\UserGpuPreferences", "PASS_REAL", "VRR/SwapEffect", "MS DirectX"),
    (r"GameConfigStore", "PASS_REAL", "FSO/FSE/GameDVR", "Windows Gaming"),
    (r"GameDVR", "PASS_POLICY", "Capture policy", "Windows Gaming"),
    (r"GameBar", "PASS_POLICY", "Game Mode/Bar", "Windows Gaming"),
    (r"Power\\PowerThrottling", "PASS_REAL", "EcoQoS", "MS power throttling"),
    (r"Control\\Power.*CsEnabled", "PASS_REAL", "Connected Standby", "MS power"),
    (r"Control\\Power\\PowerSettings", "PASS_REAL", "Power Attributes", "powercfg"),
    (r"Tcpip\\Parameters\\Interfaces.*TcpAckFrequency", "PASS_REAL", "Nagle ACK", "TCP/IP"),
    (r"Tcpip\\Parameters\\Interfaces.*TCPNoDelay", "PASS_REAL", "Disable Nagle", "TCP/IP"),
    (r"Tcpip\\Parameters\\Interfaces.*TcpDelAckTicks", "PASS_REAL", "Delayed ACK", "TCP/IP"),
    (r"Tcpip\\Parameters.*DefaultTTL", "REVIEW", "TTL rarely gaming-relevant", "TCP/IP"),
    (r"Tcpip\\Parameters.*TcpTimedWaitDelay", "TRADEOFF", "TIME_WAIT", "TCP/IP"),
    (r"Tcpip\\Parameters.*MaxUserPort", "TRADEOFF", "Ephemeral ports", "TCP/IP"),
    (r"Tcpip\\Parameters.*SynAttackProtect", "PASS_REAL", "SYN protect", "TCP security"),
    (r"Tcpip\\Parameters.*Tcp1323Opts", "TRADEOFF", "RFC1323 opts", "RFC1323"),
    (r"Tcpip\\Parameters", "REVIEW", "TCP residual", "TCP/IP"),
    (r"DeliveryOptimization", "PASS_POLICY", "P2P updates", "MS DO"),
    (r"Control Panel\\Mouse", "PASS_REAL", "Mouse accel", "MS mouse"),
    (r"Control Panel\\Desktop", "PASS_REAL", "Desktop UI timeouts", "shell"),
    (r"Control Panel\\Accessibility", "PASS_REAL", "Sticky keys", "a11y"),
    (r"WaitToKill", "PASS_REAL", "Shutdown timeouts", "shell"),
    (r"AdvertisingInfo", "PASS_POLICY", "Ad ID", "privacy"),
    (r"ActivityFeed|PublishUserActivities|UploadUserActivities", "PASS_POLICY", "Timeline", "privacy"),
    (r"TailoredExperiences", "PASS_POLICY", "Tailored diagnostics", "privacy"),
    (r"ContentDeliveryManager", "PASS_POLICY", "Suggestions", "privacy"),
    (r"CloudContent", "PASS_POLICY", "Consumer features", "privacy"),
    (r"AllowTelemetry|DataCollection|SQMClient", "PASS_POLICY", "Telemetry", "privacy"),
    (r"AllowCortana|DisableWebSearch|BingSearchEnabled", "PASS_POLICY", "Search", "privacy"),
    (r"BackgroundAccessApplications", "PASS_POLICY", "UWP background", "privacy"),
    (r"PushNotifications", "PASS_POLICY", "Toasts", "privacy"),
    (r"InputPersonalization|TrainedDataStore|HarvestContacts", "PASS_POLICY", "Typing data", "privacy"),
    (r"Windows Defender|Windows Defender Security Center|WdNis|SecurityHealth", "TRADEOFF", "Defender", "MS Defender"),
    (r"DeviceGuard|HypervisorEnforcedCodeIntegrity|LsaCfgFlags", "TRADEOFF", "VBS/HVCI", "MS VBS"),
    (r"Explorer\\Advanced|Explorer\\VisualEffects|WindowMetrics", "PASS_POLICY", "Explorer UX", "shell"),
    (r"Personalize|EnableTransparency", "PASS_POLICY", "Personalization", "shell"),
    (r"Taskbar|Feeds|Widgets|NewsAndInterests", "PASS_POLICY", "Taskbar/widgets", "shell"),
    (r"StartupDelayInMSec|Serialize", "PASS_REAL", "Startup delay", "shell"),
    (r"AutoplayHandlers|NoDriveTypeAutoRun", "PASS_POLICY", "AutoPlay", "shell"),
    (r"Windows Error Reporting", "PASS_POLICY", "WER", "shell"),
    (r"CrashControl", "TRADEOFF", "Crash dumps", "kernel"),
    (r"Microsoft\\Edge|MicrosoftEdge", "PASS_POLICY", "Edge", "debloat"),
    (r"OneDrive", "PASS_POLICY", "OneDrive", "debloat"),
    (r"Copilot|WindowsCopilot|TurnOffWindowsCopilot", "PASS_POLICY", "Copilot", "debloat"),
    (r"NVIDIA Corporation|nvlddmkm", "REVIEW", "NVIDIA vendor", "NVIDIA"),
    (r"NtfsDisableLastAccessUpdate|NtfsMemoryUsage|DisableDeleteNotify", "PASS_REAL", "NTFS", "NTFS"),
    (r"HKCR\\|HKEY_CLASSES_ROOT", "NOISE", "File associations not FPS", "shell"),
    (r"ShellNew", "NOISE", "New menu", "shell"),
    (r"SOFTWARE\\ExoOS|OEMInformation|RegisteredOwner|RegisteredOrganization", "NOISE", "Branding", "exo"),
    (r"Policies\\", "PASS_POLICY", "Policy registry", "policy"),
    (r"SvcHostSplitDisable", "TRADEOFF", "Service host grouping", "admin"),
    (r"ClearPageFileAtShutdown", "TRADEOFF", "Pagefile wipe", "security"),
    (r"Application Experience|Compatibility Appraiser|ProgramDataUpdater", "PASS_POLICY", "Compat task", "privacy"),
    (r"Customer Experience Improvement|Consolidator|UsbCeip|KernelCeip", "PASS_POLICY", "CEIP", "privacy"),
    (r"DiskDiagnostic", "PASS_POLICY", "Disk diagnostic", "privacy"),
    (r"Feedback\\Siuf|DmClient", "PASS_POLICY", "Feedback", "privacy"),
    (r"Maps\\Maps|MapsToast|MapsUpdate", "PASS_POLICY", "Maps", "debloat"),
    (r"FamilySafety", "PASS_POLICY", "Family safety", "debloat"),
    (r"CloudExperienceHost", "PASS_POLICY", "Cloud experience", "debloat"),
    (r"UpdateOrchestrator|WindowsUpdate", "TRADEOFF", "WU tasks prefer pause", "WU"),
    (r"VulnerableDriverBlocklist", "TRADEOFF", "Driver blocklist", "MS"),
    (r"AppPrivacy", "PASS_POLICY", "Capability privacy", "privacy"),
    (r"Winlogon", "REVIEW", "Winlogon", "shell"),
    (r"Control\\Class\\", "REVIEW", "Device class", "drivers"),
    (r"Control\\Session Manager", "REVIEW", "Session manager residual", "kernel"),
    (r"Microsoft\\Windows\\CurrentVersion", "REVIEW", "CurrentVersion residual", "windows"),
    (r"SYSTEM\\CurrentControlSet\\Services\\", "REVIEW", "Service params registry", "services"),
    (r"SOFTWARE\\Microsoft\\Windows", "REVIEW", "Windows software residual", "windows"),
    (r"HKCU\\|HKEY_CURRENT_USER", "REVIEW", "HKCU residual", "registry"),
    (r"HKLM\\|HKEY_LOCAL_MACHINE", "REVIEW", "HKLM residual", "registry"),
]

# Compact service map: name -> verdict
SVC = {}
for names, v in [
    ("DiagTrack dmwappushservice RetailDemo MapsBroker lfsvc PhoneSvc wisvc RemoteRegistry RemoteAccess TermService UmRdpService SessionEnv TrkWks CscService SEMgrSvc icssvc DusmSvc Fax WMPNetworkSvc WpcMonSvc MessagingService OneSyncSvc PimIndexMaintenanceSvc UnistoreSvc UserDataSvc WorkFoldersSvc WalletService Wecsvc WEPHOSTSVC whesvc WinRM workfolderssvc AJRouter ALG AppMgmt AppVClient AssignedAccessManagerSvc Autotimesvc AxInstSV diagnosticshub.standardcollector.service DmEnrollmentSvc embeddedmode EntAppSvc fhsvc KPSSVC LxpSvc McpManagementService MicrosoftEdgeElevationService MixedRealityOpenXRSvc MSiSCSI NaturalAuthentication NcaSvc NcdAutoSetup NetTcpPortSharing p2pimsvc p2psvc PeerDistSvc perceptionsimulation PNRPAutoReg PNRPsvc PushToInstall RasAuto RpcLocator shpamsvc SmsRouter SNMPTRAP spectrum ssh-agent svsvc TroubleshootingSvc tzautoupdate UevAgentService uhssvc VacSvc wbengine wcncsvc wercplsupport WFDSConMgrSvc wlpasvc WManSvc edgeupdate edgeupdatem GoogleChromeElevationService gupdate AdobeARMservice AarSvc DoSvc", "PASS_POLICY"),
    ("WbioSrvc TabletInputService PcaSvc FrameServer WerSvc WSearch SysMain Spooler PrintNotify XblAuthManager XblGameSave XboxGipSvc XboxNetApiSvc GraphicsPerfSvc DisplayEnhancementService Themes FontCache ShellHWDetection WlanSvc wuauserv UsoSvc WaaSMedicSvc BITS DPS WdiServiceHost WdiSystemHost SSDPSRV upnphost fdPHost FDResPub SharedAccess RasMan SstpSvc StiSvc stisvc CDPSvc CDPUserSvc WpnService WpnUserService InstallService ClipboardUserService cbdhsvc ConsentUxUserSvc DevicePickerUserSvc DevicesFlowUserSvc WwanSvc GamingServices GamingServicesNet BthAvctpSvc bthserv BluetoothUserService DispBrokerDesktopSvc FrameServerMonitor PrintWorkflowUserSvc RmSvc BDESVC BTAGService camsvc CertPropSvc ClipSVC defragsvc DeviceAssociationService DevQueryBroker diagsvc DisplayPolicy dot3svc DsmSvc DsSvc Eaphost EFS FontCache3.0.0.0 hidserv HvHost IKEEXT iphlpsvc IpxlatCfgSvc LicenseManager lltdsvc lmhosts MSDTC NcbService Netlogon NgcCtnrSvc NgcSvc nvagent pla PolicyAgent QWAVE SCardSvr ScDeviceEnum seclogon SgrmBroker smphost StorSvc swprv TapiSrv TieringEngineService vds vmicguestinterface vmicheartbeat vmickvpexchange vmicrdv vmicshutdown vmictimesync vmicvmsession vmicvss VSS WarpJITSvc webthreatdefsvc webthreatdefusersvc WebClient WiaRpc wlidsvc wmiApSrv WPDBusEnum wscsvc BcastDVRUserService CaptureService AppReadiness", "TRADEOFF"),
    ("LanmanServer LanmanWorkstation AudioSrv Audiosrv AudioEndpointBuilder RpcSs DcomLaunch BrokerInfrastructure SystemEventsBroker Power PlugPlay ProfSvc UserManager SamSs LSM Tcpip Dhcp Dnscache EventLog EventSystem Schedule RpcEptMapper CryptSvc KeyIso nsi CoreMessagingRegistrar Winmgmt", "DANGER"),
    ("nvlddmkm", "PASS_REAL"),
    ("NlaSvc Netman netprofm NetSetupSvc AppIDSvc Appinfo AppXSvc COMSysApp DeviceInstall hidserv KtmRm msiserver SENS StateRepository sppsvc TimeBrokerSvc TokenBroker VaultSvc W32Time Wcmsvc WinHttpAutoProxySvc WMIRegistrationService TrustedInstaller", "REVIEW"),
    ("WinDefend WdNisSvc Sense mpssvc BFE SecurityHealthService", "TRADEOFF"),
]:
    for n in names.split():
        SVC[n] = v

SVC_WHY = {
    "PASS_POLICY": "Debloat/privacy/security policy service change",
    "TRADEOFF": "Real effect but costs features/compat/security",
    "DANGER": "Critical OS service - disabling can break system",
    "PASS_REAL": "Needed hardware/runtime service",
    "REVIEW": "Needs dependency check for this SKU",
}

SEV = {
    "DANGER": 0, "FAIL_HYPE": 1, "THEATER": 2, "UNKNOWN": 3, "REVIEW": 4, "TRADEOFF": 5,
    "PASS_POLICY": 6, "PASS_COMMON": 7, "PASS_REAL": 8, "PASS_MS": 9, "OK_STOCK": 10, "NOISE": 11,
}


def clean(s: str) -> str:
    return s.strip().strip("'\"")


def parse_actions() -> list[dict]:
    actions: list[dict] = []
    for f in sorted(ACTIONS.rglob("*.yml")) + sorted(ACTIONS.rglob("*.yaml")):
        rel = str(f.relative_to(PLAYBOOK)).replace("\\", "/")
        try:
            lines = f.read_text(encoding="utf-8", errors="replace").splitlines()
        except Exception:
            continue
        cur = None
        for i, line in enumerate(lines, 1):
            m = re.match(r"^\s*-\s*type:\s*(\S+)\s*$", line)
            if m:
                if cur:
                    actions.append(cur)
                cur = {
                    "File": rel, "Line": i, "Type": m.group(1),
                    "Id": "", "Path": "", "ValueName": "", "Value": "",
                    "Service": "", "Start": "", "Description": "", "Args": "",
                    "WhenOption": "", "TaskName": "", "Package": "", "Feature": "",
                }
                continue
            if not cur:
                continue
            for key, pat in [
                ("Id", r"^\s+id:\s*(.+)$"),
                ("Path", r"^\s+path:\s*(.+)$"),
                ("ValueName", r"^\s+valueName:\s*(.+)$"),
                ("Value", r"^\s+value:\s*(.+)$"),
                ("Service", r"^\s+service:\s*(.+)$"),
                ("Start", r"^\s+start:\s*(.+)$"),
                ("Args", r"^\s+args:\s*(.+)$"),
                ("WhenOption", r"^\s+whenOption:\s*(.+)$"),
                ("TaskName", r"^\s+taskName:\s*(.+)$"),
                ("Package", r"^\s+package:\s*(.+)$"),
                ("Description", r"^\s+description:\s*(.+)$"),
                ("Feature", r"^\s+name:\s*(.+)$"),
            ]:
                mm = re.match(pat, line)
                if mm:
                    cur[key] = clean(mm.group(1))
                    break
            mm = re.match(r"^\s+file:\s*(.+)$", line)
            if mm:
                cur["Path"] = clean(mm.group(1))
            mm = re.match(r"^\s+taskPath:\s*(.+)$", line)
            if mm:
                cur["Path"] = clean(mm.group(1))
        if cur:
            actions.append(cur)
    return actions


def verdict(a: dict) -> tuple[str, str, str, str]:
    t = a["Type"]
    path, vn, val, svc = a["Path"], a["ValueName"], a["Value"], a["Service"]
    extra = " ".join([a["Description"], a["Args"], a["TaskName"], a["Package"], a["Feature"], a["Start"], a["WhenOption"]])

    if t == "note":
        return "NOISE", "Documentation note", "playbook", "note"

    # SystemResponsiveness
    if "SystemResponsiveness" in vn or "SystemResponsiveness" in path:
        try:
            n = int(str(val).strip(), 0)
        except Exception:
            n = None
        if n is not None:
            if 0 <= n < 10:
                return "FAIL_HYPE", f"SystemResponsiveness={n} clamps to 20 per MS; use 10", "learn.microsoft.com MMCSS", "SR"
            if n == 100:
                return "TRADEOFF", "100 disables MMCSS", "learn.microsoft.com MMCSS", "SR"
            if n == 10:
                return "PASS_MS", "10% low-priority reserve (min valid)", "learn.microsoft.com MMCSS", "SR"
            if n == 20:
                return "OK_STOCK", "Default 20% reserve", "learn.microsoft.com MMCSS", "SR"

    if re.search(r"Tasks\\Games", path) and vn == "Priority":
        try:
            n = int(str(val).strip(), 0)
            if n != 2:
                return "THEATER", "Priority under High always treated as 2 by MMCSS", "learn.microsoft.com MMCSS", "GamesPrio"
        except Exception:
            pass

    if vn == "TdrLevel":
        try:
            if int(str(val).strip(), 0) == 0:
                return "DANGER", "TdrLevel=0 disables GPU timeout recovery", "WDDM", "TdrLevel"
        except Exception:
            pass

    if "NetworkThrottlingIndex" in vn:
        s = str(val).lower()
        if s in ("4294967295", "0xffffffff", "ffffffff", "-1"):
            return "PASS_COMMON", "0xFFFFFFFF disables MMCSS network throttle", "MMCSS", "NetThrot"
        if s in ("10", "0xa", "0x0000000a"):
            return "OK_STOCK", "Default throttle index 10", "MMCSS", "NetThrot"

    if t == "appx.remove":
        return "PASS_POLICY", "Appx package remove", "Appx", "appx"
    if t == "task.disable":
        blob = f"{path} {extra} {val} {svc}"
        for pat, verd, why, src in RULES:
            if re.search(pat, blob, re.I):
                return verd, why, src, pat
        return "PASS_POLICY", "Scheduled task disable", "Task Scheduler", "task"
    if t == "service.set":
        s = svc or path
        base = re.sub(r"_[0-9a-fA-F]{2,}$", "", s)
        if s in SVC:
            v = SVC[s]
            return v, f"{SVC_WHY[v]} ({s})", "service map", s
        if base in SVC:
            v = SVC[base]
            return v, f"{SVC_WHY[v]} ({base})", "service map", base
        if re.search(r"Xbox|Xbl|BcastDVR|Capture", s, re.I):
            return "TRADEOFF", "Xbox/capture service", "service heuristic", "xbox"
        if re.search(r"UserSvc|UserService", s, re.I):
            return "TRADEOFF", "Per-user service instance", "service heuristic", "usersvc"
        return "REVIEW", f"Service {s} not in map", "service fallback", "svc.fb"
    if t in ("feature.disable", "capability.remove"):
        return "TRADEOFF", "Optional component removal", "DISM", t
    if t == "taskkill":
        return "TRADEOFF", "Process kill at apply", "runtime", "taskkill"
    if t == "run":
        rb = f"{path} {val} {extra} {vn}"
        if re.search(r"bcdedit", rb, re.I):
            if re.search(r"hypervisorlaunchtype", rb, re.I):
                return "TRADEOFF", "Hypervisor off impacts VBS/WSL2", "BCD", "bcd hyp"
            if re.search(r"useplatformtick|disabledynamictick|useplatformclock", rb, re.I):
                return "REVIEW", "Timer BCD stack mixed evidence", "BCD", "bcd timer"
            return "REVIEW", "BCD edit", "BCD", "bcd"
        if re.search(r"powercfg|Apply-ExoPowerPlan|Apply-ExoFullStack|Audit-Exo", rb, re.I):
            return "PASS_REAL", "Power/full-stack orchestrator", "powercfg", "power run"
        if re.search(r"Pause-WindowsUpdate", rb, re.I):
            return "PASS_POLICY", "WU pause preferred over kill", "WU", "wu"
        if re.search(r"fsutil", rb, re.I):
            return "PASS_REAL", "NTFS behavior", "fsutil", "fsutil"
        if re.search(r"netsh", rb, re.I):
            return "PASS_REAL", "TCP netsh", "netsh", "netsh"
        if re.search(r"DisableVBS|Defender|DisableDefender", rb, re.I):
            return "TRADEOFF", "Security feature script", "security", "sec"
        if re.search(r"Install-|winget|DirectX|VCRedist|DotNet", rb, re.I):
            return "PASS_REAL", "Dependency install", "deps", "install"
        if re.search(r"dism", rb, re.I):
            return "TRADEOFF", "DISM component change", "DISM", "dism"
        if re.search(r"schtasks", rb, re.I):
            return "PASS_POLICY", "Task scheduler CLI", "run", "schtasks"
        if re.search(r"powershell|pwsh|\.ps1|\.cmd|\.bat", rb, re.I):
            return "REVIEW", "Script runner - inspect payload", "run", "script"
        return "REVIEW", "Run action inspect args", "run", "run.fb"
    if t == "registry.delete":
        return "REVIEW", "Registry delete", "registry", "regdel"

    # IFEO Debugger: telemetry kill = TRADEOFF; security binary kill = DANGER
    if vn == "Debugger" and re.search(r"Image File Execution Options", path, re.I):
        if re.search(r"smartscreen\.exe|SecurityHealth|MsMpEng|NisSrv|SgrmBroker", path, re.I):
            return "DANGER", "IFEO kills security binary (SmartScreen/Defender)", "security", "IFEO-sec"
        if re.search(r"CompatTelRunner|DeviceCensus|mobsync|AggregatorHost|BCILauncher|BGAUpsell|BingChat|CrossDevice|FeatureLoader", path, re.I):
            return "TRADEOFF", "IFEO blocks telemetry/upsell process at launch", "debloat IFEO", "IFEO-tel"
        return "TRADEOFF", "IFEO debugger redirect (process block)", "IFEO", "IFEO"

    search = f"{path}\\{vn}"
    # Prefer specific rules; demote broad residual catch-alls
    residual_pats = {
        r"HKCU\\|HKEY_CURRENT_USER",
        r"HKLM\\|HKEY_LOCAL_MACHINE",
        r"Microsoft\\Windows\\CurrentVersion",
        r"SOFTWARE\\Microsoft\\Windows",
        r"SYSTEM\\CurrentControlSet\\Services\\",
        r"Control\\Session Manager",
        r"Control\\Class\\",
    }
    candidates = []
    for pat, verd, why, src in RULES:
        if verd in ("SPECIAL_SR", "SPECIAL_PRIO"):
            continue
        if re.search(pat, search, re.I) or re.search(pat, path, re.I) or (vn and re.search(pat, vn, re.I)):
            rank = 3 if pat in residual_pats or "residual" in why.lower() else 0
            if verd == "REVIEW" and rank == 0:
                rank = 1
            candidates.append((rank, -len(pat), verd, why, src, pat))
    if candidates:
        candidates.sort()
        _rank, _l, verd, why, src, pat = candidates[0]
        if _rank < 3:
            return verd, why, src, pat

    # ValueName heuristics
    for pat, verd, why, src in [
        (r"^Start$", "TRADEOFF", "Service Start via registry", "services"),
        (r"SvcHostSplitDisable", "TRADEOFF", "Service host split disable", "admin"),
        (r"CpuPriorityClass|IoPriority|BasePriority|PagePriority|OverTargetPriority|IsLowPriority", "TRADEOFF", "Process resource priority policy", "scheduler"),
        (r"CoalescingTimerInterval", "TRADEOFF", "Timer coalescing power vs latency", "power/timer"),
        (r"EnablePrefetcher|EnableSuperfetch", "TRADEOFF", "Prefetch/SysMain", "admin"),
        # Debugger handled specially below for IFEO targets
        (r"VBAWarnings|PackagerPrompt|DontUpdateLinks", "PASS_POLICY", "Office policy", "Office"),
        (r"HttpAcceptLanguageOptOut|HasAccepted|NumberOfSIUFInPeriod", "PASS_POLICY", "Default-user privacy", "privacy"),
        (r"DOTNET_CLI_TELEMETRY_OPTOUT|POWERSHELL_TELEMETRY_OPTOUT", "PASS_POLICY", "CLI telemetry opt-out", "privacy"),
        (r"UserDuckingPreference", "PASS_REAL", "Audio ducking", "audio"),
        (r"LoadBehavior", "PASS_POLICY", "Office addin load", "Office"),
        (r"InitialKeyboardIndicators", "NOISE", "Numlock default user", "shell"),
        (r"^Beep$", "NOISE", "Default beep", "shell"),
        (r"HiddenByDefault", "NOISE", "UI hide default", "shell"),
        (r"^prio$|^tdesc$|^tbst$", "REVIEW", "Third-party optimizer rule keys", "baseline merge"),
        (r"AutoGameModeEnabled|AllowAutoGameMode|UseNexusForGameBarEnabled", "PASS_REAL", "Game Mode/Bar", "Windows Gaming"),
        (r"GameDVR_|AllowGameDVR|AppCaptureEnabled|HistoricalCaptureEnabled", "PASS_REAL", "Game DVR/FSO", "Windows Gaming"),
        (r"EnableTransparency|AppsUseLightTheme|SystemUsesLightTheme|ColorPrevalence", "PASS_POLICY", "Theme cosmetic", "shell"),
        (r"MouseSpeed|MouseThreshold|MouseSensitivity|MouseHoverTime", "PASS_REAL", "Mouse input", "MS mouse"),
        (r"MenuShowDelay|ForegroundLockTimeout|HungAppTimeout|WaitToKill|AutoEndTasks|DragFullWindows|MinAnimate", "PASS_REAL", "Desktop snappiness", "shell"),
        (r"PowerThrottlingOff|CsEnabled|HiberbootEnabled", "PASS_REAL", "Power knobs", "power"),
        (r"AdvertisingInfo|TailoredExperiences|SystemPaneSuggestions|SoftLanding|SilentInstalledApps|SubscribedContent", "PASS_POLICY", "Ads/suggestions", "privacy"),
        (r"DODownloadMode", "PASS_POLICY", "Delivery Optimization mode", "MS DO"),
        (r"EnableActivityFeed|PublishUserActivities|UploadUserActivities", "PASS_POLICY", "Timeline", "privacy"),
        (r"GlobalUserDisabled", "PASS_POLICY", "Background apps", "privacy"),
        (r"EnableSmartScreen", "TRADEOFF", "SmartScreen security", "security"),
        (r"CrashDumpEnabled", "TRADEOFF", "Crash dump size", "kernel"),
        (r"DisablePageCombining|FeatureSettings|FeatureSettingsOverride|SecondLevelDataCache", "TRADEOFF", "Memory manager", "kernel"),
        (r"NtfsDisable8dot3NameCreation", "PASS_REAL", "8.3 name creation", "NTFS"),
        (r"DefaultTTL|TcpMaxConnectRetransmissions|DisableTaskOffload", "REVIEW", "TCP tuning", "TCP/IP"),
        (r"EnableClipboardHistory|CloudClipboardAutomaticUpload", "PASS_POLICY", "Clipboard privacy", "privacy"),
        (r"StartupDelayInMSec", "PASS_REAL", "Startup delay", "shell"),
        (r"DisableWindowsConsumerFeatures|DisableSoftLanding", "PASS_POLICY", "Consumer features policy", "privacy"),
        (r"ContentDeliveryAllowed|SubscribedContentEnabled|PreInstalledApps", "PASS_POLICY", "Content delivery", "privacy"),
    ]:
        if vn and re.search(pat, vn, re.I):
            return verd, why, src, pat

    # Path family second pass
    for pat, verd, why, src in [
        (r"Policies\\", "PASS_POLICY", "Group Policy-style registry", "policy"),
        (r"PolicyManager\\", "PASS_POLICY", "MDM PolicyManager", "policy"),
        (r"ResourcePolicyStore", "TRADEOFF", "Process resource policy priorities", "scheduler"),
        (r"VainGovernor", "REVIEW", "Third-party VainGovernor baseline merge", "baseline"),
        (r"OpenShell", "NOISE", "OpenShell UI", "shell"),
        (r"Office\\", "PASS_POLICY", "Office policy/telemetry", "Office"),
        (r"Adobe\\", "PASS_POLICY", "Adobe policy", "vendor"),
        (r"BraveSoftware", "PASS_POLICY", "Brave policy", "browser"),
        (r"Speech_OneCore|TabletTip|\\Input\\", "PASS_POLICY", "Input/speech privacy", "privacy"),
        (r"LabConfig", "TRADEOFF", "Setup LabConfig bypasses", "setup"),
        (r"Windows Photo Viewer", "NOISE", "Photo Viewer", "shell"),
        (r"WindowsRuntime", "REVIEW", "WinRT config", "windows"),
        (r"Control Panel\\", "PASS_REAL", "Control Panel settings", "shell"),
        (r"GameConfigStore|GameBar|GameDVR", "PASS_REAL", "Gaming UX", "Windows Gaming"),
        (r"AdvertisingInfo|ContentDeliveryManager|CloudContent", "PASS_POLICY", "Ads/suggestions", "privacy"),
        (r"DeliveryOptimization", "PASS_POLICY", "Delivery Optimization", "MS DO"),
        (r"PowerThrottling|CsEnabled|Hibernate", "PASS_REAL", "Power knobs", "power"),
        (r"CrashControl", "TRADEOFF", "Crash dumps", "kernel"),
        (r"Tcpip\\Parameters", "REVIEW", "TCP parameters", "TCP/IP"),
        (r"Memory Management", "TRADEOFF", "Memory manager knobs", "kernel"),
        (r"FileSystem", "PASS_REAL", "Filesystem behavior", "NTFS"),
        (r"SmartScreen", "TRADEOFF", "SmartScreen", "security"),
        (r"Clipboard", "PASS_POLICY", "Clipboard", "privacy"),
        (r"BackgroundAccessApplications", "PASS_POLICY", "UWP background", "privacy"),
        (r"Themes\\Personalize|\\DWM\\", "PASS_POLICY", "Theme/DWM", "shell"),
        (r"CurrentControlSet\\Services\\", "TRADEOFF", "Service configuration registry", "services"),
        (r"HKCR\\|Classes\\CLSID", "NOISE", "Class/association", "shell"),
        (r"HKU\\|\.DEFAULT", "PASS_POLICY", "Default user hive", "privacy"),
        (r"Explorer\\", "PASS_POLICY", "Explorer UX", "shell"),
        (r"Windows Search|SearchSettings", "PASS_POLICY", "Search", "privacy"),
        (r"Privacy\\", "PASS_POLICY", "Privacy settings", "privacy"),
        (r"DirectX|GraphicsDrivers", "PASS_REAL", "GPU/DX", "graphics"),
        (r"Multimedia\\SystemProfile", "PASS_MS", "MMCSS", "learn.microsoft.com MMCSS"),
        (r"PriorityControl", "TRADEOFF", "Priority control", "scheduler"),
        (r"Image File Execution Options", "TRADEOFF", "IFEO process launch control", "IFEO"),
        (r"CrossDeviceResume|AccountNotifications|Siuf\\", "PASS_POLICY", "Notifications/feedback privacy", "privacy"),
        (r"\\Search\\", "PASS_POLICY", "Search settings", "privacy"),
        (r"\\Themes\\", "PASS_POLICY", "Themes cosmetic", "shell"),
        (r"WindowsRuntime\\ActivatableClassId", "TRADEOFF", "Disable WinRT activatable classes", "WinRT"),
        (r"Winlogon", "REVIEW", "Winlogon policy", "shell"),
        (r"FirewallRules|FirewallPolicy", "TRADEOFF", "Firewall rules wipe/change", "security"),
        (r"Bags$", "NOISE", "Shell bag clear", "shell"),
        (r"\\Run\\", "REVIEW", "Run key startup entry", "startup"),
        (r"NVIDIA|NVControlPanel|NVTweak|nvlddmkm", "REVIEW", "NVIDIA vendor key", "NVIDIA"),
        (r"VainGovernor", "REVIEW", "Third-party process governor baseline", "baseline"),
        (r"SensorDataService|SensorService|SensrSvc|WdFilter|WdBoot|MDCoreSvc", "TRADEOFF", "Sensor/Defender driver service", "security"),
    ]:
        if re.search(pat, path, re.I) or re.search(pat, search, re.I) or re.search(pat, f"{path} {vn} {svc}", re.I):
            return verd, why, src, pat

    # Last-resort: any remaining registry under Software/Policies = policy-ish
    if t == "registry.set":
        if re.search(r"Policies|ContentDelivery|CloudContent|DataCollection|ConsentStore|CapabilityAccess", path, re.I):
            return "PASS_POLICY", "Policy/privacy residual", "heuristic", "pol-res"
        if re.search(r"CurrentVersion\\Explorer|Start Menu|Taskbar|TrayNotify", path, re.I):
            return "PASS_POLICY", "Shell residual", "heuristic", "shell-res"
        if re.search(r"SYSTEM\\.*\\Control\\", path, re.I):
            return "REVIEW", "System control residual - inspect value", "heuristic", "sys-res"
        if re.search(r"SOFTWARE\\Microsoft\\", path, re.I):
            return "REVIEW", "Microsoft software residual - inspect value", "heuristic", "ms-res"
        return "REVIEW", "Unmapped registry residual", "heuristic", "reg-res"

    return "UNKNOWN", "No rule matched", "none", ""


def main() -> int:
    print(f"[Audit] Playbook: {PLAYBOOK}")
    actions = parse_actions()
    print(f"[Audit] Parsed {len(actions)} actions")
    rows = []
    for i, a in enumerate(actions, 1):
        if i % 500 == 0:
            print(f"  {i}/{len(actions)}")
        verd, why, src, matched = verdict(a)
        fp = "|".join([
            a["Type"], a["Path"], a["ValueName"], a["Value"], a["Service"], a["Start"]
        ]).lower()
        rows.append({**a, "Verdict": verd, "Why": why, "Source": src, "MatchedRule": matched, "Fingerprint": fp})

    # write CSVs
    fields = list(rows[0].keys()) if rows else []
    all_csv = OUT / f"all-actions-{STAMP}.csv"
    with all_csv.open("w", newline="", encoding="utf-8") as f:
        w = csv.DictWriter(f, fieldnames=fields)
        w.writeheader()
        w.writerows(rows)

    # unique
    groups: dict[str, list] = defaultdict(list)
    for r in rows:
        groups[r["Fingerprint"]].append(r)

    unique_rows = []
    for fp, items in groups.items():
        worst = sorted(items, key=lambda x: SEV.get(x["Verdict"], 50))[0]
        unique_rows.append({
            "Count": len(items),
            "Verdict": worst["Verdict"],
            "Why": worst["Why"],
            "Source": worst["Source"],
            "Type": worst["Type"],
            "Path": worst["Path"],
            "ValueName": worst["ValueName"],
            "Value": worst["Value"],
            "Service": worst["Service"],
            "Start": worst["Start"],
            "ExampleFile": worst["File"],
            "ExampleId": worst["Id"],
            "Fingerprint": fp,
        })
    unique_rows.sort(key=lambda x: (SEV.get(x["Verdict"], 50), -x["Count"]))
    uniq_csv = OUT / f"unique-tweaks-{STAMP}.csv"
    with uniq_csv.open("w", newline="", encoding="utf-8") as f:
        w = csv.DictWriter(f, fieldnames=list(unique_rows[0].keys()) if unique_rows else [])
        w.writeheader()
        w.writerows(unique_rows)

    bad = [r for r in rows if re.search(r"FAIL|THEATER|DANGER", r["Verdict"])]
    unk = [r for r in rows if r["Verdict"] == "UNKNOWN"]
    bad_csv = OUT / f"fail-theater-danger-{STAMP}.csv"
    unk_csv = OUT / f"unknown-{STAMP}.csv"
    for path, data in [(bad_csv, bad), (unk_csv, unk)]:
        with path.open("w", newline="", encoding="utf-8") as f:
            w = csv.DictWriter(f, fieldnames=fields)
            w.writeheader()
            w.writerows(data)

    by_v = Counter(r["Verdict"] for r in rows)
    by_t = Counter(r["Type"] for r in rows)
    known = sum(1 for r in rows if r["Verdict"] != "UNKNOWN")

    lines = []
    lines.append(f"Exo FULL ACTION AUDIT  {STAMP}")
    lines.append(f"Playbook: {PLAYBOOK}")
    lines.append(f"Total actions: {len(rows)}")
    lines.append(f"Unique fingerprints: {len(unique_rows)}")
    lines.append(f"Path rules: {len(RULES)} | Service map: {len(SVC)}")
    lines.append("")
    lines.append("=== BY VERDICT ===")
    for k, c in by_v.most_common():
        pct = 100.0 * c / max(1, len(rows))
        lines.append(f"{k:<14} {c:6d}  {pct:5.1f}%")
    lines.append("")
    lines.append("=== BY TYPE ===")
    for k, c in by_t.most_common():
        lines.append(f"{k:<20} {c:6d}")
    lines.append("")
    lines.append(f"Coverage non-UNKNOWN: {known} / {len(rows)} ({100.0*known/max(1,len(rows)):.1f}%)")
    lines.append("")
    lines.append("=== FAIL/THEATER/DANGER unique ===")
    bad_u = [u for u in unique_rows if re.search(r"FAIL|THEATER|DANGER", u["Verdict"])]
    for b in bad_u[:120]:
        lines.append(
            f"[{b['Verdict']}] x{b['Count']} {b['Type']} {b['Path']} | {b['ValueName']}={b['Value']}{b['Service']} :: {b['Why']}"
        )
    lines.append("")
    unk_paths = Counter(f"{r['Path']} :: {r['ValueName']}" for r in unk)
    lines.append(f"=== UNKNOWN top ({len(unk_paths)} distinct) ===")
    for name, c in unk_paths.most_common(100):
        lines.append(f"x{c} {name}")
    rev = [r for r in rows if r["Verdict"] == "REVIEW"]
    rev_paths = Counter(f"{r['Type']} | {r['Path']} :: {r['ValueName']}{r['Service']}" for r in rev)
    lines.append("")
    lines.append(f"=== REVIEW top ({len(rev_paths)} distinct) ===")
    for name, c in rev_paths.most_common(100):
        lines.append(f"x{c} {name}")
    lines.append("")
    lines.append(f"CSV all: {all_csv}")
    lines.append(f"CSV unique: {uniq_csv}")
    lines.append(f"CSV bad: {bad_csv}")
    lines.append(f"CSV unknown: {unk_csv}")

    text = "\n".join(lines) + "\n"
    summary = OUT / f"SUMMARY-{STAMP}.txt"
    summary.write_text(text, encoding="utf-8")
    # stable copies
    for src, name in [
        (all_csv, "all-actions-latest.csv"),
        (uniq_csv, "unique-tweaks-latest.csv"),
        (bad_csv, "fail-theater-danger-latest.csv"),
        (unk_csv, "unknown-latest.csv"),
        (summary, "SUMMARY-latest.txt"),
    ]:
        (OUT / name).write_bytes(src.read_bytes())
    print(text)
    print("[Audit] Done.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
