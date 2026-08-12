# ExoOS — disable leftover motherboard/enumerator devices (offline, no DevManView / CDN)
# Extreme-only. Never touches GPU, audio, NIC, USB hubs, HID mice/keyboards, storage.
$ErrorActionPreference = 'SilentlyContinue'
Write-Host 'Exo device disable (PnP, offline)'

$exact = @(
    'AMD PSP',
    'AMD SMBus',
    'Base System Device',
    'Composite Bus Enumerator',
    'High precision event timer',
    'Intel Management Engine',
    'Intel SMBus',
    'Microsoft Kernel Debug Network Adapter',
    'Microsoft RRAS Root Enumerator',
    'Motherboard resources',
    'NDIS Virtual Network Adapter Enumerator',
    'Numeric Data Processor',
    'PCI Data Acquisition and Signal Processing Controller',
    'PCI Encryption/Decryption Controller',
    'PCI Memory Controller',
    'PCI Simple Communications Controller',
    'SM Bus Controller',
    'System CMOS/real time clock',
    'System Speaker',
    'System Timer',
    'UMBus Root Bus Enumerator'
)

$skipClass = [regex]'Display|Net|MEDIA|USB|HIDClass|SCSIAdapter|HDC|DiskDrive|CDROM|Keyboard|Mouse|Bluetooth|Monitor|Image|Camera'
$n = 0
Get-PnpDevice -EA SilentlyContinue | ForEach-Object {
    $fn = $_.FriendlyName
    if ([string]::IsNullOrWhiteSpace($fn)) { return }
    if ($exact -notcontains $fn) { return }
    if ($_.Status -eq 'Error' -or $_.Problem -eq 22) { return }
    if ($_.Class -and $skipClass.IsMatch([string]$_.Class)) {
        Write-Host "Skip essential class $($_.Class): $fn"
        return
    }
    try {
        Disable-PnpDevice -InstanceId $_.InstanceId -Confirm:$false -EA Stop
        Write-Host "Disabled: $fn"
        $n++
    } catch {
        Write-Host "Could not disable $fn"
    }
}
Write-Host "Exo device disable done ($n)"
exit 0
