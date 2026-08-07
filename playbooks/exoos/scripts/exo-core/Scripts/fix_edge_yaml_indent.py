#!/usr/bin/env python3
from pathlib import Path
import re

p = Path(__file__).resolve().parents[3] / "actions/generated/10-reg-hklm-software.yml"
lines = p.read_text(encoding="utf-8").splitlines()
out = []
i = 0
while i < len(lines):
    if re.match(r"^- type: registry\.set\s*$", lines[i]) and i + 1 < len(lines) and "stripEdge" in lines[i + 1]:
        block = [lines[i]]
        j = i + 1
        while j < len(lines) and not re.match(r"^- type:|^  - type:", lines[j]):
            if re.match(r"^  \S", lines[j]):
                block.append(lines[j])
                j += 1
            else:
                break
        for b in block:
            if b.startswith("- type"):
                out.append("  " + b)
            elif b.startswith("  "):
                out.append("  " + b)
            else:
                out.append(b)
        print("repaired ids:", [b for b in block if "id:" in b])
        i = j
        continue
    out.append(lines[i])
    i += 1
p.write_text("\n".join(out) + "\n", encoding="utf-8")
# show result
text = p.read_text(encoding="utf-8").splitlines()
for i, ln in enumerate(text, 1):
    if "exo-reg-624" in ln:
        for j in range(i - 2, i + 6):
            print(f"{j}:{text[j-1]}")
