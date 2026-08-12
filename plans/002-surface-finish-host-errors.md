# Surface finish-setup host failures (stop silent `.catch`)

> **Status:** TODO  
> **Priority:** HIGH  
> **Category:** Bugs & correctness (beyond React Doctor scan)  
> **Commit:** `1b572b5`  
> **Effort:** S  
> **Blocked by:** none (pairs with 001)  
> **Rule:** n/a

## Problem

Finish setup swallows host errors, then still calls `onDone(answers)`:

```168:185:src/ExoOS.App/ui/src/Onboarding.tsx
  const finish = async () => {
    if (busy) return
    setBusy(true)
    try {
      await host.setOptions(answersToOptions(answers)).catch(() => {})
      await host.completeOnboarding(answers).catch(() => {})
      try {
        window.localStorage.setItem(
          'exoos.onboarding.v1',
          JSON.stringify({ done: true, answers }),
        )
      } catch {
        /* */
      }
      onDone(answers)
    } finally {
      setBusy(false)
    }
  }
```

If the WebView bridge is unavailable, or `setOptions` fails, the user still lands on the plan screen and can press **Apply plan** with host defaults. Combined with in-memory options (plan 001), this silently applies the wrong plan.

Also: `host.apply` / `call()` in `src/lib/host.ts` has **no timeout** — a hung host leaves `busy` stuck until process kill. Add a bounded timeout while touching this path.

## Target

```tsx
const finish = async () => {
  if (busy) return
  setBusy(true)
  setError(null) // add useState for error string on Onboarding
  try {
    await host.setOptions(answersToOptions(answers))
    await host.completeOnboarding(answers)
    try {
      window.localStorage.setItem(
        'exoos.onboarding.v1',
        JSON.stringify({ done: true, answers }),
      )
    } catch {
      /* non-fatal: host already has complete flag */
    }
    onDone(answers)
  } catch (e) {
    setError(e instanceof Error ? e.message : 'Could not save setup')
  } finally {
    setBusy(false)
  }
}
```

Show `error` above the Finish CTA (same visual language as `App.tsx` error card: `card … text-bad`).

In `src/lib/host.ts` `call()`:

```ts
const HOST_TIMEOUT_MS = 30_000
// after pending.set(...):
const timer = setTimeout(() => {
  if (!pending.has(id)) return
  pending.delete(id)
  reject(new Error('Host did not respond'))
}, HOST_TIMEOUT_MS)
// clearTimeout(timer) on resolve/reject
```

Use a longer timeout only for `apply`/`preview` if needed (e.g. 10 minutes) via optional `timeoutMs` on `call`.

## Steps

1. Remove both `.catch(() => {})` on finish; let failures throw.
2. Add `error` state + inline error UI on the onboarding footer (ready step / all steps).
3. Do not call `onDone` unless both host calls succeed.
4. Add RPC timeout in `call()`; clear on settle; longer timeout for `apply`/`preview`.
5. Keep localStorage write best-effort after successful host complete.

## Scope boundary

- **Do not** change `answersToOptions` semantics.
- **Do not** auto-retry Apply.
- **Do not** suppress React Doctor rules.

## Conventions to match

- Error copy style in `App.tsx` (`Run ExoOS as Administrator…` / single-line card).
- `busy` disables the CTA already.

## Verification

**Mechanical**

- `npm run build` in `src/ExoOS.App/ui`.
- `npx react-doctor@latest --scope changed` score does not drop.

**Behavioral**

1. With host bridge unavailable (browser `vite` alone): Finish setup shows an error, stays on ready step, does not advance to plan.
2. With host OK: Finish still advances; plan screen loads.
3. Optional: mock a never-resolving `postMessage` and confirm timeout message within ~30s for `setOptions`.
