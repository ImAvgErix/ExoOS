#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Silently installs the .NET 10 Desktop Runtime (x64 and x86).
#>

$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$tempDir = Join-Path $env:TEMP 'DotNet10Runtime'

function Write-Step([string]$msg) { Write-Host "[.NET 10 Runtime] $msg" }

$packages = @(
    [PSCustomObject]@{
        Name = '.NET 10 Desktop Runtime (x64)'
        Url  = 'https://aka.ms/dotnet/10.0/windowsdesktop-runtime-win-x64.exe'
        File = 'windowsdesktop-runtime-10-win-x64.exe'
    }
    [PSCustomObject]@{
        Name = '.NET 10 Desktop Runtime (x86)'
        Url  = 'https://aka.ms/dotnet/10.0/windowsdesktop-runtime-win-x86.exe'
        File = 'windowsdesktop-runtime-10-win-x86.exe'
    }
)

$successCount = 0
$failCount    = 0

try {
    if (Test-Path $tempDir) { Remove-Item $tempDir -Recurse -Force }
    New-Item $tempDir -ItemType Directory -Force | Out-Null

    foreach ($pkg in $packages) {
        $dest = Join-Path $tempDir $pkg.File

        try {
            Write-Step "Downloading $($pkg.Name)..."
            Invoke-WebRequest -Uri $pkg.Url -OutFile $dest -UseBasicParsing

            Write-Step "Installing $($pkg.Name)..."
            $proc = Start-Process -FilePath $dest `
                -ArgumentList @('/install', '/quiet', '/norestart') `
                -Wait -PassThru

            switch ($proc.ExitCode) {
                0    { Write-Step "$($pkg.Name) installed successfully.";        $successCount++ }
                3010 { Write-Step "$($pkg.Name) installed (reboot pending).";    $successCount++ }
                1638 { Write-Step "$($pkg.Name) skipped (already up to date).";  $successCount++ }
                default {
                    Write-Host "[.NET 10 Runtime] WARNING: $($pkg.Name) exited with code $($proc.ExitCode)" -ForegroundColor Yellow
                    $failCount++
                }
            }
        }
        catch {
            Write-Host "[.NET 10 Runtime] WARNING: Failed on $($pkg.Name) -- $_" -ForegroundColor Yellow
            $failCount++
        }
    }

    Write-Step "Done. $successCount succeeded/skipped, $failCount failed."
    if ($failCount -gt 0) { exit 1 }
}
catch {
    Write-Host "[.NET 10 Runtime] FATAL: $_" -ForegroundColor Red
    exit 1
}
finally {
    if (Test-Path $tempDir) {
        Remove-Item $tempDir -Recurse -Force -ErrorAction SilentlyContinue
    }
    Write-Step "Temp files removed."
}
