#Requires -RunAsAdministrator
# Exo verification auditor — MS-docs + live truth, not Twitter hype.
# Flags cargo-cult values, contradictory YAML, and live misconfigurations.
# Exit 0 = report written; review Verdict column.
$ErrorActionPreference = 'Continue'
$OutDir = Join-Path $env:ProgramData 'ExoOS'
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
$Report = Join-Path $OutDir 'verification-audit.txt'
$PlaybookRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path

$rows = New-Object System.Collections.Generic.List[object]

function Add-Row($Id, $Layer, $Claim, $Evidence, $Live, $Verdict, $Action) {
  $rows.Add([pscustomobject]@{
    Id = $Id; Layer = $Layer; Claim = $Claim; Evidence = $Evidence
    Live = $Live; Verdict = $Verdict; Action = $Action
  }) | Out-Null
}

function Get-RegDword($Path, $Name) {
  try {
    $p = Get-ItemProperty -LiteralPath $Path -ErrorAction Stop
    return $p.$Name
  } catch { return $null }
}

Write-Host '[Exo Audit] Starting verified-sources audit...'

# ── 1) SystemResponsiveness (MS official) ──────────────────────────────────
# https://learn.microsoft.com/windows/win32/procthread/multimedia-class-scheduler-service
# "Values below 10 and above 100 are clamped to 20."
$sr = Get-RegDword 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile' 'SystemResponsiveness'
$srN = if ($null -eq $sr) { $null } else { [int]$sr }
$effective = if ($null -eq $srN) { 20 }
  elseif ($srN -eq 100) { 'DISABLED_MMCSS' }
  elseif ($srN -lt 10 -or $srN -gt 100) { 20 }
  else { [math]::Floor($srN / 10) * 10 }

if ($srN -eq 0 -or ($srN -lt 10 -and $null -ne $srN)) {
  Add-Row 'MMCSS-SR' 'MMCSS' 'SystemResponsiveness=0 is "max gaming"' `
    'MS: values <10 clamp to 20 (default). 0 does NOT free the CPU for games.' `
    "registry=$srN effective=$effective" 'FAIL_HYPE' 'Set decimal 10 (min valid reserve)'
} elseif ($srN -eq 10) {
  Add-Row 'MMCSS-SR' 'MMCSS' 'SystemResponsiveness=10' `
    'MS: 10% reserved for low-priority; lowest valid non-default reserve.' `
    "registry=$srN effective=$effective" 'PASS_MS' 'Keep 10'
} elseif ($srN -eq 20 -or $null -eq $srN) {
  Add-Row 'MMCSS-SR' 'MMCSS' 'SystemResponsiveness default/20' `
    'MS default behavior (20% low-priority reserve).' `
    "registry=$srN effective=$effective" 'OK_STOCK' 'Optional: set 10 for gaming'
} else {
  Add-Row 'MMCSS-SR' 'MMCSS' "SystemResponsiveness=$srN" `
    'MS: multiples of 10; 100 disables MMCSS.' `
    "registry=$srN effective=$effective" 'REVIEW' 'Confirm intent'
}

# ── 2) Games MMCSS task (MS official table) ────────────────────────────────
$gPath = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile\Tasks\Games'
$gSched = Get-RegDword $gPath 'Scheduling Category'
if ($null -eq $gSched) {
  try { $gSched = (Get-ItemProperty $gPath -EA Stop).'Scheduling Category' } catch { }
}
$gPrio = $null
try { $gPrio = (Get-ItemProperty $gPath -EA Stop).Priority } catch { }
$gGpu = $null
try { $gGpu = (Get-ItemProperty $gPath -EA Stop).'GPU Priority' } catch { }
$gSfio = $null
try { $gSfio = (Get-ItemProperty $gPath -EA Stop).'SFIO Priority' } catch { }

Add-Row 'MMCSS-SCHED' 'MMCSS' 'Games Scheduling Category' `
  'MS: High/Medium/Low sets thread priority band. High = primary meaningful Games key.' `
  "Scheduling=$gSched" $(if ($gSched -eq 'High') { 'PASS_MS' } else { 'OK_STOCK' }) `
  $(if ($gSched -eq 'High') { 'OK' } else { 'Consider High for MMCSS Games clients' })

Add-Row 'MMCSS-PRIO' 'MMCSS' "Games Priority=$gPrio with High" `
  'MS: "For tasks with a Scheduling Category of High, this value is always treated as 2."' `
  "Priority=$gPrio Sched=$gSched" `
  $(if ($gSched -eq 'High' -and $gPrio -and [int]$gPrio -ne 2) { 'THEATER' } else { 'OK' }) `
  'Do not market Priority=6 under High as a boost'

Add-Row 'MMCSS-GPU' 'MMCSS' "Games GPU Priority=$gGpu" `
  'MS: "This priority is not yet used."' `
  "GPU Priority=$gGpu" $(if ($null -ne $gGpu) { 'THEATER' } else { 'OK' }) `
  'Safe to omit; no documented effect'

Add-Row 'MMCSS-SFIO' 'MMCSS' "Games SFIO Priority=$gSfio" `
  'MS: "This value is not used."' `
  "SFIO=$gSfio" $(if ($gSfio -and $gSfio -ne 'Normal') { 'THEATER' } else { 'OK' }) `
  'Safe to omit'

# ── 3) NetworkThrottlingIndex ──────────────────────────────────────────────
$nt = Get-RegDword 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile' 'NetworkThrottlingIndex'
$ntU = if ($null -eq $nt) { $null } else { [uint32]$nt }
# Default is 10 packets/ms for non-multimedia; ffffffff disables. Not in same MS page but well-known MMCSS throttle.
$ntVerdict = if ($null -eq $ntU) { 'OK_STOCK' }
  elseif ($ntU -eq 10) { 'OK_STOCK' }
  elseif ($ntU -eq [uint32]::MaxValue) { 'PASS_COMMON' }
  else { 'REVIEW' }
Add-Row 'MMCSS-NET' 'MMCSS' "NetworkThrottlingIndex=$ntU" `
  'Default 10 (packets/ms multimedia throttle). 0xFFFFFFFF disables. Not the same page as SystemResponsiveness but long-standing MMCSS behavior.' `
  "value=$ntU" $ntVerdict 'ffffffff OK for gaming; 10 is stock'

# ── 4) Win32PrioritySeparation ─────────────────────────────────────────────
$w32 = Get-RegDword 'HKLM:\SYSTEM\CurrentControlSet\Control\PriorityControl' 'Win32PrioritySeparation'
# Documented historically in Windows Internals (not a single MS "set this for gaming" page).
# 2 = common stock; 0x26=38 short/variable/high FG — community+Internals bit model.
Add-Row 'SCHED-W32' 'Scheduler' "Win32PrioritySeparation=$w32" `
  'Bitfield (quantum length / variable|fixed / FG boost). Stock often 2. 0x26=38 is Programs-style short+variable+high FG. Not a free FPS switch; feel/quantum tradeoff.' `
  "value=$w32 (0x$('{0:X}' -f [int]$w32))" 'REVIEW_INTERNALS' 'Keep only if intentional; measure input feel'

# ── 5) HAGS ────────────────────────────────────────────────────────────────
$hags = Get-RegDword 'HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers' 'HwSchMode'
# 2 = enable. Microsoft UI exposes this; mixed game results but real mechanism.
Add-Row 'GPU-HAGS' 'GPU' "HwSchMode=$hags" `
  'Hardware-accelerated GPU scheduling. 2=on. Real Windows setting; per-title variance.' `
  "value=$hags" $(if ($hags -eq 2) { 'PASS_REAL' } else { 'OK_STOCK' }) 'On is reasonable default for modern dGPU'

# ── 6) GlobalTimerResolutionRequests ───────────────────────────────────────
$gtr = Get-RegDword 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\kernel' 'GlobalTimerResolutionRequests'
# Win11 2004+ broke global timer; this re-enables processes requesting 1ms etc. Real issue.
Add-Row 'KERN-TIMER' 'Kernel' "GlobalTimerResolutionRequests=$gtr" `
  'Win11 changed timer resolution request semantics. 1 restores process ability to raise global resolution. Real, not hype.' `
  "value=$gtr" $(if ($gtr -eq 1) { 'PASS_REAL' } else { 'REVIEW' }) '1 recommended on Win11 gaming'

# ── 7) BCD timer ───────────────────────────────────────────────────────────
$bcd = (bcdedit /enum '{current}' 2>$null | Out-String)
$dyn = if ($bcd -match 'disabledynamictick\s+Yes') { 'Yes' } else { 'No/default' }
$pt = if ($bcd -match 'useplatformtick\s+Yes') { 'Yes' } else { 'No/default' }
Add-Row 'BCD-TICK' 'BCD' "disabledynamictick=$dyn useplatformtick=$pt" `
  'Community latency stack. Mixed Blur Busters results; not MS gaming guidance. Measure before treating as required.' `
  "dyn=$dyn platformtick=$pt" 'REVIEW_MEASURE' 'Optional; do not claim free FPS'

# ── 8) Power plan present ──────────────────────────────────────────────────
$active = (powercfg /getactivescheme 2>$null | Out-String).Trim()
Add-Row 'POWER' 'Power' 'Active scheme' `
  'Platform-specific power indices (unpark, EPP, USB suspend) are real powercfg settings. .pow import exit codes can lie.' `
  $active 'PASS_REAL' 'Keep platform detection (AM4/AM5/Intel)'

# ── 9) Prefetch / SysMain extreme ──────────────────────────────────────────
$pref = Get-RegDword 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management\PrefetchParameters' 'EnablePrefetcher'
$sys = Get-Service SysMain -EA SilentlyContinue
Add-Row 'MEM-PREFETCH' 'Memory' "Prefetch=$pref SysMain=$($sys.StartType)/$($sys.Status)" `
  'Disabling SysMain/prefetch on SSD is common but not always a win (some titles use Superfetch). Tradeoff, not free FPS.' `
  "prefetch=$pref sysmain=$($sys.StartType)" 'TRADEOFF' 'Extreme-only is OK; do not force on Balanced'

# ── 10) Nagle ──────────────────────────────────────────────────────────────
$nagleHit = 0
Get-ChildItem 'HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters\Interfaces' -EA SilentlyContinue | ForEach-Object {
  $ip = Get-ItemProperty $_.PSPath -EA SilentlyContinue
  if ($ip.TCPNoDelay -eq 1 -or $ip.TcpAckFrequency -eq 1) { $nagleHit++ }
}
Add-Row 'NET-NAGLE' 'Network' "Nagle overrides on $nagleHit interface(s)" `
  'TcpNoDelay/TcpAckFrequency reduce small-packet delay. Real TCP knobs; helps some games, irrelevant offline.' `
  "interfaces_touched=$nagleHit" $(if ($nagleHit -gt 0) { 'PASS_REAL' } else { 'OK_STOCK' }) 'OK for online gaming'

# ── 11) Scan playbook YAML for known-bad SystemResponsiveness: 0 ───────────
$yamlHits = @()
Get-ChildItem -Path (Join-Path $PlaybookRoot 'actions') -Recurse -Include *.yml,*.yaml -EA SilentlyContinue | ForEach-Object {
  $txt = Get-Content $_.FullName -Raw -EA SilentlyContinue
  if ($txt -match "SystemResponsiveness[\s\S]{0,120}value:\s*['\`"]?0['\`"]?") {
    $yamlHits += $_.FullName.Replace($PlaybookRoot, '.')
  }
}
Add-Row 'YAML-SR0' 'Playbook' 'YAML still sets SystemResponsiveness=0' `
  'Any remaining 0 is a known-bad cargo-cult value per MS clamp rules.' `
  $(if ($yamlHits.Count) { ($yamlHits -join '; ') } else { 'none' }) `
  $(if ($yamlHits.Count) { 'FAIL_YAML' } else { 'PASS_CLEAN' }) `
  'Replace all with 10'

# ── 12) Count actions (scale of audit debt) ────────────────────────────────
$actionCount = 0
Get-ChildItem -Path (Join-Path $PlaybookRoot 'actions') -Recurse -Include *.yml,*.yaml -EA SilentlyContinue | ForEach-Object {
  $c = (Select-String -Path $_.FullName -Pattern '^\s*-\s*type:\s*' -AllMatches).Matches.Count
  $actionCount += $c
}
Add-Row 'SCALE' 'Meta' "Playbook action nodes ~$actionCount" `
  'Bulk baseline merges (Atlas/Revi/Winhance/…) are NOT individually MS-verified. Treat as untrusted until audited.' `
  "count=$actionCount" 'AUDIT_DEBT' 'Prioritize kernel/MMCSS/power/network; quarantine hype merges'

# ── Write report ───────────────────────────────────────────────────────────
$sb = New-Object System.Text.StringBuilder
[void]$sb.AppendLine("Exo Verified Audit  $(Get-Date -Format o)")
[void]$sb.AppendLine("Source of truth for MMCSS: Microsoft Learn multimedia-class-scheduler-service")
[void]$sb.AppendLine("Verdicts: PASS_MS / PASS_REAL / PASS_COMMON / OK_STOCK / THEATER / FAIL_HYPE / FAIL_YAML / TRADEOFF / REVIEW* / AUDIT_DEBT")
[void]$sb.AppendLine('')
foreach ($r in $rows) {
  [void]$sb.AppendLine("[$($r.Verdict)] $($r.Id) | $($r.Layer)")
  [void]$sb.AppendLine("  Claim:    $($r.Claim)")
  [void]$sb.AppendLine("  Evidence: $($r.Evidence)")
  [void]$sb.AppendLine("  Live:     $($r.Live)")
  [void]$sb.AppendLine("  Action:   $($r.Action)")
  [void]$sb.AppendLine('')
}
$fail = @($rows | Where-Object { $_.Verdict -match 'FAIL|THEATER' })
[void]$sb.AppendLine("--- SUMMARY ---")
[void]$sb.AppendLine("Total checks: $($rows.Count)")
[void]$sb.AppendLine("Fail/Theater: $($fail.Count)")
[void]$sb.AppendLine(($fail | ForEach-Object { $_.Id }) -join ', ')

$sb.ToString() | Set-Content -Path $Report -Encoding UTF8
Write-Host $sb.ToString()
Write-Host "[Exo Audit] Wrote $Report"
exit 0
