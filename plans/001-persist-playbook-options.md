# Persist playbook options across app restarts

> **Status:** TODO  
> **Priority:** HIGH  
> **Category:** Bugs & correctness (beyond React Doctor scan)  
> **Commit:** `1b572b5`  
> **Effort:** M  
> **Blocked by:** none  
> **Rule:** n/a (host/UI contract bug the scanner cannot see)

## Problem

Setup choices are written into an **in-memory** `ConcurrentDictionary` via `setOptions`, and onboarding completion is a Registry DWORD. Options are **not** written to disk/Registry.

Evidence:

```20:27:src/ExoOS.App/Services/HostBridge.cs
    private readonly ConcurrentDictionary<string, bool> _options = new(StringComparer.OrdinalIgnoreCase);
    // ...
    public HostBridge()
    {
        foreach (var (k, v) in DefaultOptions())
            _options[k] = v;
    }
```

```145:147:src/ExoOS.App/Services/HostBridge.cs
            case "completeOnboarding":
                SetOnboardingComplete(true);
                return null;
```

```346:358:src/ExoOS.App/Services/HostBridge.cs
    // Defaults align with Balanced (safe ceiling). Extreme/Privacy set via onboarding answersToOptions.
    private static Dictionary<string, bool> DefaultOptions() => new(StringComparer.OrdinalIgnoreCase)
    {
        ["defenderStrip"] = false,
        // ...
        ["extremeMode"] = false,
```

UI path that depends on this:

```168:182:src/ExoOS.App/ui/src/Onboarding.tsx
  const finish = async () => {
    if (busy) return
    setBusy(true)
    try {
      await host.setOptions(answersToOptions(answers)).catch(() => {})
      await host.completeOnboarding(answers).catch(() => {})
      // localStorage only stores answers for the plan summary card
```

**Failure mode:** User finishes setup as Maximum FPS (extremeMode/dismStrip/disableVbs/…), closes the app, reopens. `OnboardingComplete=1` → plan screen. UI may still show Extreme from `localStorage` answers, but `Apply` runs `DefaultOptions()` (Balanced ceiling). Plan card and applied machine diverge.

## Target

1. Persist the full options map whenever `setOptions` succeeds (and again on `completeOnboarding` if answers are present).
2. On `HostBridge` construction (or first attach), load persisted options over defaults.
3. Prefer Registry under `HKCU\Software\ExoOS\Options` (or a single JSON value) so it survives process exit without requiring admin (same hive as onboarding flag).
4. Optionally persist the raw onboarding answers JSON so the plan summary does not depend only on WebView `localStorage`.

## Steps

1. In `HostBridge.cs`, add `LoadPersistedOptions()` / `SaveOptions()`:
   - Serialize `_options` as JSON (camelCase keys, bool values) to `HKCU\Software\ExoOS` value `OptionsJson`, or one DWORD/string per key under `…\Options`.
   - Call `SaveOptions()` at end of `setOptions` and after applying any options derived in `completeOnboarding`.
2. In the constructor, after `DefaultOptions()`, call `LoadPersistedOptions()` and merge (persisted wins for known keys).
3. Extend `completeOnboarding` to accept `params.answers` (already sent by UI) and, if present, run the same mapping the UI uses **or** rely on the prior `setOptions` call and only persist. Do not ignore a failed `setOptions` then mark complete (see plan 002).
4. In `App.tsx` / `host.ts`, optionally add `getOptions` on plan-screen mount and rehydrate summary from host when `localStorage` answers are missing (defense in depth).
5. Add a small C# or UI test: set extreme options → simulate new `HostBridge` → assert `extremeMode` still true.

## Scope boundary

- **Do not** change playbook YAML or ActionExecutor behavior.
- **Do not** click Apply on a real Nexus host during agent self-test.
- **Do not** move options to HKLM (needs admin write during setup finish).

## Conventions to match

- Registry helpers already used for `OnboardingComplete` / `Applied` in the same file.
- UI already calls `setOptions(answersToOptions(answers))` before `completeOnboarding`.

## Verification

**Mechanical**

- `dotnet build` ExoOS.App Release succeeds.
- Manual or unit: construct bridge, `setOptions` with `extremeMode: true`, construct second bridge, `getOptions` shows `extremeMode` true.

**Behavioral**

1. Fresh profile: finish setup as Maximum FPS + Remove Defender.
2. Kill ExoOS.exe completely.
3. Relaunch → plan summary still Extreme; `getOptions` (devtools / temporary log) shows `extremeMode` / `defenderStrip` true.
4. Do **not** press Apply on shared hardware; dry-run via `preview` if available is enough.
