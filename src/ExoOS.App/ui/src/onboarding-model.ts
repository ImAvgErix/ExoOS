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

/**
 * Product default = Maximum FPS / Extreme barebones gaming OS.
 * Balanced and Privacy are explicit dial-backs — never the silent default.
 */
export const DEFAULT_ANSWERS: OnboardingAnswers = {
  goal: 'fps',
  defender: 'strip',
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

export function parseAnswers(raw: unknown): OnboardingAnswers | null {
  if (!raw || typeof raw !== 'object') return null
  const a = raw as Partial<OnboardingAnswers>
  if (a.goal !== 'fps' && a.goal !== 'balanced' && a.goal !== 'privacy') return null
  return {
    goal: a.goal,
    defender: a.defender === 'strip' ? 'strip' : 'keep',
    cleanup: a.cleanup === 'no' ? 'no' : 'yes',
    services: a.services === 'leave' ? 'leave' : 'quiet',
    browsers: Array.isArray(a.browsers) ? a.browsers.filter((x) => typeof x === 'string') : [],
    extras: Array.isArray(a.extras) ? a.extras.filter((x) => typeof x === 'string') : [],
    apps: Array.isArray(a.apps) ? a.apps.filter((x) => typeof x === 'string') : [],
  }
}

export type PlanFieldId =
  | 'goal'
  | 'defender'
  | 'cleanup'
  | 'services'
  | 'browsers'
  | 'extras'
  | 'apps'

export function planFields(
  a: OnboardingAnswers,
  style: 'ready' | 'plan' = 'plan',
): { id: PlanFieldId; label: string; value: string }[] {
  const short = style === 'ready'
  return [
    {
      id: 'goal',
      label: 'Focus',
      value:
        a.goal === 'fps'
          ? short
            ? 'Maximum FPS'
            : 'Maximum FPS · full extreme'
          : a.goal === 'privacy'
            ? 'Privacy first'
            : 'Balanced',
    },
    {
      id: 'defender',
      label: 'Defender',
      value:
        a.defender === 'strip'
          ? short
            ? 'Remove'
            : 'Remove Defender'
          : short
            ? 'Keep'
            : 'Keep Defender',
    },
    {
      id: 'cleanup',
      label: short ? 'Bloat' : 'Cleanup',
      value: a.cleanup === 'yes' ? (short ? 'Clean up' : 'Clean bloat') : short ? 'Leave' : 'Keep bloat',
    },
    {
      id: 'services',
      label: 'Services',
      value: a.services === 'quiet' ? (short ? 'Quiet' : 'Quiet services') : short ? 'Stock' : 'Stock services',
    },
    {
      id: 'browsers',
      label: 'Browsers',
      value: labelList(a.browsers, BROWSER_ITEMS, short ? 'None' : 'No browsers'),
    },
    {
      id: 'extras',
      label: 'Tools',
      value: labelList(a.extras, EXTRA_ITEMS, short ? 'None' : 'No tools'),
    },
    {
      id: 'apps',
      label: 'Apps',
      value: labelList(a.apps, APP_ITEMS, short ? 'None' : 'No apps'),
    },
  ]
}

export function answersToOptions(a: OnboardingAnswers): Record<string, boolean> {
  /**
   * Extreme / Maximum FPS (goal=fps) — PRODUCT DEFAULT:
   *   Barebones gaming OS. Strip non-essentials (registry/tasks/services/AppX/DISM/VBS/…).
   *   Keep gaming path: Store, browsers you pick, Discord/Steam-class apps.
   * Balanced: dial-back safe ceiling (no extremeMode/dismStrip/disableVbs).
   * Privacy: telemetry/AI/OneDrive quiet without full nuclear strip.
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
