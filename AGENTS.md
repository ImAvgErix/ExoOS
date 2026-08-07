# Agent rules — Exo OS

## Mandatory self-test (do not skip)

After **every** change that affects the running app (UI, chrome, host bridge, playbook wiring, onboarding, apply flow):

1. **Build** — `npm run build` in `src/ExoOS.App/ui` and `dotnet build` ExoOS.App Release; sync `wwwroot` into the output folder.
2. **Launch** with CDP when UI is involved: `EXOOS_CDP=1` / `EXOOS_CDP_PORT=9229`.
3. **Test with Aether only** — MCP `aether` or `python -m aether.mcp_server` / `SmartController` (`~/.aether/aether-driver`).  
   Prefer `compact_observe` → `smart_click` / `browser_connect_cdp` + browser tools. Never click Documentation/GitHub.
4. Only report back after Aether shows the change works (or document a hard failure with evidence).

### Tool roles

| Tool | Use for |
|------|---------|
| **Aether** (Synthetic hands + CDP/browser) | **Everything** — WebView2, native chrome, drag, close, desktop |

**Do not use Cua.** Aether v1.1 Synthetic/UIA replaces it.

### Product constraints (current)

- No Home / Settings chrome; thin native drag strip + close only.
- No dashboard; setup then plan screen.
- Brand line: **Built quiet. Tuned sharp.** (no attribution under it).
- No blur on step transitions (text must stay sharp).
- No scroll on onboarding ready / finish-setup summary.
- No “Ready” badge next to “Your plan”.
- UI **Apply plan** is LIVE — never click it on the Nexus host during agent self-test.
