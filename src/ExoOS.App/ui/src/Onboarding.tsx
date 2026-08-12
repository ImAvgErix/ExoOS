/**
 * Linear setup — one step at a time, fluid motion, no chrome clutter.
 */
import { useCallback, useEffect, useRef, useState } from 'react'
import { ChevronLeft } from 'lucide-react'
import { cn } from './lib/utils'
import { host } from './lib/host'
import { StageSwap, type StageDir } from './motion'
import { DEFAULT_ANSWERS, STEPS, answersToOptions, type OnboardingAnswers } from './onboarding-model'
import { OnboardingBody } from './onboarding-steps'

export function Onboarding({ onDone }: { onDone: (answers: OnboardingAnswers) => void }) {
  const [step, setStep] = useState(0)
  const [animKey, setAnimKey] = useState(0)
  const [dir, setDir] = useState<StageDir>('fwd')
  const prevStep = useRef(0)
  const [answers, setAnswers] = useState<OnboardingAnswers>({ ...DEFAULT_ANSWERS })
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState<string | null>(null)
  const id = STEPS[step]

  const go = useCallback((n: number) => {
    setDir(n >= prevStep.current ? 'fwd' : 'back')
    prevStep.current = n
    setStep(n)
    setAnimKey((k) => k + 1)
    setError(null)
  }, [])

  const finish = useCallback(async () => {
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
  }, [answers, busy, onDone])

  const next = useCallback(() => {
    if (step >= STEPS.length - 1) void finish()
    else go(step + 1)
  }, [finish, go, step])

  const back = useCallback(() => {
    if (step > 0) go(step - 1)
  }, [go, step])

  useEffect(() => {
    const onKey = (e: KeyboardEvent) => {
      if (e.key === 'Enter' && !busy) next()
      if (e.key === 'Escape' && step > 0) back()
    }
    window.addEventListener('keydown', onKey)
    return () => window.removeEventListener('keydown', onKey)
  }, [back, busy, next, step])

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
            <OnboardingBody
              id={id}
              answers={answers}
              setAnswers={setAnswers}
              onEdit={(target) => {
                const idx = STEPS.indexOf(target)
                if (idx >= 0) go(idx)
              }}
            />
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
              {STEPS.map((stepId, i) => (
                <span
                  key={stepId}
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
