#!/usr/bin/env python3
"""Structural tests for the shipped Extreme vs Balanced product playbook."""
from __future__ import annotations
import re
import sys
from pathlib import Path

PLAYBOOK = Path(__file__).resolve().parents[3]
ACTIONS = PLAYBOOK / "actions"
FAILS: list[str] = []


def fail(msg: str) -> None:
    FAILS.append(msg)
    print("FAIL:", msg)


def ok(msg: str) -> None:
    print("OK:", msg)


def parse_actions():
    actions = []
    for f in sorted(ACTIONS.rglob("*.yml")):
        rel = str(f.relative_to(PLAYBOOK)).replace("\\", "/")
        lines = f.read_text(encoding="utf-8", errors="replace").splitlines()
        cur = None
        for i, line in enumerate(lines, 1):
            m = re.match(r"^\s*-\s*type:\s*(\S+)\s*$", line)
            if m:
                if cur:
                    actions.append(cur)
                cur = {
                    "file": rel, "line": i, "type": m.group(1),
                    "when": "", "service": "", "path": "", "valueName": "",
                    "value": "", "id": "", "package": "", "raw": [],
                }
                continue
            if not cur:
                continue
            cur["raw"].append(line)
            for key, pat in [
                ("when", r"whenOption:\s*(.+)"),
                ("service", r"service:\s*(.+)"),
                ("path", r"path:\s*(.+)"),
                ("valueName", r"valueName:\s*(.+)"),
                ("value", r"value:\s*(.+)"),
                ("id", r"id:\s*(.+)"),
                ("package", r"package:\s*(.+)"),
            ]:
                mm = re.match(rf"^\s+{pat}\s*$", line)
                if mm:
                    cur[key] = mm.group(1).strip().strip("'\"")
        if cur:
            actions.append(cur)
    return actions


def test_deep_services_not_ungated(actions):
    deep = {"SysMain", "WSearch", "Spooler", "Themes", "LanmanServer", "LanmanWorkstation"}
    bad = []
    for a in actions:
        if a["type"] != "service.set":
            continue
        if a["service"] in deep and a["when"] != "extremeMode":
            # allow extremeMode only
            if a["when"] in ("", "serviceStrip", "defenderStrip"):
                bad.append(f"{a['file']}:{a['line']} {a['service']} when={a['when']!r}")
    if bad:
        fail(f"deep services not extremeMode-only ({len(bad)}): " + "; ".join(bad[:8]))
    else:
        ok("deep barebones services gated extremeMode only")


def test_no_active_essential_appx_remove(actions):
    # Keepers: Store + Xbox identity/TCUI. Edge is intentional strip under stripEdge (Extreme).
    # NOT XboxGamingOverlay / WindowsMaps (Extreme OK).
    ess = re.compile(
        r"Microsoft\.WindowsStore|DesktopAppInstaller|XboxIdentityProvider|"
        r"Xbox\.TCUI|\*TCUI\*|StorePurchaseApp|Microsoft\.GamingApp\*",
        re.I,
    )
    bad = []
    for a in actions:
        if a["type"] != "appx.remove":
            continue
        blob = " ".join([a["path"], a["package"], a["id"]])
        if ess.search(blob):
            bad.append(f"{a['file']}:{a['line']} {a['id']} {a['package']}")
    if bad:
        fail(f"essential Store/TCUI appx.remove still active: {bad}")
    else:
        ok("no active essential Store/TCUI appx.remove (Edge strip is stripEdge-gated)")


def test_edge_strip_gated_not_balanced_default(actions):
    """Destructive Edge strip (AppX remove / edge.ps1 / Deprovisioned) must use stripEdge."""
    bad = []
    for a in actions:
        path = a.get("path") or ""
        pkg = a.get("package") or ""
        blob = " ".join([path, pkg, a.get("id") or "", " ".join(a.get("raw") or [])])
        if "GameAssist" in blob:
            continue
        is_edge_strip = False
        if a["type"] == "appx.remove" and re.search(
            r"microsoftedge|Microsoft\.MicrosoftEdge|Microsoft\.Edge\*|microsoftedge\.stable",
            pkg,
            re.I,
        ):
            is_edge_strip = True
        if a["type"] == "run" and re.search(r"edge\.ps1", blob, re.I):
            is_edge_strip = True
        if a["type"] == "registry.set" and re.search(
            r"Deprovisioned\\Microsoft\.MicrosoftEdge", path, re.I
        ):
            is_edge_strip = True
        if not is_edge_strip:
            continue
        when = a.get("when") or ""
        if when not in ("stripEdge", "extremeMode"):
            bad.append(f"{a['file']}:{a['line']} {a['type']} {a.get('id')} when={when!r}")
    if bad:
        fail(f"Edge strip not stripEdge-gated ({len(bad)}): " + "; ".join(bad[:12]))
    else:
        ok("Edge strip actions gated stripEdge (Balanced default off)")


def test_strip_edge_default_true():
    text = (PLAYBOOK / "playbook.yml").read_text(encoding="utf-8")
    m = re.search(r"stripEdge:\s*['\"]?(\w+)", text)
    if not m or m.group(1) != "true":
        fail(f"playbook stripEdge default want true got {m.group(1) if m else None}")
    else:
        ok("playbook default stripEdge=true (Extreme product default)")


def test_no_ungated_edge_script(actions):
    """edge.ps1 must not run unless stripEdge (default false) — never ungated."""
    bad = []
    for a in actions:
        if a["type"] != "run":
            continue
        blob = " ".join([a.get("path") or "", a.get("id") or "", " ".join(a.get("raw") or [])])
        if re.search(r"edge\.ps1", blob, re.I):
            if a.get("when") not in ("stripEdge", "extremeMode"):
                bad.append(f"{a['file']}:{a['line']} when={a.get('when')!r}")
    if bad:
        fail(f"edge.ps1 not properly gated: {bad}")
    else:
        ok("edge.ps1 gated (stripEdge), not ungated")


def test_no_active_sr_zero(actions):
    bad = []
    for a in actions:
        if a.get("valueName") == "SystemResponsiveness" and a.get("value") in ("0", "0x0"):
            bad.append(f"{a['file']}:{a['line']}")
    if bad:
        fail(f"SystemResponsiveness=0 still active: {bad}")
    else:
        ok("no active SystemResponsiveness=0")


def test_no_active_smartscreen_ifeo(actions):
    bad = []
    for a in actions:
        blob = " ".join([a["path"], a["valueName"], a["value"]])
        if re.search(r"smartscreen\.exe", blob, re.I) and re.search(r"Debugger", blob, re.I):
            bad.append(f"{a['file']}:{a['line']}")
    if bad:
        fail(f"smartscreen IFEO still active: {bad}")
    else:
        ok("no active smartscreen IFEO debugger")


def test_ifeo_taskkill_extreme_only(actions):
    """IFEO Debugger=taskkill must not run on Balanced (ungated)."""
    bad = []
    for a in actions:
        if a["type"] != "registry.set":
            continue
        if a.get("valueName") != "Debugger":
            continue
        if not re.search(r"taskkill", a.get("value") or "", re.I):
            continue
        if not re.search(r"Image File Execution Options", a.get("path") or "", re.I):
            continue
        if a.get("when") != "extremeMode":
            bad.append(f"{a['file']}:{a['line']} {a['id']} when={a.get('when')!r} path={a['path'][-40:]}")
    if bad:
        fail(f"IFEO Debugger=taskkill not extremeMode-only ({len(bad)}): " + "; ".join(bad[:10]))
    else:
        ok("all IFEO Debugger=taskkill gated extremeMode")


def test_taskkill_runs_extreme_only(actions):
    """run file=taskkill.exe (shell/browser kills) must not be ungated on Balanced."""
    bad = []
    for a in actions:
        if a["type"] != "run":
            continue
        blob = " ".join([a.get("path") or "", a.get("id") or "", " ".join(a.get("raw") or [])])
        if not re.search(r"taskkill", blob, re.I):
            continue
        if a.get("when") != "extremeMode":
            bad.append(f"{a['file']}:{a['line']} {a['id']} when={a.get('when')!r}")
    if bad:
        fail(f"run taskkill not extremeMode-only ({len(bad)}): " + "; ".join(bad[:10]))
    else:
        ok("all run taskkill.exe gated extremeMode")


def test_no_research_dumps():
    """Third-party research/baseline merges must not ship."""
    banned = [
        "12-reg-research-winhance.yml",
        "12-reg-research-winutil.yml",
        "13-reg-baselines-all.yml",
        "42-services-research.yml",
        "43-services-baselines.yml",
        "92-appx-research.yml",
        "93-appx-baselines.yml",
    ]
    found = [n for n in banned if (ACTIONS / "generated" / n).exists()]
    pb = (PLAYBOOK / "playbook.yml").read_text(encoding="utf-8")
    wired = [n for n in banned if n in pb]
    if found or wired:
        fail("research dumps still present: " + ", ".join(sorted(set(found + wired))))
    else:
        ok("no research/baseline merge dumps in product playbook")


def test_no_nexus_cdn_in_wired_scripts():
    """Apply path must not download from cdn.getnexus.cc."""
    roots = [
        PLAYBOOK / "scripts" / "exo-core" / "Scripts" / "DisableDevices.ps1",
        PLAYBOOK / "scripts" / "exo-core" / "Scripts" / "Hosts.ps1",
        PLAYBOOK / "scripts" / "exo-core" / "Scripts" / "DisableDefender.ps1",
        PLAYBOOK / "scripts" / "exo-core" / "Scripts" / "DisableAI.ps1",
        PLAYBOOK / "scripts" / "exo-core" / "Scripts" / "RemoveComponents.ps1",
        PLAYBOOK / "scripts" / "exo-core" / "Scripts" / "Install-7Zip.ps1",
        PLAYBOOK / "actions" / "generated" / "05-exo-run.yml",
    ]
    bad = []
    for p in roots:
        text = p.read_text(encoding="utf-8", errors="replace")
        if "cdn.getnexus.cc" in text:
            bad.append(str(p.relative_to(PLAYBOOK)))
    if bad:
        fail("Nexus CDN still referenced in wired scripts: " + ", ".join(bad))
    else:
        ok("wired scripts have no cdn.getnexus.cc")


def test_exo_run_no_footguns_or_dupes():
    """05-exo-run must not re-run YAML-covered scripts or kill the shell."""
    text = (PLAYBOOK / "actions" / "generated" / "05-exo-run.yml").read_text(
        encoding="utf-8", errors="replace"
    )
    body = "\n".join(
        ln for ln in text.splitlines() if not ln.lstrip().startswith("#")
    )
    needles = [
        "filters.bat",
        "StartMenuExperienceHost",
        "ShellExperienceHost",
        'IM "setup"',
        "wallpaper.ps1",
        "modules.ps1",
        "StartMenu.ps1",
        "PauseUpdates.cmd",
        "powerplan.bat",
        "Windows11.bat",
        "RemoveBloatwareTasks",
        "exo-script-45",
        "cdn.getnexus.cc",
    ]
    bad = [n for n in needles if n in body]
    if bad:
        fail("05-exo-run still contains: " + ", ".join(bad))
    else:
        ok("05-exo-run has no footguns or duplicate script runs")


def test_identity_applied_at_finalize():
    ident = (PLAYBOOK / "actions" / "00-identity.yml").read_text(encoding="utf-8")
    fin = (PLAYBOOK / "actions" / "99-finalize.yml").read_text(encoding="utf-8")
    if re.search(r"valueName:\s*Applied", ident):
        fail("Applied must not be set in 00-identity (belongs in 99-finalize)")
    else:
        ok("identity does not mark Applied at start")
    if not re.search(r"valueName:\s*Applied", fin):
        fail("99-finalize must set Applied")
    else:
        ok("finalize sets Applied")
    if 'value: "1.8.0"' not in ident and "value: '1.8.0'" not in ident:
        fail("00-identity Version is not 1.8.0")
    else:
        ok("identity version 1.8.0")
    marker = (PLAYBOOK / "scripts" / "Write-AppliedMarker.ps1").read_text(encoding="utf-8")
    if "1.8.0" not in marker:
        fail("Write-AppliedMarker version is not 1.8.0")
    else:
        ok("applied.json version 1.8.0")


def test_no_orphan_hand_yaml():
    """Hand YAML under actions/*.yml except identity/finalize must not exist."""
    keep = {"00-identity.yml", "99-finalize.yml"}
    orphans = [
        p.name
        for p in (ACTIONS).glob("*.yml")
        if p.name not in keep
    ]
    if orphans:
        fail("orphaned hand YAML still present: " + ", ".join(sorted(orphans)))
    else:
        ok("no superseded hand YAML next to generated/")


def test_playbook_defaults_extreme():
    text = (PLAYBOOK / "playbook.yml").read_text(encoding="utf-8")
    for key, want in [
        ("extremeMode", "true"),
        ("dismStrip", "true"),
        ("serviceStrip", "true"),
        ("defenderStrip", "true"),
        ("disableVbs", "true"),
        ("stripEdge", "true"),
    ]:
        m = re.search(rf"{key}:\s*['\"]?(\w+)", text)
        if not m or m.group(1) != want:
            fail(f"playbook default {key} want {want} got {m.group(1) if m else None}")
        else:
            ok(f"playbook default {key}={want}")


def main() -> int:
    print("=== test_tier_gates (shipped playbook path) ===")
    actions = parse_actions()
    print(f"parsed actions: {len(actions)}")
    if len(actions) < 800:
        fail(f"product playbook too small, got {len(actions)}")
    elif len(actions) > 2000:
        fail(f"product playbook looks like research dumps returned, got {len(actions)}")
    else:
        ok(f"action inventory scale {len(actions)}")
    test_no_research_dumps()
    test_deep_services_not_ungated(actions)
    test_no_active_essential_appx_remove(actions)
    test_strip_edge_default_true()
    test_edge_strip_gated_not_balanced_default(actions)
    test_no_ungated_edge_script(actions)
    test_no_active_sr_zero(actions)
    test_no_active_smartscreen_ifeo(actions)
    test_ifeo_taskkill_extreme_only(actions)
    test_taskkill_runs_extreme_only(actions)
    test_no_nexus_cdn_in_wired_scripts()
    test_exo_run_no_footguns_or_dupes()
    test_identity_applied_at_finalize()
    test_no_orphan_hand_yaml()
    test_playbook_defaults_extreme()
    print()
    if FAILS:
        print(f"FAILED {len(FAILS)} checks")
        for f in FAILS:
            print(" -", f)
        return 1
    print("ALL CHECKS PASSED")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
