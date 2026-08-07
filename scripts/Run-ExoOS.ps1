# Build UI (if needed) + host, then launch ExoOS.
$ErrorActionPreference = 'Stop'
$Root = Split-Path -Parent $PSScriptRoot
Set-Location $Root

$uiDir = Join-Path $Root 'src\ExoOS.App\ui'
$www = Join-Path $Root 'src\ExoOS.App\wwwroot\index.html'
if (-not (Test-Path $www) -or (Get-ChildItem (Join-Path $uiDir 'src') -Recurse -File | Where-Object { $_.LastWriteTime -gt (Get-Item $www).LastWriteTime } | Select-Object -First 1)) {
    Write-Host "Building UI…" -ForegroundColor Cyan
    Push-Location $uiDir
    if (-not (Test-Path 'node_modules')) { npm ci }
    npm run build
    Pop-Location
}

Write-Host "Building ExoOS…" -ForegroundColor Cyan
dotnet build "$Root\ExoOS.sln" -c Release
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

$exe = Join-Path $Root 'src\ExoOS.App\bin\Release\net10.0-windows\ExoOS.exe'
if (-not (Test-Path $exe)) {
    Write-Error "ExoOS.exe not found at $exe"
    exit 1
}

Write-Host "Launching $exe" -ForegroundColor Green
Start-Process -FilePath $exe
