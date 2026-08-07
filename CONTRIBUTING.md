# Contributing to ExoOS

Thanks for helping. Keep changes readable, reversible where possible, and honest about risk.

## Principles

1. **Dry-run by default** — never ship a path that writes without an explicit live flag or confirm string.
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

- Core actions live under `playbooks/exoos/actions/`
- Generated depth packs under `playbooks/exoos/actions/generated/`
- Gate optional work with `whenOption` / `defaultOptions` in `playbook.yml`
- After edits: `validate` then dry-run; report `failed` counts in the PR

## Making UI changes

- Tokens and control styles: `src/ExoOS.App/App.xaml`
- Single screen: `src/ExoOS.App/MainWindow.xaml` + `.xaml.cs`
- Match the Exo AMOLED palette (true black, white ink, muted secondary)
- Keep it minimal — no multi-step wizards

## PR checklist

- [ ] Builds `ExoOS.sln` Release
- [ ] CLI `validate playbooks/exoos` passes
- [ ] Dry-run completes with `failed=0` (or document known failures)
- [ ] No live apply in CI
- [ ] No secrets, keys, or credentials committed

## License

By contributing you agree contributions are MIT-licensed under the same terms as the project.
