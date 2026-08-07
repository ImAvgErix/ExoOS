#Requires -Version 5.0


$ProgressPreference = 'SilentlyContinue'

function Kill-CopilotProcesses {
    $ErrorActionPreference = 'SilentlyContinue'
    
    foreach ($service in (Get-Service -Name '*copilot*').Name) {
        Stop-Service -Name $service -Force
    }
    
    foreach ($process in (Get-Process | Where-Object { ($_.Path -like "$([Environment]::GetFolderPath('ProgramFilesX86'))\Microsoft\Copilot\*") -or ($_.Name -like '*copilot*') }).Id) {
        Stop-Process -Id $process -Force
    }
    
    $ErrorActionPreference = 'Continue'    
}

function Remove-CopilotAppX {
    $ErrorActionPreference = 'SilentlyContinue'

    $copilotPackages = Get-AppxPackage -AllUsers *Copilot*
    
    if ($copilotPackages) {
        foreach ($package in $copilotPackages) {
            Remove-AppxPackage -Package $package.PackageFullName -AllUsers
        }
    } else {
    }
    
    $ErrorActionPreference = 'Continue'
}

function Remove-CopilotChromium {
$CopilotSetup = Get-ChildItem -Path "$([Environment]::GetFolderPath('ProgramFilesX86'))\Microsoft\Copilot\Application\*\Installer\copilot_setup.exe" -ErrorAction SilentlyContinue

if ($CopilotSetup) {
    foreach ($setup in $CopilotSetup) {
                Start-Process -FilePath $setup.FullName -ArgumentList "--uninstall --mscopilot --system-level --force-uninstall --verbose-logging" -Wait -NoNewWindow
    }
} else {
}
}

if (!([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltinRole]::Administrator)) {
    exit
}

Kill-CopilotProcesses
Remove-CopilotChromium
Remove-CopilotAppX
