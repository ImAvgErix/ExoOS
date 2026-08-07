# Aether Driver v1.1

Hardened **custom synthetic hands** + full smart computer-use brain.  
**Primary PC control stack for Grok / agents — Cua is not required.**

## Hands (v1.1 hardening)

| Layer | What |
|-------|------|
| **Windows UIA invoke** | `invoke` / `toggle` / `select` patterns before coordinate clicks |
| **Windows PostMessage** | Best-effort background click by HWND |
| **Windows SendInput** | Absolute mouse + unicode keyboard |
| **macOS AXPress** | Accessibility press by title under PID |
| **macOS CGEvent** | Coordinate path |
| **Linux** | xdotool / XTest |
| **Parallel queues** | One worker thread per virtual cursor — no mid-action interleave |

Priority: **Synthetic → pywinauto → local** (Cua optional / off by default)

## Brain
smart_click/type/fill, wait_*, memory, batch, macros, compact_observe, CDP Chrome attach, browser Spaces, safety, annotate, action log.

## Install (agent machine)

```powershell
cd $env:USERPROFILE\.aether\aether-driver
pip install -e .
pip install pywinauto
playwright install chromium
# MCP for Grok: python -m aether.mcp_server
```

## Multi-cursor agents

```
create_cursor("worker-1")
create_cursor("worker-2")
queue_stats()
```

Each cursor serializes its own injects; different cursors run in parallel workers.

MIT
