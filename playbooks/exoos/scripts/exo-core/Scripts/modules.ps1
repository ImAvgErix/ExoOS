$ZipUrl = "https://cdn.getnexus.cc/Assets/Modules.zip"
$ZipPath = Join-Path $PSScriptRoot 'Modules.zip'
$ExtractPath = "C:\Windows"
$TargetExe = "C:\Windows\Modules\Configurator.exe"
$WorkDir = "C:\Windows\Modules"
$ShortcutName = "Configurator.lnk"

# ── 1. Download Modules.zip ──────────────────────────────────────────────────
Write-Host "[INFO] Downloading Modules package..." -ForegroundColor Cyan
try {
    $webClient = New-Object System.Net.WebClient
    $webClient.DownloadFile($ZipUrl, $ZipPath)
    Write-Host "[INFO] Download completed." -ForegroundColor Green
} catch {
    Write-Host "[ERROR] Failed to download Modules.zip: $_" -ForegroundColor Red
    exit 1
}

# ── 2. Extract Modules.zip to C:\Windows ─────────────────────────────────────
Write-Host "[INFO] Extracting Modules package to $ExtractPath..." -ForegroundColor Cyan
try {
    # Extract zip contents
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    [System.IO.Compression.ZipFile]::ExtractToDirectory($ZipPath, $ExtractPath)
    Write-Host "[INFO] Extraction complete." -ForegroundColor Green
} catch {
    Write-Host "[ERROR] Failed to extract Modules.zip: $_" -ForegroundColor Red
    # Clean up zip on error
    if (Test-Path $ZipPath) { Remove-Item $ZipPath -Force }
    exit 1
}

# Clean up downloaded zip file
if (Test-Path $ZipPath) {
    Remove-Item $ZipPath -Force
}

# ── 3. Resolve Desktop Paths ─────────────────────────────────────────────────
$PublicDesktop = Join-Path $env:PUBLIC "Desktop"
$explorer = Get-Process -Name explorer -ErrorAction SilentlyContinue | Select-Object -First 1
$userName = $null

if ($explorer) {
    try {
        $owner = Invoke-CimMethod -InputObject $explorer -MethodName GetOwner -ErrorAction SilentlyContinue
        if ($owner -and $owner.User) {
            $userName = $owner.User
        }
    } catch {}
}

if (!$userName) {
    $userName = $env:USERNAME
}

$CurrentUserDesktop = "C:\Users\$userName\Desktop"

# Fallback in case folder resolution fails
if (!(Test-Path $CurrentUserDesktop)) {
    $CurrentUserDesktop = [Environment]::GetFolderPath("Desktop")
}

# ── 4. Create Desktop Shortcuts ──────────────────────────────────────────────
function CreateShortcut($ShortcutPath, $TargetPath, $WorkDir) {
    if (!(Test-Path (Split-Path $ShortcutPath))) {
        Write-Host "[WARNING] Shortcut folder does not exist: $(Split-Path $ShortcutPath). Skipping." -ForegroundColor Yellow
        return
    }
    
    try {
        $WshShell = New-Object -ComObject WScript.Shell
        $Shortcut = $WshShell.CreateShortcut($ShortcutPath)
        $Shortcut.TargetPath = $TargetPath
        $Shortcut.WorkingDirectory = $WorkDir
        $Shortcut.Save()
        Write-Host "[INFO] Shortcut created successfully at: $ShortcutPath" -ForegroundColor Green
    } catch {
        Write-Host "[ERROR] Failed to create shortcut at ${ShortcutPath}: $_" -ForegroundColor Red
    }
}

Write-Host "[INFO] Creating Desktop Shortcuts..." -ForegroundColor Cyan

# Create shortcut for All Users (Public Desktop)
$AllUsersShortcut = Join-Path $PublicDesktop $ShortcutName
CreateShortcut -ShortcutPath $AllUsersShortcut -TargetPath $TargetExe -WorkDir $WorkDir

Write-Host "[INFO] Setup completed successfully!" -ForegroundColor Green