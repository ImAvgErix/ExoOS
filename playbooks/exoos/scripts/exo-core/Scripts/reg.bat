@echo off

rmdir /s /q "C:\inetpub"
rmdir /s /q "C:\PerfLogs"
rmdir /s /q "C:\Windows\Web"

:: rebuild performance counters
lodctr /r > nul 2>nul
lodctr /r > nul 2>nul
winmgmt /resyncperf

:: debloat 'Send To' context menu, hidden files do not show up in the 'Send To' context menu
attrib +h "C:\Users\%loggedinusername%\AppData\Roaming\Microsoft\Windows\SendTo\Bluetooth File Transfer.LNK"
attrib +h "C:\Users\%loggedinusername%\AppData\Roaming\Microsoft\Windows\SendTo\Mail Recipient.MAPIMail"
attrib +h "C:\Users\%loggedinusername%\AppData\Roaming\Microsoft\Windows\SendTo\Documents.mydocs"

:: remove print from context menu
reg add "HKCR\SystemFileAssociations\image\shell\print" /v "ProgrammaticAccessOnly" /t REG_SZ /d "" /f
for %%a in (
    "batfile"
    "cmdfile"
    "docxfile"
    "fonfile"
    "htmlfile"
    "inffile"
    "inifile"
    "JSEFile"
    "otffile"
    "pfmfile"
    "regfile"
    "rtffile"
    "ttcfile"
    "ttffile"
    "txtfile"
    "VBEFile"
    "VBSFile"
    "WSFFile"
) do (
    reg add "HKCR\%%~a\shell\print" /v "ProgrammaticAccessOnly" /t REG_SZ /d "" /f
)

:: double click to import power schemes
reg add "HKLM\SOFTWARE\Classes\powerplan\DefaultIcon" /ve /t REG_SZ /d "C:\Windows\System32\powercpl.dll,1" /f
reg add "HKLM\SOFTWARE\Classes\powerplan\Shell\open\command" /ve /t REG_SZ /d "powercfg /import \"%1\"" /f
reg add "HKLM\SOFTWARE\Classes\.pow" /ve /t REG_SZ /d "powerplan" /f
reg add "HKLM\SOFTWARE\Classes\.pow" /v "FriendlyTypeName" /t REG_SZ /d "Power Plan" /f

:: remove give access to from context menu
reg delete "HKCR\*\shellex\ContextMenuHandlers\Sharing" /f > nul 2>nul
reg delete "HKCR\Directory\Background\shellex\ContextMenuHandlers\Sharing" /f > nul 2>nul
reg delete "HKCR\Directory\shellex\ContextMenuHandlers\Sharing" /f > nul 2>nul
reg delete "HKCR\Drive\shellex\ContextMenuHandlers\Sharing" /f > nul 2>nul
reg delete "HKCR\LibraryFolder\background\shellex\ContextMenuHandlers\Sharing" /f > nul 2>nul
reg delete "HKCR\UserLibraryFolder\shellex\ContextMenuHandlers\Sharing" /f > nul 2>nul

:: remove cast to device from context menu
reg add "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Shell Extensions\Blocked" /v "{7AD84985-87B4-4a16-BE58-8B72A5B390F7}" /t REG_SZ /d "" /f

:: remove share from context menu
reg delete "HKCR\*\shellex\ContextMenuHandlers\ModernSharing" /f > nul 2>nul

:: remove extract all from context menu
reg delete "HKCR\CompressedFolder\ShellEx\ContextMenuHandlers\{b8cdcb65-b1bf-4b42-9428-1dfdb7ee92af}" /f > nul 2>nul

:: remove bitmap image from the 'New' context menu
reg delete "HKCR\.bmp\ShellNew" /f > nul 2>nul

:: remove rich text document from the 'New' context menu
reg delete "HKCR\.rtf\ShellNew" /f > nul 2>nul

:: remove include in library from context menu
reg delete "HKCR\Folder\ShellEx\ContextMenuHandlers\Library Location" /f > nul 2>nul
reg delete "HKLM\SOFTWARE\Classes\Folder\ShellEx\ContextMenuHandlers\Library Location" /f > nul 2>nul

::Disabling Exclusive Mode On Audio Devices

for /f "delims=" %%a in ('reg query HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\MMDevices\Audio\Capture') do Reg.exe add "%%a\Properties" /v "{b3f8fa53-0004-438e-9003-51a46e139bfc},3" /t REG_DWORD /d "0" /f >nul 2>&1
for /f "delims=" %%a in ('reg query HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\MMDevices\Audio\Capture') do Reg.exe add "%%a\Properties" /v "{b3f8fa53-0004-438e-9003-51a46e139bfc},4" /t REG_DWORD /d "0" /f >nul 2>&1
for /f "delims=" %%a in ('reg query HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\MMDevices\Audio\Render') do Reg.exe add "%%a\Properties" /v "{b3f8fa53-0004-438e-9003-51a46e139bfc},3" /t REG_DWORD /d "0" /f >nul 2>&1
for /f "delims=" %%a in ('reg query HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\MMDevices\Audio\Render') do Reg.exe add "%%a\Properties" /v "{b3f8fa53-0004-438e-9003-51a46e139bfc},4" /t REG_DWORD /d "0" /f >nul 2>&1

for /f %%i in ('wmic path Win32_USBController get PNPDeviceID^| findstr /L "PCI\VEN_"') do reg add "HKLM\System\CurrentControlSet\Enum\%%i\Device Parameters\Interrupt Management\MessageSignaledInterruptProperties" /v "MSISupported" /t REG_DWORD /d "1" /f
for /f %%i in ('wmic path Win32_USBController get PNPDeviceID^| findstr /L "PCI\VEN_"') do reg delete "HKLM\SYSTEM\CurrentControlSet\Enum\%%i\Device Parameters\Interrupt Management\Affinity Policy" /v "DevicePriority" /f >nul 2>nul
for /f %%i in ('wmic path Win32_VideoController get PNPDeviceID^| findstr /L "PCI\VEN_"') do reg add "HKLM\System\CurrentControlSet\Enum\%%i\Device Parameters\Interrupt Management\MessageSignaledInterruptProperties" /v "MSISupported" /t REG_DWORD /d "1" /f
for /f %%i in ('wmic path Win32_VideoController get PNPDeviceID^| findstr /L "PCI\VEN_"') do reg add "HKLM\System\CurrentControlSet\Enum\%%i\Device Parameters\Interrupt Management\Affinity Policy" /v "DevicePriority" /f >nul 2>nul
for /f %%i in ('wmic path Win32_NetworkAdapter get PNPDeviceID^| findstr /L "PCI\VEN_"') do reg add "HKLM\System\CurrentControlSet\Enum\%%i\Device Parameters\Interrupt Management\MessageSignaledInterruptProperties" /v "MSISupported" /t REG_DWORD /d "1" /f
for /f %%i in ('wmic path Win32_IDEController get PNPDeviceID^| findstr /L "PCI\VEN_"') do reg add "HKLM\System\CurrentControlSet\Enum\%%i\Device Parameters\Interrupt Management\MessageSignaledInterruptProperties" /v "MSISupported" /t REG_DWORD /d "1" /f
for /f %%i in ('wmic path Win32_IDEController get PNPDeviceID^| findstr /L "PCI\VEN_"') do reg add "HKLM\System\CurrentControlSet\Enum\%%i\Device Parameters\Interrupt Management\Affinity Policy" /v "DevicePriority" /f >nul 2>nul
for /f %%i in ('wmic path Win32_NetworkAdapter get PNPDeviceID^| findstr /L "PCI\VEN_"') do reg add "HKLM\System\CurrentControlSet\Enum\%%i\Device Parameters\Interrupt Management\Affinity Policy" /v "DevicePriority" /f >nul 2>nul

for %%a in (EnableHIPM EnableDIPM EnableHDDParking) do for /f "delims=" %%b in ('reg query "HKLM\SYSTEM\CurrentControlSet\Services" /s /f "%%a" ^| findstr "HKEY"') do Reg.exe add "%%b" /v "%%a" /t REG_DWORD /d "0" /f >nul 2>&1

for %%a in (
    "Circular Kernel Context Logger"
    "CloudExperienceHostOobe"
    "DefenderApiLogger"
    "DefenderAuditLogger"
    "Diagtrack-Listener"
    "LwtNetLog"
    "Microsoft-Windows-Rdp-Graphics-RdpIdd-Trace"
    "NetCore"
    "NtfsLog"
    "RadioMgr"
    "RdrLog"
    "ReadyBoot"
    "SpoolerLogger"
    "UBPM"
    "WiFiSession"
) do (
    reg add "HKLM\SYSTEM\CurrentControlSet\Control\WMI\Autologger\%%~a" /v "Start" /t REG_DWORD /d "0" /f
)

:: open file explorer to this pc
reg add "HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced" /v "LaunchTo" /t REG_DWORD /d "1" /f

for %%a in (
    "SubscribedContent-338393Enabled"
    "SubscribedContent-353694Enabled"
    "SubscribedContent-353696Enabled"
    "SubscribedContent-338388Enabled"
    "SystemPaneSuggestionsEnabled"
) do (
    reg add "HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" /v "%%~a" /t REG_DWORD /d "0" /f
)

::SettingsPageVisiblity
reg add "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer" /v SettingsPageVisibility /t REG_SZ /d "hide:home;maps;findmydevice;privacy-automaticfiledownloads;cortana;privacy-feedback;windowsinsider;crossdevice" /f

del /f /q "%~f0" >nul 2>&1
exit /b