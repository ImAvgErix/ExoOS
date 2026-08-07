/**
 * Drives the real answersToOptions export from Onboarding.tsx via dynamic import.
 * Run: node --experimental-strip-types  OR  npx tsx src/answersToOptions.test.mjs
 * Fallback: parse Onboarding.tsx is NOT used — we import the shipped module.
 */
import { createRequire } from 'module'
import { pathToFileURL } from 'url'
import { dirname, join } from 'path'
import { fileURLToPath } from 'url'
import { readFileSync, writeFileSync, mkdirSync } from 'fs'
import { transformSync } from 'esbuild'

const __dirname = dirname(fileURLToPath(import.meta.url))
const srcPath = join(__dirname, 'Onboarding.tsx')
const outDir = join(__dirname, '..', '.test-out')
mkdirSync(outDir, { recursive: true })
const outFile = join(outDir, 'Onboarding.test-bundle.mjs')

// Bundle only the answersToOptions export by transforming the TSX with esbuild (real source).
const source = readFileSync(srcPath, 'utf8')
// Strip React component noise by transforming whole file — esbuild handles TSX.
const result = transformSync(source, {
  loader: 'tsx',
  format: 'esm',
  target: 'es2022',
  jsx: 'automatic',
})
// Write transformed module; stub react imports so Node can load answersToOptions only.
const stubbed = result.code
  .replace(/from\s+['"]react['"]/g, "from 'data:text/javascript,export default {};export const useEffect=()=>{};export const useMemo=(f)=>f();export const useRef=()=>({current:null});export const useState=(v)=>[v,()=>{}];'")
  .replace(/from\s+['"]lucide-react['"]/g, "from 'data:text/javascript,export const Check=()=>null;export const ChevronLeft=()=>null;'")
  .replace(/from\s+['"]\.\/lib\/utils['"]/g, "from 'data:text/javascript,export const cn=(...a)=>a.filter(Boolean).join(\" \");'")
  .replace(/from\s+['"]\.\/lib\/host['"]/g, "from 'data:text/javascript,export const host={};'")
  .replace(/from\s+['"]\.\/WindowChrome['"]/g, "from 'data:text/javascript,export const WindowChrome=()=>null;'")
  .replace(/from\s+['"]\.\/motion['"]/g, "from 'data:text/javascript,export const CascadeTitle=()=>null;export const FadeIn=()=>null;export const StageSwap=()=>null;export const Stagger=()=>null;'")

writeFileSync(outFile, stubbed)

const mod = await import(pathToFileURL(outFile).href)
const { answersToOptions } = mod
if (typeof answersToOptions !== 'function') {
  console.error('FAIL: answersToOptions not exported from Onboarding.tsx')
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
