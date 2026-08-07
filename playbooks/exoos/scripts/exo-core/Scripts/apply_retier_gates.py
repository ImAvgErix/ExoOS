#!/usr/bin/env python3
"""Inject whenOption: extremeMode into mis-tiered ungated Extreme actions.
Also quarantine essential-breaking appx.remove and known theater keys.
Drives real playbook YAML under playbooks/exoos/actions.
"""
from __future__ import annotations
import csv
import re
import sys
from collections import defaultdict
from pathlib import Path

PLAYBOOK = Path(__file__).resolve().parents[3]
ACTIONS = PLAYBOOK / "actions"
MIS_CSV = Path(r"C:\ProgramData\ExoOS\audit\mis-tier-ungated-extreme-latest.csv")
Q_CSV = Path(r"C:\ProgramData\ExoOS\audit\quarantine-latest.csv")

# Essential appx package name fragments — never remove on any path
ESSENTIAL_APPX = re.compile(
    r"WindowsStore|DesktopAppInstaller|StorePurchaseApp|XboxIdentityProvider|"
    r"Xbox\.TCUI|GamingApp|XboxGameCallableUI",
    re.I,
)


def inject_when_option(lines: list[str], action_start_idx: int, option: str = "extremeMode") -> bool:
    """Insert whenOption after type line if missing in this action block. Returns True if changed."""
    # Find end of action (next - type: or EOF)
    end = len(lines)
    for j in range(action_start_idx + 1, len(lines)):
        if re.match(r"^\s*-\s*type:\s*", lines[j]):
            end = j
            break
    block = "\n".join(lines[action_start_idx:end])
    if re.search(r"^\s+whenOption:\s*", block, re.M):
        return False
    # Indent: match first property indent or default 4 spaces
    indent = "    "
    for j in range(action_start_idx + 1, end):
        m = re.match(r"^(\s+)\S", lines[j])
        if m:
            indent = m.group(1)
            break
    # Insert right after type line
    insert_at = action_start_idx + 1
    lines.insert(insert_at, f"{indent}whenOption: {option}")
    return True


def find_action_starts(lines: list[str]) -> list[int]:
    return [i for i, l in enumerate(lines) if re.match(r"^\s*-\s*type:\s*", l)]


def process_file_by_lines(rel: str, target_lines: set[int], option: str = "extremeMode") -> tuple[int, int]:
    """target_lines are 1-based line numbers of type: lines from auditor."""
    path = PLAYBOOK / rel.replace("/", "\\")
    if not path.exists():
        # try forward
        path = PLAYBOOK / rel
    if not path.exists():
        print(f"MISSING {rel}")
        return 0, 0
    text = path.read_text(encoding="utf-8", errors="replace")
    lines = text.splitlines()
    # Map 1-based line -> 0-based index; after inserts, line numbers shift — process bottom-up
    targets = sorted([ln - 1 for ln in target_lines if 1 <= ln <= len(lines)], reverse=True)
    changed = 0
    for idx in targets:
        if idx < 0 or idx >= len(lines):
            continue
        if not re.match(r"^\s*-\s*type:\s*", lines[idx]):
            # search nearby for type line
            found = None
            for d in range(0, 5):
                for cand in (idx - d, idx + d):
                    if 0 <= cand < len(lines) and re.match(r"^\s*-\s*type:\s*", lines[cand]):
                        found = cand
                        break
                if found is not None:
                    break
            if found is None:
                continue
            idx = found
        if inject_when_option(lines, idx, option):
            changed += 1
    if changed:
        path.write_text("\n".join(lines) + "\n", encoding="utf-8")
    return changed, len(targets)


def quarantine_essential_appx() -> list[str]:
    """Comment out appx.remove for essential packages (Store / Xbox identity)."""
    reports = []
    for f in list(ACTIONS.rglob("*.yml")):
        text = f.read_text(encoding="utf-8", errors="replace")
        lines = text.splitlines()
        out = []
        i = 0
        changed = 0
        while i < len(lines):
            line = lines[i]
            if re.match(r"^\s*-\s*type:\s*appx\.remove\s*$", line):
                # collect block
                block = [line]
                j = i + 1
                while j < len(lines) and not re.match(r"^\s*-\s*type:\s*", lines[j]):
                    block.append(lines[j])
                    j += 1
                blob = "\n".join(block)
                if ESSENTIAL_APPX.search(blob) or re.search(
                    r"appx-xbox-tcui|appx-xbox-identity|XboxIdentity|Xbox\.TCUI|WindowsStore",
                    blob,
                    re.I,
                ):
                    out.append(f"  # QUARANTINED essential keeper (audit): was appx.remove")
                    for bl in block:
                        out.append(f"  # {bl.lstrip()}" if bl.strip() else "  #")
                    changed += 1
                    i = j
                    continue
            out.append(line)
            i += 1
        if changed:
            f.write_text("\n".join(out) + "\n", encoding="utf-8")
            reports.append(f"{f.relative_to(PLAYBOOK)}: quarantined {changed} essential appx")
    return reports


def quarantine_theater_registry() -> list[str]:
    """Comment theater Games GPU Priority / Priority!=2 / SystemResponsiveness 0 if any remain."""
    reports = []
    theater_vn = {
        "GPU Priority": True,
        "SFIO Priority": True,
    }
    for f in list(ACTIONS.rglob("*.yml")):
        text = f.read_text(encoding="utf-8", errors="replace")
        lines = text.splitlines()
        out = []
        i = 0
        changed = 0
        while i < len(lines):
            line = lines[i]
            if re.match(r"^\s*-\s*type:\s*registry\.set\s*$", line):
                block = [line]
                j = i + 1
                while j < len(lines) and not re.match(r"^\s*-\s*type:\s*", lines[j]):
                    block.append(lines[j])
                    j += 1
                blob = "\n".join(block)
                kill = False
                why = ""
                if re.search(r"Tasks\\Games", blob) and re.search(r"valueName:\s*['\"]?GPU Priority", blob):
                    kill, why = True, "MS GPU Priority unused"
                if re.search(r"Tasks\\Games", blob) and re.search(r"valueName:\s*['\"]?SFIO Priority", blob):
                    kill, why = True, "MS SFIO unused"
                if re.search(r"Tasks\\Games", blob) and re.search(r"valueName:\s*['\"]?Priority['\"]?\s*$", blob, re.M):
                    if re.search(r"value:\s*['\"]?[3-9]", blob) or re.search(r"value:\s*['\"]?6", blob):
                        kill, why = True, "MS Priority under High forced to 2"
                if re.search(r"SystemResponsiveness", blob) and re.search(r"value:\s*['\"]?0['\"]?\s*$", blob, re.M):
                    kill, why = True, "SR=0 clamps to 20"
                if re.search(r"smartscreen\.exe", blob, re.I) and re.search(r"Debugger", blob):
                    kill, why = True, "IFEO smartscreen"
                if kill:
                    out.append(f"  # QUARANTINED THEATER/DANGER ({why})")
                    for bl in block:
                        out.append("  # " + bl if not bl.startswith("  #") else bl)
                    changed += 1
                    i = j
                    continue
            out.append(line)
            i += 1
        if changed:
            f.write_text("\n".join(out) + "\n", encoding="utf-8")
            reports.append(f"{f.relative_to(PLAYBOOK)}: quarantined {changed} theater/danger")
    return reports


def main() -> int:
    if not MIS_CSV.exists():
        print(f"Missing mis-tier CSV: {MIS_CSV}")
        return 1

    by_file: dict[str, set[int]] = defaultdict(set)
    with MIS_CSV.open(encoding="utf-8") as f:
        for row in csv.DictReader(f):
            rel = row["File"].replace("\\", "/")
            try:
                ln = int(row["Line"])
            except Exception:
                continue
            by_file[rel].add(ln)

    total_changed = 0
    total_targets = 0
    file_reports = []
    for rel, lineset in sorted(by_file.items()):
        ch, tg = process_file_by_lines(rel, lineset, "extremeMode")
        total_changed += ch
        total_targets += tg
        file_reports.append(f"{rel}: injected {ch}/{tg}")

    q1 = quarantine_essential_appx()
    q2 = quarantine_theater_registry()

    print("=== RETIER APPLY ===")
    print(f"Files touched (gate inject): {len(by_file)}")
    print(f"whenOption extremeMode injected: {total_changed} / targets {total_targets}")
    for r in file_reports:
        print(" ", r)
    print("=== QUARANTINE ===")
    for r in q1 + q2:
        print(" ", r)
    if not q1 and not q2:
        print("  (no additional quarantine edits or already clean)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
