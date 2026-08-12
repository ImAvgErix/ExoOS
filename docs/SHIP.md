# Ship checklist (ExoOS)

Product version: root `VERSION` (currently **1.8.1**). Playbook version: `playbooks/exoos/playbook.yml`.

## Before a public release

1. **Versions match**
   - [ ] `VERSION`
   - [ ] `Directory.Build.props` / app csproj
   - [ ] `src/ExoOS.App/ui/package.json`
   - [ ] `CHANGELOG.md` top section
   - [ ] Playbook `playbook.yml` version noted in changelog if depth changed

2. **Quality**
   - [ ] `python playbooks/exoos/scripts/exo-core/Scripts/test_tier_gates.py` → ALL CHECKS PASSED
   - [ ] CLI dry-run Balanced: `ExoForge.Cli apply playbooks/exoos --dry-run` → `failed=0`
   - [ ] CLI dry-run Extreme: `--option extremeMode=true --option stripEdge=true --option dismStrip=true` → `failed=0`
   - [ ] UI build: `cd src/ExoOS.App/ui && npm run build`

3. **Package**
   - [ ] `.\scripts\Publish-ExoOS.ps1`
   - [ ] Stage has `ExoOS.exe`, `wwwroot/index.html`, `playbooks/exoos/playbook.yml`, `VERSION`, `LICENSE`, `README.md`
   - [ ] Zip + `.sha256` under `publish/`

4. **GitHub**
   - [ ] Tag `v1.8.1` (or current VERSION)
   - [ ] Release notes from CHANGELOG
   - [ ] Attach zip + sha256

5. **Smoke (manual)**
   - [ ] Cold start → setup → plan screen shows version
   - [ ] Non-admin: blocked CTA
   - [ ] Admin dry path: Apply shows progress, reboot note
   - [ ] Browsers list: Brave / Helium / Zen / LibreWolf only

## Do not ship if

- Playbook fails `validate`
- UI `wwwroot` is stale (forgot `npm run build`)
- Extreme actions apply on Balanced dry-run without option gates
