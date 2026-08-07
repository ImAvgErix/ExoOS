#requires -Version 7
<#
.SYNOPSIS
  Pull registry (and light service/appx) tweaks from research baselines into ExoOS playbook YAML.
  Sources: Winhance Optimize models, Chris Titus WinUtil tweaks.json (+ appx.json).
  Dedupes against existing playbooks/exoos actions. Exo branding only in output.
#>
param(
    [string]$ResearchRoot = "$env:USERPROFILE\Documents\ExoOS\research\baselines",
    [string]$PlaybookRoot = (Join-Path (Split-Path $PSScriptRoot -Parent) 'playbooks\exoos')
)

$ErrorActionPreference = 'Stop'
$outDir = Join-Path $PlaybookRoot 'actions\generated'
New-Item -ItemType Directory -Force -Path $outDir | Out-Null

function Normalize-Hive([string]$p) {
    if ([string]::IsNullOrWhiteSpace($p)) { return $p }
    $p = $p.Trim()
    $p = $p -replace '^HKLM:\\', 'HKLM\' -replace '^HKCU:\\', 'HKCU\' -replace '^HKCR:\\', 'HKCR\' -replace '^HKU:\\', 'HKU\'
    $p = $p -replace '^HKEY_LOCAL_MACHINE\\', 'HKLM\' -replace '^HKEY_CURRENT_USER\\', 'HKCU\'
    $p = $p -replace '^HKEY_CLASSES_ROOT\\', 'HKCR\' -replace '^HKEY_USERS\\', 'HKU\'
    $p = $p -replace '\\\\', '\'
    # collapse CurrentControlSet variants
    $p = $p -replace '\\ControlSet001\\', '\CurrentControlSet\'
    $p = $p -replace '\\ControlSet002\\', '\CurrentControlSet\'
    return $p
}

function Fingerprint([string]$path, [string]$name) {
    $p = (Normalize-Hive $path).ToLowerInvariant()
    $n = if ($name) { $name.ToLowerInvariant() } else { '' }
    return "$p|$n"
}

function Yaml-Escape([string]$s) {
    if ($null -eq $s) { return "''" }
    $s = $s -replace "'", "''"
    return "'$s'"
}

function Map-Type([string]$t) {
    switch -Regex ($t) {
        '^(?i)dword|reg_dword$' { return 'dword' }
        '^(?i)qword|reg_qword$' { return 'qword' }
        '^(?i)string|sz|reg_sz$' { return 'string' }
        '^(?i)expand|expandstring|reg_expand_sz$' { return 'expandstring' }
        '^(?i)binary|bin|reg_binary$' { return 'binary' }
        '^(?i)multi|multistring|reg_multi_sz$' { return 'string' }
        default { return 'dword' }
    }
}

# --- Existing fingerprints ---
$existing = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
$existingServices = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
$existingAppx = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)

# Exclude our own merge outputs so re-runs regenerate cleanly
Get-ChildItem (Join-Path $PlaybookRoot 'actions') -Recurse -Filter *.yml | Where-Object {
    $_.Name -notmatch '^(12-reg-research|42-services-research|92-appx-research)'
} | ForEach-Object {
    $lines = Get-Content $_.FullName
    $path = $null; $name = $null
    foreach ($line in $lines) {
        if ($line -match "^\s+path:\s*'([^']+)'") { $path = $Matches[1] }
        if ($line -match '^\s+path:\s*"([^"]+)"') { $path = $Matches[1] }
        if ($line -match "^\s+valueName:\s*'([^']+)'") { $name = $Matches[1] }
        if ($line -match '^\s+valueName:\s*"([^"]+)"') { $name = $Matches[1] }
        if ($line -match "^\s+service:\s*'([^']+)'") { [void]$existingServices.Add($Matches[1]) }
        if ($line -match "^\s+package:\s*'([^']+)'") { [void]$existingAppx.Add($Matches[1]) }
        if ($path -and $name -and $line -match '^\s+(value:|description:|id:)') {
            [void]$existing.Add((Fingerprint $path $name))
            $name = $null
        }
    }
}
Write-Host "Existing registry fingerprints: $($existing.Count)"
Write-Host "Existing services: $($existingServices.Count)  appx: $($existingAppx.Count)"

# Skip pure UI cosmetics / high-risk identity / product branding
$skipName = [regex]'^(?i)(Wallpaper|LockScreen|Theme|AccentColor|Start_Layout|TaskbarAl)$'
$skipPath = [regex]'(?i)\\(Themes|Personalization\\|Desktop\\Wallpaper|CloudStore\\)'

$candidates = New-Object System.Collections.Generic.List[object]

function Add-Reg {
    param($Path, $Name, $Value, $Type, $Source, $Note)
    if ([string]::IsNullOrWhiteSpace($Path) -or [string]::IsNullOrWhiteSpace($Name)) { return }
    if ($null -eq $Value -or "$Value" -eq '' -or "$Value" -eq '<RemoveEntry>') { return }
    $Path = Normalize-Hive $Path
    if ($skipName.IsMatch($Name)) { return }
    if ($skipPath.IsMatch($Path)) { return }
    # skip empty binary placeholders
    if ("$Value" -match '^(?i)<.*>$') { return }
    $fp = Fingerprint $Path $Name
    if ($existing.Contains($fp)) { return }
    # also skip if already in this batch
    foreach ($c in $candidates) {
        if ((Fingerprint $c.Path $c.Name) -eq $fp) { return }
    }
    $vt = Map-Type $Type
    $val = "$Value"
    # strip 0x prefix
    if ($val -match '^0x([0-9a-fA-F]+)$') { $val = [Convert]::ToInt64($Matches[1], 16).ToString() }
    $candidates.Add([pscustomobject]@{
            Path   = $Path
            Name   = $Name
            Value  = $val
            Type   = $vt
            Source = $Source
            Note   = $Note
        }) | Out-Null
    [void]$existing.Add($fp)
}

# ========== Winhance Optimize models ==========
$whDir = Join-Path $ResearchRoot 'Winhance\src\Winhance.Core\Features\Optimize\Models'
$whCount = 0
if (Test-Path $whDir) {
    foreach ($f in Get-ChildItem $whDir -Filter *Optimizations.cs) {
        $text = Get-Content $f.FullName -Raw
        # Split into RegistrySetting blocks
        $blocks = [regex]::Matches($text, 'new RegistrySetting\s*\{(?<body>[\s\S]*?)\n\s*\},?')
        foreach ($b in $blocks) {
            $body = $b.Groups['body'].Value
            $key = $null; $name = $null; $rec = $null; $en = $null; $vtype = 'DWord'
            if ($body -match 'KeyPath\s*=\s*@"(?<k>[^"]+)"') { $key = $Matches['k'] }
            elseif ($body -match 'KeyPath\s*=\s*"(?<k>[^"]+)"') { $key = $Matches['k'] }
            if ($body -match 'ValueName\s*=\s*"(?<n>[^"]+)"') { $name = $Matches['n'] }
            if ($body -match 'ValueType\s*=\s*RegistryValueKind\.(?<t>\w+)') { $vtype = $Matches['t'] }
            # RecommendedValue preferred
            if ($body -match 'RecommendedValue\s*=\s*(?<v>\d+)') { $rec = $Matches['v'] }
            elseif ($body -match 'RecommendedValue\s*=\s*"(?<v>[^"]*)"') { $rec = $Matches['v'] }
            elseif ($body -match 'RecommendedValue\s*=\s*null') { $rec = $null }
            # EnabledValue first element as fallback (toggle ON path)
            if ($body -match 'EnabledValue\s*=\s*\[(?<list>[^\]]+)\]') {
                $list = $Matches['list']
                if ($list -match '^\s*(\d+)') { $en = $Matches[1] }
                elseif ($list -match '"([^"]*)"') { $en = $Matches[1] }
            }
            # DisabledValue when recommended is "off" style and EnabledValue empty
            $val = $null
            if ($null -ne $rec -and "$rec" -ne '') { $val = $rec }
            elseif ($null -ne $en -and "$en" -ne '') { $val = $en }
            if ($null -eq $val -or "$val" -eq 'null') { continue }
            Add-Reg -Path $key -Name $name -Value $val -Type $vtype -Source 'winhance' -Note $f.BaseName
            $whCount++
        }
    }
}
Write-Host "Winhance blocks scanned: $whCount  (new candidates so far $($candidates.Count))"

# ========== Chris Titus WinUtil ==========
$twPath = Join-Path $ResearchRoot 'winutil\config\tweaks.json'
$wuReg = 0
if (Test-Path $twPath) {
    $tj = Get-Content $twPath -Raw | ConvertFrom-Json
    foreach ($prop in $tj.PSObject.Properties) {
        $t = $prop.Value
        $title = $t.Content
        if ($t.registry) {
            foreach ($r in @($t.registry)) {
                $path = $r.Path; if (-not $path) { $path = $r.path }
                $name = $r.Name; if (-not $name) { $name = $r.name }
                $val = $r.Value; if ($null -eq $val) { $val = $r.value }
                $type = $r.Type; if (-not $type) { $type = $r.type }
                if ("$val" -eq '<RemoveEntry>') { continue } # delete not always safe in bulk
                Add-Reg -Path $path -Name $name -Value $val -Type $type -Source 'winutil' -Note $prop.Name
                $wuReg++
            }
        }
    }
}
Write-Host "WinUtil registry rows scanned: $wuReg  candidates: $($candidates.Count)"

# ========== Winhance Privacy + Gaming already in Optimize — also scan Customize? ==========
$custDir = Join-Path $ResearchRoot 'Winhance\src\Winhance.Core\Features\Customize\Models'
if (Test-Path $custDir) {
    $before = $candidates.Count
    foreach ($f in Get-ChildItem $custDir -Filter *.cs -ErrorAction SilentlyContinue) {
        $text = Get-Content $f.FullName -Raw
        $blocks = [regex]::Matches($text, 'new RegistrySetting\s*\{(?<body>[\s\S]*?)\n\s*\},?')
        foreach ($b in $blocks) {
            $body = $b.Groups['body'].Value
            $key = $null; $name = $null; $rec = $null; $en = $null; $vtype = 'DWord'
            if ($body -match 'KeyPath\s*=\s*@"(?<k>[^"]+)"') { $key = $Matches['k'] }
            elseif ($body -match 'KeyPath\s*=\s*"(?<k>[^"]+)"') { $key = $Matches['k'] }
            if ($body -match 'ValueName\s*=\s*"(?<n>[^"]+)"') { $name = $Matches['n'] }
            if ($body -match 'ValueType\s*=\s*RegistryValueKind\.(?<t>\w+)') { $vtype = $Matches['t'] }
            if ($body -match 'RecommendedValue\s*=\s*(?<v>\d+)') { $rec = $Matches['v'] }
            elseif ($body -match 'RecommendedValue\s*=\s*"(?<v>[^"]*)"') { $rec = $Matches['v'] }
            if ($body -match 'EnabledValue\s*=\s*\[(?<list>[^\]]+)\]') {
                $list = $Matches['list']
                if ($list -match '^\s*(\d+)') { $en = $Matches[1] }
                elseif ($list -match '"([^"]*)"') { $en = $Matches[1] }
            }
            $val = if ($null -ne $rec -and "$rec" -ne '') { $rec } else { $en }
            if ($null -eq $val -or "$val" -eq 'null') { continue }
            Add-Reg -Path $key -Name $name -Value $val -Type $vtype -Source 'winhance-customize' -Note $f.BaseName
        }
    }
    Write-Host "Winhance Customize added: $($candidates.Count - $before)"
}

# ========== WinUtil services / scheduled tasks if present ==========
$serviceAdds = New-Object System.Collections.Generic.List[object]
$appxAdds = New-Object System.Collections.Generic.List[object]
if (Test-Path $twPath) {
    $tj = Get-Content $twPath -Raw | ConvertFrom-Json
    foreach ($prop in $tj.PSObject.Properties) {
        $t = $prop.Value
        if ($null -ne $t.service) {
            $svcList = @($t.service)
            foreach ($s in $svcList) {
                if ($null -eq $s) { continue }
                $sn = $s.Name; if (-not $sn) { $sn = $s.name }
                $st = $s.StartupType; if (-not $st) { $st = $s.startupType }
                if (-not $sn) { continue }
                if ($existingServices.Contains($sn)) { continue }
                $start = switch -Regex ("$st") {
                    '(?i)disable' { '4'; break }
                    '(?i)manual' { '3'; break }
                    '(?i)auto' { '2'; break }
                    default { '4' }
                }
                $serviceAdds.Add([pscustomobject]@{ Name = $sn; Start = $start; Source = $prop.Name }) | Out-Null
                [void]$existingServices.Add($sn)
            }
        }
    }
}

# WinUtil appx.json — PackageId fields
$appxJson = Join-Path $ResearchRoot 'winutil\config\appx.json'
if (Test-Path $appxJson) {
    try {
        $aj = Get-Content $appxJson -Raw | ConvertFrom-Json
        foreach ($prop in $aj.PSObject.Properties) {
            $val = $prop.Value
            $pkg = $val.PackageId
            if (-not $pkg) { $pkg = $val.packageId }
            if (-not $pkg) { continue }
            $pat = "*$pkg*"
            if ($existingAppx.Contains($pat) -or $existingAppx.Contains($pkg)) { continue }
            $appxAdds.Add($pkg) | Out-Null
            [void]$existingAppx.Add($pat)
        }
    } catch { Write-Host "appx.json parse skip: $_" }
}

Write-Host "New registry: $($candidates.Count)  services: $($serviceAdds.Count)  appx: $($appxAdds.Count)"

# ========== Emit YAML ==========
function Emit-RegFile($items, $fileName, $title) {
    $sb = [System.Text.StringBuilder]::new()
    [void]$sb.AppendLine("title: $title")
    [void]$sb.AppendLine("# Auto-merged from research baselines. Deduped against existing ExoOS actions.")
    [void]$sb.AppendLine("actions:")
    $i = 0
    foreach ($c in ($items | Sort-Object Path, Name)) {
        $i++
        $id = "exo-merge-$($c.Source)-$i"
        [void]$sb.AppendLine("  - type: registry.set")
        [void]$sb.AppendLine("    id: $(Yaml-Escape $id)")
        [void]$sb.AppendLine("    path: $(Yaml-Escape $c.Path)")
        [void]$sb.AppendLine("    valueName: $(Yaml-Escape $c.Name)")
        [void]$sb.AppendLine("    valueType: $($c.Type)")
        [void]$sb.AppendLine("    value: $(Yaml-Escape $c.Value)")
        [void]$sb.AppendLine("    description: 'Exo'")
        [void]$sb.AppendLine("")
    }
    $path = Join-Path $outDir $fileName
    [System.IO.File]::WriteAllText($path, $sb.ToString())
    Write-Host "Wrote $path ($i actions)"
    return $i
}

$whItems = @($candidates | Where-Object { $_.Source -like 'winhance*' })
$wuItems = @($candidates | Where-Object { $_.Source -eq 'winutil' })
$nWh = Emit-RegFile $whItems '12-reg-research-winhance.yml' 'Research merge — registry (Winhance-class)'
$nWu = Emit-RegFile $wuItems '12-reg-research-winutil.yml' 'Research merge — registry (WinUtil-class)'

# services
$svcPath = Join-Path $outDir '42-services-research.yml'
$sb = [System.Text.StringBuilder]::new()
[void]$sb.AppendLine('title: Research merge — services')
[void]$sb.AppendLine('actions:')
$si = 0
foreach ($s in $serviceAdds) {
    $si++
    [void]$sb.AppendLine('  - type: service.set')
    [void]$sb.AppendLine("    id: 'exo-svc-merge-$si'")
    [void]$sb.AppendLine("    service: $(Yaml-Escape $s.Name)")
    [void]$sb.AppendLine("    start: '$($s.Start)'")
    [void]$sb.AppendLine('    stop: true')
    [void]$sb.AppendLine("    whenOption: serviceStrip")
    [void]$sb.AppendLine("    description: 'Exo'")
    [void]$sb.AppendLine('')
}
[System.IO.File]::WriteAllText($svcPath, $sb.ToString())
Write-Host "Wrote $svcPath ($si services)"

# appx — gate behind keep bloat false? use no gate for gaming strip common apps; limit to 80 to avoid nuking everything
$appxPath = Join-Path $outDir '92-appx-research.yml'
$sb = [System.Text.StringBuilder]::new()
[void]$sb.AppendLine('title: Research merge — AppX candidates')
[void]$sb.AppendLine('# Conservative: only well-known consumer bloat package name fragments')
[void]$sb.AppendLine('actions:')
# Keep Store, Calculator, Photos, Terminal, Notepad, Camera, Clock, Paint out of auto-remove
$deny = [regex]'(?i)(WindowsStore|XboxIdentityProvider|DesktopAppInstaller|SecHealthUI|Windows\.Photos|WindowsCalculator|WindowsNotepad|WindowsTerminal|WindowsCamera|WindowsAlarms|MSPaint|Microsoft\.Paint|HEIFImageExtension|VP9VideoExtensions|WebMediaExtensions|WebpImageExtension)'
$ai = 0
foreach ($pkg in ($appxAdds | Sort-Object -Unique)) {
    if ($deny.IsMatch($pkg)) { continue }
    $ai++
    [void]$sb.AppendLine('  - type: appx.remove')
    [void]$sb.AppendLine("    id: 'exo-appx-merge-$ai'")
    [void]$sb.AppendLine("    package: $(Yaml-Escape "*$pkg*")")
    [void]$sb.AppendLine('    ignoreErrors: true')
    [void]$sb.AppendLine("    description: 'Exo'")
    [void]$sb.AppendLine('')
}
[System.IO.File]::WriteAllText($appxPath, $sb.ToString())
Write-Host "Wrote $appxPath ($ai appx)"

# stats
$stats = [ordered]@{
    existingRegistryFingerprints = $existing.Count
    newWinhanceRegistry          = $nWh
    newWinutilRegistry           = $nWu
    newServices                  = $si
    newAppx                      = $ai
    researchRoot                 = $ResearchRoot
    generated                    = (Get-Date).ToString('o')
    intent                       = 'Max-coverage merge from RE baselines (Winhance + Chris Titus WinUtil) + dedupe'
}
$stats | ConvertTo-Json | Set-Content (Join-Path $PlaybookRoot 'RESEARCH-MERGE-STATS.json')
Write-Host ($stats | ConvertTo-Json)
Write-Host 'Done. Wire new YAML files into playbook.yml actionFiles if not already present.'
