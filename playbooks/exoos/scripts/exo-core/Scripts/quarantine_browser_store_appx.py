#!/usr/bin/env python3
"""Quarantine Edge browser packages and TCUI/Store identity appx removes."""
from __future__ import annotations
import re
from pathlib import Path

PLAYBOOK = Path(__file__).resolve().parents[3]
ACTIONS = PLAYBOOK / "actions"

# Edge browser packages (not GameAssist overlay)
EDGE_PKG = re.compile(
    r"microsoft\.microsoftedge|Microsoft\.MicrosoftEdge|Microsoft\.Edge\*|"
    r"microsoftedge\.stable|MicrosoftEdgeDevTools|Microsoft\.Edge(?!\.GameAssist)",
    re.I,
)
# Store / Xbox identity keepers
KEEPER_PKG = re.compile(
    r"\*TCUI\*|Xbox\.TCUI|XboxIdentityProvider|Microsoft\.WindowsStore|"
    r"DesktopAppInstaller|StorePurchaseApp|Microsoft\.GamingApp\*",
    re.I,
)


def quarantine_file(path: Path) -> int:
    lines = path.read_text(encoding="utf-8", errors="replace").splitlines()
    out: list[str] = []
    i = 0
    ch = 0
    while i < len(lines):
        line = lines[i]
        if re.match(r"^\s*-\s*type:\s*appx\.remove\s*$", line):
            block = [line]
            j = i + 1
            while j < len(lines) and not re.match(r"^\s*-\s*type:\s*", lines[j]):
                block.append(lines[j])
                j += 1
            blob = "\n".join(block)
            # already commented?
            why = None
            if EDGE_PKG.search(blob) and "GameAssist" not in blob:
                why = "Edge browser package (essentials keep browsers)"
            elif KEEPER_PKG.search(blob):
                why = "Store/Xbox identity/TCUI keeper"
            if why:
                out.append(f"  # QUARANTINED essential ({why})")
                for bl in block:
                    out.append("  # " + bl.lstrip() if bl.strip() else "  #")
                ch += 1
                i = j
                continue
            out.extend(block)
            i = j
            continue
        # Also quarantine Edge deprovision registry (prevents Edge reinstall/use)
        if re.match(r"^\s*-\s*type:\s*registry\.set\s*$", line):
            block = [line]
            j = i + 1
            while j < len(lines) and not re.match(r"^\s*-\s*type:\s*", lines[j]):
                block.append(lines[j])
                j += 1
            blob = "\n".join(block)
            if re.search(r"Deprovisioned\\Microsoft\.MicrosoftEdge", blob, re.I):
                out.append("  # QUARANTINED essential (Edge deprovision — breaks browsers)")
                for bl in block:
                    out.append("  # " + bl.lstrip() if bl.strip() else "  #")
                ch += 1
                i = j
                continue
            out.extend(block)
            i = j
            continue
        out.append(line)
        i += 1
    if ch:
        path.write_text("\n".join(out) + "\n", encoding="utf-8")
    return ch


def main() -> int:
    total = 0
    for f in sorted(ACTIONS.rglob("*.yml")):
        n = quarantine_file(f)
        if n:
            print(f"{f.relative_to(PLAYBOOK)}: {n}")
            total += n
    print(f"TOTAL quarantined blocks: {total}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
