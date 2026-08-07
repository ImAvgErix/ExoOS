# UI design system (Exo 4.8 AMOLED)

ExoOS uses the **same visual design system as Exo** via a WebView2 + React shell.

## Architecture

| Layer | Role |
|-------|------|
| WPF `MainWindow` | Black chrome host, WebView2, drag strip |
| `HostBridge` | JSON-RPC (dashboard, live, options, preview, apply) |
| `ui/` React | Exact Exo tokens + layout patterns |
| `wwwroot/` | Built assets loaded at `https://exoos.local/` |

## Tokens (from Exo `tweaks.css`)

| Token | Value |
|-------|--------|
| bg | `#000000` |
| surface | `#0c0c0c` |
| elevated | `#141414` |
| hover | `#1c1c1c` |
| line / line-soft | `#222222` / `#161616` |
| fg / muted / faint | `#f2f2f2` / `#8a8a8a` / `#555555` |
| good / bad | `#3dd68c` / `#ff5c5c` |
| radius | 14px |
| font | Geist Variable stack |

## Layout parity with Exo

1. **Title bar** — Home left · module icon center · Settings + Close right  
2. **Home** — CPU / GPU / Memory / Disk meter cards · net · OS  
3. **Module (ExoOS)** — logo plate · title + status pill · Status list · Options · Preview + Apply (percent while busy)  
4. **Status dots** — green = OK/info, red = real miss only  

## Build UI

```powershell
cd src\ExoOS.App\ui
npm ci
npm run build   # → ../wwwroot
```

Then `dotnet build ExoOS.sln -c Release`.
