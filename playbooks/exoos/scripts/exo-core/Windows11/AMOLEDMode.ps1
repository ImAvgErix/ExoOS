#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Applies a pure black / AMOLED theme to Windows — ideal for OLED displays.
.DESCRIPTION
    Silently applies the black accent colour, disables transparency and enables dark mode
    system-wide via registry writes and a .reg import. No user interaction required.
    Changes take effect on the next Explorer restart or sign-in.
#>

$ErrorActionPreference = 'Stop'

function Write-Step([string]$msg) { Write-Host "[AMOLED] $msg" }

try {
    Write-Step "Applying AMOLED / pure black theme..."

    function Set-RegValue {
        param(
            [string]$Hive,
            [string]$Key,
            [string]$Name,
            $Value,
            [string]$Type = 'DWord'
        )
        $path = "${Hive}:\$Key"
        if (-not (Test-Path $path)) {
            New-Item -Path $path -Force | Out-Null
        }
        Set-ItemProperty -Path $path -Name $Name -Value $Value -Type $Type -Force
    }

    Write-Step "Setting registry values natively..."

    # ── Dark mode (system + apps) ────────────────────────────────────────────────
    Set-RegValue -Hive 'HKCU' -Key 'SOFTWARE\Microsoft\Windows\CurrentVersion\Themes\Personalize' -Name 'AppsUseLightTheme' -Value 0 -Type 'DWord'
    Set-RegValue -Hive 'HKCU' -Key 'SOFTWARE\Microsoft\Windows\CurrentVersion\Themes\Personalize' -Name 'SystemUsesLightTheme' -Value 0 -Type 'DWord'
    Set-RegValue -Hive 'HKCU' -Key 'SOFTWARE\Microsoft\Windows\CurrentVersion\Themes\Personalize' -Name 'ColorPrevalence' -Value 1 -Type 'DWord'
    Set-RegValue -Hive 'HKCU' -Key 'SOFTWARE\Microsoft\Windows\CurrentVersion\Themes\Personalize' -Name 'EnableTransparency' -Value 0 -Type 'DWord'

    Set-RegValue -Hive 'HKLM' -Key 'SOFTWARE\Microsoft\Windows\CurrentVersion\Themes\Personalize' -Name 'AppsUseLightTheme' -Value 0 -Type 'DWord'

    # ── Accent colour: pure black ─────────────────────────────────────────────────
    $accentPalette = [byte[]](0x64,0x64,0x64,0x00,0x6b,0x6b,0x6b,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00)
    Set-RegValue -Hive 'HKCU' -Key 'Software\Microsoft\Windows\CurrentVersion\Explorer\Accent' -Name 'AccentPalette' -Value $accentPalette -Type 'Binary'
    Set-RegValue -Hive 'HKCU' -Key 'Software\Microsoft\Windows\CurrentVersion\Explorer\Accent' -Name 'StartColorMenu' -Value 0 -Type 'DWord'
    Set-RegValue -Hive 'HKCU' -Key 'Software\Microsoft\Windows\CurrentVersion\Explorer\Accent' -Name 'AccentColorMenu' -Value 0 -Type 'DWord'

    # ── DWM window chrome ─────────────────────────────────────────────────────────
    Set-RegValue -Hive 'HKCU' -Key 'Software\Microsoft\Windows\DWM' -Name 'EnableWindowColorization' -Value 1 -Type 'DWord'
    Set-RegValue -Hive 'HKCU' -Key 'Software\Microsoft\Windows\DWM' -Name 'AccentColor' -Value 0xff191919 -Type 'DWord'
    Set-RegValue -Hive 'HKCU' -Key 'Software\Microsoft\Windows\DWM' -Name 'ColorizationColor' -Value 0xc4191919 -Type 'DWord'
    Set-RegValue -Hive 'HKCU' -Key 'Software\Microsoft\Windows\DWM' -Name 'ColorizationAfterglow' -Value 0xc4191919 -Type 'DWord'

    # ── Desktop background colour ─────────────────────────────────────────────────
    Set-RegValue -Hive 'HKCU' -Key 'Control Panel\Colors' -Name 'Background' -Value '0 0 0' -Type 'String'

    Write-Step "Registry values set successfully."

    # ── Notify Shell ──────────────────────────────────────────────────────────────
    # Broadcasts a WM_SETTINGCHANGE so Explorer picks up the theme change
    # without a sign-out. Best-effort — fails silently if the shell isn't running.
    try {
        Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public class WinMsg {
    [DllImport("user32.dll", SetLastError=true)]
    public static extern IntPtr SendMessageTimeout(
        IntPtr hWnd, uint Msg, UIntPtr wParam, string lParam,
        uint fuFlags, uint uTimeout, out UIntPtr lpdwResult);
}
'@ -ErrorAction SilentlyContinue

        $HWND_BROADCAST  = [IntPtr]0xffff
        $WM_SETTINGCHANGE = 0x001A
        $result = [UIntPtr]::Zero
        [WinMsg]::SendMessageTimeout($HWND_BROADCAST, $WM_SETTINGCHANGE, [UIntPtr]::Zero,
            'ImmersiveColorSet', 2, 5000, [ref]$result) | Out-Null
        Write-Step "Shell notified of theme change."
    }
    catch { Write-Step "Shell notification skipped (non-critical)." }

    Write-Step "AMOLED theme applied. Changes will be fully visible after sign-out or Explorer restart."
}
catch {
    Write-Host "[AMOLED] ERROR: $_" -ForegroundColor Red
    exit 1
}
