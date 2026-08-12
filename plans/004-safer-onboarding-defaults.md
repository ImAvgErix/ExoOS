# Safer setup defaults (Balanced, keep Defender)

> **Status:** TODO  
> **Priority:** HIGH  
> **Category:** Bugs / product safety (beyond scan)  
> **Commit:** `1b572b5`  
> **Effort:** S  
> **Blocked by:** none  
> **Rule:** n/a

## Problem

Onboarding **initial state** pre-selects the most destructive path:

```149:157:src/ExoOS.App/ui/src/Onboarding.tsx
  const [answers, setAnswers] = useState<OnboardingAnswers>({
    goal: 'fps',
    defender: 'strip',
    cleanup: 'yes',
    services: 'quiet',
    browsers: [],
    extras: [...DEFAULT_EXTRAS],
    apps: [],
  })
```

Host `DefaultOptions()` comment says defaults align with **Balanced (safe ceiling)** and `defenderStrip: false` — UI defaults disagree. Users who mash Continue without reading (or Enter via the keydown handler) finish Extreme + Remove Defender.

The Maximum FPS choice already carries `warn: true` copy about printers / anti-cheat; Defender strip says “Hard to reverse.” Defaults should match the safer host ceiling and force an explicit opt-in to nuclear options.

## Target

```ts
const [answers, setAnswers] = useState<OnboardingAnswers>({
  goal: 'balanced',
  defender: 'keep',
  cleanup: 'yes',   // keep current mild cleanup, or 'no' if you want stocker — prefer 'yes' only if product still wants AI/OneDrive strip on Balanced
  services: 'quiet',
  browsers: [],
  extras: [...DEFAULT_EXTRAS],
  apps: [],
})
```

Align with `HostBridge.DefaultOptions()`:

- `extremeMode` / `dismStrip` / `disableVbs` false
- `defenderStrip` false
- cleanup/privacy hosts can stay true if host defaults keep `removeAi`/`privacyHosts` true

Update any copy that assumes Extreme is the “home” selection (progress labels, tests).

## Steps

1. Change initial `useState` defaults as above.
2. Extend `answersToOptions.test.mjs` with an assert that the **documented product default answers** object maps to non-extreme / defender keep (export a `DEFAULT_ANSWERS` constant from `onboarding-model.ts` if plan 003 landed first).
3. Confirm goal step still lists Maximum FPS with `warn: true` — user must click it to opt in.
4. Optional UX: require an explicit confirm checkbox on ready step when `goal === 'fps'` or `defender === 'strip'` before Finish enables (nice-to-have; keep out of minimal fix if scope creeps).

## Scope boundary

- **Do not** remove Extreme mode from the product.
- **Do not** change YAML nuclear gates.
- **Do not** change brand line / motion.

## Conventions to match

- Host comment: “Defaults align with Balanced (safe ceiling).”
- README honesty about Extreme risk.

## Verification

**Mechanical**

- Test: default answers → `extremeMode === false`, `defenderStrip === false`.
- `npm run build`

**Behavioral**

1. Launch setup: goal step shows **Balanced** selected; Defender shows **Keep**.
2. Enter/Continue through without changing choices → plan summary Focus = Balanced, Defender = Keep Defender.
3. Selecting Maximum FPS still sets extreme flags via `answersToOptions`.
