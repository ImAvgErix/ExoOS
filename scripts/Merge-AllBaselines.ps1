#requires -Version 7
<#
.SYNOPSIS
  Sweep ALL research baselines (playbooks, ISOs/KernelOS dumps, WinUtil, Winhance, CSVs)
  and merge useful registry / service / appx actions into ExoOS playbook YAML.
  Dedupes against existing actions (excluding our research-merge outputs for regenerate).
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
    $p = $p.Trim().Trim("'").Trim('"')
    $p = $p -replace '^HKLM:\\', 'HKLM\' -replace '^HKCU:\\', 'HKCU\' -replace '^HKCR:\\', 'HKCR\'
    $p = $p -replace '^HKEY_LOCAL_MACHINE\\', 'HKLM\' -replace '^HKEY_CURRENT_USER\\', 'HKCU\'
    $p = $p -replace '^HKEY_CLASSES_ROOT\\', 'HKCR\' -replace '^HKEY_USERS\\', 'HKU\'
    $p = $p -replace '\\\\', '\'
    $p = $p -replace '\\ControlSet001\\', '\CurrentControlSet\'
    $p = $p -replace '\\ControlSet002\\', '\CurrentControlSet\'
    $p = $p -replace '\\OfflineSys\\', '\SYSTEM\'
    $p = $p -replace 'HKU\\AME_UserHive_Default', 'HKCU'
    $p = $p -replace 'HKU\\Default', 'HKCU'
    return $p
}

function Fingerprint([string]$path, [string]$name) {
    return ((Normalize-Hive $path).ToLowerInvariant() + '|' + ($name ?? '').ToLowerInvariant())
}

function Yaml-Escape([string]$s) {
    if ($null -eq $s) { return "''" }
    return ("'" + ($s -replace "'", "''") + "'")
}

function Map-Type([string]$t) {
    switch -Regex ("$t") {
        '^(?i)REG_DWORD|DWORD$' { 'dword'; break }
        '^(?i)REG_QWORD|QWORD$' { 'qword'; break }
        '^(?i)REG_SZ|STRING|SZ$' { 'string'; break }
        '^(?i)REG_EXPAND_SZ|EXPAND' { 'expandstring'; break }
        '^(?i)REG_BINARY|BINARY' { 'binary'; break }
        '^(?i)REG_MULTI_SZ' { 'string'; break }
        default { 'dword' }
    }
}

# --- Existing fingerprints (skip regenerable merge outputs) ---
$existingReg = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
$existingSvc = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
$existingAppx = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)

Get-ChildItem (Join-Path $PlaybookRoot 'actions') -Recurse -Filter *.yml | Where-Object {
    $_.Name -notmatch '^(12-reg-research|13-reg-baselines|42-services-research|43-services-baselines|92-appx-research|93-appx-baselines)'
} | ForEach-Object {
    $path = $null; $name = $null
    foreach ($line in Get-Content $_.FullName) {
        if ($line -match "^\s+path:\s*'([^']+)'") { $path = $Matches[1] }
        if ($line -match "^\s+valueName:\s*'([^']+)'") { $name = $Matches[1] }
        if ($line -match "^\s+service:\s*'([^']+)'") { [void]$existingSvc.Add($Matches[1]) }
        if ($line -match "^\s+package:\s*'([^']+)'") { [void]$existingAppx.Add($Matches[1].Trim('*')) }
        if ($path -and $name -and $line -match '^\s+(value:|description:|id:|valueType:)') {
            [void]$existingReg.Add((Fingerprint $path $name))
            $name = $null
        }
    }
}
# Also index previous research merge files so we don't double-add if keeping them
Get-ChildItem $outDir -Filter '12-reg-research*.yml' -EA SilentlyContinue | ForEach-Object {
    $path = $null; $name = $null
    foreach ($line in Get-Content $_.FullName) {
        if ($line -match "^\s+path:\s*'([^']+)'") { $path = $Matches[1] }
        if ($line -match "^\s+valueName:\s*'([^']+)'") { $name = $Matches[1] }
        if ($path -and $name -and $line -match '^\s+(value:|description:)') {
            [void]$existingReg.Add((Fingerprint $path $name)); $name = $null
        }
    }
}
Write-Host "Existing reg fingerprints: $($existingReg.Count)  svc: $($existingSvc.Count)  appx: $($existingAppx.Count)"

$skipPath = [regex]'(?i)(\\Themes\\|\\Desktop\\Wallpaper|\\CloudStore\\|AtlasDesktop|AtlasModules|\\Policies\\Microsoft\\Edge\\.*Extension|\\Uninstall\\)'
$skipName = [regex]'(?i)^(Wallpaper|Theme|AccentColor)$'
# Skip OEM branding from other distros
$skipPath2 = [regex]'(?i)(OEMInformation|RegisteredOwner|RegisteredOrganization|AtlasOS|ReviOS|KernelOS|NOVA OS|RapidOS)'

$regs = New-Object System.Collections.Generic.List[object]
$svcs = New-Object System.Collections.Generic.List[object]
$appx = New-Object System.Collections.Generic.List[object]
$stats = [ordered]@{}

function Add-Reg($Path, $Name, $Data, $Type, $Source) {
    if ([string]::IsNullOrWhiteSpace($Path) -or [string]::IsNullOrWhiteSpace($Name)) { return }
    if ($null -eq $Data -or "$Data" -eq '' -or "$Data" -eq 'null') { return }
    if ("$Data" -match '^(?i)<.*>$') { return }
    $Path = Normalize-Hive $Path
    if ($Path -notmatch '^(HKLM|HKCU|HKCR|HKU)\\') { return }
    if ($skipPath.IsMatch($Path) -or $skipPath2.IsMatch($Path) -or $skipName.IsMatch($Name)) { return }
    # skip interface-wildcard Nagle (engine can't expand %%i)
    if ($Path -match 'Interfaces\\%') { return }
    $fp = Fingerprint $Path $Name
    if ($existingReg.Contains($fp)) { return }
    [void]$existingReg.Add($fp)
    $val = "$Data"
    if ($val -match '^0x([0-9a-fA-F]+)$') { $val = [Convert]::ToInt64($Matches[1], 16).ToString() }
    # uint32 max for NetworkThrottlingIndex etc.
    if ($val -eq '4294967295') { $val = '4294967295' }
    $regs.Add([pscustomobject]@{ Path = $Path; Name = $Name; Value = $val; Type = (Map-Type $Type); Source = $Source }) | Out-Null
}

function Add-Svc($Name, $Start, $Source) {
    if ([string]::IsNullOrWhiteSpace($Name)) { return }
    $Name = $Name.Trim()
    if ($existingSvc.Contains($Name)) { return }
    # skip critical always-on
    if ($Name -match '^(?i)(RpcSs|DcomLaunch|LSM|EventLog|PlugPlay|Power|SystemEventsBroker|Schedule|ProfSvc|UserManager|BrokerInfrastructure|CoreMessagingRegistrar|StateRepository|camsvc|AppXSvc|ClipSVC|gpsvc|CryptSvc|Dhcp|Dnscache|NlaSvc|nsi|Wcmsvc|Winmgmt|SamSs|LanmanServer|LanmanWorkstation|BFE|mpssvc|WinDefend|SecurityHealthService|WdNisSvc|Sense|wscsvc)$') { return }
    [void]$existingSvc.Add($Name)
    $start = switch -Regex ("$Start") {
        '^(?i)4|disabled?$' { '4'; break }
        '^(?i)3|manual$' { '3'; break }
        '^(?i)2|auto' { '2'; break }
        '^(?i)1|system$' { '1'; break }
        default { '4' }
    }
    $svcs.Add([pscustomobject]@{ Name = $Name; Start = $start; Source = $Source }) | Out-Null
}

function Add-Appx($Name, $Source) {
    if ([string]::IsNullOrWhiteSpace($Name)) { return }
    $Name = $Name.Trim().Trim('*')
    if ($Name.Length -lt 4) { return }
    if ($Name -match '^(?i)(REG_|DWORD|SZ|BINARY|QWORD|\d+$)') { return }
    if ($Name -notmatch '\.') { return } # package families look like Publisher.Name
    if ($Name -match '^(?i)(Microsoft\.WindowsStore|Microsoft\.DesktopAppInstaller|Microsoft\.SecHealthUI|Microsoft\.WindowsTerminal|Microsoft\.WindowsNotepad|Microsoft\.WindowsCalculator|Microsoft\.Windows\.Photos|Microsoft\.Paint|Microsoft\.WindowsCamera|Microsoft\.XboxIdentityProvider)$') { return }
    if ($existingAppx.Contains($Name)) { return }
    [void]$existingAppx.Add($Name)
    $appx.Add([pscustomobject]@{ Name = $Name; Source = $Source }) | Out-Null
}

# ========== 1) AME-style YAML across playbook trees ==========
$yamlRoots = @(
    'Atlas-apbx-extracted',
    'ReviOS-apbx-extracted',
    'meetrevision-playbook-Revi-PB-26.04-extracted',
    'RapidOS-apbx-extracted',
    'NOVA-apbx-extracted',
    'PrivacyPlus-extracted',
    'AME10-Beta-extracted',
    'FSOS-X-extracted',
    'RivalsOS',
    'SynergyOS',
    'KiyomizuOS',
    'NOVA-source',
    'RapidOS-source',
    'ReviOS-playbook',
    'Atlas',
    'Vain-extracted',
    'XOS-extracted',
    'XOS V0.574-extracted',
    'vain v14 hotfix6-extracted'
)

$yamlFiles = 0
foreach ($root in $yamlRoots) {
    $dir = Join-Path $ResearchRoot $root
    if (-not (Test-Path $dir)) { continue }
    $before = $regs.Count
    Get-ChildItem $dir -Recurse -Filter *.yml -EA SilentlyContinue | Where-Object {
        $_.FullName -notmatch '\\(node_modules|\.git|Executables\\AtlasDesktop)\\'
    } | ForEach-Object {
        $yamlFiles++
        $text = Get-Content $_.FullName -Raw -EA SilentlyContinue
        if (-not $text) { return }
        $src = $root

        # Inline: !registryValue: {path: '...', value: '...', data: '...', type: REG_DWORD}
        foreach ($m in [regex]::Matches($text, '!registryValue:\s*\{([^}]+)\}')) {
            $body = $m.Groups[1].Value
            $p = $null; $v = $null; $d = $null; $t = 'REG_DWORD'
            if ($body -match "path:\s*'([^']+)'") { $p = $Matches[1] }
            if ($body -match "value:\s*'([^']*)'") { $v = $Matches[1] }
            if ($body -match "data:\s*'([^']*)'") { $d = $Matches[1] }
            if ($body -match "type:\s*([A-Za-z0-9_]+)") { $t = $Matches[1] }
            Add-Reg $p $v $d $t $src
        }

        # Multiline blocks
        foreach ($m in [regex]::Matches($text, '!registryValue:\s*\r?\n(?<b>(?:[ \t]+[^\r\n]*\r?\n)+)')) {
            $body = $m.Groups['b'].Value
            $p = $null; $v = $null; $d = $null; $t = 'REG_DWORD'
            if ($body -match "(?m)^\s+path:\s*'([^']+)'") { $p = $Matches[1] }
            if ($body -match "(?m)^\s+value:\s*'([^']*)'") { $v = $Matches[1] }
            if ($body -match "(?m)^\s+data:\s*'([^']*)'") { $d = $Matches[1] }
            if ($body -match "(?m)^\s+data:\s*(\d+)") { $d = $Matches[1] }
            if ($body -match "(?m)^\s+type:\s*([A-Za-z0-9_]+)") { $t = $Matches[1] }
            Add-Reg $p $v $d $t $src
        }

        # AppX: !appx: {name: '...', type: family}
        foreach ($m in [regex]::Matches($text, "!appx:\s*\{[^}]*name:\s*'([^']+)'")) {
            Add-Appx $Matches[1] $src
        }
        foreach ($m in [regex]::Matches($text, "(?m)!appx:\s*\r?\n(?:[ \t]+[^\r\n]*\r?\n)*?[ \t]+name:\s*'([^']+)'")) {
            Add-Appx $Matches[1] $src
        }

        # Services: !service: {name: '...', operation: change, startup: 4} variants
        foreach ($m in [regex]::Matches($text, "!service:\s*\{([^}]+)\}")) {
            $body = $m.Groups[1].Value
            $n = $null; $st = '4'
            if ($body -match "name:\s*'([^']+)'") { $n = $Matches[1] }
            if ($body -match "startup:\s*(\d+)") { $st = $Matches[1] }
            if ($body -match "operation:\s*'?delete'?") { $st = '4' }
            Add-Svc $n $st $src
        }
    }
    $stats["yaml_$root"] = ($regs.Count - $before)
    Write-Host ("YAML {0}: +{1} reg (files scanned cumulative {2})" -f $root, ($regs.Count - $before), $yamlFiles)
}

# ========== 2) KernelOS services CSVs ==========
foreach ($csvName in @('KernelOS\KernelOS-services-disabled.csv', 'KernelOS\KernelOS-23H2-services.csv')) {
    $p = Join-Path $ResearchRoot $csvName
    if (-not (Test-Path $p)) { continue }
    $before = $svcs.Count
    Import-Csv $p | ForEach-Object {
        $n = $_.Service; if (-not $n) { $n = $_.Name }
        $st = $_.Start; if (-not $st) { $st = '4' }
        Add-Svc $n $st 'kernelos-csv'
    }
    Write-Host "KernelOS CSV $csvName services +$($svcs.Count - $before)"
}

# ========== 3) KernelOS reg add text dumps ==========
foreach ($f in @(
        'KernelOS\KernelOS-reg-adds.txt',
        'KernelOS\tweaks-cleartext\*.txt',
        'KernelOS\KernelOS-23H2-bcdedit-dmv.txt'
    )) {
    $paths = @()
    if ($f -match '\*') {
        $paths = @(Get-ChildItem (Join-Path $ResearchRoot (Split-Path $f)) -Filter (Split-Path $f -Leaf) -EA SilentlyContinue)
    } else {
        $fp = Join-Path $ResearchRoot $f
        if (Test-Path $fp) { $paths = @(Get-Item $fp) }
    }
    foreach ($file in $paths) {
        $before = $regs.Count
        Get-Content $file.FullName -EA SilentlyContinue | ForEach-Object {
            $line = $_
            # reg add HKLM\... /v Name /t REG_DWORD /d 1
            if ($line -match '(?i)(?:reg\s+add\s+)?((?:HK[A-Z]{2}|HKEY_[A-Z_]+)\\[^\s/]+)\s+/v\s+"?([^"/\s]+)"?\s+/t\s+(REG_\w+)\s+/d\s+"?([^"/\s]+)"?') {
                Add-Reg $Matches[1] $Matches[2] $Matches[3] $Matches[4] 'kernelos-reg'
            }
            elseif ($line -match '(?i)^((?:HKLM|HKCU|HKCR)\\[^\s]+)\s+/v\s+([^\s/]+)\s+/t\s+(REG_\w+)\s+/d\s+([^\s/]+)') {
                Add-Reg $Matches[1] $Matches[2] $Matches[3] $Matches[4] 'kernelos-reg'
            }
        }
        Write-Host "KernelOS text $($file.Name) reg +$($regs.Count - $before)"
    }
}

# ========== 4) KernelOS cleartext bat reg add ==========
Get-ChildItem (Join-Path $ResearchRoot 'KernelOS') -Filter '*CLEARTEXT*.bat' -EA SilentlyContinue | ForEach-Object {
    $before = $regs.Count
    Get-Content $_.FullName -Raw | ForEach-Object {
        foreach ($m in [regex]::Matches($_, '(?i)reg\s+add\s+"?((?:HK[A-Z]{2}|HKEY_[A-Z_]+)\\[^"\r\n]+?)"?\s+/v\s+"?([^"\r\n/]+)"?\s+/t\s+(REG_\w+)\s+/d\s+"?([^"\r\n/]+)"?')) {
            Add-Reg $m.Groups[1].Value.Trim() $m.Groups[2].Value.Trim() $m.Groups[3].Value.Trim() $m.Groups[4].Value $m.Groups[0].Value.Substring(0, 0) 
            # fix: last arg source
        }
    }
}
# fix bat parse properly
Get-ChildItem (Join-Path $ResearchRoot 'KernelOS') -Filter '*CLEARTEXT*.bat' -EA SilentlyContinue | ForEach-Object {
    $before = $regs.Count
    $raw = Get-Content $_.FullName -Raw
    foreach ($m in [regex]::Matches($raw, '(?i)reg\s+add\s+"?((?:HK[A-Z]{2}|HKEY_[A-Z_]+)\\[^"\s\r\n]+)"?\s+/v\s+"?([^"/\s\r\n]+)"?\s+/t\s+(REG_\w+)\s+/d\s+"?([^"/\s\r\n]+)"?')) {
        Add-Reg $m.Groups[1].Value $m.Groups[2].Value $m.Groups[4].Value $m.Groups[3].Value 'kernelos-bat'
    }
    # sc config Name start= disabled
    foreach ($m in [regex]::Matches($raw, '(?i)sc\s+config\s+([A-Za-z0-9_\-]+)\s+start=\s*(demand|disabled|auto|system)')) {
        $st = switch ($m.Groups[2].Value.ToLower()) { 'disabled' { '4' } 'demand' { '3' } 'auto' { '2' } 'system' { '1' } default { '4' } }
        Add-Svc $m.Groups[1].Value $st 'kernelos-bat'
    }
    Write-Host "KernelOS bat $($_.Name) reg+svc delta reg=$($regs.Count - $before)"
}

# ========== 5) WinUtil (again, only missing) ==========
$twPath = Join-Path $ResearchRoot 'winutil\config\tweaks.json'
if (Test-Path $twPath) {
    $before = $regs.Count
    $tj = Get-Content $twPath -Raw | ConvertFrom-Json
    foreach ($prop in $tj.PSObject.Properties) {
        $t = $prop.Value
        if ($t.registry) {
            foreach ($r in @($t.registry)) {
                $path = $r.Path; $name = $r.Name; $val = $r.Value; $type = $r.Type
                if ("$val" -eq '<RemoveEntry>') { continue }
                Add-Reg $path $name $val $type 'winutil'
            }
        }
        if ($null -ne $t.service) {
            foreach ($s in @($t.service)) {
                if ($null -eq $s) { continue }
                Add-Svc ($s.Name ?? $s.name) ($s.StartupType ?? $s.startupType ?? 'Disabled') 'winutil'
            }
        }
    }
    Write-Host "WinUtil extras +$($regs.Count - $before) reg"
}

# ========== 6) Winhance Optimize+Customize (missing only) ==========
foreach ($sub in @('Optimize\Models', 'Customize\Models')) {
    $dir = Join-Path $ResearchRoot "Winhance\src\Winhance.Core\Features\$sub"
    if (-not (Test-Path $dir)) { continue }
    $before = $regs.Count
    Get-ChildItem $dir -Filter *.cs -EA SilentlyContinue | ForEach-Object {
        $text = Get-Content $_.FullName -Raw
        foreach ($b in [regex]::Matches($text, 'new RegistrySetting\s*\{(?<body>[\s\S]*?)\n\s*\},?')) {
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
            Add-Reg $key $name $val $vtype 'winhance'
        }
    }
    Write-Host "Winhance $sub +$($regs.Count - $before)"
}

# ========== 7) WinUtil appx.json ==========
$appxJson = Join-Path $ResearchRoot 'winutil\config\appx.json'
if (Test-Path $appxJson) {
    $aj = Get-Content $appxJson -Raw | ConvertFrom-Json
    foreach ($prop in $aj.PSObject.Properties) {
        $pkg = $prop.Value.PackageId
        if ($pkg) { Add-Appx $pkg 'winutil-appx' }
    }
}

Write-Host "`nTOTAL new reg=$($regs.Count) svc=$($svcs.Count) appx=$($appx.Count)"

# ========== Emit ==========
function Emit-Reg($items, $file, $title) {
    $sb = [System.Text.StringBuilder]::new()
    [void]$sb.AppendLine("title: $title")
    [void]$sb.AppendLine('# Auto-merged from multi-baseline RE. Exo branding only.')
    [void]$sb.AppendLine('actions:')
    $i = 0
    foreach ($c in ($items | Sort-Object Path, Name)) {
        $i++
        [void]$sb.AppendLine('  - type: registry.set')
        [void]$sb.AppendLine("    id: 'exo-bl-$i'")
        [void]$sb.AppendLine("    path: $(Yaml-Escape $c.Path)")
        [void]$sb.AppendLine("    valueName: $(Yaml-Escape $c.Name)")
        [void]$sb.AppendLine("    valueType: $($c.Type)")
        [void]$sb.AppendLine("    value: $(Yaml-Escape $c.Value)")
        [void]$sb.AppendLine("    description: 'Exo'")
        [void]$sb.AppendLine('')
    }
    [System.IO.File]::WriteAllText((Join-Path $outDir $file), $sb.ToString())
    Write-Host "Wrote $file ($i)"
    return $i
}

$nReg = Emit-Reg $regs '13-reg-baselines-all.yml' 'Baseline merge — registry (all RE sources)'

$sb = [System.Text.StringBuilder]::new()
[void]$sb.AppendLine('title: Baseline merge — services')
[void]$sb.AppendLine('actions:')
$si = 0
foreach ($s in ($svcs | Sort-Object Name)) {
    $si++
    [void]$sb.AppendLine('  - type: service.set')
    [void]$sb.AppendLine("    id: 'exo-bl-svc-$si'")
    [void]$sb.AppendLine("    service: $(Yaml-Escape $s.Name)")
    [void]$sb.AppendLine("    start: '$($s.Start)'")
    [void]$sb.AppendLine('    stop: true')
    [void]$sb.AppendLine('    whenOption: serviceStrip')
    [void]$sb.AppendLine("    description: 'Exo'")
    [void]$sb.AppendLine('')
}
[System.IO.File]::WriteAllText((Join-Path $outDir '43-services-baselines.yml'), $sb.ToString())
Write-Host "Wrote 43-services-baselines.yml ($si)"

$sb = [System.Text.StringBuilder]::new()
[void]$sb.AppendLine('title: Baseline merge — AppX')
[void]$sb.AppendLine('actions:')
$ai = 0
foreach ($a in ($appx | Sort-Object Name)) {
    $ai++
    [void]$sb.AppendLine('  - type: appx.remove')
    [void]$sb.AppendLine("    id: 'exo-bl-appx-$ai'")
    [void]$sb.AppendLine("    package: $(Yaml-Escape ('*' + $a.Name + '*'))")
    [void]$sb.AppendLine('    ignoreErrors: true')
    [void]$sb.AppendLine("    description: 'Exo'")
    [void]$sb.AppendLine('')
}
[System.IO.File]::WriteAllText((Join-Path $outDir '93-appx-baselines.yml'), $sb.ToString())
Write-Host "Wrote 93-appx-baselines.yml ($ai)"

$report = [ordered]@{
    generated     = (Get-Date).ToString('o')
    newRegistry   = $nReg
    newServices   = $si
    newAppx       = $ai
    yamlFilesScan = $yamlFiles
    perRoot       = $stats
}
$report | ConvertTo-Json -Depth 5 | Set-Content (Join-Path $PlaybookRoot 'BASELINE-MERGE-STATS.json')
Write-Host ($report | ConvertTo-Json -Depth 3)
Write-Host 'Done.'
