# Exo OS playbook

Barebones **gaming OS** transform. Curated ExoForge actions — registry, tasks, services,
AppX, DISM, power, network, gaming polish. Product catalog only (no Atlas/Revi/Winhance dumps).

## Product default = Extreme (Maximum FPS)

Strip every non-essential Windows surface while keeping the gaming path alive (MS Store,
browsers you choose, Discord/Steam-class apps). Balanced exists only as an explicit dial-back.

| | **Extreme** (default) | **Balanced** (dial-back) |
|--|----------------------|---------------------------|
| Intent | Pure gaming OS — strip non-essentials hard | Snappy gaming desktop that keeps more of Windows |
| Windows overhead | Max strip: processes, services, DISM, VBS, prefetch, registry, tasks | Light quiet + shared baseline |
| `extremeMode` | **true** | false |
| `dismStrip` / `disableVbs` / `defenderStrip` / `stripEdge` / `serviceStrip` | **true** | false (cleanup can still set stripEdge) |
| Deep kills (SysMain, Spooler, Lanman, Themes, IFEO) | **applied** | not applied |
| Shared baseline | WU pause ~35d, mouse 1:1, MMCSS Games High, SR=10, HAGS, SwapEffect/VRR, network throttle off, privacy | same without nuclear overlay |
| Runtimes | DirectX / VC++ / .NET always | same |
| Store / install apps | kept / optional installs | kept / optional installs |

Privacy focus still forces mild `serviceStrip` + privacy hosts; it is **not** full Extreme barebones.

## Defaults

| Option | Default |
|--------|---------|
| `extremeMode` / `dismStrip` / `disableVbs` | **true** |
| `serviceStrip` / `defenderStrip` / `stripEdge` | **true** (Edge = forced bloat; install Brave/Helium/Zen/LibreWolf separately) |
| `removeAi` / `removeOneDrive` / `privacyHosts` | true |
| Gaming runtimes (DX / VC++ / .NET) | true |

## Tests

```text
python playbooks/exoos/scripts/exo-core/Scripts/test_tier_gates.py
```

Hand YAML lives under `actions/` (one file per layer) and is listed in `playbook.yml` `actionFiles`.

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
