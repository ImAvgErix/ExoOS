# Split onboarding catalog out of the component module

> **Status:** TODO  
> **Priority:** MEDIUM  
> **Category:** Maintainability  
> **Commit:** `1b572b5`  
> **Effort:** M  
> **Blocked by:** none  
> **Rule:** `react-doctor/only-export-components` (+ reduces `no-giant-component`)

## Problem

React Doctor (score 62) flags `Onboarding.tsx` for exporting non-components alongside the component, which breaks Vite Fast Refresh:

- `answersToOptions` at line 79
- re-exports `BROWSER_ITEMS`, `EXTRA_ITEMS`, `APP_ITEMS`, `labelList` at line 686

Canonical fix: move utilities into a sibling non-component file and re-import.

`App.tsx` imports those helpers from `./Onboarding`:

```6:14:src/ExoOS.App/ui/src/App.tsx
import {
  Onboarding,
  type OnboardingAnswers,
  BROWSER_ITEMS,
  EXTRA_ITEMS,
  APP_ITEMS,
  labelList,
} from './Onboarding'
```

`answersToOptions.test.mjs` also loads `Onboarding.tsx` via esbuild solely for `answersToOptions`.

## Target

Create `src/ExoOS.App/ui/src/onboarding-model.ts` (no JSX) containing:

- `OnboardingAnswers` type
- `BROWSER_ITEMS`, `EXTRA_ITEMS`, `APP_ITEMS`, `DEFAULT_EXTRAS`
- `labelList`, `toggleId`, `answersToOptions`
- (optional) `STEPS` / `StepId` if useful

`Onboarding.tsx` exports **only** the `Onboarding` component (and allowed constants if any).

`App.tsx` imports catalog helpers from `./onboarding-model` and `Onboarding` from `./Onboarding`.

Update `answersToOptions.test.mjs` to transform/import `onboarding-model.ts` instead of the giant TSX (simpler stubs — no react/lucide/motion).

Also fix `WindowChrome.tsx`: drop unused `requestDrag` export (`deslop/unused-export` + `only-export-components`) or move drag helper next to `host.ts` if still wanted. Prefer **delete** — nothing imports it; `WindowChrome` is currently an empty `aria-hidden` stub.

## Exact recipe (from react.doctor)

Split the module so the component file exports only components: move utility functions/objects into a sibling non-component file and re-import. Do not disable the rule.

## Steps

1. Add `src/onboarding-model.ts` with types + catalogs + `answersToOptions` copied verbatim from `Onboarding.tsx` (preserve comments about Balanced/Extreme gates — they document product intent).
2. Trim `Onboarding.tsx` to import from `./onboarding-model`; remove bottom `export { BROWSER_ITEMS, … }`.
3. Update `App.tsx` imports.
4. Point `answersToOptions.test.mjs` at `onboarding-model.ts` (plain TS — drop most stubs).
5. Remove `requestDrag` from `WindowChrome.tsx` (or the whole no-op file if `App`/`Onboarding` can drop `<WindowChrome />` — only if native strip fully covers chrome; keep the empty drag layer if it is intentional for stacking).
6. Run the answers test + `npm run build`.

## Scope boundary

- **Do not** change `answersToOptions` boolean mapping.
- **Do not** redesign onboarding steps.
- **Do not** split every step into files in this plan (optional follow-up for `no-giant-component`).

## Conventions to match

- Existing `src/lib/*.ts` for non-UI modules.
- Test: `node` + esbuild strip pattern already in `answersToOptions.test.mjs`.

## Verification

**Mechanical**

- `node src/answersToOptions.test.mjs` (from `ui/` with esbuild available) — all OK asserts.
- `npm run build`
- `npx react-doctor@latest --json` — `only-export-components` gone for Onboarding/WindowChrome; score improves.

**Behavioral**

- Onboarding still advances through steps; Finish still calls `answersToOptions` → `setOptions` with same keys (spot-check Extreme vs Balanced via test file).
