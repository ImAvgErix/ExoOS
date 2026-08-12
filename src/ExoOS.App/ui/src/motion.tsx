/**
 * Smooth step transitions via Motion (AnimatePresence).
 * Subtle opacity + x only — no scale (avoids blurry/janky text).
 */
import { AnimatePresence, motion, useReducedMotion } from 'motion/react'
import type { ReactNode } from 'react'
import { cn } from './lib/utils'

export type StageDir = 'fwd' | 'back'

/** Snappy 60fps-friendly ease (short, no heavy springs) */
const ease = [0.25, 0.1, 0.25, 1] as const

const slide = {
  initial: (dir: StageDir) => ({
    opacity: 0,
    x: dir === 'fwd' ? 24 : -24,
  }),
  animate: {
    opacity: 1,
    x: 0,
    transition: {
      duration: 0.28,
      ease,
      delayChildren: 0.04,
      staggerChildren: 0.03,
    },
  },
  exit: (dir: StageDir) => ({
    opacity: 0,
    x: dir === 'fwd' ? -16 : 16,
    transition: { duration: 0.2, ease },
  }),
}

const item = {
  initial: { opacity: 0, y: 8 },
  animate: {
    opacity: 1,
    y: 0,
    transition: { duration: 0.24, ease },
  },
}

/**
 * Sequential page transition: old step exits fully, then new enters.
 * mode="wait" is what makes this feel finished instead of half-baked.
 */
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
  const reduce = useReducedMotion()

  if (reduce) {
    return <div className={className}>{children}</div>
  }

  return (
    <div className={cn('exo-stage-root', className)}>
      <AnimatePresence mode="wait" custom={dir} initial={false}>
        <motion.div
          key={stepKey}
          className="exo-panel"
          custom={dir}
          variants={slide}
          initial="initial"
          animate="animate"
          exit="exit"
        >
          {children}
        </motion.div>
      </AnimatePresence>
    </div>
  )
}

/** Soft whole-title fade (no per-word split — that felt gimmicky). */
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
  const reduce = useReducedMotion()
  if (reduce) {
    return <Tag className={className}>{text}</Tag>
  }
  return (
    <motion.div
      variants={item}
      initial="initial"
      animate="animate"
      className={className}
    >
      <Tag className="m-0">{text}</Tag>
    </motion.div>
  )
}

/** Staggered children for choice lists */
export function Stagger({
  children,
  className,
}: {
  children: ReactNode
  className?: string
  stepMs?: number
}) {
  const reduce = useReducedMotion()
  const items = Array.isArray(children) ? children : [children]

  if (reduce) {
    return <div className={className}>{children}</div>
  }

  return (
    <motion.div
      className={className}
      initial="initial"
      animate="animate"
      variants={{
        animate: { transition: { staggerChildren: 0.05, delayChildren: 0.04 } },
      }}
    >
      {items.map((child, i) => (
        <motion.div key={i} variants={item}>
          {child}
        </motion.div>
      ))}
    </motion.div>
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
  const reduce = useReducedMotion()
  if (reduce) return <div className={className}>{children}</div>
  return (
    <motion.div
      className={className}
      initial={{ opacity: 0, y: 10 }}
      animate={{ opacity: 1, y: 0 }}
      transition={{ duration: 0.4, ease, delay }}
    >
      {children}
    </motion.div>
  )
}
