# ─────────────────────────────────────────────────────────────
# Compare two hardware snapshots.
# ─────────────────────────────────────────────────────────────

param(
    [Parameter(Mandatory)][string]$Reference,
    [Parameter(Mandatory)][string]$Current,
    [double]$Threshold = 2.0,
    [switch]$All
)

$ErrorActionPreference = 'Stop'

if (-not (Test-Path -LiteralPath $Reference)) { throw "Reference not found: $Reference" }
if (-not (Test-Path -LiteralPath $Current))   { throw "Current not found:   $Current" }

$ref = Get-Content -LiteralPath $Reference -Raw | ConvertFrom-Json
$cur = Get-Content -LiteralPath $Current   -Raw | ConvertFrom-Json

Write-Host ''
Write-Host 'Snapshot comparison' -ForegroundColor Cyan
Write-Host ("  Reference: {0}  (tag={1}, {2})" -f (Split-Path $Reference -Leaf), $ref.Tag, $ref.Timestamp) -ForegroundColor Gray
Write-Host ("  Current:   {0}  (tag={1}, {2})" -f (Split-Path $Current -Leaf),   $cur.Tag, $cur.Timestamp) -ForegroundColor Gray
Write-Host ("  Threshold: {0}%" -f $Threshold) -ForegroundColor Gray

$refMap = @{}
foreach ($s in $ref.Sensors) { $refMap[$s.Key] = $s }

$curMap = @{}
foreach ($s in $cur.Sensors) { $curMap[$s.Key] = $s }

$changed = @()
foreach ($key in $curMap.Keys) {
    if (-not $refMap.ContainsKey($key)) { continue }
    $a = $refMap[$key].Value
    $b = $curMap[$key].Value

    if ($null -eq $a -or $null -eq $b) { continue }

    $delta = $b - $a
    if ($a -eq 0) {
        $pct = if ($b -eq 0) { 0 } else { [double]::PositiveInfinity }
    } else {
        $pct = ($delta / [math]::Abs($a)) * 100
    }

    if ([math]::Abs($pct) -ge $Threshold) {
        $changed += [pscustomobject]@{
            Hardware   = $curMap[$key].Hardware
            SensorType = $curMap[$key].SensorType
            Name       = $curMap[$key].Name
            Reference  = [math]::Round($a, 3)
            Current    = [math]::Round($b, 3)
            Delta      = [math]::Round($delta, 3)
            Percent    = if ([double]::IsInfinity($pct)) { 'inf' } else { [math]::Round($pct, 1) }
        }
    }
}

$appeared    = $curMap.Keys | Where-Object { -not $refMap.ContainsKey($_) }
$disappeared = $refMap.Keys | Where-Object { -not $curMap.ContainsKey($_) }

$alerts = @()
foreach ($s in $cur.Sensors) {
    $name = $s.Name
    $type = $s.SensorType
    $val  = $s.Value
    if ($null -eq $val) { continue }

    if ($type -eq 'Temperature' -and $name -match 'Tctl|Tdie|Core \(Tctl' -and $val -ge 90) {
        $alerts += "CPU Tctl/Tdie at $([math]::Round($val,1))C (>= 90C)"
    }
    if ($type -eq 'Temperature' -and $s.Hardware -eq 'Memory' -and $name -match '^DIMM' -and $val -ge 55) {
        $alerts += "DIMM $name at $([math]::Round($val,1))C (>= 55C)"
    }
    if ($type -eq 'Temperature' -and $s.Hardware -eq 'Storage' -and $name -match 'Composite' -and $val -ge 70) {
        $alerts += "NVMe '$($s.Path)' at $([math]::Round($val,1))C (>= 70C)"
    }
    if ($type -eq 'Level' -and $s.Hardware -eq 'Storage' -and $name -eq 'Life' -and $val -le 20) {
        $alerts += "NVMe '$($s.Path)' life at $val% (<= 20%)"
    }
}

Write-Host ''
if ($alerts) {
    Write-Host 'ALERTS' -ForegroundColor Red
    $alerts | ForEach-Object { Write-Host "  [!] $_" -ForegroundColor Red }
} else {
    Write-Host 'ALERTS: none' -ForegroundColor Green
}

Write-Host ''
if ($changed) {
    Write-Host ("Changed sensors (>|{0}%|): {1}" -f $Threshold, @($changed).Count) -ForegroundColor Yellow
    $changed |
        Sort-Object -Property @{Expression={ [math]::Abs([double]$_.Percent) };Descending=$true} |
        Select-Object Hardware, SensorType, Name, Reference, Current, Delta, Percent |
        Format-Table -AutoSize | Out-String | Write-Host
} else {
    Write-Host 'No sensors changed beyond threshold.' -ForegroundColor Green
}

if ($appeared) {
    Write-Host ''
    Write-Host ("Appeared: {0}" -f @($appeared).Count) -ForegroundColor Cyan
    if ($All) { $appeared | Sort-Object | ForEach-Object { Write-Host "  $_" -ForegroundColor DarkGray } }
}

if ($disappeared) {
    Write-Host ''
    Write-Host ("Disappeared: {0}" -f @($disappeared).Count) -ForegroundColor Cyan
    if ($All) { $disappeared | Sort-Object | ForEach-Object { Write-Host "  $_" -ForegroundColor DarkGray } }
}

Write-Host ''
