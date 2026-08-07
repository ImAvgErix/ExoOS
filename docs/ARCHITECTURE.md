# ExoForge — better than AME Beta, playbook built-in

## Product thesis

**AME Wizard** = closed GUI + open-ish backend (TrustedUninstaller) + password-zipped `.apbx` playbooks.  
**ExoForge** = open engine + first-class playbooks + deeper Windows control + **detect / apply / rollback** (what Exo already does per-module, generalized).

You are not shipping “another ISO.” You ship:

1. **Forge Host** — GUI (later) that runs playbooks, shows tiers, AC risk, diffs  
2. **Forge Engine** — applies actions with snapshot + dry-run  
3. **Playbooks** — versioned OS recipes (ExoOS Soft / Hard / Nuclear)  
4. **Optional ISO bake** — only after playbook is stable

## Why beat AME

| AME / TrustedUninstaller | ExoForge target |
|---|---|
| Apply-forward, weak first-class rollback | **Snapshot before every stage**, one-click rollback |
| YAML actions, limited discoverability | **Live detect** (“already applied?”) like Exo modules |
| `.apbx` + password `malte` | **Open folder or `.exoforge` zip**, no secret password |
| Stages are playbook author-defined | **Risk tiers**: base / gaming / privacy / nuclear |
| No anti-cheat awareness | **AC profile**: mark actions `risk: ac-sensitive` |
| GUI gated / verified playbook politics | Your brand; ship Exo + Nexus pipeline |
| One-shot transform | **Idempotent** actions + re-apply safe |

## Architecture

```
┌─────────────────────────────────────────────────────────┐
│  ExoForge.Host (WinUI / WPF)     [phase 2]              │
│  - pick playbook, tiers, dry-run, apply, rollback UI    │
└───────────────────────┬─────────────────────────────────┘
                        │
┌───────────────────────▼─────────────────────────────────┐
│  ExoForge.Cli                                           │
│  forge apply|detect|rollback|validate <playbook>        │
└───────────────────────┬─────────────────────────────────┘
                        │
┌───────────────────────▼─────────────────────────────────┐
│  ExoForge.Engine                                        │
│  PlaybookLoader → Planner → Executor → SnapshotStore    │
│  Action handlers: reg, service, task, appx, feature,    │
│  power, path, process, script, package, capability…     │
└───────────────────────┬─────────────────────────────────┘
                        │
┌───────────────────────▼─────────────────────────────────┐
│  Playbook (folder or .exoforge)                         │
│  playbook.yml + actions/*.yml + scripts/* + assets/*    │
└─────────────────────────────────────────────────────────┘
```

## Playbook format (v0)

```
playbooks/exoos-soft/
  playbook.yml          # manifest, tiers, options
  actions/
    10-services.yml
    20-apps.yml
    30-gaming.yml
  scripts/              # optional ps1/cmd used by !script
  assets/
```

Open by design. Package as zip renamed `.exoforge` if you want one file — **no password required**.

## Action model (beyond AME)

Core (AME-parity):

- `registry.set` / `registry.delete`
- `service.set` (start type + stop/start)
- `task.enable` / `task.disable`
- `appx.remove` / `appx.clearCache`
- `capability.remove` / `feature.disable` (optional features)
- `run` (exe/script elevated)

ExoForge extras:

- `detect` blocks — assert state before apply  
- `snapshot` scope — what to save for rollback  
- `risk: safe | gaming | privacy | nuclear | ac-sensitive`  
- `requiresAdmin: true`  
- `reboot: suggest | require`  
- `when:` conditions (build range, edition, GPU vendor)  
- `power.plan` (import/activate .pow or known GUID)  
- `hosts` / `firewall` (gated nuclear)  
- `package.winget` install/uninstall  
- `iso.note` — documentation only for bake step  

## Safety model (anti-cheat)

Default playbook **ExoOS Soft**:

- Keep: desktop shell, audio, GPU stack, Defender (optional toggle), Store optional  
- Strip: consumer apps, tips, Game Bar overlay, obvious junk services  
- Never default-nuke: random 200-service lists, Secure Boot, TPM stack, whole CI  

**Nuclear tier** is opt-in and labeled “may break Vanguard/EAC.”

## Relation to Exo app

| Exo today | ExoForge |
|---|---|
| Per-product modules (Discord, NVIDIA, system) | Whole-machine OS recipe |
| Detect/apply per module | Detect/apply per playbook stage |
| Great as **post-playbook** runtime | Great as **base OS transform** |

Ideal flow:

```
Clean Windows → ExoForge playbook → install Exo → Exo modules for games/browsers
```

## Phases

1. **Now** — Engine + CLI + sample Soft playbook + validate/detect/apply dry-run  
2. **Next** — Real handlers (reg/service/task/appx), snapshot/rollback store  
3. **Host UI** — AME-class UX, tier toggles, live log  
4. **Nexus bridge** — import/export or shared action IR  
5. **ISO bake** (optional) — unattend + first-boot runs Forge  

## Non-goals (v1)

- Replacing the Windows kernel  
- Closed playbook marketplace politics  
- Shipping unsigned “mystery ISO” as the only path  
