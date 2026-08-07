#!/usr/bin/env python3
"""Move deep barebones services from serviceStrip to extremeMode."""
from __future__ import annotations
import re
from pathlib import Path

PLAYBOOK = Path(__file__).resolve().parents[3]
DEEP = {
    "SysMain", "WSearch", "Spooler", "Themes", "FontCache", "ShellHWDetection",
    "LanmanServer", "LanmanWorkstation", "XblAuthManager", "XblGameSave",
    "XboxGipSvc", "XboxNetApiSvc", "Fax",
}

def main() -> int:
    files = list((PLAYBOOK / "actions").rglob("*.yml"))
    total = 0
    for f in files:
        lines = f.read_text(encoding="utf-8", errors="replace").splitlines()
        out = []
        i = 0
        ch = 0
        while i < len(lines):
            line = lines[i]
            if re.match(r"^\s*-\s*type:\s*service\.set\s*$", line):
                block = [line]
                j = i + 1
                while j < len(lines) and not re.match(r"^\s*-\s*type:\s*", lines[j]):
                    block.append(lines[j])
                    j += 1
                blob = "\n".join(block)
                svc_m = re.search(r"service:\s*['\"]?([A-Za-z0-9_.]+)", blob)
                svc = svc_m.group(1) if svc_m else ""
                if svc in DEEP:
                    newb = []
                    has_when = False
                    for bl in block:
                        if re.match(r"^\s*whenOption:\s*", bl):
                            indent = re.match(r"^(\s*)", bl).group(1)
                            newb.append(f"{indent}whenOption: extremeMode")
                            has_when = True
                        else:
                            newb.append(bl)
                    if not has_when:
                        indent = "    "
                        for bl in block[1:]:
                            m = re.match(r"^(\s+)\S", bl)
                            if m:
                                indent = m.group(1)
                                break
                        newb = [block[0], f"{indent}whenOption: extremeMode"] + block[1:]
                    out.extend(newb)
                    ch += 1
                    i = j
                    continue
                out.extend(block)
                i = j
                continue
            out.append(line)
            i += 1
        if ch:
            f.write_text("\n".join(out) + "\n", encoding="utf-8")
            print(f"{f.relative_to(PLAYBOOK)}: {ch}")
            total += ch
    print(f"TOTAL deep services gated extremeMode: {total}")
    return 0

if __name__ == "__main__":
    raise SystemExit(main())
