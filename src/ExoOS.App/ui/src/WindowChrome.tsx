/**
 * In-web close only — native strip handles real drag (WPF).
 * host.drag remains a fallback for empty areas.
 */
import { host } from './lib/host'

export function WindowChrome() {
  // Native title strip already has Close; keep a secondary close only if needed.
  // Full-bleed was broken for drag, so native strip is primary — hide duplicate close.
  return (
    <div
      className="pointer-events-none absolute inset-0 z-0"
      aria-hidden
    />
  )
}

/** Optional: call from empty layout regions to request drag via HT_CAPTION. */
export function requestDrag() {
  void host.drag().catch(() => {})
}
