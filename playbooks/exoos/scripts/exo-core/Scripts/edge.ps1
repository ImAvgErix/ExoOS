$ErrorActionPreference = 'SilentlyContinue'

# ── Shared uninstaller helper ─────────────────────────────────────────────────
function Uninstall-Process {
    param (
        [Parameter(Mandatory = $true)]
        [string]$Key
    )

    $baseKey = 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\EdgeUpdate'
    Write-Host "[Edge] Base registry key: $baseKey"
    $registryPath = $baseKey + '\ClientState\' + $Key

    if (!(Test-Path -Path $registryPath)) {
        Write-Host "[Edge] Registry key not found: $registryPath"
        return
    }

    Remove-ItemProperty -Path $registryPath -Name "experiment_control_labels" -ErrorAction SilentlyContinue | Out-Null

    try {
        # Activates BrowserReplacement and allows uninstallation directly from Settings > Apps,
        # even after Edge gets reinstalled.
        $folderPath = "$env:SystemRoot\SystemApps\Microsoft.MicrosoftEdge_8wekyb3d8bbwe"

        if (!(Test-Path -Path $folderPath)) {
            New-Item -ItemType Directory -Path $folderPath -Force | Out-Null
        }
        New-Item -ItemType File -Path $folderPath -Name "MicrosoftEdge.exe" -Force | Out-Null
    }
    catch {
        Write-Host "[Edge] Failed to create fake MicrosoftEdge.exe: $_"
        return
    }

    # Setting windir temporarily to an empty string allows the Edge uninstallation to work.
    $env:windir = ""

    $uninstallString    = (Get-ItemProperty -Path $registryPath).UninstallString
    $uninstallArguments = (Get-ItemProperty -Path $registryPath).UninstallArguments

    if ([string]::IsNullOrEmpty($uninstallString) -or [string]::IsNullOrEmpty($uninstallArguments)) {
        Write-Host "[Edge] Cannot find uninstall methods for key $Key"
        return
    }

    $uninstallArguments += " --force-uninstall --delete-profile"

    if (!(Test-Path -Path $uninstallString)) {
        Write-Host "[Edge] setup.exe not found at: $uninstallString"
        return
    }

    # Process spoofing — allowed parent list: dllhost.exe, msiexec.exe, sihost.exe, SystemSettings.exe
    $spoofDir  = "$env:SystemRoot\ImmersiveControlPanel"
    $spoofPath = "$spoofDir\sihost.exe"

    try {
        Copy-Item -Path "$env:SystemRoot\System32\cmd.exe" -Destination $spoofPath -Force
        Write-Host "[Edge] Created spoofed process at: $spoofPath"

        $cmdArgs = "/c `"$uninstallString`" $uninstallArguments"
        $process = Start-Process -FilePath $spoofPath -ArgumentList $cmdArgs -Wait -NoNewWindow -PassThru
        Write-Host "[Edge] Uninstallation exit code: $($process.ExitCode)"

        Remove-Item -Path $spoofPath -Force -ErrorAction SilentlyContinue
        Write-Host "[Edge] Cleaned up spoofed process"
    }
    catch {
        Write-Host "[Edge] Failed during process spoofing: $_"
        Remove-Item -Path $spoofPath -Force -ErrorAction SilentlyContinue
        return
    }

    if ((Get-ItemProperty -Path $baseKey -ErrorAction SilentlyContinue).IsEdgeStableUninstalled -eq 1) {
        Write-Host "[Edge] Edge Stable has been successfully uninstalled"
    }
}

# ── 1. Uninstall Edge Browser ─────────────────────────────────────────────────
function Uninstall-Edge {
    Write-Host "[Edge] Uninstalling Microsoft Edge..."

    Remove-ItemProperty -Path "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\Microsoft Edge" `
        -Name "NoRemove" -ErrorAction SilentlyContinue | Out-Null

    [microsoft.win32.registry]::SetValue(
        "HKEY_LOCAL_MACHINE\SOFTWARE\WOW6432Node\Microsoft\EdgeUpdateDev",
        "AllowUninstall", 1,
        [Microsoft.Win32.RegistryValueKind]::DWord) | Out-Null

    Uninstall-Process -Key '{56EB18F8-B008-4CBD-B6D2-8C97FE7E9062}'

    # Remove Edge shortcuts
    @(
        "$env:ProgramData\Microsoft\Windows\Start Menu\Programs",
        "$env:PUBLIC\Desktop",
        "$env:USERPROFILE\Desktop"
    ) | ForEach-Object {
        $shortcutPath = Join-Path $_ "Microsoft Edge.lnk"
        if (Test-Path $shortcutPath) {
            Remove-Item $shortcutPath -Force
            Write-Host "[Edge] Removed shortcut: $shortcutPath"
        }
    }
}

# ── 2. Uninstall WebView2 ─────────────────────────────────────────────────────
function Uninstall-WebView {
    Write-Host "[Edge] Uninstalling Microsoft Edge WebView2..."

    Remove-ItemProperty -Path "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\Microsoft EdgeWebView" `
        -Name "NoRemove" -ErrorAction SilentlyContinue | Out-Null

    Uninstall-Process -Key '{F3017226-FE2A-4295-8BDF-00C3A9A7E4C5}'
}

# ── 3. Uninstall Edge Update ──────────────────────────────────────────────────
function Uninstall-EdgeUpdate {
    Write-Host "[Edge] Uninstalling Microsoft Edge Update..."

    Remove-ItemProperty -Path "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\Microsoft Edge Update" `
        -Name "NoRemove" -ErrorAction SilentlyContinue | Out-Null

    $registryPath = 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\EdgeUpdate'
    if (!(Test-Path -Path $registryPath)) {
        Write-Host "[Edge] EdgeUpdate registry key not found: $registryPath"
        return
    }

    $uninstallCmdLine = (Get-ItemProperty -Path $registryPath).UninstallCmdLine
    if ([string]::IsNullOrEmpty($uninstallCmdLine)) {
        Write-Host "[Edge] Cannot find uninstall command for EdgeUpdate"
        return
    }

    Write-Host "[Edge] Running: $uninstallCmdLine"
    Start-Process cmd.exe "/c $uninstallCmdLine" -WindowStyle Hidden -Wait
}

# ── 4. Force-delete Edge folders ──────────────────────────────────────────────
function Remove-EdgeFolders {
    Write-Host "[Edge] Scanning for residual Edge folders..."

    # Define base directories using proper string interpolation for x86
    $baseDirs = @(
        "$env:ProgramFiles\Microsoft",
        "${env:ProgramFiles(x86)}\Microsoft"
    )

    $edgePaths = @()

    # 1. Dynamically find folders starting with 'Edge' in Program Files
    foreach ($dir in $baseDirs) {
        if (Test-Path $dir) {
            $foundFolders = Get-ChildItem -Path $dir -Filter "Edge*" -Directory -ErrorAction SilentlyContinue | Select-Object -ExpandProperty FullName
            if ($foundFolders) {
                $edgePaths += $foundFolders
            }
        }
    }

    # 2. Add specific system folders that don't fit the 'Microsoft\Edge*' pattern
    $systemFolders = @(
        "$env:SystemRoot\SystemApps\Microsoft.MicrosoftEdge_8wekyb3d8bbwe",
        "$env:SystemDrive\Windows\System32\Microsoft-Edge-WebView"
    )

    foreach ($sysFolder in $systemFolders) {
        if (Test-Path $sysFolder) {
            $edgePaths += $sysFolder
        }
    }

    if ($edgePaths.Count -eq 0) {
        Write-Host "[Edge] No Edge folders found."
        return
    }

    # 3. Iterate and destroy
    foreach ($path in $edgePaths) {
        Write-Host "[Edge] Found folder: $path. Attempting deletion..."
        
        try {
            # Take ownership and grant full control before deletion
            cmd.exe /c "takeown /F `"$path`" /R /D Y >nul 2>&1"
            cmd.exe /c "icacls `"$path`" /grant *S-1-1-0:F /T /C /Q >nul 2>&1"
            
            Remove-Item -Path $path -Recurse -Force -ErrorAction Stop
            Write-Host "[Edge] Successfully deleted: $path"
        }
        catch {
            # Last resort — use cmd rd which can bypass some locks
            cmd.exe /c "rd /S /Q `"$path`"" 2>$null
            
            if (!(Test-Path $path)) {
                Write-Host "[Edge] Deleted (rd fallback): $path"
            } else {
                Write-Host "[Edge] Could not delete (files in use or reboot required): $path" -ForegroundColor Yellow
            }
        }
    }
}

# ── Run all steps ─────────────────────────────────────────────────────────────
Uninstall-Edge
Uninstall-WebView
Uninstall-EdgeUpdate
Remove-EdgeFolders

# Restore windir in case it was blanked during uninstall
if ([string]::IsNullOrEmpty($env:windir)) {
    $env:windir = $env:SystemRoot
}

Write-Host ""
Write-Host "[Edge] All Edge removal steps completed." -ForegroundColor Green