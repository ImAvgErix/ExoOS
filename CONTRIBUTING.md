# Contributing to ExoOS

Thanks for helping. Keep changes readable, reversible where possible, and honest about risk.

## Principles

1. **CLI dry-run by default** — `ExoForge.Cli apply` writes nothing unless `--live`. The app **Apply plan** button is live.
2. **No folklore** — every registry/service/AppX change should be explainable (what it does, why gaming benefits).
3. **Exo branding only** — product UI and docs do not name-drop third-party playbook sources.
4. **Modern desktop** — do not reintroduce always-on shell replacements or always-on Windhawk by default.

## Dev setup

- Windows 11 x64
- .NET 10 SDK
- PowerShell 7 recommended

```powershell
dotnet build ExoOS.sln -c Release
dotnet run --project src\ExoForge.Cli -c Release -- apply playbooks\exoos --dry-run
```

## Making playbook changes

- Actions live under `playbooks/exoos/actions/` (one file per layer, listed in `playbook.yml`)
- Gate optional work with `whenOption` / `defaultOptions` in `playbook.yml`
- After edits: `python playbooks/exoos/scripts/exo-core/Scripts/test_tier_gates.py` then CLI `validate` + dry-run

## Making UI changes

- React UI: `src/ExoOS.App/ui` → `npm run build` writes `wwwroot`
- Native drag strip + close: `src/ExoOS.App/MainWindow.xaml`
- Setup then plan screen — no Home / Settings / dashboard
- Brand line: **Built quiet. Tuned sharp.**

## PR checklist

- [ ] Builds `ExoOS.sln` Release
- [ ] CLI `validate playbooks/exoos` passes
- [ ] Dry-run completes with `failed=0` (or document known failures)
- [ ] No live apply in CI
- [ ] No secrets, keys, or credentials committed

## License

By contributing you agree contributions are MIT-licensed under the same terms as the project.
