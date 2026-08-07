#!/usr/bin/env python3
"""Restore Edge strip actions under whenOption: stripEdge (Extreme + opt-in cleanup).

Browsers = user-chosen Chrome/Brave/Firefox/etc. Edge is forced Windows bloat and
should die on Extreme / stripEdge. TCUI/Store identity stays quarantined.
"""
from __future__ import annotations
import re
from pathlib import Path

PLAYBOOK = Path(__file__).resolve().parents[3]
ACTIONS = PLAYBOOK / "actions"

EDGE_MARK = re.compile(
    r"QUARANTINED essential \(Edge|Edge browser package|Edge deprovision",
    re.I,
)


def uncomment_block(lines: list[str], start: int) -> tuple[list[str], int]:
    """From a quarantine comment header, restore following # - type: block."""
    # skip header lines that are only quarantine notices
    i = start
    restored: list[str] = []
    # consume consecutive comment lines that form one or more actions
    while i < len(lines):
        ln = lines[i]
        if EDGE_MARK.search(ln):
            i += 1
            continue
        if not ln.strip().startswith("#"):
            break
        # strip leading comment + optional space
        body = re.sub(r"^\s*#\s?", "", ln)
        # empty comment line ends a sub-block sometimes
        if not body.strip():
            i += 1
            # if next is another quarantine header or real action, stop
            if i < len(lines) and (
                EDGE_MARK.search(lines[i]) or re.match(r"^\s*-\s*type:", lines[i])
            ):
                break
            continue
        restored.append(body if body.startswith(" ") or body.startswith("-") else "  " + body)
        i += 1
        # stop after one full action if we hit next quarantine header peek
        if i < len(lines) and EDGE_MARK.search(lines[i]):
            break
        # stop if uncommented next real action
        if i < len(lines) and re.match(r"^\s*-\s*type:", lines[i]):
            break
    return restored, i


def ensure_when_strip_edge(block_lines: list[str]) -> list[str]:
    out = []
    has_when = False
    for bl in block_lines:
        if re.match(r"^\s*whenOption:\s*", bl):
            indent = re.match(r"^(\s*)", bl).group(1)
            out.append(f"{indent}whenOption: stripEdge")
            has_when = True
        else:
            out.append(bl)
    if not has_when and out:
        # insert after type line
        indent = "    "
        for bl in out[1:]:
            m = re.match(r"^(\s+)\S", bl)
            if m:
                indent = m.group(1)
                break
        out = [out[0], f"{indent}whenOption: stripEdge"] + out[1:]
    return out


def process_file(path: Path) -> int:
    lines = path.read_text(encoding="utf-8", errors="replace").splitlines()
    out: list[str] = []
    i = 0
    ch = 0
    while i < len(lines):
        ln = lines[i]
        if EDGE_MARK.search(ln):
            # restore following commented action(s) for Edge only
            restored, ni = uncomment_block(lines, i)
            # group restored into actions
            if restored:
                # may be multiple actions - re-split by type
                cur: list[str] = []
                for bl in restored:
                    if re.match(r"^\s*-\s*type:", bl) and cur:
                        fixed = ensure_when_strip_edge(cur)
                        out.extend(fixed)
                        ch += 1
                        cur = [bl]
                    else:
                        cur.append(bl)
                if cur:
                    fixed = ensure_when_strip_edge(cur)
                    out.extend(fixed)
                    ch += 1
            i = ni
            continue
        out.append(ln)
        i += 1
    if ch:
        path.write_text("\n".join(out) + "\n", encoding="utf-8")
    return ch


def main() -> int:
    total = 0
    for f in sorted(ACTIONS.rglob("*.yml")):
        n = process_file(f)
        if n:
            print(f"{f.relative_to(PLAYBOOK)}: restored {n}")
            total += n
    print(f"TOTAL restored Edge strip blocks: {total}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
