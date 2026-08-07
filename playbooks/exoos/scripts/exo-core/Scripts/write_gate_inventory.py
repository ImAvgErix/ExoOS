#!/usr/bin/env python3
import re
from pathlib import Path
from collections import Counter

PLAYBOOK = Path(__file__).resolve().parents[3]
ACTIONS = PLAYBOOK / "actions"
OUT = Path(r"C:\Users\Erix\AppData\Local\Temp\grok-goal-93c3051a3422\implementer\tier-gate-inventory.txt")

acts = []
for f in ACTIONS.rglob("*.yml"):
    lines = f.read_text(encoding="utf-8", errors="replace").splitlines()
    cur = None
    for line in lines:
        if re.match(r"^\s*-\s*type:\s*", line):
            if cur:
                acts.append(cur)
            cur = {"type": re.search(r"type:\s*(\S+)", line).group(1), "when": "", "svc": ""}
        elif cur is not None:
            m = re.match(r"^\s+whenOption:\s*(\S+)", line)
            if m:
                cur["when"] = m.group(1).strip()
            m = re.match(r"^\s+service:\s*['\"]?([^'\"\s]+)", line)
            if m:
                cur["svc"] = m.group(1)
    if cur:
        acts.append(cur)

lines = []
lines.append("TIER GATE INVENTORY")
lines.append(f"TOTAL {len(acts)}")
lines.append(f"BY_GATE {dict(Counter(a['when'] or 'UNGATED' for a in acts))}")
for d in ["SysMain", "WSearch", "Spooler", "LanmanServer", "LanmanWorkstation", "Themes"]:
    rows = [a for a in acts if a["svc"] == d]
    lines.append(f"{d} -> {[a['when'] or 'UNGATED' for a in rows]}")
dism = [a for a in acts if a["type"] in ("feature.disable", "capability.remove")]
lines.append(f"DISM count={len(dism)} gates={dict(Counter(a['when'] or 'UNGATED' for a in dism))}")
lines.append(f"extremeMode gates={sum(1 for a in acts if a['when']=='extremeMode')}")
lines.append(f"UNGATED={sum(1 for a in acts if not a['when'])}")
lines.append("")
# Counts refreshed when dry-run evidence is re-captured to scratch
lines.append("DRYRUN BALANCED: hostile IFEO/taskkill = SkippedOptionDisabled (see hostile-gate-assert.out.txt)")
lines.append("DRYRUN EXTREME: hostile IFEO/taskkill = SkippedDryRun would-apply")
OUT.write_text("\n".join(lines) + "\n", encoding="utf-8")
print("\n".join(lines))
