import { StrictMode } from 'react'
import { createRoot } from 'react-dom/client'
import '@fontsource-variable/geist'
import './exo-shell.css'
import './tweaks.css'
import { App } from './App'
import { ErrorBoundary } from './error-boundary'
import { initHost } from './lib/host'

initHost()

createRoot(document.getElementById('root')!).render(
  <StrictMode>
    <ErrorBoundary>
      <App />
    </ErrorBoundary>
  </StrictMode>,
)
