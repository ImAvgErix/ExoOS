#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Silently installs the DirectX End-User Runtime (June 2010).
.DESCRIPTION
    Downloads directx_Jun2010_redist.exe from the Exo content CDN, extracts its contents
    to a subfolder of the script's own directory (the secure ACL work folder), then
    runs DXSETUP.exe /silent to install the legacy DirectX components (D3DX9, D3DX10,
    D3DX11, XACT, XInput 9.1.0, etc.).

    These components are NOT included in modern Windows -- they are required by many
    older DirectX 9/10 games.
#>

$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$cdnUrl      = 'https://download.microsoft.com/download/8/4/a/84a35bf1-dafe-4ae8-82af-ad2ae20b6b14/directx_Jun2010_redist.exe'
$selfExtract = Join-Path $PSScriptRoot 'directx_Jun2010_redist.exe'
$extractDir  = Join-Path $PSScriptRoot 'dxextracted'
$dxSetup     = Join-Path $extractDir   'DXSETUP.exe'

function Write-Step([string]$msg) { Write-Host "[DirectX] $msg" }

try {
    # -- Prepare extract directory -----------------------------------------------
    if (Test-Path $extractDir) { Remove-Item $extractDir -Recurse -Force }
    New-Item $extractDir -ItemType Directory -Force | Out-Null

    # -- Download ----------------------------------------------------------------
    Write-Step "Downloading DirectX Jun 2010 Redist..."
    Invoke-WebRequest -Uri $cdnUrl -OutFile $selfExtract -UseBasicParsing

    if (-not (Test-Path $selfExtract)) {
        throw "Download failed -- file not found at: $selfExtract"
    }
    Write-Step "Download complete ($(('{0:N1}' -f ((Get-Item $selfExtract).Length / 1MB))) MB)"

    # -- Extract -----------------------------------------------------------------
    # directx_Jun2010_redist.exe is a self-extracting cabinet archive.
    # /Q  -- quiet mode (no progress UI)
    # /T  -- extract-to directory (must be an absolute path)
    Write-Step "Extracting archive..."
    $proc = Start-Process -FilePath $selfExtract `
                          -ArgumentList "/Q", "/T:`"$extractDir`"" `
                          -Wait -PassThru

    if ($proc.ExitCode -ne 0) {
        throw "Self-extractor exited with code $($proc.ExitCode)"
    }

    if (-not (Test-Path $dxSetup)) {
        throw "Extraction succeeded but DXSETUP.exe was not found in: $extractDir"
    }
    Write-Step "Extraction complete."

    # -- Install -----------------------------------------------------------------
    # /silent -- no UI, no prompts.  DXSETUP returns:
    #   0     = success
    #   2     = already installed / nothing to do
    #   other = error
    Write-Step "Running DXSETUP /silent..."
    $install = Start-Process -FilePath $dxSetup `
                             -ArgumentList '/silent' `
                             -WorkingDirectory $extractDir `
                             -Wait -PassThru

    switch ($install.ExitCode) {
        0 { Write-Step "DirectX Jun 2010 Redist installed successfully." }
        2 { Write-Step "DirectX Jun 2010 Redist already installed (nothing to do)." }
        default { throw "DXSETUP.exe exited with code $($install.ExitCode)" }
    }
}
catch {
    Write-Host "[DirectX] ERROR: $_" -ForegroundColor Red
    exit 1
}
finally {
    # Remove only the files this script created -- do not delete $PSScriptRoot itself
    # since other scripts in the secure work folder may still be running.
    if (Test-Path $selfExtract) { Remove-Item $selfExtract -Force -ErrorAction SilentlyContinue }
    if (Test-Path $extractDir)  { Remove-Item $extractDir  -Recurse -Force -ErrorAction SilentlyContinue }
    Write-Step "Temp files removed."
}
