#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Disables SvcHost service splitting for all applicable Windows services.
.DESCRIPTION
    Windows 10+ introduced "Service Host Splitting" - each svchost.exe instance
    hosts only a single service when the system has more than 3.5 GB of RAM.
    While this improves isolation and crash containment, it creates dozens of
    extra svchost.exe processes which consume additional memory and CPU overhead.

    This script sets SvcHostSplitDisable = 1 on every service that has a Start
    value (i.e. every real service entry), which allows Windows to group services
    back into shared svchost.exe processes as it did prior to Windows 10 1703.

    Xbox / Xbl services are skipped - splitting those can cause game/store issues.

    A reboot is required for the changes to take full effect.
#>

$ErrorActionPreference = 'SilentlyContinue'

function Write-Step([string]$msg) { Write-Host "[SvcHost] $msg" }

$servicesPath = 'HKLM:\SYSTEM\CurrentControlSet\Services'
$applied      = 0
$skipped      = 0
$failed       = 0

try {
    Write-Step "Enumerating services under $servicesPath..."

    $serviceKeys = Get-ChildItem -Path $servicesPath -ErrorAction SilentlyContinue

    foreach ($key in $serviceKeys) {
        $name = $key.PSChildName

        if ($name -match 'Xbl|Xbox') {
            $skipped++
            continue
        }

        try {
            $startValue = Get-ItemProperty -Path $key.PSPath -Name 'Start' -ErrorAction SilentlyContinue

            if ($null -ne $startValue) {
                Set-ItemProperty -Path $key.PSPath `
                                 -Name  'SvcHostSplitDisable' `
                                 -Value 1 `
                                 -Type  DWord `
                                 -Force -ErrorAction Stop
                $applied++
            }
        }
        catch {
            $failed++
        }
    }

    Write-Step "Complete - Applied: $applied  |  Xbox skipped: $skipped  |  Access denied: $failed"
    Write-Step "SvcHost splitting disabled. A reboot is required for the changes to take effect."
}
catch {
    Write-Host "[SvcHost] ERROR: $_" -ForegroundColor Red
    exit 1
}
