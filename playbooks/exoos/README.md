# Exo OS playbook

Open gaming transform with depth-oriented ExoForge actions.

## Two modes (setup goal)

| | **Balanced** | **Extreme** (Maximum FPS) |
|--|--------------|---------------------------|
| Intent | Highest **safe ceiling** — snappy gaming desktop that does not break general use | **Barebones essentials-only** strip for gaming + browsers + MS Store + Discord/Steam-class apps |
| Windows overhead | Light quiet + shared baseline | Max strip: processes, services, DISM, VBS, prefetch, deep registry |
| `extremeMode` | false | true |
| `dismStrip` / `disableVbs` | false | true |
| Deep kills (SysMain, Spooler, Lanman, Themes, IFEO, bulk baseline) | **not applied** | applied |
| Shared baseline | WU pause ~35d, mouse 1:1, MMCSS Games High, SR=10 (MS-verified), HAGS, SwapEffect/VRR, network throttle off, light privacy | same + nuclear overlay |
| Runtimes | DirectX / VC++ / .NET always available | same |
| Store / install apps | kept / optional installs | kept / optional installs (identity keepers quarantined from remove lists) |

Privacy focus still forces mild `serviceStrip` + privacy hosts; it is **not** full Extreme barebones.

## Defaults (Balanced-safe)

| Option | Default |
|--------|---------|
| `extremeMode` / `dismStrip` / `disableVbs` | false |
| `serviceStrip` / `defenderStrip` / `stripEdge` | false by default; **Extreme always sets stripEdge** (Edge = forced bloat; install Brave/Chrome/etc. separately) |
| `removeAi` / `removeOneDrive` / `privacyHosts` | true |
| Gaming runtimes (DX / VC++ / .NET) | true |

## Audit

Full 3400+ action classification + tiering:

```text
python playbooks/exoos/scripts/exo-core/Scripts/audit_tier_gate.py
python playbooks/exoos/scripts/exo-core/Scripts/test_tier_gates.py
```

Reports: `AUDIT-REPORT.md`, `%ProgramData%\ExoOS\audit\`.

## Dry-run

```text
dotnet run --project src/ExoForge.Cli -c Release -- apply playbooks/exoos --dry-run
dotnet run --project src/ExoForge.Cli -c Release -- apply playbooks/exoos --dry-run --option extremeMode=true --option dismStrip=true --option serviceStrip=true
```

## App

```text
dotnet run --project src/ExoOS.App -c Release
```

Resume updates: **Settings → Windows Update → Resume**.
