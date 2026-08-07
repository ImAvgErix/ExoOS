#!/usr/bin/env node
/**
 * Exo OS PC Control
 * -----------------
 * Cua Driver 0.19 explicitly cannot typed-mutate WebView2 (split Chromium process).
 * UIA only sees the native title bar (Settings + Close). Pixel clicks on Chromium
 * need foreground SendInput and still miss when coordinates drift.
 *
 * This tool attaches to WebView2 via CDP (EXOOS_CDP=1 → --remote-debugging-port)
 * and drives the React UI with real DOM selectors / accessible names.
 *
 * Usage:
 *   node cli.mjs status
 *   node cli.mjs shot [path]
 *   node cli.mjs click "Continue"
 *   node cli.mjs click-role button "Continue"
 *   node cli.mjs text
 *   node cli.mjs verify          # full onboarding → home → apply (no docs/github)
 *   node cli.mjs eval "document.title"
 */

import { chromium } from 'playwright-core'
import { mkdir, writeFile } from 'node:fs/promises'
import { dirname, resolve } from 'node:path'
import { fileURLToPath } from 'node:url'

const __dirname = dirname(fileURLToPath(import.meta.url))
const DEFAULT_PORT = Number(process.env.EXOOS_CDP_PORT || 9229)
const DEFAULT_SHOT = resolve(__dirname, '../../docs/media/pc-control')

async function connect(port = DEFAULT_PORT) {
  const endpoint = `http://127.0.0.1:${port}`
  let browser
  try {
    browser = await chromium.connectOverCDP(endpoint, { timeout: 8000 })
  } catch (e) {
    throw new Error(
      `Cannot attach CDP at ${endpoint}.\n` +
        `Launch Exo OS with EXOOS_CDP=1 (or EXOOS_CDP_PORT=${port}).\n` +
        `Detail: ${e.message}`,
    )
  }
  const context = browser.contexts()[0]
  if (!context) throw new Error('CDP connected but no browser context (WebView2 not ready)')
  const page = context.pages()[0] || (await context.newPage())
  // Prefer the exoos virtual host page
  const pages = context.pages()
  const exo = pages.find((p) => /exoos\.local|localhost|index\.html/i.test(p.url())) || page
  return { browser, context, page: exo, pages }
}

async function waitReady(page, ms = 8000) {
  await page.waitForLoadState('domcontentloaded', { timeout: ms }).catch(() => {})
  // React root mounted
  await page.waitForFunction(
    () => {
      const r = document.getElementById('root')
      return r && r.childElementCount > 0
    },
    null,
    { timeout: ms },
  )
}

async function visibleText(page) {
  return page.evaluate(() => {
    const skip = new Set(['SCRIPT', 'STYLE', 'NOSCRIPT'])
    const walk = (n, acc) => {
      if (!n) return acc
      if (n.nodeType === 3) {
        const t = n.textContent?.replace(/\s+/g, ' ').trim()
        if (t) acc.push(t)
        return acc
      }
      if (n.nodeType === 1 && !skip.has(n.tagName)) {
        for (const c of n.childNodes) walk(c, acc)
      }
      return acc
    }
    return walk(document.body, []).join(' · ').slice(0, 4000)
  })
}

async function shot(page, outPath) {
  await mkdir(dirname(outPath), { recursive: true })
  await page.screenshot({ path: outPath, fullPage: false })
  return outPath
}

/** Click by exact or partial accessible name / visible text. Never opens external links. */
async function clickLabel(page, label, { timeout = 6000 } = {}) {
  const name = String(label)
  // Block navigation away from the app
  page.once('popup', async (p) => {
    await p.close().catch(() => {})
  })

  const candidates = [
    page.getByRole('button', { name: new RegExp(`^${escapeRe(name)}$`, 'i') }),
    page.getByRole('radio', { name: new RegExp(escapeRe(name), 'i') }),
    page.getByRole('menuitem', { name: new RegExp(escapeRe(name), 'i') }),
    page.getByLabel(new RegExp(escapeRe(name), 'i')),
    page.getByText(name, { exact: true }),
    page.getByText(new RegExp(escapeRe(name), 'i')),
  ]

  let lastErr
  for (const loc of candidates) {
    try {
      const target = loc.first()
      await target.waitFor({ state: 'visible', timeout: Math.min(timeout, 2500) })
      await target.click({ timeout: 3000 })
      return { ok: true, matched: name }
    } catch (e) {
      lastErr = e
    }
  }
  throw new Error(`No clickable control matching "${name}". Last: ${lastErr?.message || lastErr}`)
}

function escapeRe(s) {
  return s.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')
}

async function cmdStatus() {
  const { browser, page, pages } = await connect()
  try {
    await waitReady(page)
    const text = await visibleText(page)
    console.log(
      JSON.stringify(
        {
          ok: true,
          url: page.url(),
          title: await page.title(),
          pages: pages.map((p) => p.url()),
          textPreview: text.slice(0, 500),
        },
        null,
        2,
      ),
    )
  } finally {
    await browser.close().catch(() => {})
  }
}

async function cmdShot(out) {
  const { browser, page } = await connect()
  try {
    await waitReady(page)
    const path = resolve(out || `${DEFAULT_SHOT}/shot-${Date.now()}.png`)
    await shot(page, path)
    console.log(JSON.stringify({ ok: true, path, url: page.url() }))
  } finally {
    await browser.close().catch(() => {})
  }
}

async function cmdClick(label) {
  if (!label) throw new Error('Usage: click <label>')
  // Safety: never click Documentation (opens GitHub)
  if (/documentation|github|docs/i.test(label)) {
    throw new Error('Refusing to click Documentation/GitHub — that opens an external browser.')
  }
  const { browser, page } = await connect()
  try {
    await waitReady(page)
    const before = await visibleText(page)
    const r = await clickLabel(page, label)
    await new Promise((r) => setTimeout(r, 400))
    const after = await visibleText(page)
    console.log(
      JSON.stringify({
        ok: true,
        ...r,
        changed: before !== after,
        textPreview: after.slice(0, 400),
      }),
    )
  } finally {
    await browser.close().catch(() => {})
  }
}

async function cmdText() {
  const { browser, page } = await connect()
  try {
    await waitReady(page)
    console.log(await visibleText(page))
  } finally {
    await browser.close().catch(() => {})
  }
}

async function cmdEval(expr) {
  if (!expr) throw new Error('Usage: eval <js>')
  const { browser, page } = await connect()
  try {
    await waitReady(page)
    const result = await page.evaluate(expr)
    console.log(JSON.stringify({ ok: true, result }, null, 2))
  } finally {
    await browser.close().catch(() => {})
  }
}

/**
 * Full product verify — no Settings Documentation, no GitHub, no live Apply.
 * Walks setup → home → apply, screenshots each step.
 */
async function cmdVerify() {
  const { browser, page } = await connect()
  const outDir = resolve(DEFAULT_SHOT)
  await mkdir(outDir, { recursive: true })
  const log = []

  const step = async (name, fn) => {
    try {
      await fn()
      const path = resolve(outDir, `${String(log.length + 1).padStart(2, '0')}-${name}.png`)
      await shot(page, path)
      const text = await visibleText(page)
      log.push({ step: name, ok: true, path, textPreview: text.slice(0, 280) })
      console.error(`✓ ${name}`)
    } catch (e) {
      const path = resolve(outDir, `${String(log.length + 1).padStart(2, '0')}-${name}-FAIL.png`)
      await shot(page, path).catch(() => {})
      log.push({ step: name, ok: false, error: e.message, path })
      console.error(`✗ ${name}: ${e.message}`)
      throw e
    }
  }

  try {
    await waitReady(page)

    // If already past onboarding, go home for branding check
    let text = await visibleText(page)
    if (/Welcome to Exo OS/i.test(text)) {
      await step('welcome', async () => {
        /* already here — CTA is Get started, not Continue */
      })
      // welcome → goal
      await step('goal', async () => {
        await clickLabel(page, 'Get started')
        await new Promise((r) => setTimeout(r, 400))
      })
      // goal → defender → cleanup → services → browsers → extras → apps → ready
      for (const name of ['defender', 'cleanup', 'services', 'browsers', 'extras', 'apps', 'ready']) {
        await step(name, async () => {
          await clickLabel(page, 'Continue')
          await new Promise((r) => setTimeout(r, 400))
        })
      }
      // ready → plan shell (Finish setup)
      await step('open-app', async () => {
        try {
          await clickLabel(page, 'Finish setup')
        } catch {
          try {
            await clickLabel(page, 'Open Exo OS')
          } catch {
            await clickLabel(page, 'Continue')
          }
        }
        // HostBridge save can take a moment
        await page
          .waitForFunction(
            () => /Your plan|Apply plan|actions ready/i.test(document.body?.innerText || ''),
            null,
            { timeout: 10000 },
          )
          .catch(() => {})
        await new Promise((r) => setTimeout(r, 400))
      })
    } else {
      log.push({ step: 'onboarding-skip', ok: true, note: 'already complete', textPreview: text.slice(0, 200) })
      console.error('· onboarding already complete — checking shell')
    }

    text = await visibleText(page)
    // Plan shell (post-setup) — no separate dashboard
    if (!/Exo OS|Your plan|Apply plan|actions ready/i.test(text)) {
      throw new Error(`Expected plan shell after setup. Got: ${text.slice(0, 200)}`)
    }

    // Plan shell only — NEVER click "Apply plan" (UI apply is LIVE and mutates the host).
    await step('plan-shell', async () => {
      const t = await visibleText(page)
      if (!/Your plan|Apply plan|actions ready/i.test(t)) {
        throw new Error(`Plan shell not visible: ${t.slice(0, 200)}`)
      }
      // Assert CTA exists but do not activate it
      const applyBtn = page.getByRole('button', { name: /Apply plan|Run again/i }).first()
      await applyBtn.waitFor({ state: 'visible', timeout: 5000 })
    })

    text = await visibleText(page)
    const allText = log.map((l) => l.textPreview || '').join(' · ') + ' · ' + text
    const checks = {
      hasExoOS: /Exo OS|Your plan/i.test(allText),
      hasApplyCta: /Apply plan|Run again/i.test(text),
      hasActionCount: /2,?859|actions ready/i.test(allText),
      // Legacy confirm UX must stay gone (do not flag "Terminal Preview" etc.)
      noTypeConfirm: !/type\s+EXOOS|confirm.*EXOOS/i.test(allText),
      walkedOnboarding: log.filter((l) => l.ok && /welcome|goal|ready|open-app/.test(l.step)).length >= 3,
      didNotLiveApply: !/^\d+%$/.test(text) && !log.some((l) => /%/.test(l.textPreview || '')),
    }

    const report = { ok: Object.values(checks).every(Boolean), checks, log }
    const reportPath = resolve(outDir, 'verify-report.json')
    await writeFile(reportPath, JSON.stringify(report, null, 2))
    console.log(JSON.stringify(report, null, 2))
    if (!report.ok) process.exitCode = 2
  } finally {
    await browser.close().catch(() => {})
  }
}

async function main() {
  const [cmd, ...rest] = process.argv.slice(2)
  switch (cmd) {
    case 'status':
      return cmdStatus()
    case 'shot':
      return cmdShot(rest[0])
    case 'click':
      return cmdClick(rest.join(' '))
    case 'click-role':
      // click-role button Continue
      return cmdClick(rest.slice(1).join(' ') || rest[0])
    case 'text':
      return cmdText()
    case 'eval':
      return cmdEval(rest.join(' '))
    case 'verify':
      return cmdVerify()
    case undefined:
    case 'help':
    case '-h':
    case '--help':
      console.log(`exoos-pc-control — WebView2 CDP driver (better than Cua for this app)

  status              attach + dump page text
  shot [path]         screenshot
  click <label>       click button/radio by name (blocks Documentation)
  text                full visible text
  eval <js>           page.evaluate
  verify              onboarding → home → apply + checks (no GitHub)

Env: EXOOS_CDP_PORT (default 9229)
Launch app:  $env:EXOOS_CDP=1; .\\ExoOS.exe
`)
      return
    default:
      throw new Error(`Unknown command: ${cmd}`)
  }
}

main().catch((e) => {
  console.error(e.message || e)
  process.exit(1)
})
