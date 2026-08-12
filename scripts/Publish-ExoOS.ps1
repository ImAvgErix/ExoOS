#Requires -Version 5.1
<#
.SYNOPSIS
  Ship polish: build React UI, publish ExoOS + CLI, stage folder + zip under publish/
#>
$ErrorActionPreference = 'Stop'
$Root = Split-Path -Parent $PSScriptRoot
Set-Location $Root

$Version = (Get-Content (Join-Path $Root 'VERSION') -Raw).Trim()
if (-not $Version) { throw 'VERSION file missing or empty' }

$Stage = Join-Path $Root 'publish\ExoOS-win-x64'
$Zip = Join-Path $Root "publish\ExoOS-v$Version-win-x64.zip"
$Ui = Join-Path $Root 'src\ExoOS.App\ui'
$Www = Join-Path $Root 'src\ExoOS.App\wwwroot'

Write-Host "=== ExoOS ship $Version ===" -ForegroundColor Cyan

# 1) UI
if (-not (Test-Path (Join-Path $Ui 'package.json'))) { throw "UI missing: $Ui" }
Write-Host "Building UI…" -ForegroundColor Cyan
Push-Location $Ui
try {
  if (-not (Test-Path 'node_modules')) {
    npm ci 2>$null
    if ($LASTEXITCODE -ne 0) { npm install }
  }
  npm run build
  if ($LASTEXITCODE -ne 0) { throw "UI build failed ($LASTEXITCODE)" }
} finally {
  Pop-Location
}

# Vite outDir should be ../wwwroot — verify
if (-not (Test-Path (Join-Path $Www 'index.html'))) {
  throw "UI build did not produce wwwroot/index.html"
}
Write-Host "UI → wwwroot OK" -ForegroundColor Green

# 2) Clean stage
if (Test-Path $Stage) { Remove-Item $Stage -Recurse -Force }
New-Item -ItemType Directory -Path $Stage | Out-Null

# 3) Publish app (self-contained — no separate .NET install)
Write-Host "Publishing ExoOS.App (self-contained win-x64)…" -ForegroundColor Cyan
dotnet publish "$Root\src\ExoOS.App\ExoOS.App.csproj" `
  -c Release -r win-x64 --self-contained true `
  -p:Version=$Version -p:FileVersion=$Version -p:AssemblyVersion=$Version.0 `
  -p:PublishReadyToRun=false `
  -o $Stage
if ($LASTEXITCODE -ne 0) { throw "App publish failed" }

# 4) Publish CLI (self-contained)
Write-Host "Publishing ExoForge.Cli (self-contained win-x64)…" -ForegroundColor Cyan
$CliOut = Join-Path $Stage 'cli'
dotnet publish "$Root\src\ExoForge.Cli\ExoForge.Cli.csproj" `
  -c Release -r win-x64 --self-contained true `
  -p:Version=$Version `
  -o $CliOut
if ($LASTEXITCODE -ne 0) { throw "CLI publish failed" }

# 5) Ship docs into package
Copy-Item (Join-Path $Root 'VERSION') $Stage -Force
Copy-Item (Join-Path $Root 'LICENSE') $Stage -Force
Copy-Item (Join-Path $Root 'README.md') $Stage -Force
if (Test-Path (Join-Path $Root 'CHANGELOG.md')) {
  Copy-Item (Join-Path $Root 'CHANGELOG.md') $Stage -Force
}
if (Test-Path (Join-Path $Root 'SECURITY.md')) {
  Copy-Item (Join-Path $Root 'SECURITY.md') $Stage -Force
}
if (Test-Path (Join-Path $Root 'docs\SHIP.md')) {
  Copy-Item (Join-Path $Root 'docs\SHIP.md') $Stage -Force
}

# 6) BUILDINFO
$buildInfo = @"
ExoOS $Version
Built: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss K')
Machine: $env:COMPUTERNAME
User: $env:USERNAME
Playbook: playbooks/exoos (see playbook.yml version)
"@
Set-Content -Path (Join-Path $Stage 'BUILDINFO.txt') -Value $buildInfo -Encoding UTF8

# 7) Sanity
$exe = Join-Path $Stage 'ExoOS.exe'
$pb = Join-Path $Stage 'playbooks\exoos\playbook.yml'
$idx = Join-Path $Stage 'wwwroot\index.html'
if (-not (Test-Path $exe)) { throw "Missing ExoOS.exe" }
if (-not (Test-Path $pb)) { throw "Missing playbook in package" }
if (-not (Test-Path $idx)) { throw "Missing wwwroot/index.html in package" }

# 8) Zip
if (Test-Path $Zip) { Remove-Item $Zip -Force }
Write-Host "Zipping $Zip …" -ForegroundColor Cyan
Compress-Archive -Path (Join-Path $Stage '*') -DestinationPath $Zip -CompressionLevel Optimal

# SHA-256
$sha = (Get-FileHash -Path $Zip -Algorithm SHA256).Hash
Set-Content -Path ($Zip + '.sha256') -Value "$sha  $(Split-Path $Zip -Leaf)" -Encoding ASCII

Write-Host ""
Write-Host "SHIP OK" -ForegroundColor Green
Write-Host "  Folder: $Stage"
Write-Host "  Zip:    $Zip"
Write-Host "  SHA256: $sha"
Write-Host "Run ExoOS.exe as Administrator for live apply."
