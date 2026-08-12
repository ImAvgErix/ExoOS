/**
 * Onboarding answers → playbook option map (no React).
 * Kept separate so Fast Refresh can preserve Onboarding component state.
 */

export type OnboardingAnswers = {
  goal: 'fps' | 'balanced' | 'privacy'
  defender: 'strip' | 'keep'
  cleanup: 'yes' | 'no'
  services: 'quiet' | 'leave'
  browsers: string[]
  extras: string[]
  apps: string[]
}

export type MultiItem = { id: string; title: string; detail: string }

// Good browsers only — no Chrome/stock Edge bait. Firefox stock is meh; use Zen/LibreWolf.
export const BROWSER_ITEMS: MultiItem[] = [
  { id: 'brave', title: 'Brave', detail: 'Ad-block Chromium, low telemetry' },
  { id: 'helium', title: 'Helium', detail: 'Private, no bloat' },
  { id: 'zen', title: 'Zen', detail: 'Calm, vertical tabs, Firefox-based' },
  { id: 'librewolf', title: 'LibreWolf', detail: 'Hardened Firefox, privacy-first' },
]

export const EXTRA_ITEMS: MultiItem[] = [
  { id: '7zip', title: '7-Zip', detail: 'Archives' },
  { id: 'snipping', title: 'Snipping Tool', detail: 'Screenshots' },
  { id: 'photos', title: 'Photos', detail: 'Gallery' },
  { id: 'notepad', title: 'Notepad', detail: 'Notes' },
  { id: 'terminal', title: 'Terminal Preview', detail: 'Shell' },
  { id: 'pwsh', title: 'PowerShell Preview', detail: 'Latest PS' },
]

export const APP_ITEMS: MultiItem[] = [
  { id: 'steam', title: 'Steam', detail: 'Games' },
  { id: 'discord', title: 'Discord', detail: 'Voice' },
  { id: 'epic', title: 'Epic Games', detail: 'Launcher' },
  { id: 'riot', title: 'Riot Client', detail: 'Valorant…' },
  { id: 'revo', title: 'Revo', detail: 'Uninstall' },
  { id: 'obs', title: 'OBS Studio', detail: 'Capture' },
  { id: 'spotify', title: 'Spotify', detail: 'Music' },
]

export const DEFAULT_EXTRAS = ['7zip', 'snipping', 'photos', 'notepad', 'terminal']

/** Product-safe ceiling — matches HostBridge.DefaultOptions() philosophy. */
export const DEFAULT_ANSWERS: OnboardingAnswers = {
  goal: 'balanced',
  defender: 'keep',
  cleanup: 'yes',
  services: 'quiet',
  browsers: [],
  extras: [...DEFAULT_EXTRAS],
  apps: [],
}

export function toggleId(list: string[], id: string) {
  return list.includes(id) ? list.filter((x) => x !== id) : [...list, id]
}

export function labelList(ids: string[], catalog: MultiItem[], empty: string) {
  if (ids.length === 0) return empty
  const map = new Map(catalog.map((c) => [c.id, c.title]))
  return ids.map((id) => map.get(id) ?? id).join(' · ')
}

export function answersToOptions(a: OnboardingAnswers): Record<string, boolean> {
  /**
   * Balanced (goal=balanced): safe ceiling — shared baseline + optional quiet services.
   *   Does NOT set extremeMode/dismStrip/disableVbs. Deep barebones kills are gated extremeMode.
   * Privacy: quiet services + privacy hosts + cleanup; still not full barebones strip.
   * Extreme / Maximum FPS (goal=fps): barebones gaming strip — store/browsers/Discord/apps stay;
   *   max privacy/overhead/RAM/latency strip (extremeMode + DISM + VBS + deep services).
   * Defender always follows the Defender step (strip|keep).
   */
  const extreme = a.goal === 'fps'
  const privacy = a.goal === 'privacy'
  const b = new Set(a.browsers)
  const e = new Set(a.extras)
  const apps = new Set(a.apps)
  return {
    defenderStrip: a.defender === 'strip',
    removeAi: a.cleanup === 'yes' || privacy || extreme,
    removeOneDrive: a.cleanup === 'yes' || privacy || extreme,
    // Edge = forced Windows bloat. Extreme always strips it; Balanced only if cleanup=yes.
    // Good browsers (Brave/Helium/Zen/LibreWolf) install from setup multi-select.
    stripEdge: extreme || a.cleanup === 'yes',
    privacyHosts: a.cleanup === 'yes' || privacy || extreme,
    // Mild quiet: user quiet pick, Privacy, or Extreme. Deep kills (SysMain/Spooler/…) are extremeMode-only in YAML.
    serviceStrip: a.services === 'quiet' || privacy || extreme,
    dismStrip: extreme,
    disableVbs: extreme,
    extremeMode: extreme,
    installDirectX: true,
    installVcRedist: true,
    installDotNet8: true,
    installDotNet10: true,
    installBrave: b.has('brave'),
    installHelium: b.has('helium'),
    installZen: b.has('zen'),
    installLibreWolf: b.has('librewolf'),
    // Chrome / stock Firefox not offered in setup (CLI can still force if needed)
    installFirefox: false,
    installChrome: false,
    install7zip: e.has('7zip'),
    installSnipping: e.has('snipping'),
    installPhotos: e.has('photos'),
    installNotepad: e.has('notepad'),
    installTerminalPreview: e.has('terminal'),
    installPowerShellPreview: e.has('pwsh'),
    installSteam: apps.has('steam'),
    installDiscord: apps.has('discord'),
    installEpic: apps.has('epic'),
    installRiot: apps.has('riot'),
    installRevo: apps.has('revo'),
    installObs: apps.has('obs'),
    installSpotify: apps.has('spotify'),
  }
}
