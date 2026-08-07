#!/usr/bin/env python3
"""Gate all IFEO Debugger=taskkill and taskkill run/taskkill actions to extremeMode.
Also lists remaining ungated hostile actions.
"""
from __future__ import annotations
import re
from pathlib import Path

PLAYBOOK = Path(__file__).resolve().parents[3]
ACTIONS = PLAYBOOK / "actions"


def inject_extreme(block: list[str]) -> list[str]:
    if any(re.match(r"^\s*whenOption:\s*", bl) for bl in block):
        # replace non-extreme with extremeMode for hostile
        out = []
        for bl in block:
            if re.match(r"^\s*whenOption:\s*", bl):
                indent = re.match(r"^(\s*)", bl).group(1)
                out.append(f"{indent}whenOption: extremeMode")
            else:
                out.append(bl)
        return out
    indent = "    "
    for bl in block[1:]:
        m = re.match(r"^(\s+)\S", bl)
        if m:
            indent = m.group(1)
            break
    return [block[0], f"{indent}whenOption: extremeMode"] + block[1:]


def is_ifeo_taskkill(blob: str) -> bool:
    return bool(
        re.search(r"Image File Execution Options", blob, re.I)
        and re.search(r"Debugger", blob, re.I)
        and re.search(r"taskkill", blob, re.I)
    )


def is_taskkill_run(blob: str) -> bool:
    return bool(re.search(r"taskkill\.exe|file:\s*taskkill", blob, re.I))


def main() -> int:
    changed_files = 0
    inject_count = 0
    for f in sorted(ACTIONS.rglob("*.yml")):
        lines = f.read_text(encoding="utf-8", errors="replace").splitlines()
        out: list[str] = []
        i = 0
        file_ch = 0
        while i < len(lines):
            line = lines[i]
            mtype = re.match(r"^\s*-\s*type:\s*(\S+)\s*$", line)
            if mtype:
                block = [line]
                j = i + 1
                while j < len(lines) and not re.match(r"^\s*-\s*type:\s*", lines[j]):
                    block.append(lines[j])
                    j += 1
                blob = "\n".join(block)
                t = mtype.group(1)
                need = False
                if t == "registry.set" and is_ifeo_taskkill(blob):
                    need = True
                if t == "run" and is_taskkill_run(blob):
                    need = True
                if t == "taskkill":
                    # process reduction: if only serviceStrip, still ok for mild; force extreme for shell/browser
                    if re.search(
                        r"msedge|MicrosoftEdge|StartMenuExperienceHost|ShellExperienceHost|SearchHost|SearchIndexer|GameBar|smartscreen|SecurityHealth",
                        blob,
                        re.I,
                    ):
                        need = True
                    elif not re.search(r"whenOption:", blob):
                        # ungated generic taskkill -> extreme
                        need = True
                if need:
                    has = re.search(r"whenOption:\s*(\S+)", blob)
                    if not has or has.group(1) != "extremeMode":
                        block = inject_extreme(block)
                        file_ch += 1
                        inject_count += 1
                out.extend(block)
                i = j
                continue
            out.append(line)
            i += 1
        if file_ch:
            f.write_text("\n".join(out) + "\n", encoding="utf-8")
            print(f"{f.relative_to(PLAYBOOK)}: gated {file_ch}")
            changed_files += 1
    print(f"TOTAL files={changed_files} injects={inject_count}")

    # verify list remaining ungated
    print("--- remaining ungated hostile ---")
    left = 0
    for f in sorted(ACTIONS.rglob("*.yml")):
        lines = f.read_text(encoding="utf-8", errors="replace").splitlines()
        i = 0
        while i < len(lines):
            mtype = re.match(r"^\s*-\s*type:\s*(\S+)\s*$", lines[i])
            if mtype:
                block = [lines[i]]
                j = i + 1
                while j < len(lines) and not re.match(r"^\s*-\s*type:\s*", lines[j]):
                    block.append(lines[j])
                    j += 1
                blob = "\n".join(block)
                t = mtype.group(1)
                when = re.search(r"whenOption:\s*(\S+)", blob)
                w = when.group(1) if when else ""
                if t == "registry.set" and is_ifeo_taskkill(blob) and w != "extremeMode":
                    print(f"STILL {f}:{i+1} IFEO when={w!r}")
                    left += 1
                if t == "run" and is_taskkill_run(blob) and w != "extremeMode":
                    print(f"STILL {f}:{i+1} RUN taskkill when={w!r}")
                    left += 1
                i = j
                continue
            i += 1
    print(f"remaining={left}")
    return 0 if left == 0 else 1


if __name__ == "__main__":
    raise SystemExit(main())
