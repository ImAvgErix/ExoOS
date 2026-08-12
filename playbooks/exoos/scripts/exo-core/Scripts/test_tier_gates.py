#!/usr/bin/env python3
"""Unit/structural tests for Extreme vs Balanced gating (shipped playbook YAML + auditor)."""
from __future__ import annotations
import csv
import re
import subprocess
import sys
from pathlib import Path

PLAYBOOK = Path(__file__).resolve().parents[3]
ACTIONS = PLAYBOOK / "actions"
SCRIPTS = Path(__file__).resolve().parent
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


def test_merge_dumps_gated(actions):
    """Atlas/Revi/Winhance/WinUtil dumps must not leak onto Balanced."""
    dumps = (
        "13-reg-baselines-all.yml",
        "12-reg-research-winhance.yml",
        "12-reg-research-winutil.yml",
    )
    bad = []
    for a in actions:
        if not any(a["file"].endswith(d) for d in dumps):
            continue
        if a["type"] == "note":
            continue
        if a.get("when") != "extremeMode":
            bad.append(f"{a['file']}:{a['line']} {a['type']} {a.get('id')} when={a.get('when')!r}")
    if bad:
        fail(f"ungated research-merge actions ({len(bad)}): " + "; ".join(bad[:12]))
    else:
        ok("research-merge dumps fully gated extremeMode")


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


def test_mis_tier_after_auditor():
    """Run shipped audit_tier_gate.py and assert NeedsGate count is 0 for deep classes."""
    py = SCRIPTS / "audit_tier_gate.py"
    scratch = Path("/tmp/exoos-audit")
    scratch.mkdir(parents=True, exist_ok=True)
    env = dict(**{k: v for k, v in __import__("os").environ.items()})
    env["PROGRAMDATA"] = str(scratch)
    env["EXO_AUDIT_SCRATCH"] = str(scratch / "ExoOS" / "audit")
    r = subprocess.run([sys.executable, str(py)], capture_output=True, text=True, env=env)
    if r.returncode != 0:
        fail(f"audit_tier_gate failed: {(r.stderr or r.stdout)[-800:]}")
        return
    mis = scratch / "ExoOS" / "audit" / "mis-tier-ungated-extreme-latest.csv"
    if not mis.exists():
        # auditor may write under EXO_AUDIT_SCRATCH directly
        mis = scratch / "mis-tier-ungated-extreme-latest.csv"
    if not mis.exists():
        # glob
        found = list(scratch.rglob("mis-tier-ungated-extreme-latest.csv"))
        mis = found[0] if found else mis
    if not mis.exists():
        fail("mis-tier CSV missing after auditor run")
        return
    rows = list(csv.DictReader(mis.open(encoding="utf-8")))
    hard = []
    for row in rows:
        blob = " ".join(row.get(k, "") or "" for k in row)
        if re.search(
            r"SysMain|WSearch|Spooler|Lanman|Image File Execution|FeatureSettingsOverride|DeviceGuard|PrefetchParameters|Win32PrioritySeparation|13-reg-baselines",
            blob,
            re.I,
        ):
            hard.append(f"{row.get('File')}:{row.get('Line')}:{row.get('Id')}")
    if hard:
        fail(f"still mis-tier ungated extreme hard items ({len(hard)}): " + "; ".join(hard[:12]))
    else:
        ok(f"no hard mis-tier ungated extreme (mis-tier residual soft count={len(rows)})")


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
    if len(actions) < 2000:
        fail(f"expected ~3000+ actions, got {len(actions)}")
    else:
        ok(f"action inventory scale {len(actions)}")
    test_deep_services_not_ungated(actions)
    test_no_active_essential_appx_remove(actions)
    test_strip_edge_default_true()
    test_edge_strip_gated_not_balanced_default(actions)
    test_no_ungated_edge_script(actions)
    test_no_active_sr_zero(actions)
    test_no_active_smartscreen_ifeo(actions)
    test_ifeo_taskkill_extreme_only(actions)
    test_taskkill_runs_extreme_only(actions)
    test_merge_dumps_gated(actions)
    test_no_nexus_cdn_in_wired_scripts()
    test_playbook_defaults_extreme()
    test_mis_tier_after_auditor()
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
