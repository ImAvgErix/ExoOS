$ErrorActionPreference = 'SilentlyContinue'

# ── Download layout files from CDN ────────────────────────────────────────────
$tempDir = Join-Path $env:TEMP "ExoStartMenu_$(Get-Random)"
New-Item $tempDir -ItemType Directory -Force | Out-Null

$jsonUrl = "https://cdn.getnexus.cc/Windows11/LayoutModification.json"
$xmlUrl  = "https://cdn.getnexus.cc/Windows11/LayoutModification.xml"

$jsonPath = Join-Path $tempDir 'LayoutModification.json'
$xmlPath  = Join-Path $tempDir 'LayoutModification.xml'

Write-Host '[*] Downloading LayoutModification.json...'
Invoke-WebRequest -Uri $jsonUrl -OutFile $jsonPath -UseBasicParsing

Write-Host '[*] Downloading LayoutModification.xml...'
Invoke-WebRequest -Uri $xmlUrl  -OutFile $xmlPath  -UseBasicParsing

if (-not (Test-Path $jsonPath) -or -not (Test-Path $xmlPath)) {
    Write-Error 'Failed to download one or more layout files. Aborting.'
    exit 1
}

# ── Helper: write both layout files to a Shell folder ────────────────────────
function Deploy-Layout([string]$shellDir) {
    New-Item $shellDir -ItemType Directory -Force | Out-Null
    Copy-Item $jsonPath "$shellDir\LayoutModification.json" -Force
    Copy-Item $xmlPath  "$shellDir\LayoutModification.xml"  -Force
}

# ── Remove legacy StartMenuLayout.xml ────────────────────────────────────────
$legacyLayout = "$env:SystemDrive\Windows\StartMenuLayout.xml"
if (Test-Path $legacyLayout) {
    Remove-Item $legacyLayout -Force
    Write-Host "[+] Removed legacy $legacyLayout"
}

# ── Apply to Default user profile ────────────────────────────────────────────
$defaultShell = "$env:SystemDrive\Users\Default\AppData\Local\Microsoft\Windows\Shell"
Deploy-Layout $defaultShell
Write-Host "[+] Layout applied to Default profile."

# ── Enumerate all loaded user hives ──────────────────────────────────────────
# Matches real SIDs (S-1-5-...) and Exo injected hives (Exo_UserHive_*)
$hiveNames = (Get-ChildItem 'Registry::HKEY_USERS').PSChildName |
    Where-Object { $_ -match '^S-\d-\d+-(\d+-){1,14}\d+$' -or $_ -match '^Exo_UserHive_[^_]+$' }

foreach ($hive in $hiveNames) {
    $hiveRoot = "Registry::HKEY_USERS\$hive"

    # Only act on proper user hives — must have Volatile Environment OR be an AME hive
    $isExoHive     = $hive -match '^Exo_UserHive_'
    $hasVolatile   = Test-Path "$hiveRoot\Volatile Environment"
    if (-not ($hasVolatile -or $isExoHive)) { continue }

    # Resolve LocalAppData for this hive
    $localAppData = (Get-ItemProperty `
        "$hiveRoot\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Shell Folders" `
        -Name 'Local AppData').'Local AppData'

    if ([string]::IsNullOrWhiteSpace($localAppData)) {
        Write-Warning "[$hive] Could not resolve LocalAppData — skipping."
        continue
    }

    Write-Host "[$hive] Applying to $localAppData..."

    # ── Deploy layout files ───────────────────────────────────────────────────
    Deploy-Layout "$localAppData\Microsoft\Windows\Shell"

    # ── Delete start*.bin from StartMenuExperienceHost LocalState ─────────────
    $smehDir = Get-ChildItem "$localAppData\Packages" -Directory |
        Where-Object Name -like '*Microsoft.Windows.StartMenuExperienceHost*' |
        Select-Object -ExpandProperty FullName -First 1

    if ($smehDir) {
        Get-ChildItem "$smehDir\LocalState" -File |
            Where-Object Name -match '^start.*\.bin$' |
            ForEach-Object {
                Write-Host "  [-] Deleting $($_.Name)"
                Remove-Item $_.FullName -Force
            }
    }

    # ── Wipe CloudStore start tile grid keys (prevents cloud restore) ─────────
    $cloudStorePath = "$hiveRoot\SOFTWARE\Microsoft\Windows\CurrentVersion\CloudStore\Store\Cache\DefaultAccount"
    if (Test-Path "Registry::$($cloudStorePath -replace '^Registry::','')") {
        Get-ChildItem "Registry::HKEY_USERS\$hive\SOFTWARE\Microsoft\Windows\CurrentVersion\CloudStore\Store\Cache\DefaultAccount" |
            Where-Object PSChildName -like '*start.tilegrid*' |
            ForEach-Object {
                Write-Host "  [-] Removing CloudStore key: $($_.PSChildName)"
                Remove-Item "Registry::$($_.Name)" -Recurse -Force
            }
    }

    # ── Remove Start\Config (required for 23H2+ to take effect) ──────────────
    $startKey = "$hiveRoot\Software\Microsoft\Windows\CurrentVersion\Start"
    if (Test-Path $startKey) {
        Remove-ItemProperty $startKey -Name 'Config' -Force
        Write-Host "  [-] Removed Start\Config"
    }
}

# ── Restore CBS .bak files (WsxPackManager etc.) if originals were replaced ──
$cbsDir = "$env:SystemDrive\Windows\SystemApps\MicrosoftWindows.Client.CBS_cw5n1h2txyewy"
@(
    'WsxPackManager.dll'
    'WebExperienceHostApp.exe'
    'WebExperienceHost.dll'
    'SystemSettingsExtensions.dll'
) | ForEach-Object {
    $file    = Join-Path $cbsDir $_
    $bakFile = "$file.bak"
    if (-not (Test-Path $file) -and (Test-Path $bakFile)) {
        Rename-Item $bakFile $_ -Force
        Write-Host "[+] Restored $_ from .bak"
    }
}

# ── Cleanup temp files ────────────────────────────────────────────────────────
Remove-Item $tempDir -Recurse -Force

Write-Host ''
Write-Host '[+] Start menu layout applied successfully.' -ForegroundColor Green
