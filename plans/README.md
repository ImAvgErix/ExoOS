# Exo OS UI improvement plans

React Doctor: **62 → 64** after executing plans on branch `cursor/react-audit-plans-81e9` (remaining 5 are deferred observations / cold-path nits).

## Recommended order

| Order | Plan | Priority | Depends on |
| --- | --- | --- | --- |
| 1 | [001-persist-playbook-options.md](./001-persist-playbook-options.md) | HIGH | — |
| 2 | [002-surface-finish-host-errors.md](./002-surface-finish-host-errors.md) | HIGH | pairs with 001 |
| 3 | [004-safer-onboarding-defaults.md](./004-safer-onboarding-defaults.md) | — | **CANCELLED** — Extreme is product default |
| 4 | [003-split-onboarding-model.md](./003-split-onboarding-model.md) | MEDIUM | — |
| 5 | [005-a11y-motion-hygiene.md](./005-a11y-motion-hygiene.md) | MEDIUM | — |

## Status

| Plan | Status |
| --- | --- |
| 001 persist options | DONE |
| 002 finish errors | DONE |
| 003 split model | DONE |
| 004 safer defaults | CANCELLED (Extreme = product default) |
| 005 a11y/motion (+ tweaks.css) | DONE |

## Also shipped with 005

- Fixed missing `@keyframes exo-item-in` (plan rows / stagger were no-ops)
- Added `.exo-hero-glow`, `.exo-dot`, `.exo-apply-fill`, `.exo-title-show`
- Removed unused float/ring keyframes; named transitions only
- Softened ambient gradients

## Rejected / observation (left intentionally)

| Finding | Verdict |
| --- | --- |
| `postmessage-origin-risk` (`host.ts`) | Observation — WebView2 host bridge |
| `js-set-map-lookups` (MultiPick) | Reject — lists of size ≤7 |
| `no-array-index-as-key` (`Stagger`) | Observation — animation wrappers |
| `use-lazy-motion` | Defer — measure bundle first |
| `no-giant-component` (Onboarding) | Deferred — model extract done; further splits optional |
