$CabPath = Join-Path $PSScriptRoot 'NexusOS-Defender-Removal31bf3856ad364e35amd641.0.0.0.cab'
$certRegPath = "HKLM:\Software\Microsoft\SystemCertificates\ROOT\Certificates"
$remove_appx = @("SecHealthUI")
$provisioned = Get-AppxProvisionedPackage -Online
$appxpackage = Get-AppxPackage -AllUsers
$store = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Appx\AppxAllUserStore'
$users = @('S-1-5-18')
$visRegPath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer"
$visName    = "SettingsPageVisibility"
$addEntry   = "windowsdefender"

if (!(Test-Path $CabPath)) {
    Write-Host "[INFO] Downloading Defender removal package from CDN..." -ForegroundColor Cyan
    try {
        $webClient = New-Object System.Net.WebClient
        $webClient.DownloadFile("https://cdn.getnexus.cc/Assets/NexusOS-Defender-Removal31bf3856ad364e35amd641.0.0.0.cab", $CabPath)
        Write-Host "[INFO] Download complete."
    } catch {
        Write-Host "[ERROR] Failed to download package from CDN: $_" -ForegroundColor Red
        exit 1
    }
}

function ProcessCab($cabPath) {
	$filePath = Split-Path $cabPath -Leaf
	Write-Host "`nInstalling $filePath..." -ForegroundColor Cyan
	Write-Host ("-" * 84) -ForegroundColor Magenta

	Write-Host "[INFO] Checking certificate..."
	try {
		$cert = (Get-AuthenticodeSignature $cabPath).SignerCertificate
		if ($cert.Extensions.EnhancedKeyUsages.Value -ne "1.3.6.1.4.1.311.10.3.6") {
			Write-Host "[ERROR] Cert doesn't have proper key usages, can't continue." -ForegroundColor Red
			$script:errorLevel++
			return $false
		}

		$certRegPath = "HKLM:\Software\Microsoft\SystemCertificates\ROOT\Certificates\8A334AA8052DD244A647306A76B8178FA215F344"
		if (!(Test-Path "$certRegPath")) {
			New-Item -Path $certRegPath -Force | Out-Null
		}
	} catch {
		Write-Host "[ERROR] Cert error from '$cabPath': $_" -ForegroundColor Red
		$script:errorLevel++
		return $false
	}

	Write-Host "[INFO] Adding package..."
	try {
		Add-WindowsPackage -Online -PackagePath $cabPath -NoRestart -IgnoreCheck -LogLevel 1 *>$null
	} catch {
		Write-Host "[ERROR] Error when adding package '$cabPath': $_" -ForegroundColor Red
		$script:errorLevel++
		return $false
	}

    Write-Host "[INFO] Removing Defender Icon from Start Menu..."

    
    if (Test-Path $store) {
        $users += $((dir $store -ea 0 | where { $_ -like '*S-1-5-21*' }).PSChildName)
    }

    foreach ($choice in $remove_appx) {
        if ('' -eq $choice.Trim()) { continue }

        foreach ($appx in $($provisioned | where { $_.PackageName -like "*$choice*" })) {
            $PackageName = $appx.PackageName
            $PackageFamilyName = ($appxpackage | where { $_.Name -eq $appx.DisplayName }).PackageFamilyName
            ni "$store\Deprovisioned\$PackageFamilyName" -force >$null
            foreach ($sid in $users) { ni "$store\EndOfLife\$sid\$PackageName" -force >$null }
            Write-Host "Hidden: $PackageFamilyName"
        }
    }

    Write-Host "[INFO] Disabling Smart App Control..."
    try {
        $ciPath = "HKLM:\SYSTEM\CurrentControlSet\Control\CI\Policy"
        if (!(Test-Path $ciPath)) {
            New-Item -Path $ciPath -Force | Out-Null
        }
        Set-ItemProperty -Path $ciPath -Name "VerifiedAndReputablePolicyState" -Value 0 -Type DWord -Force
        
        $wtdsPath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WTDS\Components"
        if (!(Test-Path $wtdsPath)) {
            New-Item -Path $wtdsPath -Force | Out-Null
        }
        Set-ItemProperty -Path $wtdsPath -Name "ServiceEnabled" -Value 0 -Type DWord -Force
    } catch {
        Write-Host "[WARNING] Failed to disable Smart App Control: $_" -ForegroundColor Yellow
    }

    try {
        if (!(Test-Path $visRegPath)) {
            New-Item -Path $visRegPath -Force | Out-Null
        }

        $current = (Get-ItemProperty -Path $visRegPath -Name $visName -ErrorAction SilentlyContinue).$visName

        if ([string]::IsNullOrEmpty($current)) {
            $newValue = "hide:$addEntry"
        } elseif ($current -notmatch [regex]::Escape($addEntry)) {
            $newValue = $current.TrimEnd(';') + ";$addEntry"
        } else {
            $newValue = $current
            Write-Host "[INFO] '$addEntry' already present in SettingsPageVisibility, skipping." -ForegroundColor Yellow
        }

        Set-ItemProperty -Path $visRegPath -Name $visName -Value $newValue -Type String -Force
        Write-Host "[INFO] SettingsPageVisibility updated: $newValue" -ForegroundColor Cyan
    } catch {
        Write-Host "[ERROR] Failed to update SettingsPageVisibility: $_" -ForegroundColor Red
    }
    
	Write-Host "[INFO] Completed sucessfully."
	
	return $true
}

ProcessCab $CabPath