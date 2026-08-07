$currentDir = $PSScriptRoot
if (!$currentDir) {
    $currentDir = Get-Location
}

$localExe = Join-Path $currentDir "DevManView.exe"

# ── 1. Download DevManView if not present ────────────────────────────────────
if (!(Test-Path $localExe)) {
    Write-Host "[INFO] DevManView.exe not found. Downloading from CDN..." -ForegroundColor Cyan

    try {
        $webClient = New-Object System.Net.WebClient
        $webClient.DownloadFile("https://cdn.getnexus.cc/Assets/DevManView.exe", $localExe)
        Write-Host "[INFO] DevManView.exe ready." -ForegroundColor Green
    } catch {
        Write-Host "[ERROR] Failed to download DevManView: $_" -ForegroundColor Red
        exit 1
    }
}

# ── 2. Device Disabling Action ──────────────────────────────────────────────
Write-Host "[INFO] Disabling unnecessary hardware devices..." -ForegroundColor Cyan
Write-Host ("-" * 84) -ForegroundColor Magenta

$devices = @(
    "AMD PSP",
    "AMD SMBus",
    "Base System Device",
    "Composite Bus Enumerator",
    "High precision event timer",
    "Intel Management Engine",
    "Intel SMBus",
    "Microsoft Kernel Debug Network Adapter",
    "Microsoft RRAS Root Enumerator",
    "Motherboard resources",
    "NDIS Virtual Network Adapter Enumerator",
    "Numeric Data Processor",
    "PCI Data Acquisition and Signal Processing Controller",
    "PCI Encryption/Decryption Controller",
    "PCI Memory Controller",
    "PCI Simple Communications Controller",
    "SM Bus Controller",
    "System CMOS/real time clock",
    "System Speaker",
    "System Timer",
    "UMBus Root Bus Enumerator"
)

# Run standard disable commands
foreach ($device in $devices) {
    Write-Host "[ACTION] Disabling '$device'..."
    Start-Process -FilePath $localExe -ArgumentList "/disable `"$device`"" -Wait -NoNewWindow
}

Write-Host "[INFO] Device optimization completed successfully!" -ForegroundColor Green