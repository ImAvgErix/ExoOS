# ExoForge engine depth

Open playbook executor used by ExoOS.

## Action types

`registry.set` / `registry.delete` · `service.set` · `task.disable` / `task.enable` · `taskkill` · `appx.remove` · `run` (admin or `runAs: system`) · `package.add` / `package.remove` · `capability.remove` · `feature.disable` / `feature.enable` · `power.import` / `power.activate` · `file.delete` / `file.write` · `note`

## Feature flags

`playbook.yml` → `defaultOptions`  
Actions: `whenOption: key`  
CLI: `--option key=value`

## Design notes

- Dry-run is the default safety path.
- SYSTEM elevation uses a one-shot scheduled task (deep path for locked components).
- CAB Defender removal uses the shipping PowerShell kit under `playbooks/exoos/scripts`.
