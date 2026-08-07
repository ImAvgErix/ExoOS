$ZipUrl = "https://cdn.getnexus.cc/Assets/Web.zip" # Replace with your actual CDN/Download URL
$ZipPath = "C:\Windows\Web.zip"
$ExtractPath = "C:\Windows"

$DesktopWallpaperPath = "C:\Windows\Web\Wallpaper\Windows\img0.jpg"
$LockScreenWallpaperPath = "C:\Windows\Web\Screen\img100.jpg"

# ── 1. Unconditionally Download and Extract Web.zip ──────────────────────────────────
Write-Host "[INFO] Downloading Web package..." -ForegroundColor Cyan
$zip = $null

try {

    # Clean taskbar first
    Stop-Process -Name explorer -Force
    Remove-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Taskband" -Name "Favorites" -ErrorAction SilentlyContinue
    Remove-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Taskband" -Name "FavoritesResolve" -ErrorAction SilentlyContinue

    $webClient = New-Object System.Net.WebClient
    $webClient.DownloadFile($ZipUrl, $ZipPath)
    Write-Host "[INFO] Download completed." -ForegroundColor Green
    
    # WORKAROUND: Take ownership of the Web directory from TrustedInstaller to allow overwriting default wallpapers
    Write-Host "[INFO] Bypassing TrustedInstaller permissions on C:\Windows\Web..." -ForegroundColor Yellow
    if (Test-Path "C:\Windows\Web") {
        takeown /f "C:\Windows\Web" /r /d y *>&1 | Out-Null
        icacls "C:\Windows\Web" /grant "Administrators:F" /t /c /q *>&1 | Out-Null
        icacls "C:\Windows\Web" /grant "SYSTEM:F" /t /c /q *>&1 | Out-Null
    }

    Write-Host "[INFO] Extracting Web package to $ExtractPath..." -ForegroundColor Cyan
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    
    $zip = [System.IO.Compression.ZipFile]::OpenRead($ZipPath)
    foreach ($entry in $zip.Entries) {
        $targetFile = [System.IO.Path]::Combine($ExtractPath, $entry.FullName)
        $targetDir = [System.IO.Path]::GetDirectoryName($targetFile)
        
        if (-not (Test-Path $targetDir)) {
            New-Item -ItemType Directory -Force -Path $targetDir | Out-Null
        }
        
        if (-not $entry.FullName.EndsWith("/")) {
            [System.IO.Compression.ZipFileExtensions]::ExtractToFile($entry, $targetFile, $true)
        }
    }
    Write-Host "[INFO] Extraction complete." -ForegroundColor Green

} catch {
    Write-Host "[ERROR] Failed to download or extract Web.zip: $_" -ForegroundColor Red
} finally {
    # FIX: Ensure the zip stream is disposed of even if the loop crashes, releasing the file lock
    if ($null -ne $zip) {
        $zip.Dispose()
    }
    
    # Clean up zip file if it exists
    if (Test-Path $ZipPath) {
        Remove-Item $ZipPath -Force
    }
}

# ── 2. Helper functions for setting wallpapers ───────────────────────────────────────
function Set-DesktopWallpaper {
    param(
        [string]$imagePath
    )

    if (-not (Test-Path $imagePath)) {
        Write-Error "Desktop wallpaper image path does not exist: $imagePath"
        return
    }

    Get-ChildItem -Path "Registry::HKU" | ForEach-Object {
        $userKey = $_.Name
        [microsoft.win32.registry]::SetValue("$userKey\Control Panel\Desktop", "WallPaper", $imagePath, [Microsoft.Win32.RegistryValueKind]::String)
    }
    
    $setwallpapersrc = @"
    using System.Runtime.InteropServices;

    public class DesktopWallpaper
    {
      public const int SetDesktopWallpaper = 20;
      public const int UpdateIniFile = 0x01;
      public const int SendWinIniChange = 0x02;
      [DllImport("user32.dll", SetLastError = true, CharSet = CharSet.Auto)]
      private static extern int SystemParametersInfo(int uAction, int uParam, string lpvParam, int fuWinIni);
      public static void SetWallpaper(string path)
      {
        SystemParametersInfo(SetDesktopWallpaper, 0, path, UpdateIniFile |  SendWinIniChange);
      }
    }
"@
    if (-not ([System.Management.Automation.PSTypeName]'DesktopWallpaper').Type) {
        Add-Type -TypeDefinition $setwallpapersrc
    }

    [DesktopWallpaper]::SetWallpaper($imagePath)
    Write-Host "[INFO] Desktop wallpaper set to $imagePath" -ForegroundColor Green
}

function Set-LockScreenWallpaper {
    param(
        [string]$imagePath
    )

    if (!(Test-Path $imagePath)) {
        Write-Error "LockScreen wallpaper image path does not exist: $imagePath"
        return
    }

    $newImagePath = [System.IO.Path]::GetDirectoryName($imagePath) + '\' + (New-Guid).Guid + [System.IO.Path]::GetExtension($imagePath)
    Copy-Item $imagePath $newImagePath
    [Windows.System.UserProfile.LockScreen, Windows.System.UserProfile, ContentType = WindowsRuntime] | Out-Null
    Add-Type -AssemblyName System.Runtime.WindowsRuntime
    $asTaskGeneric = ([System.WindowsRuntimeSystemExtensions].GetMethods() | Where-Object { $_.Name -eq 'AsTask' -and $_.GetParameters().Count -eq 1 -and $_.GetParameters()[0].ParameterType.Name -eq 'IAsyncOperation`1' })[0]
    Function Await($WinRtTask, $ResultType) {
        $asTask = $asTaskGeneric.MakeGenericMethod($ResultType)
        $netTask = $asTask.Invoke($null, @($WinRtTask))
        $netTask.Wait(-1) | Out-Null
        $netTask.Result
    }
    Function AwaitAction($WinRtAction) {
        $asTask = ([System.WindowsRuntimeSystemExtensions].GetMethods() | Where-Object { $_.Name -eq 'AsTask' -and $_.GetParameters().Count -eq 1 -and !$_.IsGenericMethod })[0]
        $netTask = $asTask.Invoke($null, @($WinRtAction))
        $netTask.Wait(-1) | Out-Null
    }
    [Windows.Storage.StorageFile, Windows.Storage, ContentType = WindowsRuntime] | Out-Null
    $image = Await ([Windows.Storage.StorageFile]::GetFileFromPathAsync($newImagePath)) ([Windows.Storage.StorageFile])
    AwaitAction ([Windows.System.UserProfile.LockScreen]::SetImageFileAsync($image))
    Remove-Item $newImagePath -Force
    Write-Host "[INFO] Lockscreen wallpaper set to $imagePath" -ForegroundColor Green
}

# ── 3. Apply Wallpapers ──────────────────────────────────────────────────────────────
Set-DesktopWallpaper -imagePath $DesktopWallpaperPath
Set-LockScreenWallpaper -imagePath $LockScreenWallpaperPath