/**
 * Drives answersToOptions / DEFAULT_ANSWERS from onboarding-model.ts
 * Run from ui/: node --experimental-strip-types src/answersToOptions.test.mjs
 * Fallback: esbuild transform when strip-types is unavailable.
 */
import { pathToFileURL } from 'url'
import { dirname, join } from 'path'
import { fileURLToPath } from 'url'
import { readFileSync, writeFileSync, mkdirSync } from 'fs'
import { transformSync } from 'esbuild'

const __dirname = dirname(fileURLToPath(import.meta.url))
const srcPath = join(__dirname, 'onboarding-model.ts')
const outDir = join(__dirname, '..', '.test-out')
mkdirSync(outDir, { recursive: true })
const outFile = join(outDir, 'onboarding-model.test-bundle.mjs')

const source = readFileSync(srcPath, 'utf8')
const result = transformSync(source, {
  loader: 'ts',
  format: 'esm',
  target: 'es2022',
})
writeFileSync(outFile, result.code)

const mod = await import(pathToFileURL(outFile).href)
const { answersToOptions, DEFAULT_ANSWERS } = mod
if (typeof answersToOptions !== 'function') {
  console.error('FAIL: answersToOptions not exported from onboarding-model.ts')
  process.exit(1)
}

const base = {
  goal: 'balanced',
  defender: 'keep',
  cleanup: 'no',
  services: 'leave',
  browsers: [],
  extras: ['7zip'],
  apps: [],
}

function assert(cond, msg) {
  if (!cond) {
    console.error('FAIL:', msg)
    process.exit(1)
  }
  console.log('OK:', msg)
}

assert(DEFAULT_ANSWERS.goal === 'fps', 'DEFAULT_ANSWERS: Maximum FPS goal')
assert(DEFAULT_ANSWERS.defender === 'strip', 'DEFAULT_ANSWERS: strip defender')
const defOpts = answersToOptions(DEFAULT_ANSWERS)
assert(defOpts.extremeMode === true, 'DEFAULT_ANSWERS map: extremeMode true')
assert(defOpts.defenderStrip === true, 'DEFAULT_ANSWERS map: defenderStrip true')
assert(defOpts.dismStrip === true, 'DEFAULT_ANSWERS map: dismStrip true')
assert(defOpts.disableVbs === true, 'DEFAULT_ANSWERS map: disableVbs true')
assert(defOpts.stripEdge === true, 'DEFAULT_ANSWERS map: stripEdge true')
assert(defOpts.serviceStrip === true, 'DEFAULT_ANSWERS map: serviceStrip true')

const bal = answersToOptions({ ...base, goal: 'balanced' })
assert(bal.extremeMode === false, 'Balanced: extremeMode false')
assert(bal.dismStrip === false, 'Balanced: dismStrip false')
assert(bal.disableVbs === false, 'Balanced: disableVbs false')
assert(bal.serviceStrip === false, 'Balanced leave services: serviceStrip false')
assert(bal.defenderStrip === false, 'Balanced keep defender: defenderStrip false')
assert(bal.stripEdge === false, 'Balanced: stripEdge false (browsers kept)')
assert(bal.installDirectX === true, 'Balanced: DirectX install still true')

const balQuiet = answersToOptions({ ...base, goal: 'balanced', services: 'quiet' })
assert(balQuiet.serviceStrip === true, 'Balanced quiet: serviceStrip true')
assert(balQuiet.extremeMode === false, 'Balanced quiet: still not extremeMode')
assert(balQuiet.stripEdge === false, 'Balanced quiet: stripEdge still false')

const ext = answersToOptions({ ...base, goal: 'fps', defender: 'strip', services: 'quiet' })
assert(ext.extremeMode === true, 'Extreme fps: extremeMode true')
assert(ext.dismStrip === true, 'Extreme: dismStrip true')
assert(ext.disableVbs === true, 'Extreme: disableVbs true')
assert(ext.serviceStrip === true, 'Extreme: serviceStrip true')
assert(ext.defenderStrip === true, 'Extreme strip defender: defenderStrip true')
assert(ext.stripEdge === true, 'Extreme: stripEdge true (Edge is forced bloat; user browsers install separately)')

const balCleanup = answersToOptions({ ...base, goal: 'balanced', cleanup: 'yes' })
assert(balCleanup.stripEdge === true, 'Balanced + cleanup yes: stripEdge opt-in true')
assert(balCleanup.extremeMode === false, 'Balanced + cleanup: still not extremeMode')

const priv = answersToOptions({ ...base, goal: 'privacy' })
assert(priv.extremeMode === false, 'Privacy: not extremeMode')
assert(priv.serviceStrip === true, 'Privacy: serviceStrip true')
assert(priv.dismStrip === false, 'Privacy: no dismStrip')
assert(priv.stripEdge === false, 'Privacy: stripEdge false unless cleanup yes')

console.log('ALL answersToOptions checks passed')
