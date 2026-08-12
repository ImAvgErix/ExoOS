/**
 * Exo OS — setup, then a single premium plan screen. No dashboard, no chrome bar.
 */
import { useCallback, useEffect, useMemo, useState } from 'react'
import { host, onHostEvent, type Dashboard } from './lib/host'
import { Onboarding } from './Onboarding'
import {
  parseAnswers,
  planFields,
  type OnboardingAnswers,
} from './onboarding-model'

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

  const summary = useMemo(
    () => (answers ? planFields(answers, 'plan') : null),
    [answers],
  )

  const machineLine = useMemo(() => {
    if (!dash) return null
    const cpu = dash.specs?.cpu?.replace(/\s+/g, ' ').trim()
    const shortCpu =
      cpu && cpu.length > 42 ? `${cpu.slice(0, 40).trimEnd()}…` : cpu
    const parts = [dash.osLabel, shortCpu, dash.specs?.ram].filter(
      (x): x is string => Boolean(x && x !== 'CPU' && x !== 'GPU' && x !== 'Windows'),
    )
    return parts.length ? parts.join(' · ') : null
  }, [dash])

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
            {machineLine && (
              <p className="exo-enter exo-enter-delay-2 mt-1 max-w-[360px] truncate text-[11px] text-faint">
                {machineLine}
              </p>
            )}
            <p className="exo-enter exo-enter-delay-3 mt-4 text-[11px] text-faint">
              Family:{' '}
              {(
                [
                  ['Hub', 'https://github.com/ImAvgErix/ExoHub/releases/latest'],
                  ['Launcher', 'https://github.com/ImAvgErix/ExoLauncher/releases/latest'],
                  ['Link', 'https://github.com/ImAvgErix/ExoLink/releases/latest'],
                ] as const
              ).map(([name, href], i) => (
                <span key={name}>
                  {i > 0 ? ' · ' : null}
                  <a
                    className="text-muted underline-offset-2 hover:text-fg hover:underline"
                    href={href}
                    aria-label={`Exo ${name} releases`}
                    onClick={(e) => {
                      e.preventDefault()
                      void host.openUrl(href)
                    }}
                  >
                    {name}
                  </a>
                </span>
              ))}
            </p>
          </div>

          <div className="exo-enter exo-enter-delay-3 card mt-8 overflow-hidden">
            {summary ? (
              <div className="divide-y divide-line-soft">
                {summary.map((row) => (
                  <div key={row.id} className="exo-plan-row flex items-center gap-3 px-4 py-2.5">
                    <span className="w-[72px] shrink-0 text-[11px] font-medium tracking-wide text-faint uppercase">
                      {row.label}
                    </span>
                    <span className="min-w-0 flex-1 truncate text-[13px] font-medium text-fg/90">
                      {row.value}
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
            Stay on AC power. Reboot after apply.
            {summary?.some((r) => r.id === 'goal' && r.value.includes('Maximum FPS'))
              ? ' Extreme strips hard — browsers stay via Brave/Helium/Zen/LibreWolf if you picked them.'
              : ' You dialed back from Extreme — Balanced stays on the safer ceiling.'}
          </p>
        </div>
      </main>
    </div>
  )
}
