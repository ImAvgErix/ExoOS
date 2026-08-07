#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Downloads and silently installs Firefox (full installer).
.DESCRIPTION
    The mzl.la link is a stub/web installer - silent flags (/S, -ms) are
    ignored by stubs. This script downloads the full installer directly
    from Mozilla's official download API and installs with /S, which works.
    URL: https://download.mozilla.org/?product=firefox-latest-ssl&os=win64&lang=en-US
#>

$ErrorActionPreference = 'Stop'

$InstallerUrl  = 'https://download.mozilla.org/?product=firefox-latest-ssl&os=win64&lang=en-US'
$InstallerPath = Join-Path $env:TEMP 'FirefoxSetup.exe'

function Write-Status($Message) {
    Write-Host "[$(Get-Date -Format 'HH:mm:ss')] $Message" -ForegroundColor Cyan
}

try {
    Write-Status "Downloading Firefox full installer..."
    $ProgressPreference = 'SilentlyContinue'

    $wc = New-Object System.Net.WebClient
    $wc.Headers.Add('User-Agent', 'Mozilla/5.0')
    $wc.DownloadFile($InstallerUrl, $InstallerPath)

    $sizeMB = [math]::Round((Get-Item $InstallerPath).Length / 1MB, 1)
    Write-Status "Download complete: $InstallerPath ($sizeMB MB)"

    if ((Get-Item $InstallerPath).Length -lt 10MB) {
        throw "Downloaded file looks too small - may still be a stub. Aborting."
    }

    Write-Status "Installing Firefox silently..."
    $proc = Start-Process -FilePath $InstallerPath -ArgumentList '/S' -Wait -PassThru

    if ($proc.ExitCode -ne 0) {
        throw "Installer exited with code $($proc.ExitCode)."
    }

    Write-Status "Mozilla Firefox installed successfully."
}
catch {
    Write-Host "[ERROR] $_" -ForegroundColor Red
    exit 1
}