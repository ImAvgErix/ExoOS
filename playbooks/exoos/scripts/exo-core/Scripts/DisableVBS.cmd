@echo off
echo [VBS] Disabling Virtualization Based Security...

:: ── Device Guard / VBS core ──────────────────────────────────────────────────
reg add "HKLM\SYSTEM\CurrentControlSet\Control\DeviceGuard" /v "EnableVirtualizationBasedSecurity" /t REG_DWORD /d 0 /f >nul 2>&1
reg add "HKLM\SYSTEM\CurrentControlSet\Control\DeviceGuard" /v "RequirePlatformSecurityFeatures"   /t REG_DWORD /d 0 /f >nul 2>&1
reg add "HKLM\SYSTEM\CurrentControlSet\Control\DeviceGuard" /v "Locked"                           /t REG_DWORD /d 0 /f >nul 2>&1

:: ── HVCI (Hypervisor-Protected Code Integrity) ────────────────────────────────
reg add "HKLM\SYSTEM\CurrentControlSet\Control\DeviceGuard\Scenarios\HypervisorEnforcedCodeIntegrity" /v "Enabled"       /t REG_DWORD /d 0 /f >nul 2>&1
reg add "HKLM\SYSTEM\CurrentControlSet\Control\DeviceGuard\Scenarios\HypervisorEnforcedCodeIntegrity" /v "Locked"        /t REG_DWORD /d 0 /f >nul 2>&1
reg add "HKLM\SYSTEM\CurrentControlSet\Control\DeviceGuard\Scenarios\HypervisorEnforcedCodeIntegrity" /v "WasEnabledBy"  /t REG_DWORD /d 0 /f >nul 2>&1

:: ── Credential Guard ─────────────────────────────────────────────────────────
reg add "HKLM\SYSTEM\CurrentControlSet\Control\Lsa" /v "LsaCfgFlags" /t REG_DWORD /d 0 /f >nul 2>&1

:: ── Hypervisor boot entry (bcdedit) ──────────────────────────────────────────
:: Setting hypervisorlaunchtype to "off" prevents the hypervisor from loading at boot,
:: which removes the VBS sandbox entirely and recovers the associated CPU/RAM overhead.
bcdedit /set hypervisorlaunchtype off >nul 2>&1

echo [VBS] Done. Virtualization Based Security will be fully disabled after restart.
