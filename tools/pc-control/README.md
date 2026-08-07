# Exo OS PC Control

Reliable UI automation for the **WPF + WebView2** shell.

## Note

Agent PC control is **Aether only** (`~/.aether/aether-driver`). This Node tool remains a thin CDP helper for Exo WebView2 if needed.

## Why not Cua?

Cua Driver 0.19 documents this limit:

| Surface | Typed browser mutation |
| --- | --- |
| Chrome / Edge | Supported |
| **WebView2 hosts** | **Unsupported** — use native UIA / pixels |

On Exo OS, UIA only sees the **native title bar** (Settings ⚙ + Close ×). The React UI lives inside WebView2’s Chromium process, so:

- `get_window_state` tree has ~2 buttons
- Background pixel `PostMessage` is often dropped on Chromium
- Guessing `x,y` for “Continue” misses when layout shifts
- Clicking Settings “Documentation” opens **GitHub** (we refuse that)

## Solution

1. **App** (when `EXOOS_CDP=1` or `EXOOS_CDP_PORT` is set):
   - `--force-renderer-accessibility`
   - `--remote-debugging-port=<port>` (default **9229**)
2. **This tool** attaches with Playwright over CDP and clicks by **role / accessible name / text**.

Native chrome (drag bar, Settings, Exit) can still use Cua UIA. Page content uses this tool.

## Quick start

```powershell
# Terminal 1 — launch with CDP
$env:EXOOS_CDP = "1"
$env:EXOOS_CDP_PORT = "9229"
.\src\ExoOS.App\bin\Release\net10.0-windows\ExoOS.exe

# Terminal 2 — control
cd tools\pc-control
npm install
node cli.mjs status
node cli.mjs click "Continue"
node cli.mjs verify
```

Or one shot:

```powershell
.\scripts\Verify-UiPcControl.ps1
```

## Commands

| Command | Purpose |
| --- | --- |
| `status` | Attach + dump URL / visible text |
| `shot [path]` | Screenshot the web surface |
| `click <label>` | Click button/radio by name (**blocks Documentation**) |
| `text` | Visible text dump |
| `eval <js>` | `page.evaluate` |
| `verify` | Onboarding → Home → Apply + product checks |

## Safety

- Never clicks **Documentation** (would open GitHub in the default browser).
- `verify` does **not** press the live **Apply** action that mutates Windows.
- CDP is **off** unless you set `EXOOS_CDP` / `EXOOS_CDP_PORT` (not for end users by default).
