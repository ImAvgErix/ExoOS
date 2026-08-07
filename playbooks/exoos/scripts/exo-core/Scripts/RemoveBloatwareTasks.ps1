#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Removes Microsoft bloatware scheduled tasks and blocks their reinstallation.
.DESCRIPTION
    Targets tasks that silently install or re-install unwanted apps:
      - Outlook (new) / OutlookUpdate orchestrator
      - PC Health Check (GetHealthCheckApp)
      - Windows Copilot
      - OneDrive setup nudge
      - Xbox / GamingApp install tasks
      - Dev Home
      - Clipchamp
      - Teams (consumer/personal)
      - Content Delivery Manager (suggested apps / spotlight)
      - Edge update tasks

    Also writes BlockedOobeUpdaters registry values to prevent Outlook
    and other apps from being silently re-pushed via Windows Update.
#>

$ErrorActionPreference = 'SilentlyContinue'

function Write-Step([string]$msg)    { Write-Host "[*] $msg" -ForegroundColor Cyan }
function Write-Ok([string]$msg)      { Write-Host "[+] $msg" -ForegroundColor Green }
function Write-WarnMsg([string]$msg) { Write-Host "[!] $msg" -ForegroundColor Yellow }

function Remove-Task {
    param([string]$TaskPath, [string]$TaskName)
    $task = Get-ScheduledTask -TaskPath $TaskPath -TaskName $TaskName -ErrorAction SilentlyContinue
    if ($task) {
        try {
            Unregister-ScheduledTask -TaskPath $TaskPath -TaskName $TaskName -Confirm:$false -ErrorAction Stop
            Write-Ok "Removed task: $TaskPath$TaskName"
        }
        catch {
            Write-WarnMsg "Could not remove task $TaskPath$TaskName : $($_.Exception.Message)"
        }
    }
    else {
        Write-Host "    [skip] Not found: $TaskPath$TaskName" -ForegroundColor DarkGray
    }
}

function Remove-TasksByPattern {
    param([string]$TaskPath, [string]$Pattern)
    $tasks = Get-ScheduledTask -TaskPath $TaskPath -ErrorAction SilentlyContinue |
             Where-Object { $_.TaskName -match $Pattern }
    foreach ($task in $tasks) {
        try {
            Unregister-ScheduledTask -TaskPath $task.TaskPath -TaskName $task.TaskName -Confirm:$false -ErrorAction Stop
            Write-Ok "Removed task: $($task.TaskPath)$($task.TaskName)"
        }
        catch {
            Write-WarnMsg "Could not remove $($task.TaskName): $($_.Exception.Message)"
        }
    }
}

function Remove-RegKey([string]$Path) {
    if (Test-Path $Path) {
        try {
            Remove-Item -LiteralPath $Path -Recurse -Force -ErrorAction Stop
            Write-Ok "Removed registry key: $Path"
        }
        catch {
            Write-WarnMsg "Could not remove registry key $Path : $($_.Exception.Message)"
        }
    }
    else {
        Write-Host "    [skip] Registry key not found: $Path" -ForegroundColor DarkGray
    }
}

function Set-RegValue([string]$Path, [string]$Name, $Value, [string]$Type = 'String') {
    try {
        if (-not (Test-Path $Path)) { New-Item -Path $Path -Force | Out-Null }
        New-ItemProperty -Path $Path -Name $Name -Value $Value -PropertyType $Type -Force | Out-Null
        Write-Ok "Set registry: $Path\$Name = $Value"
    }
    catch {
        Write-WarnMsg "Could not set $Path\$Name : $($_.Exception.Message)"
    }
}

# ---------------------------------------------------------------------------
# 1. Outlook (new)
# ---------------------------------------------------------------------------
Write-Step 'Removing Outlook (new) install tasks...'
Remove-Task '\Microsoft\Windows\WindowsUpdate\' 'OutlookUpdate'
Remove-Task '\Microsoft\Windows\WindowsUpdate\Orchestrator\' 'OutlookUpdate'
Remove-RegKey 'HKLM:\SOFTWARE\Microsoft\WindowsUpdate\Orchestrator\UScheduler_Oobe\OutlookUpdate'

# Block Outlook from being silently re-pushed via Windows Update
Set-RegValue `
    'HKLM:\SOFTWARE\Microsoft\WindowsUpdate\Orchestrator\UScheduler_Oobe' `
    'BlockedOobeUpdaters' `
    '["MS_Outlook"]'

# ---------------------------------------------------------------------------
# 2. PC Health Check (GetHealthCheckApp / PCHealthCheck)
# ---------------------------------------------------------------------------
Write-Step 'Removing PC Health Check install tasks...'
Remove-Task '\Microsoft\Windows\WindowsUpdate\' 'GetHealthCheckApp'
Remove-Task '\Microsoft\Windows\WindowsUpdate\Orchestrator\' 'GetHealthCheckApp'
Remove-RegKey 'HKLM:\SOFTWARE\Microsoft\WindowsUpdate\Orchestrator\UScheduler_Oobe\PCHealthCheck'
Remove-RegKey 'HKLM:\SOFTWARE\Microsoft\WindowsUpdate\Orchestrator\UScheduler_Oobe\GetHealthCheckApp'

# ---------------------------------------------------------------------------
# 5. Teams (consumer/personal - not the work one)
# ---------------------------------------------------------------------------
Write-Step 'Removing Teams consumer install tasks...'
Remove-Task '\Microsoft\Windows\WindowsUpdate\' 'Teams'
Remove-RegKey 'HKLM:\SOFTWARE\Microsoft\WindowsUpdate\Orchestrator\UScheduler_Oobe\MSTeamsUpdate'
Remove-TasksByPattern '\Microsoft\Windows\' 'Teams.*Install'

# ---------------------------------------------------------------------------
# 6. Dev Home
# ---------------------------------------------------------------------------
Write-Step 'Removing Dev Home install tasks...'
Remove-Task '\Microsoft\Windows\WindowsUpdate\' 'DevHomeUpdate'
Remove-RegKey 'HKLM:\SOFTWARE\Microsoft\WindowsUpdate\Orchestrator\UScheduler_Oobe\DevHomeUpdate'

# ---------------------------------------------------------------------------
# 7. Clipchamp
# ---------------------------------------------------------------------------
Write-Step 'Removing Clipchamp install tasks...'
Remove-Task '\Microsoft\Windows\WindowsUpdate\' 'ClipchampUpdate'
Remove-RegKey 'HKLM:\SOFTWARE\Microsoft\WindowsUpdate\Orchestrator\UScheduler_Oobe\ClipchampUpdate'

# ---------------------------------------------------------------------------
# 9. Content Delivery Manager (suggested apps / spotlight bloatware push)
# ---------------------------------------------------------------------------
Write-Step 'Removing Content Delivery Manager tasks...'
Remove-Task '\Microsoft\Windows\CloudExperienceHost\' 'CreateObjectTask'
Remove-TasksByPattern '\Microsoft\Windows\ContentDeliveryManager\' '.*'

# Disable CDM silently-installed apps via registry
Set-RegValue 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager' 'SilentInstalledAppsEnabled'   0 'DWord'
Set-RegValue 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager' 'SystemPaneSuggestionsEnabled' 0 'DWord'
Set-RegValue 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager' 'SoftLandingEnabled'           0 'DWord'
Set-RegValue 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager' 'SubscribedContentEnabled'     0 'DWord'

# ---------------------------------------------------------------------------
# 10. Edge update tasks (if Edge is already removed or unwanted)
# ---------------------------------------------------------------------------
Write-Step 'Removing Edge update tasks...'
Remove-TasksByPattern '\' 'MicrosoftEdgeUpdateTask.*'

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
Write-Host ''
Write-Ok 'Done. Bloatware install tasks removed and reinstall blocks applied.'
Write-Host '    Some changes (CDM, OOBE blockers) take effect after the next login or reboot.' -ForegroundColor DarkGray
