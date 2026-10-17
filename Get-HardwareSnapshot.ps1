# ─────────────────────────────────────────────────────────────
# Headless LibreHardwareMonitor snapshot
# Read-only. Loads LibreHardwareMonitorLib.dll, samples sensors.
# ─────────────────────────────────────────────────────────────

param(
    [string]$LhmPath    = 'C:\Tools\Libre Hardware Monitor',
    [string]$Tag        = '',
    [string]$Directory  = '',
    [string]$OutputJson = '',
    [switch]$IncludeAll,
    [switch]$Quiet
)

$ErrorActionPreference = 'Stop'

function Say { param($m,$c='Gray') if (-not $Quiet) { Write-Host $m -ForegroundColor $c } }

$libPath = Join-Path $LhmPath 'LibreHardwareMonitorLib.dll'
if (-not (Test-Path -LiteralPath $libPath)) {
    Write-Error "LibreHardwareMonitorLib.dll not found at $libPath"
    exit 1
}

Say "Loading $libPath ..." 'Cyan'
Add-Type -Path $libPath

function Clean-Name {
    param([string]$Name)
    if ([string]::IsNullOrEmpty($Name)) { return '' }
    $clean = -join ($Name.ToCharArray() | Where-Object {
        [int]$_ -ge 32 -and [int]$_ -ne 127
    })
    $clean = $clean -replace '\s+', ' '
    return $clean.Trim()
}

Say 'Opening hardware access...' 'Cyan'
$computer = New-Object LibreHardwareMonitor.Hardware.Computer
$computer.IsCpuEnabled         = $true
$computer.IsGpuEnabled         = $true
$computer.IsMemoryEnabled      = $true
$computer.IsMotherboardEnabled = $true
$computer.IsStorageEnabled     = $true
$computer.IsNetworkEnabled     = $true
$computer.IsBatteryEnabled     = $true
$computer.IsControllerEnabled  = $true

$computer.Open()

function Get-HardwareSensors {
    param($Hardware, [string]$ParentPath = '')

    $rawName = Clean-Name $Hardware.Name
    $path    = if ($ParentPath) { "$ParentPath/$rawName" } else { $rawName }

    $Hardware.Update()

    foreach ($sub in $Hardware.SubHardware) {
        Get-HardwareSensors -Hardware $sub -ParentPath $path
    }

    foreach ($sensor in $Hardware.Sensors) {
        $sensorName = Clean-Name $sensor.Name
        [pscustomobject]@{
            Key        = "$path|$($sensor.SensorType)|$sensorName"
            Path       = $path
            Hardware   = $Hardware.HardwareType.ToString()
            SensorType = $sensor.SensorType.ToString()
            Name       = $sensorName
            Value      = $sensor.Value
        }
    }
}

Say 'Sampling sensors...' 'Cyan'
$all = foreach ($hw in $computer.Hardware) {
    Get-HardwareSensors -Hardware $hw
}

$computer.Close()

$interesting = @(
    'Temperature','Load','Clock','Power','Voltage','Fan',
    'Level','Data','Throughput','Factor'
)

$filtered = if ($IncludeAll) { $all } else {
    $all | Where-Object { $interesting -contains $_.SensorType }
}

$snapshot = [pscustomobject]@{
    SchemaVersion = 1
    Timestamp     = (Get-Date).ToString('o')
    Tag           = $Tag
    Host          = $env:COMPUTERNAME
    User          = $env:USERNAME
    SensorCount   = @($filtered).Count
    Sensors       = $filtered
}

$target = $null
if ($OutputJson) {
    $target = $OutputJson
} elseif ($Directory) {
    if (-not (Test-Path -LiteralPath $Directory)) {
        New-Item -ItemType Directory -Path $Directory -Force | Out-Null
    }
    $stamp = (Get-Date).ToString('yyyyMMdd-HHmmss')
    $label = if ($Tag) { "$Tag-" } else { '' }
    $target = Join-Path $Directory "$label$stamp.json"
}

if ($target) {
    $snapshot | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $target -Encoding UTF8
    Say "Snapshot written to $target" 'Green'
    Say ("  sensors: {0}   tag: {1}" -f $snapshot.SensorCount, $snapshot.Tag) 'DarkGray'
} else {
    $snapshot.Sensors | Format-Table -AutoSize
}
