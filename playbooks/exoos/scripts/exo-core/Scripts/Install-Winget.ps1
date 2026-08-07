#Requires -RunAsAdministrator
<#
.SYNOPSIS
  Install a package via winget (silent). Used by optional software actions.
.PARAMETER PackageId
  Winget package id, e.g. Valve.Steam
.PARAMETER DisplayName
  Log label
#>
param(
    [Parameter(Mandatory = $true, Position = 0)]
    [string]$PackageId,
    [Parameter(Position = 1)]
    [string]$DisplayName = ''
)

$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

if ([string]::IsNullOrWhiteSpace($DisplayName)) { $DisplayName = $PackageId }
function Write-Step([string]$msg) { Write-Host "[$DisplayName] $msg" }

$winget = Get-Command winget -ErrorAction SilentlyContinue
if (-not $winget) {
    Write-Host "[$DisplayName] ERROR: winget not found. Install App Installer from the Microsoft Store." -ForegroundColor Red
    exit 1
}

# Already installed?
$list = & winget list -e --id $PackageId --accept-source-agreements 2>$null | Out-String
if ($list -match [regex]::Escape($PackageId)) {
    Write-Step "Already installed — skip."
    exit 0
}

Write-Step "Installing via winget ($PackageId)..."
$args = @(
    'install', '-e', '--id', $PackageId,
    '--accept-package-agreements',
    '--accept-source-agreements',
    '--silent',
    '--disable-interactivity',
    '--force'
)
$proc = Start-Process -FilePath $winget.Source -ArgumentList $args -Wait -PassThru -NoNewWindow
$code = $proc.ExitCode
# 0 success, -1978335189 already installed (some builds), -1978335212 no upgrade
switch ($code) {
    0 { Write-Step "Installed successfully."; exit 0 }
    -1978335189 { Write-Step "Already installed."; exit 0 }
    -1978335212 { Write-Step "Already up to date."; exit 0 }
    default {
        Write-Host "[$DisplayName] winget exit $code — retry without --force..." -ForegroundColor Yellow
        $args2 = @(
            'install', '-e', '--id', $PackageId,
            '--accept-package-agreements',
            '--accept-source-agreements',
            '--silent',
            '--disable-interactivity'
        )
        $proc2 = Start-Process -FilePath $winget.Source -ArgumentList $args2 -Wait -PassThru -NoNewWindow
        if ($proc2.ExitCode -eq 0 -or $proc2.ExitCode -eq -1978335189) {
            Write-Step "Installed successfully."
            exit 0
        }
        Write-Host "[$DisplayName] ERROR: winget failed with exit $($proc2.ExitCode)" -ForegroundColor Red
        exit 1
    }
}
