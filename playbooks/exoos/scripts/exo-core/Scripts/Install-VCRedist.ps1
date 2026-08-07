#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Silently installs all Visual C++ Redistributable packages (2005-2022).
.DESCRIPTION
    Downloads individual VC++ redist installers from your CDN and installs each one
    silently in order from oldest to newest.  Already-installed versions are skipped
    gracefully via exit codes 0, 3010 (reboot pending), or 1638 (newer version present).
#>

$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$cdnBase = 'https://raw.githubusercontent.com/Ryan2159/Visual-C-Redist-AIO/main/'
$tempDir = Join-Path $env:TEMP 'VCRedist'

function Write-Step([string]$msg) { Write-Host "[VC++ Redist] $msg" }

# Each entry: FileName, ArgumentList (as array — avoids quoting issues)
# Ordered oldest to newest so dependencies are always satisfied first.
$packages = @(
    [PSCustomObject]@{ File = 'vcredist2005_x64.exe'; Args = @('/q:a', '/c:msiexec /i vcredist.msi /qn') }
    [PSCustomObject]@{ File = 'vcredist2008_x86.exe'; Args = @('/qb') }
    [PSCustomObject]@{ File = 'vcredist2008_x64.exe'; Args = @('/qb') }
    [PSCustomObject]@{ File = 'vcredist2010_x86.exe'; Args = @('/quiet', '/norestart') }
    [PSCustomObject]@{ File = 'vcredist2010_x64.exe'; Args = @('/quiet', '/norestart') }
    [PSCustomObject]@{ File = 'vcredist2012_x86.exe'; Args = @('/quiet', '/norestart') }
    [PSCustomObject]@{ File = 'vcredist2012_x64.exe'; Args = @('/quiet', '/norestart') }
    [PSCustomObject]@{ File = 'vcredist2013_x86.exe'; Args = @('/quiet', '/norestart') }
    [PSCustomObject]@{ File = 'vcredist2013_x64.exe'; Args = @('/quiet', '/norestart') }
    [PSCustomObject]@{ File = 'vcredist_v14.x86.exe'; Args = @('/quiet', '/norestart') }
    [PSCustomObject]@{ File = 'vcredist_v14.x64.exe'; Args = @('/quiet', '/norestart') }
)

$successCount = 0
$failCount    = 0

try {
    # Prepare temp directory
    if (Test-Path $tempDir) { Remove-Item $tempDir -Recurse -Force }
    New-Item $tempDir -ItemType Directory -Force | Out-Null

    foreach ($pkg in $packages) {
        # TrimEnd('/') ensures no double-slash if $cdnBase was set with a trailing slash
        $url  = "$($cdnBase.TrimEnd('/'))/$($pkg.File)"
        $dest = Join-Path $tempDir $pkg.File

        try {
            # Download
            Write-Step "Downloading $($pkg.File)..."
            Invoke-WebRequest -Uri $url -OutFile $dest -UseBasicParsing

            # Install
            Write-Step "Installing $($pkg.File)..."
            $proc = Start-Process -FilePath $dest -ArgumentList $pkg.Args -Wait -PassThru

            switch ($proc.ExitCode) {
                0    { Write-Step "$($pkg.File) installed successfully.";          $successCount++ }
                3010 { Write-Step "$($pkg.File) installed (reboot pending).";      $successCount++ }
                1638 { Write-Step "$($pkg.File) skipped (newer version present)."; $successCount++ }
                default {
                    Write-Host "[VC++ Redist] WARNING: $($pkg.File) exited with code $($proc.ExitCode)" -ForegroundColor Yellow
                    $failCount++
                }
            }
        }
        catch {
            Write-Host "[VC++ Redist] WARNING: Failed on $($pkg.File) -- $_" -ForegroundColor Yellow
            $failCount++
            # Continue with remaining packages even if one fails
        }
    }

    Write-Step "Done. $successCount succeeded/skipped, $failCount failed."
    if ($failCount -gt 0) { exit 1 }
}
catch {
    Write-Host "[VC++ Redist] FATAL: $_" -ForegroundColor Red
    exit 1
}
finally {
    if (Test-Path $tempDir) {
        Remove-Item $tempDir -Recurse -Force -ErrorAction SilentlyContinue
    }
    Write-Step "Temp files removed."
}
