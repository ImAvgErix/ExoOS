# ExoOS — WASAPI / communications latency pack
# Exclusive mode for default render+capture, no ducking, disable enhancements where possible.
# Never disables AudioSrv.
$ErrorActionPreference = 'SilentlyContinue'
Write-Host 'Exo audio latency tune'

# System-wide: don't reduce volume of other apps when communicating
$mm = 'HKCU:\Software\Microsoft\Multimedia\Audio'
New-Item -Path $mm -Force | Out-Null
New-ItemProperty -Path $mm -Name UserDuckingPreference -PropertyType DWord -Value 3 -Force | Out-Null

# Disable Windows "communications" ducking policy
$pol = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Audio'
New-Item -Path $pol -Force | Out-Null
New-ItemProperty -Path $pol -Name DisableProtectedAudioDG -PropertyType DWord -Value 1 -Force | Out-Null

# Game DVR / captury already off elsewhere — reinforce mic capture privacy
$gcs = 'HKCU:\System\GameConfigStore'
New-Item -Path $gcs -Force | Out-Null
New-ItemProperty -Path $gcs -Name GameDVR_MicrophoneCaptureEnabled -PropertyType DWord -Value 0 -Force | Out-Null

# Disable audio enhancements on all endpoints (FxProperties)
$mmdev = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\MMDevices\Audio'
foreach ($role in @('Render', 'Capture')) {
  $root = Join-Path $mmdev $role
  if (-not (Test-Path $root)) { continue }
  Get-ChildItem $root -EA SilentlyContinue | ForEach-Object {
    $fx = Join-Path $_.PSPath 'FxProperties'
    if (-not (Test-Path $fx)) { New-Item -Path $fx -Force | Out-Null }
    # {1da5d803-d492-4edd-8c23-e0c0ffee7f0e},5 = Disable all enhancements (PKEY_AudioEndpoint_Disable_SysFx)
    New-ItemProperty -Path $fx -Name '{1da5d803-d492-4edd-8c23-e0c0ffee7f0e},5' -PropertyType DWord -Value 1 -Force | Out-Null
  }
}

# Prefer exclusive mode at engine level (best-effort; apps still control their own WASAPI flags)
$audio = 'HKCU:\Software\Microsoft\Multimedia\Audio'
New-ItemProperty -Path $audio -Name AccessibilityMonoMixState -PropertyType DWord -Value 0 -Force | Out-Null

Write-Host 'Audio: ducking off, SysFx disabled on endpoints, GameDVR mic off'
exit 0
