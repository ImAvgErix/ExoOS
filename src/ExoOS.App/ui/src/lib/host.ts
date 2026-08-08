/**
 * JSON-RPC bridge to the WPF host (WebView2 PostWebMessageAsJson).
 */

export type ModuleState = 'ready' | 'applied' | 'blocked' | 'missing'

export type Dashboard = {
  version: string
  appVersion?: string
  playbookName: string
  actionCount: number
  state: ModuleState
  detail: string
  isAdmin: boolean
  osLabel: string
  specs: { cpu: string; gpu: string; ram: string }
}

export type LiveStats = {
  cpuPercent: number
  gpuPercent: number
  memoryPercent: number
  diskPercent: number
  memorySecondary: string
  diskSecondary: string
  netDownMbps: number | null
  netUpMbps: number | null
  netLink: string
}

export type OptionDef = {
  key: string
  label: string
  value: boolean
}

export type RunResult = {
  dryRun: boolean
  applied: number
  skipped: number
  failed: number
  log: string
}

type Pending = {
  resolve: (v: unknown) => void
  reject: (e: Error) => void
}

const pending = new Map<number, Pending>()
let nextId = 1
const listeners = new Map<string, Set<(data: unknown) => void>>()

function chrome() {
  return (window as unknown as { chrome?: { webview?: { postMessage: (m: unknown) => void } } }).chrome
}

export function initHost() {
  const wv = chrome()?.webview
  if (!wv) return
  // WebView2: addEventListener on window for messages from host
  window.chrome.webview.addEventListener('message', (ev: MessageEvent) => {
    const msg = ev.data as Record<string, unknown>
    if (!msg || typeof msg !== 'object') return
    if (typeof msg.event === 'string') {
      const set = listeners.get(msg.event)
      if (set) for (const fn of set) fn(msg.data)
      return
    }
    const id = msg.id as number | undefined
    if (id == null) return
    const p = pending.get(id)
    if (!p) return
    pending.delete(id)
    if (msg.error) p.reject(new Error(String(msg.error)))
    else p.resolve(msg.result)
  })
}

declare global {
  interface Window {
    chrome: {
      webview: {
        postMessage: (message: unknown) => void
        addEventListener: (type: string, listener: (ev: MessageEvent) => void) => void
      }
    }
  }
}

function call<T>(method: string, params?: Record<string, unknown>): Promise<T> {
  const id = nextId++
  return new Promise<T>((resolve, reject) => {
    pending.set(id, {
      resolve: (v) => resolve(v as T),
      reject,
    })
    const wv = chrome()?.webview
    if (!wv) {
      pending.delete(id)
      reject(new Error('Host bridge not available'))
      return
    }
    wv.postMessage({ id, method, params: params ?? {} })
  })
}

export function onHostEvent(event: string, fn: (data: unknown) => void) {
  let set = listeners.get(event)
  if (!set) {
    set = new Set()
    listeners.set(event, set)
  }
  set.add(fn)
  return () => set!.delete(fn)
}

export type OnboardingState = {
  complete: boolean
}

export const host = {
  getDashboard: () => call<Dashboard>('getDashboard'),
  getLive: () => call<LiveStats>('getLive'),
  getOptions: () => call<OptionDef[]>('getOptions'),
  setOptions: (options: Record<string, boolean>) => call<void>('setOptions', { options }),
  preview: () => call<RunResult>('preview'),
  apply: (_confirm?: string) => call<RunResult>('apply', {}),
  close: () => call<void>('close'),
  drag: () => call<void>('drag'),
  openDocs: () => call<void>('openDocs'),
  openUrl: (url: string) => call<void>('openUrl', { url }),
  getOnboarding: () => call<OnboardingState>('getOnboarding'),
  completeOnboarding: (answers?: unknown) =>
    call<void>('completeOnboarding', { answers: answers ?? {} }),
  resetOnboarding: () => call<void>('resetOnboarding'),
}
