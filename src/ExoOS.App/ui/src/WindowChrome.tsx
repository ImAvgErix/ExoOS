/**
 * In-web close only — native strip handles real drag (WPF).
 */
export function WindowChrome() {
  // Native title strip already has Close; keep stacking space without a duplicate control.
  return <div className="pointer-events-none absolute inset-0 z-0" aria-hidden />
}
