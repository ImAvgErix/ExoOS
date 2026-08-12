$ErrorActionPreference = 'Stop'
$dir = Join-Path $env:ProgramData 'ExoOS'
New-Item -ItemType Directory -Path $dir -Force | Out-Null
$obj = [ordered]@{
    product    = 'ExoOS'
    version    = '1.8.1'
    appliedUtc = (Get-Date).ToUniversalTime().ToString('o')
    machine    = $env:COMPUTERNAME
    note       = 'One-way transform. Reinstall Windows to fully undo. Modern shell kept.'
}
$obj | ConvertTo-Json | Set-Content -Path (Join-Path $dir 'applied.json') -Encoding UTF8
exit 0
