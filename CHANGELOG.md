# Changelog

## 1.8.0

Extreme-by-default gaming OS. Product catalog only — no third-party research dumps.

### App
- Setup then a single plan screen (no Home / Settings / dashboard)
- Brand line: **Built quiet. Tuned sharp.**
- Option defaults load from `playbook.yml`; setup answers persist
- Plan screen shows app/playbook version and machine specs
- CSS step transitions (no Motion runtime); error boundary around the shell

### Playbook
- 1,175 unique actions in 13 themed files
- Extreme (`extremeMode` / `dismStrip` / `disableVbs` / `defenderStrip` / `stripEdge` / `serviceStrip`) on by default
- Balanced is an explicit dial-back
- Shared DNS and .NET installers; apply path has no `cdn.getnexus.cc`

### Engine
- Extreme unlocks nuclear-risk actions on CLI the same way the app does
- `ExoForge.Cli audit` compares desired state to the live PC

## 1.3.3

- Remove Preview from the app UI (apply only, with EXOOS confirm)
- Always install DirectX, VC++, .NET 8, and .NET 10 (no choice)
- Drop runtimes question from onboarding

## 1.3.2

- Onboarding: one progress system (step dots only), no Skip setup, title bar matches main shell

## 1.3.1

- Apple-like first-run onboarding (questions for goal, Defender, cleanup, services, runtimes)
- Answers map to playbook options
- Forced linear setup, large choice cards

## 1.3.0

- Deep playbook coverage (registry, services, AppX)
- Dry-run: `failed=0`
- Version strings are plain numbers only

## 1.2.0

- Exo design system via WebView2 + React (Geist, AMOLED tokens)
- Plan/apply with percent progress

## 1.1.1

- Single-screen WPF pass (superseded by later shell)
- Apply requires typing `EXOOS`

## 1.1.0

- Exo AMOLED tokens, monorepo docs, CI dry-run, publish scripts
- Engine depth playbook with SYSTEM / CAB / whenOption support
- Dry-run by default; live apply requires `EXOOS` confirm

## 1.0.1

**Distinct Exo OS brand mark.**

- New app icon and logo: glass layered-windows transform mark
- Wired ApplicationIcon; welcome UI uses the logo asset
- README brand mark

## 1.0.0

- Initial ExoOS monorepo: App, Engine, Schema, CLI, open playbook
