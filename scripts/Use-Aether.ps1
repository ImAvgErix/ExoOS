#Requires -Version 5.1
<#
.SYNOPSIS
  Exo OS + Aether Driver helper (until ego lite on Windows).

.EXAMPLE
  .\scripts\Use-Aether.ps1 -Launch
  .\scripts\Use-Aether.ps1 -Status
  .\scripts\Use-Aether.ps1 -Click "Continue"
  .\scripts\Use-Aether.ps1 -Verify
#>
param(
  [switch]$Launch,
  [switch]$Status,
  [switch]$Verify,
  [string]$Click,
  [int]$Port = 9229,
  [switch]$ResetOnboarding
)

$ErrorActionPreference = 'Stop'
$Repo = Split-Path $PSScriptRoot -Parent
$Py = "$env:LOCALAPPDATA\Programs\Python\Python312\python.exe"
$Aether = "$env:LOCALAPPDATA\Programs\Python\Python312\Scripts\aether.exe"
$Exe = Join-Path $Repo 'src\ExoOS.App\bin\Release\net10.0-windows\ExoOS.exe'

if (-not (Test-Path $Aether)) {
  if (-not (Test-Path $Py)) { throw "Python 3.12 not found. winget install Python.Python.3.12" }
  Write-Host "Installing aether-driver..."
  & $Py -m pip install -e (Join-Path $Repo 'tools\aether-driver')
  & $Py -m playwright install chromium
}

if ($ResetOnboarding) {
  reg add 'HKCU\Software\ExoOS' /v OnboardingComplete /t REG_DWORD /d 0 /f | Out-Null
  $wv = Join-Path $env:LOCALAPPDATA 'ExoOS\WebView2'
  if (Test-Path $wv) { Remove-Item -Recurse -Force $wv -ErrorAction SilentlyContinue }
  Write-Host "Onboarding reset."
}

if ($Launch) {
  Get-Process ExoOS -ErrorAction SilentlyContinue | Stop-Process -Force
  Start-Sleep -Milliseconds 400
  $env:EXOOS_CDP = '1'
  $env:EXOOS_CDP_PORT = "$Port"
  if (-not (Test-Path $Exe)) { throw "Build ExoOS first: dotnet build src\ExoOS.App -c Release" }
  Start-Process $Exe
  Write-Host "Launched Exo OS with CDP on $Port"
  $deadline = (Get-Date).AddSeconds(15)
  while ((Get-Date) -lt $deadline) {
    try {
      $r = Invoke-WebRequest "http://127.0.0.1:$Port/json/version" -UseBasicParsing -TimeoutSec 1
      if ($r.StatusCode -eq 200) { Write-Host "CDP ready."; break }
    } catch { Start-Sleep -Milliseconds 300 }
  }
}

if ($Status) { & $Aether cdp status --port $Port }
if ($Click) { & $Aether cdp click --port $Port --text $Click }
if ($Verify) {
  & $Aether cdp verify-exoos --port $Port --out-dir (Join-Path $Repo 'docs\media\aether')
}

if (-not ($Launch -or $Status -or $Verify -or $Click -or $ResetOnboarding)) {
  Write-Host @"
Use-Aether.ps1 — Exo OS helper (agent PC control is Aether-only; no Cua)

  -Launch              Start ExoOS with EXOOS_CDP=1
  -ResetOnboarding     Clear setup so Welcome shows
  -Status              CDP page text (if aether CLI present)
  -Click "Continue"    DOM click by label
  -Verify              Full onboarding walk
  -Port 9229

Agent stack: ~/.aether/aether-driver v1.1 Synthetic hands + MCP (prefer_cua=false).
"@
}
