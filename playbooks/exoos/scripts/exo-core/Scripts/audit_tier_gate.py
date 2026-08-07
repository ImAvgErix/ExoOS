#!/usr/bin/env python3
"""Parse all playbook actions; classify verdict + Balanced/Extreme/Both tier; gate inventory."""
from __future__ import annotations
import csv, os, re, sys
from collections import Counter, defaultdict
from datetime import datetime
from pathlib import Path

PLAYBOOK = Path(__file__).resolve().parents[3]
ACTIONS = PLAYBOOK / "actions"
OUT_PROG = Path(os.environ.get("PROGRAMDATA", "C:/ProgramData")) / "ExoOS" / "audit"
OUT_PROG.mkdir(parents=True, exist_ok=True)
SCRATCH = Path(os.environ.get("EXO_AUDIT_SCRATCH", str(OUT_PROG)))
SCRATCH.mkdir(parents=True, exist_ok=True)
STAMP = datetime.now().strftime("%Y%m%d-%H%M%S")

# Import core verdict logic by reusing simplified rules + tier philosophy
# Extreme = barebones gaming strip (store/browsers/discord/games OK; max strip)
# Balanced = safe ceiling + select aggressive worth-it tweaks
# Both = shared baseline always

EXTREME_ONLY_PATTERNS = [
    r"Spooler|spoolsv",
    r"SysMain",
    r"WSearch",
    r"LanmanServer|LanmanWorkstation",
    r"service:\s*Themes\b|Services\\Themes",
    r"FontCache",
    r"ShellHWDetection",
    r"Image File Execution Options",
    r"Debugger",
    r"smartscreen",
    r"DeviceGuard|HypervisorEnforcedCodeIntegrity|LsaCfgFlags|DisableVBS",
    r"FeatureSettingsOverride|MitigationOptions",
    r"dismStrip|feature\.disable|capability\.remove",
    r"EnablePrefetcher|EnableSuperfetch",
    r"Win32PrioritySeparation",
    r"disabledynamictick|useplatformtick|useplatformclock|hypervisorlaunchtype",
    r"ResourcePolicyStore",
    r"VainGovernor",
    r"PerfOptions",
    r"CpuPriorityClass|IoPriority|BasePriority",
    r"CoalescingTimerInterval",
    r"DisablePagingExecutive",
    r"TdrLevel|TdrDelay",
    r"SystemResponsiveness",  # value-checked separately; extreme can set 10 same as balanced
    r"BBR2|bbr2",
    r"NetworkThrottlingIndex",  # both actually - refined below
    r"HwSchMode",  # both - HAGS ok balanced
    r"extremeMode|extreme-nuclear|extreme-edge",
]

# Patterns that MUST stay on Balanced/shared (safe ceiling)
BALANCED_SAFE_PATTERNS = [
    r"MouseSpeed|MouseThreshold|MouseHoverTime",
    r"MenuShowDelay|ForegroundLockTimeout|HungAppTimeout|AutoEndTasks",
    r"StickyKeys|ToggleKeys|MouseKeys|Keyboard Response",
    r"GameDVR|GameBar|GameConfigStore|AllowGameDVR",
    r"AdvertisingInfo|ActivityFeed|PublishUserActivities|TailoredExperiences",
    r"ContentDeliveryManager|CloudContent|DisableWindowsConsumerFeatures",
    r"AllowCortana|DisableWebSearch|BingSearchEnabled",
    r"BackgroundAccessApplications",
    r"DeliveryOptimization|DODownloadMode",
    r"Pause-WindowsUpdate|PowerThrottlingOff|CsEnabled|HiberbootEnabled",
    r"DirectXUserGlobalSettings|SwapEffectUpgrade|VRROptimize",
    r"GlobalTimerResolutionRequests",
    r"Scheduling Category",
    r"NetworkThrottlingIndex",
    r"SystemResponsiveness",
    r"HwSchMode",
    r"AutoplayHandlers|NoDriveTypeAutoRun",
    r"EnableTransparency|MinAnimate|VisualFXSetting|TaskbarAnimations",
    r"installDirectX|installVcRedist|installDotNet|Install-",
    r"keepStore|WindowsStore",
]

# Essentials that Extreme must NOT remove
ESSENTIAL_KEEP_PATTERNS = [
    r"Microsoft\.WindowsStore|WindowsStore",
    r"Microsoft\.DesktopAppInstaller",
    r"Microsoft\.StorePurchaseApp",
    r"Microsoft\.XboxIdentityProvider",  # some games need
    r"AudioSrv|Audiosrv|AudioEndpointBuilder",
    r"RpcSs|DcomLaunch|BrokerInfrastructure|Power|PlugPlay|ProfSvc|UserManager|EventLog|Schedule|CryptSvc|Dhcp|Dnscache|nsi|Winmgmt|LSM|SamSs",
    r"nvlddmkm",
    r"Install-DirectX|Install-VCRedist|Install-DotNet|installDirectX|installVcRedist",
]


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
                    "Service": "", "Start": "", "WhenOption": "",
                    "Description": "", "Args": "", "Package": "", "TaskName": "",
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
                ("WhenOption", r"^\s+whenOption:\s*(.+)$"),
                ("Args", r"^\s+args:\s*(.+)$"),
                ("Package", r"^\s+package:\s*(.+)$"),
                ("Description", r"^\s+description:\s*(.+)$"),
                ("TaskName", r"^\s+taskName:\s*(.+)$"),
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
            mm = re.match(r"^\s+name:\s*(.+)$", line)
            if mm and cur["Type"] in ("feature.disable", "capability.remove", "appx.remove", "task.disable"):
                cur["Package"] = clean(mm.group(1))
        if cur:
            actions.append(cur)
    return actions


def blob(a: dict) -> str:
    return " ".join(str(a.get(k, "") or "") for k in (
        "Type", "Path", "ValueName", "Value", "Service", "Start", "Package", "Args", "Description", "TaskName", "File"
    ))


def assign_tier(a: dict) -> tuple[str, str]:
    """Return (tier, reason). tier in Balanced|Extreme|Both."""
    b = blob(a)
    when = (a.get("WhenOption") or "").strip()
    t = a["Type"]
    path = a.get("Path") or ""
    vn = a.get("ValueName") or ""
    val = a.get("Value") or ""

    # --- HOSTILE FIRST (before any GameBar/GameDVR "safe" regex) ---
    # IFEO Debugger=taskkill is process hijack — Extreme only (policy preferred on Balanced)
    if t == "registry.set" and (
        (vn == "Debugger" and re.search(r"taskkill", val, re.I))
        or (re.search(r"Image File Execution Options", path, re.I) and vn == "Debugger")
    ):
        if re.search(r"smartscreen\.exe", path, re.I):
            return "QUARANTINE", "IFEO smartscreen — use policy disable, not Debugger hijack"
        return "Extreme", "IFEO Debugger=taskkill process hijack (barebones)"
    if t == "run" and re.search(r"taskkill", b, re.I):
        return "Extreme", "taskkill.exe run (shell/browser/noise kill — barebones)"
    if t == "taskkill":
        return "Extreme", "runtime process kill barebones"

    # Theater / cargo-cult
    if vn == "SystemResponsiveness":
        try:
            n = int(str(val or "10"), 0)
            if 0 <= n < 10:
                return "QUARANTINE", "SystemResponsiveness <10 clamps to 20 (MS)"
        except Exception:
            pass
    if re.search(r"Tasks\\Games", path) and vn in ("GPU Priority", "SFIO Priority"):
        return "QUARANTINE", "MS: GPU/SFIO Priority unused"
    if vn == "Priority" and re.search(r"Tasks\\Games", path):
        try:
            if int(str(val or "2"), 0) != 2:
                return "QUARANTINE", "MS: Priority under High forced to 2"
        except Exception:
            pass

    # Gate-driven
    if when == "extremeMode" or when == "dismStrip" or when == "disableVbs":
        return "Extreme", f"gated by {when or 'extreme'}"
    if when == "defenderStrip":
        return "Extreme", "defenderStrip (Extreme barebones security strip)"
    if when == "serviceStrip":
        # serviceStrip is used by Privacy+Extreme today; philosophy: deep service strip = Extreme-ish
        # but some serviceStrip is shared quiet — mark Extreme for nuclear services, Both for mild
        if re.search(r"Spooler|SysMain|WSearch|Lanman|Themes|FontCache|ShellHWDetection|Fax", b, re.I):
            return "Extreme", "deep service kill (barebones)"
        return "Both", "service quiet (shared privacy/gaming)"

    # Type defaults
    if t == "note":
        return "Both", "documentation"
    if t in ("feature.disable", "capability.remove"):
        return "Extreme", "DISM strip barebones"
    if t == "appx.remove":
        if re.search(r"WindowsStore|DesktopAppInstaller|StorePurchase|XboxIdentity|GamingApp|Xbox\.TCUI", b, re.I):
            return "QUARANTINE", "essential Store/Xbox identity keeper"
        if re.search(r"Clipchamp|Bing|Zune|People|YourPhone|GetHelp|MixedReality|Copilot|OneDrive|Teams|Outlook|Todo|PowerAutomate|CrossDevice|Family|Feedback|Maps|News|Weather", b, re.I):
            return "Both", "bloat appx safe remove"
        return "Extreme", "aggressive appx strip"
    if t == "task.disable":
        if re.search(r"UpdateOrchestrator|WindowsUpdate|Schedule Scan", b, re.I):
            return "Extreme", "hard WU task kill (Balanced uses pause)"
        return "Both", "telemetry/CEIP task quiet"
    if t == "service.set":
        svc = a.get("Service") or ""
        start = (a.get("Start") or "").lower()
        if re.search(r"AudioSrv|Audiosrv|AudioEndpointBuilder|RpcSs|DcomLaunch|Power|PlugPlay|ProfSvc|UserManager|EventLog|CryptSvc|Dhcp|Dnscache|nsi|Winmgmt|LSM|SamSs|BrokerInfrastructure|SystemEventsBroker|Schedule|nvlddmkm", svc, re.I):
            if start in ("disabled", "manual") and re.search(r"Audio|RpcSs|DcomLaunch|Power|PlugPlay|ProfSvc|UserManager|EventLog|CryptSvc|Dhcp|Dnscache|nsi|Winmgmt|LSM|SamSs|Broker|Schedule", svc, re.I):
                return "QUARANTINE", f"must not disable essential {svc}"
        if re.search(r"Spooler|SysMain|WSearch|Lanman|Themes|FontCache|ShellHWDetection|Fax|RemoteRegistry|RetailDemo|MapsBroker|icssvc|DiagTrack|dmwappushservice", svc, re.I):
            if re.search(r"DiagTrack|dmwappushservice|RetailDemo|MapsBroker|icssvc|Fax|RemoteRegistry", svc, re.I):
                return "Both", f"safe quiet {svc}"
            return "Extreme", f"barebones service {svc}={start}"
        if re.search(r"Xbl|Xbox|BcastDVR|CaptureService", svc, re.I):
            return "Extreme", "Xbox service quiet (some titles need; Extreme opts in)"
        return "Both", f"service {svc}"

    if t == "run":
        if re.search(r"Apply-ExoPowerPlan|Apply-ExoFullStack|Pause-WindowsUpdate|powercfg|fsutil|Disable-Nagle|netsh", b, re.I):
            if re.search(r"Apply-ExoFullStack.*Extreme|-Extreme|DisableVBS|dism", b, re.I):
                return "Extreme", "extreme orchestrator"
            return "Both", "shared power/network/WU pause"
        if re.search(r"bcdedit", b, re.I):
            return "Extreme", "BCD timer/hypervisor barebones"
        if re.search(r"Install-|winget|DirectX|VCRedist|DotNet", b, re.I):
            return "Both", "gaming runtime deps"
        if re.search(r"DisableDefender|DefenderOFF|DisableVBS|RemoveComponents|DisableDevices", b, re.I):
            return "Extreme", "security/component strip script"
        return "Both", "run script"

    if t == "registry.delete":
        if re.search(r"FirewallRules", b, re.I):
            return "Extreme", "firewall rules wipe"
        return "Both", "registry delete cleanup"

    if t == "registry.set":
        # Nuclear IFEO / mitigations BEFORE safe GameBar/GameDVR path match
        if re.search(r"Image File Execution Options|FeatureSettingsOverride|DeviceGuard|HypervisorEnforced|LsaCfg|PrefetchParameters|DisablePagingExecutive|Win32PrioritySeparation|ResourcePolicyStore|VainGovernor|PerfOptions|CpuPriorityClass|Mitigation|LabConfig", b, re.I):
            return "Extreme", "aggressive kernel/IFEO/mitigation registry"
        # Known safe shared (GameBar policy keys — not IFEO Debugger hijacks)
        if re.search(r"MouseSpeed|MouseThreshold|MenuShowDelay|StickyKeys|GameDVR|GameBar|GameConfigStore|AdvertisingInfo|ActivityFeed|ContentDelivery|CloudContent|AllowCortana|DisableWebSearch|BingSearch|BackgroundAccess|DODownloadMode|PowerThrottlingOff|CsEnabled|Hiberboot|DirectXUserGlobal|SwapEffect|GlobalTimerResolution|Scheduling Category|NetworkThrottlingIndex|SystemResponsiveness|HwSchMode|Autoplay|VisualFX|MinAnimate|Taskbar|EnableTransparency|WaitToKill|ForegroundLock|HungApp", b, re.I):
            if vn == "SystemResponsiveness":
                try:
                    n = int(str(val or "10"), 0)
                    if 0 <= n < 10:
                        return "QUARANTINE", "SR cargo-cult 0"
                except Exception:
                    pass
            return "Both", "safe ceiling / shared gaming baseline"
        if re.search(r"Services\\(Spooler|SysMain|WSearch|Themes|Lanman|FontCache)", b, re.I):
            return "Extreme", "service start via registry barebones"
        if re.search(r"Policies\\", b, re.I):
            if re.search(r"Windows Defender|SmartScreen|DeviceGuard|CredentialGuard", b, re.I):
                return "Extreme", "security policy strip"
            return "Both", "privacy policy"
        if re.search(r"HKCR\\|ShellNew|OEMInformation|RegisteredOwner", b, re.I):
            return "Both", "shell noise / branding"
        if re.search(r"Windows Defender|WdNis|SecurityHealth", b, re.I):
            return "Extreme", "defender registry strip"
        if re.search(r"Office\\|Adobe\\|BraveSoftware", b, re.I):
            return "Both", "vendor telemetry/policy"
        if re.search(r"Tcpip\\Parameters", b, re.I):
            return "Both", "TCP gaming knobs (safe-ish)"
        if re.search(r"Multimedia\\SystemProfile", b, re.I):
            return "Both", "MMCSS"
        # Bulk baseline residual → Extreme by default (Atlas/Revi nuclear)
        if "13-reg-baselines-all" in (a.get("File") or "") or "12-reg-research" in (a.get("File") or ""):
            if re.search(r"Policies|ContentDelivery|CloudContent|Advertising|Telemetry|DataCollection|GameDVR|Search|Explorer|Privacy", b, re.I):
                return "Both", "baseline privacy/shell safe"
            return "Extreme", "bulk baseline aggressive residual"
        if "10-reg-" in (a.get("File") or ""):
            if re.search(r"Services\\(Spooler|SysMain|WSearch|Themes|Lanman)|IFEO|Debugger|FeatureSettings|DeviceGuard", b, re.I):
                return "Extreme", "core reg nuclear"
            return "Both", "core exo reg"
        return "Both", "registry residual shared"

    return "Both", "default both"


def assign_verdict(a: dict, tier: str) -> tuple[str, str, str]:
    """Lightweight verdict for report."""
    b = blob(a)
    if tier == "QUARANTINE":
        if re.search(r"SystemResponsiveness|GPU Priority|SFIO|Priority under High|clamps", b + tier, re.I):
            return "THEATER", "cargo-cult / unused per MS", "MS MMCSS"
        if re.search(r"essential|must not disable|WindowsStore|smartscreen IFEO", b, re.I):
            return "DANGER", "breaks essentials or hostile technique", "policy"
        return "FAIL_HYPE", "quarantined", "audit"
    if a["Type"] == "note":
        return "NOISE", "note", "playbook"
    if re.search(r"SystemResponsiveness", a.get("ValueName") or ""):
        try:
            n = int(str(a.get("Value") or "10"), 0)
            if n == 10:
                return "PASS_MS", "min valid SR=10", "learn.microsoft.com MMCSS"
        except Exception:
            pass
    if re.search(r"Scheduling Category", a.get("ValueName") or ""):
        return "PASS_MS", "MMCSS category", "learn.microsoft.com MMCSS"
    if re.search(r"HwSchMode|GlobalTimerResolution|GameDVR|MouseSpeed|PowerThrottling|powercfg|fsutil|Nagle|TCPNoDelay", b, re.I):
        return "PASS_REAL", "real OS mechanism", "windows"
    if tier == "Extreme":
        return "TRADEOFF", "Extreme barebones tradeoff", "philosophy"
    if a["Type"] in ("appx.remove", "task.disable") or re.search(r"Policies|privacy|Advertising|Telemetry", b, re.I):
        return "PASS_POLICY", "privacy/debloat policy", "policy"
    if re.search(r"HKCR|ShellNew|OEM|branding|Theme|wallpaper", b, re.I):
        return "NOISE", "cosmetic/shell", "shell"
    return "PASS_POLICY", "classified", "tier engine"


def gate_label(a: dict) -> str:
    w = (a.get("WhenOption") or "").strip()
    return w if w else "UNGATED"


def main() -> int:
    actions = parse_actions()
    rows = []
    mis_tier = []  # Extreme-tier but ungated (Balanced would get them)
    quarantine = []
    for a in actions:
        tier, treason = assign_tier(a)
        verd, why, src = assign_verdict(a, tier)
        g = gate_label(a)
        # Mis-tier: wants Extreme but currently ungated (or only serviceStrip which Balanced may enable)
        if tier == "Extreme" and g == "UNGATED":
            mis_tier.append(a)
        if tier == "QUARANTINE":
            quarantine.append(a)
        # Also mis if Extreme content on serviceStrip only and serviceStrip is balanced-default — still flag deep kills
        rows.append({
            **a,
            "Gate": g,
            "Tier": tier if tier != "QUARANTINE" else "Extreme",
            "TierReason": treason,
            "Verdict": verd if tier != "QUARANTINE" else ("DANGER" if "essential" in treason or "smartscreen" in treason else "THEATER"),
            "Why": why if tier != "QUARANTINE" else treason,
            "Source": src,
            "NeedsGate": "extremeMode" if (tier == "Extreme" and g == "UNGATED") else "",
            "Quarantine": "yes" if tier == "QUARANTINE" else "",
        })

    # CSVs
    fields = list(rows[0].keys()) if rows else []
    all_csv = OUT_PROG / f"tier-all-{STAMP}.csv"
    with all_csv.open("w", newline="", encoding="utf-8") as f:
        w = csv.DictWriter(f, fieldnames=fields)
        w.writeheader()
        w.writerows(rows)
    (OUT_PROG / "tier-all-latest.csv").write_bytes(all_csv.read_bytes())

    mis_csv = OUT_PROG / f"mis-tier-ungated-extreme-{STAMP}.csv"
    with mis_csv.open("w", newline="", encoding="utf-8") as f:
        w = csv.DictWriter(f, fieldnames=fields)
        w.writeheader()
        w.writerows([r for r in rows if r["NeedsGate"] == "extremeMode"])
    (OUT_PROG / "mis-tier-ungated-extreme-latest.csv").write_bytes(mis_csv.read_bytes())

    q_csv = OUT_PROG / f"quarantine-{STAMP}.csv"
    with q_csv.open("w", newline="", encoding="utf-8") as f:
        w = csv.DictWriter(f, fieldnames=fields)
        w.writeheader()
        w.writerows([r for r in rows if r["Quarantine"] == "yes"])
    (OUT_PROG / "quarantine-latest.csv").write_bytes(q_csv.read_bytes())

    by_tier = Counter(r["Tier"] for r in rows)
    by_gate = Counter(r["Gate"] for r in rows)
    by_verd = Counter(r["Verdict"] for r in rows)
    unk = sum(1 for r in rows if r["Verdict"] == "UNKNOWN")
    bad_active = [r for r in rows if r["Verdict"] in ("FAIL_HYPE", "THEATER", "DANGER") and r["Quarantine"] != "yes"]
    # Active path bad = still in YAML and not marked quarantine recommendation only — count quarantine rows separately

    lines = []
    lines.append(f"Exo TIER+GATE AUDIT {STAMP}")
    lines.append(f"Playbook: {PLAYBOOK}")
    lines.append(f"Total actions: {len(rows)}")
    lines.append(f"UNKNOWN: {unk}")
    lines.append("")
    lines.append("=== PHILOSOPHY ===")
    lines.append("Extreme: barebones essentials-only (gaming, browsers, MS Store, Discord/apps); max strip privacy/overhead/RAM/latency.")
    lines.append("Balanced: highest safe ceiling + select aggressive worth-it tweaks; no nuclear desktop breakers.")
    lines.append("Both: shared baseline always.")
    lines.append("")
    lines.append("=== BY TIER ===")
    for k, c in by_tier.most_common():
        lines.append(f"{k:<12} {c:6d}  {100*c/len(rows):5.1f}%")
    lines.append("")
    lines.append("=== BY GATE (current YAML) ===")
    for k, c in by_gate.most_common():
        lines.append(f"{k:<20} {c:6d}")
    lines.append("")
    lines.append("=== BY VERDICT ===")
    for k, c in by_verd.most_common():
        lines.append(f"{k:<14} {c:6d}")
    lines.append("")
    lines.append(f"Mis-tier Extreme but UNGATED (Balanced would apply): {sum(1 for r in rows if r['NeedsGate']=='extremeMode')}")
    lines.append(f"Quarantine candidates: {sum(1 for r in rows if r['Quarantine']=='yes')}")
    lines.append("")
    lines.append("=== MIS-TIER SAMPLE (file:id path/service) ===")
    for r in [x for x in rows if x["NeedsGate"] == "extremeMode"][:40]:
        lines.append(f"  {r['File']}:{r['Line']} {r['Id']} {r['Type']} {(r['Service'] or r['Path'])[:70]} | {r['TierReason'][:50]}")
    lines.append("")
    lines.append("=== QUARANTINE SAMPLE ===")
    for r in [x for x in rows if x["Quarantine"] == "yes"][:30]:
        lines.append(f"  {r['File']}:{r['Line']} {r['Id']} {r['Why'][:80]}")
    lines.append("")
    lines.append(f"CSV all: {all_csv}")
    lines.append(f"CSV mis-tier: {mis_csv}")
    lines.append(f"CSV quarantine: {q_csv}")

    text = "\n".join(lines) + "\n"
    summary = OUT_PROG / f"TIER-SUMMARY-{STAMP}.txt"
    summary.write_text(text, encoding="utf-8")
    (OUT_PROG / "TIER-SUMMARY-latest.txt").write_text(text, encoding="utf-8")
    # scratch copies if different
    if SCRATCH.resolve() != OUT_PROG.resolve():
        (SCRATCH / "full-audit-summary.txt").write_text(text, encoding="utf-8")
        (SCRATCH / "tier-all-latest.csv").write_bytes(all_csv.read_bytes())
        (SCRATCH / "mis-tier-ungated-extreme-latest.csv").write_bytes(mis_csv.read_bytes())
    else:
        (SCRATCH / "full-audit-summary.txt").write_text(text, encoding="utf-8")
    print(text)
    return 0


if __name__ == "__main__":
    # Allow override scratch
    if len(sys.argv) > 1:
        os.environ["EXO_AUDIT_SCRATCH"] = sys.argv[1]
        SCRATCH = Path(sys.argv[1])
        SCRATCH.mkdir(parents=True, exist_ok=True)
    sys.exit(main())
