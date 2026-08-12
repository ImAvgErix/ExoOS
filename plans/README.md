# Exo OS UI improvement plans

React Doctor baseline (commit `1b572b5`): **62 / 100**, 13 warnings in `src/ExoOS.App/ui`.

This folder is the output of an **improve-react** audit: read-only on app source; executors implement one plan at a time.

## Recommended order

| Order | Plan | Priority | Depends on |
| --- | --- | --- | --- |
| 1 | [001-persist-playbook-options.md](./001-persist-playbook-options.md) | HIGH | — |
| 2 | [002-surface-finish-host-errors.md](./002-surface-finish-host-errors.md) | HIGH | pairs with 001 |
| 3 | [004-safer-onboarding-defaults.md](./004-safer-onboarding-defaults.md) | HIGH | nicer after 003 if exporting `DEFAULT_ANSWERS` |
| 4 | [003-split-onboarding-model.md](./003-split-onboarding-model.md) | MEDIUM | — |
| 5 | [005-a11y-motion-hygiene.md](./005-a11y-motion-hygiene.md) | MEDIUM | — |

## Status

| Plan | Status |
| --- | --- |
| 001 persist options | TODO |
| 002 finish errors | TODO |
| 003 split model | TODO |
| 004 safer defaults | TODO |
| 005 a11y/motion | TODO |

## Rejected / observation (do not “fix” blindly)

| Finding | Verdict |
| --- | --- |
| `postmessage-origin-risk` (`host.ts`) | Observation — WebView2 host bridge, not window cross-origin |
| `js-set-map-lookups` (MultiPick) | Reject — lists of size ≤7 |
| `no-array-index-as-key` (`Stagger`) | Observation — animation wrappers, not identity-sensitive data |
| `use-lazy-motion` | Defer — measure bundle before LazyMotion migration |
| `no-giant-component` | Partially addressed by 003; further step splits optional |

## Missed opportunities (not planned yet)

1. **ErrorBoundary** around `App` / onboarding — host or render throw currently blanks the WebView.
2. **Rehydrate plan summary from host** when Registry says complete but `localStorage` was cleared.
3. **Confirm gate** on Extreme / Defender strip before Finish (product).
4. **Dead `WindowChrome`** — empty stub; either restore close/drag or delete call sites.
5. **RPC method allowlist hardening** on host `openUrl` (already https-only; consider domain allowlist for family links).
