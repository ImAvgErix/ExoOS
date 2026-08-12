/**
 * Step transitions via CSS (tweaks.css). No Motion runtime.
 * Opacity + x only — no scale (keeps text sharp).
 */
import type { HTMLAttributes, ReactNode } from 'react'
import { cn } from './lib/utils'

export type StageDir = 'fwd' | 'back'

export function StageSwap({
  stepKey,
  dir,
  children,
  className,
}: {
  stepKey: number
  dir: StageDir
  children: ReactNode
  className?: string
}) {
  return (
    <div className={cn('exo-stage-root', className)}>
      <div
        key={stepKey}
        className={cn('exo-panel', dir === 'fwd' ? 'exo-stage-fwd' : 'exo-stage-back')}
      >
        {children}
      </div>
    </div>
  )
}

export function CascadeTitle({
  text,
  className,
  as: Tag = 'h1',
}: {
  text: string
  className?: string
  as?: 'h1' | 'h2' | 'p'
  delayMs?: number
}) {
  return <Tag className={cn('exo-enter', className)}>{text}</Tag>
}

export function Stagger({
  children,
  className,
  stepMs: _stepMs,
  ...rest
}: {
  children: ReactNode
  className?: string
  stepMs?: number
} & HTMLAttributes<HTMLDivElement>) {
  return (
    <div className={cn('exo-stagger', className)} {...rest}>
      {children}
    </div>
  )
}

export function FadeIn({
  children,
  className,
  delay = 0,
}: {
  children: ReactNode
  className?: string
  delay?: number
}) {
  const delayClass =
    delay >= 0.14
      ? 'exo-enter-delay-3'
      : delay >= 0.08
        ? 'exo-enter-delay-2'
        : delay >= 0.05
          ? 'exo-enter-delay-1'
          : ''
  return <div className={cn('exo-enter', delayClass, className)}>{children}</div>
}
