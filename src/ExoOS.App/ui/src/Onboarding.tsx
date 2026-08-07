/**
 * Linear setup — one step at a time, fluid motion, no chrome clutter.
 */
import { useEffect, useMemo, useRef, useState } from 'react'
import { Check, ChevronLeft } from 'lucide-react'
import { cn } from './lib/utils'
import { host } from './lib/host'
import { WindowChrome } from './WindowChrome'
import { CascadeTitle, FadeIn, StageSwap, Stagger, type StageDir } from './motion'

export type OnboardingAnswers = {
  goal: 'fps' | 'balanced' | 'privacy'
  defender: 'strip' | 'keep'
  cleanup: 'yes' | 'no'
  services: 'quiet' | 'leave'
  browsers: string[]
  extras: string[]
  apps: string[]
}

type StepId =
  | 'welcome'
  | 'goal'
  | 'defender'
  | 'cleanup'
  | 'services'
  | 'browsers'
  | 'extras'
  | 'apps'
  | 'ready'

const STEPS: StepId[] = [
  'welcome',
  'goal',
  'defender',
  'cleanup',
  'services',
  'browsers',
  'extras',
  'apps',
  'ready',
]

type Choice = { id: string; title: string; detail: string; warn?: boolean }
type MultiItem = { id: string; title: string; detail: string }

// Good browsers only — no Chrome/stock Edge bait. Firefox stock is meh; use Zen/LibreWolf.
const BROWSER_ITEMS: MultiItem[] = [
  { id: 'brave', title: 'Brave', detail: 'Ad-block Chromium, low telemetry' },
  { id: 'helium', title: 'Helium', detail: 'Private, no bloat' },
  { id: 'zen', title: 'Zen', detail: 'Calm, vertical tabs, Firefox-based' },
  { id: 'librewolf', title: 'LibreWolf', detail: 'Hardened Firefox, privacy-first' },
]

const EXTRA_ITEMS: MultiItem[] = [
  { id: '7zip', title: '7-Zip', detail: 'Archives' },
  { id: 'snipping', title: 'Snipping Tool', detail: 'Screenshots' },
  { id: 'photos', title: 'Photos', detail: 'Gallery' },
  { id: 'notepad', title: 'Notepad', detail: 'Notes' },
  { id: 'terminal', title: 'Terminal Preview', detail: 'Shell' },
  { id: 'pwsh', title: 'PowerShell Preview', detail: 'Latest PS' },
]

const APP_ITEMS: MultiItem[] = [
  { id: 'steam', title: 'Steam', detail: 'Games' },
  { id: 'discord', title: 'Discord', detail: 'Voice' },
  { id: 'epic', title: 'Epic Games', detail: 'Launcher' },
  { id: 'riot', title: 'Riot Client', detail: 'Valorant…' },
  { id: 'revo', title: 'Revo', detail: 'Uninstall' },
  { id: 'obs', title: 'OBS Studio', detail: 'Capture' },
  { id: 'spotify', title: 'Spotify', detail: 'Music' },
]

const DEFAULT_EXTRAS = ['7zip', 'snipping', 'photos', 'notepad', 'terminal']

/** Single brand line — ecosystem catchphrase, not a rotating quote. */
const BRAND_LINE = 'Built quiet. Tuned sharp.'

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
  const balanced = a.goal === 'balanced'
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

function toggleId(list: string[], id: string) {
  return list.includes(id) ? list.filter((x) => x !== id) : [...list, id]
}

function labelList(ids: string[], catalog: MultiItem[], empty: string) {
  if (ids.length === 0) return empty
  const map = new Map(catalog.map((c) => [c.id, c.title]))
  return ids.map((id) => map.get(id) ?? id).join(' · ')
}

export function Onboarding({ onDone }: { onDone: (answers: OnboardingAnswers) => void }) {
  const [step, setStep] = useState(0)
  const [animKey, setAnimKey] = useState(0)
  const [dir, setDir] = useState<StageDir>('fwd')
  const prevStep = useRef(0)
  const [answers, setAnswers] = useState<OnboardingAnswers>({
    goal: 'fps',
    defender: 'strip',
    cleanup: 'yes',
    services: 'quiet',
    browsers: [],
    extras: [...DEFAULT_EXTRAS],
    apps: [],
  })
  const [busy, setBusy] = useState(false)
  const id = STEPS[step]

  const go = (n: number) => {
    setDir(n >= prevStep.current ? 'fwd' : 'back')
    prevStep.current = n
    setStep(n)
    setAnimKey((k) => k + 1)
  }

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

  const next = () => {
    if (step >= STEPS.length - 1) void finish()
    else go(step + 1)
  }

  const back = () => {
    if (step > 0) go(step - 1)
  }

  // Auto-advance feel: double-click choice advances after short delay on single-select
  useEffect(() => {
    const onKey = (e: KeyboardEvent) => {
      if (e.key === 'Enter' && !busy) next()
      if (e.key === 'Escape' && step > 0) back()
    }
    window.addEventListener('keydown', onKey)
    return () => window.removeEventListener('keydown', onKey)
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [step, busy, answers])

  const body = useMemo(() => {
    switch (id) {
      case 'welcome':
        return (
          <div className="flex flex-col items-center text-center">
            <div
              className="exo-logo-in grid size-[80px] place-items-center text-[34px] font-bold tracking-tight text-fg"
              style={{
                borderRadius: 22,
                background: 'linear-gradient(160deg,#2e2e32 0%,#121214 50%,#050505 100%)',
                border: '1px solid #282828',
                boxShadow: '0 20px 60px rgba(0,0,0,0.55), inset 0 1px 0 rgba(255,255,255,0.06)',
              }}
            >
              E
            </div>
            <CascadeTitle
              text="Welcome to Exo OS"
              className="mt-8 text-[36px] font-semibold tracking-tight leading-none"
            />
            <FadeIn delay={0.08} className="mt-5 max-w-sm text-[17px] font-medium leading-snug tracking-tight">
              {BRAND_LINE}
            </FadeIn>
            <FadeIn delay={0.14} className="mt-6 max-w-sm text-[14px] leading-relaxed text-muted">
              A few choices so the plan matches how you play.
            </FadeIn>
          </div>
        )
      case 'goal':
        return (
          <Question
            title="What matters most?"
            subtitle="Sets how aggressive the plan is."
            choices={[
              {
                id: 'fps',
                title: 'Maximum FPS',
                detail:
                  'Full extreme: DISM, VBS off, HAGS, spooler off, mitigations stripped, max quiet. WU paused (all plans). Can break printers / some anti-cheat.',
                warn: true,
              },
              {
                id: 'balanced',
                title: 'Balanced',
                detail: 'Shared baseline (WU pause, input, light privacy) plus your service/cleanup picks — no spooler/mitigation strip.',
              },
              {
                id: 'privacy',
                title: 'Privacy first',
                detail: 'Telemetry quiet, AI/OneDrive strip, service strip — WU paused. Not full extreme (no spooler/mitigations/DISM).',
              },
            ]}
            value={answers.goal}
            onChange={(v) => setAnswers((a) => ({ ...a, goal: v as OnboardingAnswers['goal'] }))}
          />
        )
      case 'defender':
        return (
          <Question
            title="Windows Defender?"
            subtitle="Some anti-cheat expects it. Hard to reverse."
            choices={[
              {
                id: 'strip',
                title: 'Remove Defender',
                detail: 'Lowest background load. Plan on reinstall to fully restore.',
                warn: true,
              },
              {
                id: 'keep',
                title: 'Keep Defender',
                detail: 'Safer for multiplayer and work software.',
              },
            ]}
            value={answers.defender}
            onChange={(v) =>
              setAnswers((a) => ({ ...a, defender: v as OnboardingAnswers['defender'] }))
            }
          />
        )
      case 'cleanup':
        return (
          <Question
            title="Bloat and extras?"
            subtitle="Copilot, OneDrive, Edge noise, privacy hosts."
            choices={[
              {
                id: 'yes',
                title: 'Clean them up',
                detail: 'Strip AI surfaces, OneDrive hooks, and telemetry hosts.',
              },
              {
                id: 'no',
                title: 'Leave them',
                detail: 'Keep cloud extras and stock Microsoft features.',
              },
            ]}
            value={answers.cleanup}
            onChange={(v) =>
              setAnswers((a) => ({ ...a, cleanup: v as OnboardingAnswers['cleanup'] }))
            }
          />
        )
      case 'services':
        return (
          <Question
            title="Background services?"
            subtitle="Quiet systems free CPU and disk while you play."
            choices={[
              {
                id: 'quiet',
                title: 'Quiet them',
                detail: 'Turn down telemetry, diagnostics, non-essentials.',
              },
              {
                id: 'leave',
                title: 'Leave alone',
                detail: 'Keep stock service startup.',
              },
            ]}
            value={answers.services}
            onChange={(v) =>
              setAnswers((a) => ({ ...a, services: v as OnboardingAnswers['services'] }))
            }
          />
        )
      case 'browsers':
        return (
          <MultiPick
            title="Browsers"
            subtitle="Brave, Helium, Zen, LibreWolf — no Chrome. Skip if you already have one."
            items={BROWSER_ITEMS}
            selected={answers.browsers}
            onToggle={(itemId) =>
              setAnswers((a) => ({ ...a, browsers: toggleId(a.browsers, itemId) }))
            }
            onClear={() => setAnswers((a) => ({ ...a, browsers: [] }))}
            onSelectAll={() =>
              setAnswers((a) => ({ ...a, browsers: BROWSER_ITEMS.map((x) => x.id) }))
            }
          />
        )
      case 'extras':
        return (
          <MultiPick
            title="Tools"
            subtitle="Useful utilities. Defaults are on."
            items={EXTRA_ITEMS}
            selected={answers.extras}
            onToggle={(itemId) =>
              setAnswers((a) => ({ ...a, extras: toggleId(a.extras, itemId) }))
            }
            onClear={() => setAnswers((a) => ({ ...a, extras: [] }))}
            onSelectAll={() =>
              setAnswers((a) => ({ ...a, extras: EXTRA_ITEMS.map((x) => x.id) }))
            }
          />
        )
      case 'apps':
        return (
          <MultiPick
            title="Apps"
            subtitle="Launchers and everyday gaming tools."
            items={APP_ITEMS}
            selected={answers.apps}
            onToggle={(itemId) => setAnswers((a) => ({ ...a, apps: toggleId(a.apps, itemId) }))}
            onClear={() => setAnswers((a) => ({ ...a, apps: [] }))}
            onSelectAll={() => setAnswers((a) => ({ ...a, apps: APP_ITEMS.map((x) => x.id) }))}
          />
        )
      case 'ready':
        return (
          <Ready
            answers={answers}
            onEdit={(target) => {
              const idx = STEPS.indexOf(target)
              if (idx >= 0) go(idx)
            }}
          />
        )
    }
  }, [id, answers])

  const cta =
    id === 'welcome'
      ? 'Get started'
      : id === 'ready'
        ? busy
          ? 'Saving…'
          : 'Finish setup'
        : 'Continue'

  return (
    <div className="exo-app relative flex h-dvh flex-col overflow-hidden bg-bg text-fg">
      <div className="exo-ambient" />
      <WindowChrome />

      <div className="relative z-10 flex h-11 shrink-0 items-center px-3">
        {step > 0 ? (
          <button
            type="button"
            onClick={back}
            aria-label="Back"
            className="grid size-9 place-items-center rounded-full text-muted transition-all duration-200 hover:bg-hover hover:text-fg active:scale-95"
          >
            <ChevronLeft className="size-5" strokeWidth={1.75} />
          </button>
        ) : (
          <span className="w-9" />
        )}
      </div>

      <main className="relative z-10 flex min-h-0 flex-1 flex-col items-center justify-center overflow-hidden px-8 pb-10">
        <div className="flex w-full max-w-lg flex-col">
          <StageSwap stepKey={animKey} dir={dir}>
            {body}
          </StageSwap>

          <div className="exo-footer-in mt-8 flex shrink-0 flex-col items-center gap-5">
            <div
              className="exo-progress"
              role="progressbar"
              aria-valuemin={1}
              aria-valuemax={STEPS.length}
              aria-valuenow={step + 1}
              aria-label={`Step ${step + 1} of ${STEPS.length}`}
            >
              {STEPS.map((_, i) => (
                <span
                  key={i}
                  data-active={i === step ? 'true' : undefined}
                  data-done={i < step ? 'true' : undefined}
                  className={cn(
                    'exo-progress-dot h-1.5 rounded-full',
                    i === step
                      ? 'w-6 bg-fg'
                      : i < step
                        ? 'w-1.5 bg-fg/50'
                        : 'w-1.5 bg-faint/40',
                  )}
                />
              ))}
            </div>
            <button
              type="button"
              disabled={busy}
              onClick={next}
              aria-label={cta}
              className="exo-cta flex h-12 w-full max-w-sm items-center justify-center rounded-full bg-fg text-[15px] font-semibold text-bg disabled:opacity-50"
            >
              <span key={cta} className="exo-cta-label">
                {cta}
              </span>
            </button>
          </div>
        </div>
      </main>
    </div>
  )
}

function Question({
  title,
  subtitle,
  choices,
  value,
  onChange,
}: {
  title: string
  subtitle: string
  choices: Choice[]
  value: string
  onChange: (id: string) => void
}) {
  return (
    <div>
      <CascadeTitle
        text={title}
        className="text-[28px] font-semibold tracking-tight leading-tight"
      />
      <FadeIn delay={0.05} className="mt-2 text-[14px] leading-relaxed text-muted">
        {subtitle}
      </FadeIn>
      <Stagger className="mt-6 space-y-2.5">
        {choices.map((c) => {
          const on = value === c.id
          return (
            <button
              key={c.id}
              type="button"
              role="radio"
              aria-checked={on}
              aria-label={c.title}
              data-on={on}
              onClick={() => onChange(c.id)}
              className="exo-choice card flex w-full items-start gap-3.5 p-4 text-left"
            >
              <span
                className={cn(
                  'mt-0.5 grid size-5 shrink-0 place-items-center rounded-full border transition-all duration-200',
                  on ? 'border-fg bg-fg text-bg scale-100' : 'border-faint scale-95',
                )}
              >
                {on && <Check className="size-3" strokeWidth={3} />}
              </span>
              <span className="min-w-0 flex-1">
                <span className="block text-[15px] font-semibold">{c.title}</span>
                <span
                  className={cn(
                    'mt-1 block text-[13px] leading-snug',
                    c.warn ? 'text-bad/90' : 'text-muted',
                  )}
                >
                  {c.detail}
                </span>
              </span>
            </button>
          )
        })}
      </Stagger>
    </div>
  )
}

function MultiPick({
  title,
  subtitle,
  items,
  selected,
  onToggle,
  onClear,
  onSelectAll,
}: {
  title: string
  subtitle: string
  items: MultiItem[]
  selected: string[]
  onToggle: (id: string) => void
  onClear: () => void
  onSelectAll: () => void
}) {
  return (
    <div>
      <CascadeTitle
        text={title}
        className="text-[28px] font-semibold tracking-tight leading-tight"
      />
      <FadeIn delay={0.05} className="mt-2 text-[14px] leading-relaxed text-muted">
        {subtitle}
      </FadeIn>
      <FadeIn delay={0.08} className="mt-3 flex items-center gap-3 text-[12px]">
        <button
          type="button"
          onClick={onSelectAll}
          className="font-medium text-muted transition-colors hover:text-fg"
        >
          All
        </button>
        <span className="text-faint">·</span>
        <button
          type="button"
          onClick={onClear}
          className="font-medium text-muted transition-colors hover:text-fg"
        >
          None
        </button>
        <span className="ml-auto tabular text-faint">{selected.length} selected</span>
      </FadeIn>
      <Stagger className="mt-3 grid grid-cols-2 gap-2">
        {items.map((item) => {
          const on = selected.includes(item.id)
          return (
            <button
              key={item.id}
              type="button"
              role="checkbox"
              aria-checked={on}
              aria-label={item.title}
              data-on={on}
              onClick={() => onToggle(item.id)}
              className="exo-choice card flex h-full w-full items-start gap-2.5 p-3.5 text-left"
            >
              <span
                className={cn(
                  'mt-0.5 grid size-4 shrink-0 place-items-center rounded border transition-all duration-200',
                  on ? 'border-fg bg-fg text-bg' : 'border-faint',
                )}
              >
                {on && <Check className="size-2.5" strokeWidth={3} />}
              </span>
              <span className="min-w-0 flex-1">
                <span className="block text-[13px] font-semibold leading-tight">{item.title}</span>
                <span className="mt-0.5 block text-[11px] leading-snug text-muted">
                  {item.detail}
                </span>
              </span>
            </button>
          )
        })}
      </Stagger>
    </div>
  )
}

function Ready({
  answers,
  onEdit,
}: {
  answers: OnboardingAnswers
  onEdit: (step: StepId) => void
}) {
  const rows: { label: string; value: string; step: StepId }[] = [
    {
      label: 'Focus',
      value:
        answers.goal === 'fps'
          ? 'Maximum FPS'
          : answers.goal === 'privacy'
            ? 'Privacy first'
            : 'Balanced',
      step: 'goal',
    },
    {
      label: 'Defender',
      value: answers.defender === 'strip' ? 'Remove' : 'Keep',
      step: 'defender',
    },
    {
      label: 'Bloat',
      value: answers.cleanup === 'yes' ? 'Clean up' : 'Leave',
      step: 'cleanup',
    },
    {
      label: 'Services',
      value: answers.services === 'quiet' ? 'Quiet' : 'Stock',
      step: 'services',
    },
    {
      label: 'Browsers',
      value: labelList(answers.browsers, BROWSER_ITEMS, 'None'),
      step: 'browsers',
    },
    {
      label: 'Tools',
      value: labelList(answers.extras, EXTRA_ITEMS, 'None'),
      step: 'extras',
    },
    {
      label: 'Apps',
      value: labelList(answers.apps, APP_ITEMS, 'None'),
      step: 'apps',
    },
  ]

  return (
    <div className="text-center">
      <CascadeTitle text="You're set" className="text-[26px] font-semibold tracking-tight" />
      <FadeIn delay={0.06} className="mt-1.5 text-[13px] text-muted">
        Tap a row to change it.
      </FadeIn>
      {/* Compact grid — no scroll */}
      <div className="mt-5 grid grid-cols-2 gap-2 text-left">
        {rows.map((r) => (
          <button
            key={r.step}
            type="button"
            aria-label={`${r.label}: ${r.value}`}
            onClick={() => onEdit(r.step)}
            className="exo-ready-row exo-choice card flex min-h-[52px] flex-col justify-center gap-0.5 px-3 py-2.5 text-left"
          >
            <span className="text-[10px] font-medium tracking-[0.12em] text-faint uppercase">
              {r.label}
            </span>
            <span className="truncate text-[13px] font-semibold leading-tight">{r.value}</span>
          </button>
        ))}
      </div>
    </div>
  )
}

export { BROWSER_ITEMS, EXTRA_ITEMS, APP_ITEMS, labelList }
