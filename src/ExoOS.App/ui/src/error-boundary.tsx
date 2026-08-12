import { Component, type ErrorInfo, type ReactNode } from 'react'

type Props = { children: ReactNode }
type State = { message: string | null }

export class ErrorBoundary extends Component<Props, State> {
  state: State = { message: null }

  static getDerivedStateFromError(err: Error): State {
    return { message: err.message || 'Something went wrong' }
  }

  componentDidCatch(err: Error, info: ErrorInfo) {
    console.error(err, info.componentStack)
  }

  render() {
    if (!this.state.message) return this.props.children
    return (
      <div className="exo-app flex h-dvh items-center justify-center bg-bg px-8 text-center text-fg">
        <div className="max-w-sm">
          <p className="text-[17px] font-semibold tracking-tight">Couldn’t load Exo OS</p>
          <p className="mt-2 text-[13px] leading-relaxed text-muted">{this.state.message}</p>
        </div>
      </div>
    )
  }
}
