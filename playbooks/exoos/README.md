# Exo OS playbook

Ultimate barebones **gaming OS** transform. Depth-oriented ExoForge actions across registry,
tasks, services, AppX, DISM, power, network, and gaming polish — audited and tiered.

## Product default = Extreme (Maximum FPS)

Strip every non-essential Windows surface while keeping the gaming path alive (MS Store,
browsers you choose, Discord/Steam-class apps). Compete with **Nexus / FSOS-X / KernelOS / AME**
on FPS, RAM, startup, process count, input/network/audio latency, privacy, and clutter.
Balanced exists only as an explicit dial-back.

| | **Extreme** (default) | **Balanced** (dial-back) |
|--|----------------------|---------------------------|
| Intent | Pure gaming OS — strip non-essentials hard | Snappy gaming desktop that keeps more of Windows |
| Windows overhead | Max strip: processes, services, DISM, VBS, prefetch, deep registry, tasks | Light quiet + shared baseline |
| `extremeMode` | **true** | false |
| `dismStrip` / `disableVbs` / `defenderStrip` / `stripEdge` / `serviceStrip` | **true** | false (cleanup can still set stripEdge) |
| Deep kills (SysMain, Spooler, Lanman, Themes, IFEO, bulk baseline) | **applied** | not applied |
| Shared baseline | WU pause ~35d, mouse 1:1, MMCSS Games High, SR=10, HAGS, SwapEffect/VRR, network throttle off, privacy | same without nuclear overlay |
| Runtimes | DirectX / VC++ / .NET always | same |
| Store / install apps | kept / optional installs | kept / optional installs |

Privacy focus still forces mild `serviceStrip` + privacy hosts; it is **not** full Extreme barebones.

## Defaults (Extreme / gaming strip)

| Option | Default |
|--------|---------|
| `extremeMode` / `dismStrip` / `disableVbs` | **true** |
| `serviceStrip` / `defenderStrip` / `stripEdge` | **true** (Edge = forced bloat; install Brave/Helium/Zen/LibreWolf separately) |
| `removeAi` / `removeOneDrive` / `privacyHosts` | true |
| Gaming runtimes (DX / VC++ / .NET) | true |

## Audit

Full 3400+ action classification + tiering:

```text
python playbooks/exoos/scripts/exo-core/Scripts/audit_tier_gate.py
python playbooks/exoos/scripts/exo-core/Scripts/test_tier_gates.py
```

Reports: `AUDIT-REPORT.md`, `%ProgramData%\ExoOS\audit\`.

Hand YAML under `actions/*.yml` is only `00-identity.yml` and `99-finalize.yml`. Everything else lives in `actions/generated/*` and is listed in `playbook.yml` `actionFiles`.

## Dry-run

```text
dotnet run --project src/ExoForge.Cli -c Release -- apply playbooks/exoos --dry-run
# Dial back to Balanced:
dotnet run --project src/ExoForge.Cli -c Release -- apply playbooks/exoos --dry-run --option extremeMode=false --option dismStrip=false --option disableVbs=false --option defenderStrip=false --option stripEdge=false --option serviceStrip=false
```

## App

```text
dotnet run --project src/ExoOS.App -c Release
```

Resume updates: **Settings → Windows Update → Resume**.
