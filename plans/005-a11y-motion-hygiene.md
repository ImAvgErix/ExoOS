# A11y + motion hygiene (Link name, will-change, transition-all)

> **Status:** TODO  
> **Priority:** MEDIUM  
> **Category:** Accessibility + Performance  
> **Commit:** `1b572b5`  
> **Effort:** S  
> **Blocked by:** none  
> **Rules:** `react-doctor/anchor-ambiguous-text`, `react-doctor/no-permanent-will-change`, `react-doctor/no-transition-all`

## Problem

React Doctor report (`/tmp` scan at audit time, score **62**):

1. **`anchor-ambiguous-text`** — `App.tsx` ~233: visible text `Link` lowercases to the banned word `link`. Product is Exo Link; screen readers hear a meaningless “link”.
2. **`no-permanent-will-change`** — `motion.tsx:78` static `style={{ willChange: 'transform, opacity' }}` on every stage panel.
3. **`no-transition-all`** — `Onboarding.tsx` back button uses `transition-all`.

Rejected / deferred from this plan:

- `postmessage-origin-risk` on `host.ts` — WebView2 `chrome.webview` host channel, not `window` cross-origin; treat as **Observation** (do not invent a fake `event.origin` check that breaks the bridge).
- `js-set-map-lookups` on 4–7 item MultiPick — **Reject** (premature).
- `no-array-index-as-key` in `Stagger` — wrappers around static children; **LOW / Observation**.
- `use-lazy-motion` — optional follow-up; measure bundle first (`motion` package + `LazyMotion`/`m` from `motion/react-m`).

## Target

### Links (`anchor-ambiguous-text` recipe)

Name the destination. Prefer visible text change so Label-in-Name stays honest:

```tsx
<a … aria-label="Exo Hub releases">Hub</a>
<a … aria-label="Exo Launcher releases">Launcher</a>
<a … aria-label="Exo Link releases">Link</a>
```

Because accessible name becomes “Exo Link releases”, it no longer equals bare `link`. Keep visible “Hub / Launcher / Link” for layout if desired, or show “Exo Link” visibly.

### will-change (`no-permanent-will-change` recipe)

Remove the permanent hint first:

```tsx
// delete: style={{ willChange: 'transform, opacity' }}
```

Rely on Motion’s transform/opacity animations. Only re-add a temporary hint if profiling shows jank.

### transition-all

```tsx
className="… transition-[color,background-color,transform] duration-200 …"
// or Tailwind: transition-colors + active:scale already — use transition-transform + transition-colors
```

Exact back button today:

```404:409:src/ExoOS.App/ui/src/Onboarding.tsx
          <button
            type="button"
            onClick={back}
            aria-label="Back"
            className="grid size-9 place-items-center rounded-full text-muted transition-all duration-200 hover:bg-hover hover:text-fg active:scale-95"
```

Replace `transition-all` with `transition-colors transition-transform duration-200`.

## Steps

1. Patch the three family anchors in `App.tsx`.
2. Remove `willChange` from `StageSwap`’s `motion.div`.
3. Replace `transition-all` on the back control (and grep for any other `transition-all` in `ui/src`).
4. Re-run React Doctor; confirm those three rules clear.

## Scope boundary

- **Do not** migrate to LazyMotion in this plan.
- **Do not** add origin checks to WebView2 `initHost`.
- **Do not** rewrite MultiPick to Sets.

## Verification

**Mechanical**

- `npx react-doctor@latest` — those three diagnostics gone; score > 62.
- `npm run build`

**Behavioral**

- Plan screen still shows Family row; links still call `host.openUrl`.
- Onboarding step transitions still slide; reduced-motion path unchanged.
- Back button hover/scale still feels snappy.
