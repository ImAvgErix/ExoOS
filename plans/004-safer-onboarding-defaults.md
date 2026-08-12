# Safer setup defaults — SUPERSEDED

> **Status:** CANCELLED  
> **Priority:** —  
> **Commit:** superseded by product direction (Extreme = default)  
> **Rule:** n/a

## Why cancelled

Product intent is a **pure gaming OS**: strip every non-essential Windows surface by default
(registry, tasks, services, AppX, DISM, VBS, Defender, Edge). Users of Exo OS expect Maximum FPS.

Balanced / Keep Defender remain available as **explicit dial-backs** in setup — not the silent default.

See `onboarding-model.ts` `DEFAULT_ANSWERS`, `HostBridge.DefaultOptions()`, and `playbooks/exoos/playbook.yml` `defaultOptions`.
