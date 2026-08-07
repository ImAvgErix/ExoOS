#Requires -Version 7
<#
.SYNOPSIS
  Reliable Exo OS UI verification via WebView2 CDP (not Cua pixel guessing).

.DESCRIPTION
  Cua Driver cannot typed-mutate WebView2. This script:
    1. Resets onboarding (registry + WebView2 profile)
    2. Launches ExoOS with EXOOS_CDP=1 (remote debugging port 9229)
    3. Runs tools/pc-control verify (Playwright DOM clicks)
    4. Never opens Documentation / GitHub

.PARAMETER Port
  CDP port (default 9229)

.PARAMETER SkipBuild
  Skip npm ui + dotnet build
#>
param(
  [int]$Port = 9229,
  [switch]$SkipBuild
)

$ErrorActionPreference = 'Stop'
$Repo = Resolve-Path (Join-Path $PSScriptRoot '..')
$Ui = Join-Path $Repo 'src\ExoOS.App\ui'
$AppProj = Join-Path $Repo 'src\ExoOS.App\ExoOS.App.csproj'
$Exe = Join-Path $Repo 'src\ExoOS.App\bin\Release\net10.0-windows\ExoOS.exe'
$Pc = Join-Path $Repo 'tools\pc-control'

function Write-Step($m) { Write-Host "`n==> $m" -ForegroundColor Cyan }

# Kill previous
Get-Process -Name ExoOS -ErrorAction SilentlyContinue | Stop-Process -Force
Start-Sleep -Milliseconds 400

if (-not $SkipBuild) {
  Write-Step 'Build UI'
  Push-Location $Ui
  npm run build
  Pop-Location
  Write-Step 'Build app'
  dotnet build $AppProj -c Release --nologo
}

if (-not (Test-Path $Exe)) { throw "Missing $Exe" }

Write-Step 'Reset onboarding (no UI clicks)'
reg add 'HKCU\Software\ExoOS' /v OnboardingComplete /t REG_DWORD /d 0 /f | Out-Null
$wv = Join-Path $env:LOCALAPPDATA 'ExoOS\WebView2'
if (Test-Path $wv) { Remove-Item -Recurse -Force $wv -ErrorAction SilentlyContinue }

Write-Step "Launch Exo OS with CDP on port $Port"
$env:EXOOS_CDP = '1'
$env:EXOOS_CDP_PORT = "$Port"
# Clear after child inherits
Start-Process -FilePath $Exe -WorkingDirectory (Split-Path $Exe)
Start-Sleep -Seconds 3

if (-not (Get-Process -Name ExoOS -ErrorAction SilentlyContinue)) {
  throw 'ExoOS failed to start'
}

# Wait for CDP port
Write-Step 'Wait for CDP'
$deadline = (Get-Date).AddSeconds(20)
$ready = $false
while ((Get-Date) -lt $deadline) {
  try {
    $r = Invoke-WebRequest -Uri "http://127.0.0.1:$Port/json/version" -UseBasicParsing -TimeoutSec 2
    if ($r.StatusCode -eq 200) { $ready = $true; break }
  } catch { Start-Sleep -Milliseconds 400 }
}
if (-not $ready) {
  Write-Warning "CDP port $Port not open — is EXOOS_CDP wired? Falling through; pc-control will error clearly."
}

Write-Step 'Install pc-control deps if needed'
Push-Location $Pc
if (-not (Test-Path 'node_modules\playwright-core')) {
  npm install --no-fund --no-audit
}
Write-Step 'Run DOM verify (no Documentation / no GitHub)'
$env:EXOOS_CDP_PORT = "$Port"
node .\cli.mjs verify
$code = $LASTEXITCODE
Pop-Location

Write-Host "`nDone. Screenshots: docs/media/pc-control/" -ForegroundColor Green
exit $code
