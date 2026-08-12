/**
 * Exo OS — setup, then a single premium plan screen. No dashboard, no chrome bar.
 */
import { useCallback, useEffect, useMemo, useState } from 'react'
import { host, onHostEvent, type Dashboard } from './lib/host'
import { Onboarding } from './Onboarding'
import {
  APP_ITEMS,
  BROWSER_ITEMS,
  EXTRA_ITEMS,
  labelList,
  type OnboardingAnswers,
} from './onboarding-model'

function parseAnswers(raw: unknown): OnboardingAnswers | null {
  if (!raw || typeof raw !== 'object') return null
  const a = raw as Partial<OnboardingAnswers>
  if (
    a.goal !== 'fps' &&
    a.goal !== 'balanced' &&
    a.goal !== 'privacy'
  )
    return null
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

function loadAnswersFromStorage(): OnboardingAnswers | null {
  try {
    const raw = window.localStorage.getItem('exoos.onboarding.v1')
    if (!raw) return null
    const p = JSON.parse(raw) as { answers?: unknown }
    return parseAnswers(p.answers)
  } catch {
    return null
  }
}

function loadAnswersFromHostPayload(answersField: unknown): OnboardingAnswers | null {
  if (typeof answersField !== 'string' || !answersField) return null
  try {
    return parseAnswers(JSON.parse(answersField))
  } catch {
    return null
  }
}

export function App() {
  const [onboarding, setOnboarding] = useState<'loading' | 'show' | 'done'>('loading')
  const [answers, setAnswers] = useState<OnboardingAnswers | null>(null)
  const [dash, setDash] = useState<Dashboard | null>(null)
  const [error, setError] = useState<string | null>(null)
  const [busy, setBusy] = useState(false)
  const [progress, setProgress] = useState(0)
  const [lastLog, setLastLog] = useState<string | null>(null)

  const refresh = useCallback(async () => {
    try {
      const d = await host.getDashboard()
      setDash(d)
      setError(null)
    } catch (e) {
      setError(e instanceof Error ? e.message : 'Failed to load')
    }
  }, [])

  useEffect(() => {
    let cancelled = false
    ;(async () => {
      try {
        const s = await host.getOnboarding()
        if (cancelled) return
        if (s.complete) {
          setAnswers(
            loadAnswersFromHostPayload(s.answers) ?? loadAnswersFromStorage(),
          )
          setOnboarding('done')
          return
        }
      } catch {
        /* show setup */
      }
      try {
        const raw = window.localStorage.getItem('exoos.onboarding.v1')
        if (raw) {
          const parsed = JSON.parse(raw) as { done?: boolean }
          if (parsed.done) window.localStorage.removeItem('exoos.onboarding.v1')
        }
      } catch {
        /* */
      }
      if (!cancelled) setOnboarding('show')
    })()
    return () => {
      cancelled = true
    }
  }, [])

  useEffect(() => {
    if (onboarding !== 'done') return
    void refresh()
  }, [refresh, onboarding])

  useEffect(() => {
    return onHostEvent('progress', (data) => {
      const p = data as { percent?: number }
      if (typeof p.percent === 'number') setProgress(Math.min(99, p.percent))
    })
  }, [])

  const runApply = async () => {
    if (busy) return
    setBusy(true)
    setProgress(4)
    setError(null)
    setLastLog(null)
    try {
      const r = await host.apply()
      setProgress(100)
      const failBit =
        r.failed > 0 ? ` · ${r.failed} failed (see log if needed)` : ''
      setLastLog(
        `Done · ${r.applied} applied · ${r.skipped} skipped${failBit}. Reboot when you can.`,
      )
      await refresh()
    } catch (e) {
      const msg = e instanceof Error ? e.message : 'Apply failed'
      setError(
        msg.includes('admin') || msg.includes('Administrator')
          ? 'Run ExoOS as Administrator, then try again.'
          : msg,
      )
    } finally {
      setBusy(false)
      setProgress(0)
    }
  }

  const summary = useMemo(() => {
    if (!answers) return null
    return {
      focus:
        answers.goal === 'fps'
          ? 'Maximum FPS · full extreme'
          : answers.goal === 'privacy'
            ? 'Privacy first'
            : 'Balanced',
      defender: answers.defender === 'strip' ? 'Remove Defender' : 'Keep Defender',
      cleanup: answers.cleanup === 'yes' ? 'Clean bloat' : 'Keep bloat',
      services: answers.services === 'quiet' ? 'Quiet services' : 'Stock services',
      browsers: labelList(answers.browsers, BROWSER_ITEMS, 'No browsers'),
      tools: labelList(answers.extras, EXTRA_ITEMS, 'No tools'),
      apps: labelList(answers.apps, APP_ITEMS, 'No apps'),
    }
  }, [answers])

  if (onboarding === 'loading') {
    return (
      <div className="exo-app relative flex h-dvh items-center justify-center bg-bg text-[13px] text-muted">
        <span className="exo-enter">Starting…</span>
      </div>
    )
  }

  if (onboarding === 'show') {
    return (
      <Onboarding
        onDone={(a) => {
          setAnswers(a)
          setOnboarding('done')
          void refresh()
        }}
      />
    )
  }

  return (
    <div className="exo-app relative flex h-dvh flex-col overflow-hidden bg-bg text-fg">
      <div className="exo-ambient" />

      <main className="relative z-10 flex min-h-0 flex-1 flex-col items-center justify-center overflow-hidden px-8 pb-10">
        <div className="exo-stage exo-stage-fwd flex w-full max-w-[440px] flex-col">
          <div className="flex flex-col items-center text-center">
            <div className="relative">
              <div className="exo-hero-glow" aria-hidden />
              <img
                src="./logo.png"
                alt=""
                width={72}
                height={72}
                className="exo-logo-in relative size-[72px] rounded-[20px] shadow-[0_24px_64px_rgba(0,0,0,0.6)]"
                draggable={false}
              />
            </div>

            <h1 className="exo-title-show mt-6 text-[30px] font-semibold tracking-tight">
              Your plan
            </h1>
            <p className="exo-enter exo-enter-delay-2 mt-2 text-[13px] text-muted">
              {dash?.state === 'blocked'
                ? 'Run as administrator to apply'
                : dash?.state === 'applied'
                  ? 'Already applied on this PC'
                  : dash?.detail ||
                    `${dash?.actionCount?.toLocaleString() ?? '—'} actions ready for this PC`}
            </p>
            {(dash?.appVersion || dash?.version) && (
              <p className="exo-enter exo-enter-delay-2 mt-1 text-[11px] tabular text-faint">
                Exo OS {dash.appVersion ?? '—'}
                {dash.version ? ` · playbook ${dash.version}` : ''}
              </p>
            )}
            <p className="exo-enter exo-enter-delay-3 mt-4 text-[11px] text-faint">
              Family:{' '}
              <a
                className="text-muted underline-offset-2 hover:text-fg hover:underline"
                href="https://github.com/ImAvgErix/ExoHub/releases/latest"
                aria-label="Exo Hub releases"
                onClick={(e) => {
                  e.preventDefault()
                  void host.openUrl('https://github.com/ImAvgErix/ExoHub/releases/latest')
                }}
              >
                Hub
              </a>
              {' · '}
              <a
                className="text-muted underline-offset-2 hover:text-fg hover:underline"
                href="https://github.com/ImAvgErix/ExoLauncher/releases/latest"
                aria-label="Exo Launcher releases"
                onClick={(e) => {
                  e.preventDefault()
                  void host.openUrl('https://github.com/ImAvgErix/ExoLauncher/releases/latest')
                }}
              >
                Launcher
              </a>
              {' · '}
              <a
                className="text-muted underline-offset-2 hover:text-fg hover:underline"
                href="https://github.com/ImAvgErix/ExoLink/releases/latest"
                aria-label="Exo Link releases"
                onClick={(e) => {
                  e.preventDefault()
                  void host.openUrl('https://github.com/ImAvgErix/ExoLink/releases/latest')
                }}
              >
                Link
              </a>
            </p>
          </div>

          <div className="exo-enter exo-enter-delay-3 card mt-8 overflow-hidden">
            {summary ? (
              <div className="divide-y divide-line-soft">
                {(
                  [
                    ['Focus', summary.focus],
                    ['Defender', summary.defender],
                    ['Cleanup', summary.cleanup],
                    ['Services', summary.services],
                    ['Browsers', summary.browsers],
                    ['Tools', summary.tools],
                    ['Apps', summary.apps],
                  ] as const
                ).map(([k, v]) => (
                  <div key={k} className="exo-plan-row flex items-center gap-3 px-4 py-2.5">
                    <span className="w-[72px] shrink-0 text-[11px] font-medium tracking-wide text-faint uppercase">
                      {k}
                    </span>
                    <span className="min-w-0 flex-1 truncate text-[13px] font-medium text-fg/90">
                      {v}
                    </span>
                  </div>
                ))}
              </div>
            ) : (
              <ul className="exo-stagger space-y-3 p-5">
                <li className="flex items-start gap-3 text-[13px] leading-snug text-fg/90">
                  <span className="exo-dot exo-dot-good" />
                  Gaming tune — registry, services, tasks, AppX, power
                </li>
                <li className="flex items-start gap-3 text-[13px] leading-snug text-fg/90">
                  <span className="exo-dot exo-dot-good" />
                  Setup picks install with this plan
                </li>
                <li className="flex items-start gap-3 text-[13px] leading-snug text-fg/90">
                  <span className="exo-dot exo-dot-good" />
                  One action — nothing else to configure here
                </li>
              </ul>
            )}
          </div>

          {dash && !dash.isAdmin && (
            <p className="exo-enter mt-3 text-center text-[12px] text-bad">
              Run as administrator to apply
            </p>
          )}

          {error && (
            <div className="card mt-3 border-bad/30 p-3 text-[12px] text-bad">
              {error.split('\n')[0]}
            </div>
          )}

          {lastLog && !busy && (
            <p className="mt-3 text-center text-[12px] text-muted">{lastLog}</p>
          )}

          {dash?.state !== 'missing' && (
            <button
              type="button"
              disabled={busy || dash?.state === 'blocked'}
              onClick={() => void runApply()}
              className="exo-cta relative isolate mt-7 flex h-13 w-full items-center justify-center overflow-hidden rounded-full bg-fg text-[15px] font-semibold tabular text-bg disabled:opacity-50"
              style={{ height: 52 }}
            >
              {busy && (
                <span
                  className="exo-apply-fill"
                  style={{ width: `${Math.round(progress)}%` }}
                />
              )}
              <span className="relative z-[1]">
                {busy
                  ? `${Math.round(progress)}%`
                  : dash?.state === 'applied'
                    ? 'Run again'
                    : 'Apply plan'}
              </span>
            </button>
          )}

          <p className="exo-footer-in mt-4 text-center text-[11px] leading-relaxed text-faint">
            Create a restore point first. Stay on AC power. Reboot after apply.
            {summary?.focus?.includes('Maximum FPS')
              ? ' Extreme strips hard — browsers stay via Brave/Helium/Zen/LibreWolf if you picked them.'
              : ' You dialed back from Extreme — Balanced stays on the safer ceiling.'}
          </p>
        </div>
      </main>
    </div>
  )
}
