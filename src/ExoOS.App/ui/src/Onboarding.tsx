/**
 * Linear setup — one step at a time, fluid motion, no chrome clutter.
 */
import { useEffect, useMemo, useRef, useState } from 'react'
import { Check, ChevronLeft } from 'lucide-react'
import { cn } from './lib/utils'
import { host } from './lib/host'
import { CascadeTitle, FadeIn, StageSwap, Stagger, type StageDir } from './motion'
import {
  APP_ITEMS,
  BROWSER_ITEMS,
  DEFAULT_ANSWERS,
  EXTRA_ITEMS,
  answersToOptions,
  planFields,
  toggleId,
  type OnboardingAnswers,
  type MultiItem,
} from './onboarding-model'

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

/** Single brand line — ecosystem catchphrase, not a rotating quote. */
const BRAND_LINE = 'Built quiet. Tuned sharp.'

export function Onboarding({ onDone }: { onDone: (answers: OnboardingAnswers) => void }) {
  const [step, setStep] = useState(0)
  const [animKey, setAnimKey] = useState(0)
  const [dir, setDir] = useState<StageDir>('fwd')
  const prevStep = useRef(0)
  const [answers, setAnswers] = useState<OnboardingAnswers>({ ...DEFAULT_ANSWERS })
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState<string | null>(null)
  const id = STEPS[step]

  const go = (n: number) => {
    setDir(n >= prevStep.current ? 'fwd' : 'back')
    prevStep.current = n
    setStep(n)
    setAnimKey((k) => k + 1)
    setError(null)
  }

  const finish = async () => {
    if (busy) return
    setBusy(true)
    setError(null)
    try {
      await host.setOptions(answersToOptions(answers))
      await host.completeOnboarding(answers)
      try {
        window.localStorage.setItem(
          'exoos.onboarding.v1',
          JSON.stringify({ done: true, answers }),
        )
      } catch {
        /* host already persisted */
      }
      onDone(answers)
    } catch (e) {
      setError(e instanceof Error ? e.message : 'Could not save setup')
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
            <img
              src="./logo.png"
              alt=""
              width={80}
              height={80}
              className="exo-logo-in size-[80px] rounded-[22px] shadow-[0_24px_64px_rgba(0,0,0,0.55)]"
              draggable={false}
            />
            <CascadeTitle
              text="Welcome to Exo OS"
              className="mt-8 text-[36px] font-semibold tracking-tight leading-none"
            />
            <FadeIn delay={0.08} className="mt-5 max-w-sm text-[17px] font-medium leading-snug tracking-tight">
              {BRAND_LINE}
            </FadeIn>
            <FadeIn delay={0.14} className="mt-6 max-w-sm text-[14px] leading-relaxed text-muted">
              Strip Windows to a pure gaming OS. Dial back only if you need to.
            </FadeIn>
          </div>
        )
      case 'goal':
        return (
          <Question
            title="How hard do we strip?"
            subtitle="Default is Maximum FPS — barebones gaming OS. Balanced keeps more of Windows."
            choices={[
              {
                id: 'fps',
                title: 'Maximum FPS',
                detail:
                  'Ultimate strip: registry, tasks, services, AppX, DISM, VBS off, mitigations, max quiet. WU paused. Keep Store + browsers/apps you pick. Can break printers / some anti-cheat.',
                warn: true,
              },
              {
                id: 'privacy',
                title: 'Privacy first',
                detail:
                  'Telemetry quiet, AI/OneDrive strip, service strip — WU paused. Not full extreme (no spooler/mitigations/DISM).',
              },
              {
                id: 'balanced',
                title: 'Balanced',
                detail:
                  'Dial-back: shared gaming baseline without nuclear strip (no spooler/mitigations/DISM/IFEO).',
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
            subtitle="Default strips it for lowest load. Keep only if anti-cheat or work software needs it."
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
                detail: 'Safer for multiplayer and work software — dial-back from pure strip.',
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

      <div className="relative z-10 flex h-11 shrink-0 items-center px-3">
        {step > 0 ? (
          <button
            type="button"
            onClick={back}
            aria-label="Back"
            className="grid size-9 place-items-center rounded-full text-muted transition-colors transition-transform duration-200 hover:bg-hover hover:text-fg active:scale-95"
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
            {error && (
              <div className="card w-full max-w-sm border-bad/30 p-3 text-center text-[12px] text-bad">
                {error}
              </div>
            )}
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
                  'mt-0.5 grid size-5 shrink-0 place-items-center rounded-full border transition-colors transition-transform duration-200',
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
                  'mt-0.5 grid size-4 shrink-0 place-items-center rounded border transition-colors duration-200',
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
  const rows = planFields(answers, 'ready')

  return (
    <div className="text-center">
      <CascadeTitle text="You're set" className="text-[26px] font-semibold tracking-tight" />
      <FadeIn delay={0.06} className="mt-1.5 text-[13px] text-muted">
        Tap a row to change it.
      </FadeIn>
      <div className="mt-5 grid grid-cols-2 gap-2 text-left">
        {rows.map((r) => (
          <button
            key={r.id}
            type="button"
            aria-label={`${r.label}: ${r.value}`}
            onClick={() => onEdit(r.id as StepId)}
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
