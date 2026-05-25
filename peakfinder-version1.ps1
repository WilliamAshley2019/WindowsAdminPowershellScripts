Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# =========================
# FORM
# =========================
$form = New-Object System.Windows.Forms.Form
$form.Text = "System Diagnostic Console (CPU Intelligence Mode)"
$form.Width = 1100
$form.Height = 950
$form.StartPosition = "CenterScreen"

# =========================
# CPU GRID
# =========================
$cpuGrid = New-Object System.Windows.Forms.DataGridView
$cpuGrid.Width = 1050
$cpuGrid.Height = 260
$cpuGrid.Location = New-Object System.Drawing.Point(10,10)
$cpuGrid.ReadOnly = $true
$cpuGrid.AllowUserToAddRows = $false
$cpuGrid.RowHeadersVisible = $false
$cpuGrid.AutoSizeColumnsMode = "Fill"

$cpuGrid.ColumnCount = 3
$cpuGrid.Columns[0].Name = "Process"
$cpuGrid.Columns[1].Name = "PID"
$cpuGrid.Columns[2].Name = "CPU %"

$form.Controls.Add($cpuGrid)

# =========================
# ACTIVE PROCESSES
# =========================
$activeGrid = New-Object System.Windows.Forms.DataGridView
$activeGrid.Width = 1050
$activeGrid.Height = 200
$activeGrid.Location = New-Object System.Drawing.Point(10,280)
$activeGrid.ReadOnly = $true
$activeGrid.AllowUserToAddRows = $false
$activeGrid.RowHeadersVisible = $false
$activeGrid.AutoSizeColumnsMode = "Fill"

$activeGrid.ColumnCount = 3
$activeGrid.Columns[0].Name = "Process"
$activeGrid.Columns[1].Name = "PID"
$activeGrid.Columns[2].Name = "Start Time"

$form.Controls.Add($activeGrid)

# =========================
# SPIKE LOG (NEW)
# =========================
$spikeGrid = New-Object System.Windows.Forms.DataGridView
$spikeGrid.Width = 1050
$spikeGrid.Height = 200
$spikeGrid.Location = New-Object System.Drawing.Point(10,490)
$spikeGrid.ReadOnly = $true
$spikeGrid.AllowUserToAddRows = $false
$spikeGrid.RowHeadersVisible = $false
$spikeGrid.AutoSizeColumnsMode = "Fill"

$spikeGrid.ColumnCount = 3
$spikeGrid.Columns[0].Name = "Time"
$spikeGrid.Columns[1].Name = "Process"
$spikeGrid.Columns[2].Name = "CPU Spike %"

$form.Controls.Add($spikeGrid)

# =========================
# SUMMARY BOX
# =========================
$summaryBox = New-Object System.Windows.Forms.TextBox
$summaryBox.Multiline = $true
$summaryBox.Width = 1050
$summaryBox.Height = 140
$summaryBox.Location = New-Object System.Drawing.Point(10,700)
$summaryBox.ReadOnly = $true
$summaryBox.Font = New-Object System.Drawing.Font("Consolas",10)

$form.Controls.Add($summaryBox)

# =========================
# STATUS
# =========================
$label = New-Object System.Windows.Forms.Label
$label.Location = New-Object System.Drawing.Point(10, 850)
$label.Width = 600
$form.Controls.Add($label)

# =========================
# STORAGE
# =========================
$running = @{}
$spikes = New-Object System.Collections.Generic.List[object]
$cpuHistory = New-Object System.Collections.Generic.Queue[double]

$hold = $false

# =========================
# CPU FUNCTION
# =========================
function Get-CPUData {

    Get-CimInstance Win32_PerfFormattedData_PerfProc_Process |
        Where-Object { $_.Name -ne "_Total" -and $_.Name -ne "Idle" } |
        Sort-Object PercentProcessorTime -Descending |
        Select-Object -First 20 |
        ForEach-Object {

            [PSCustomObject]@{
                Name = $_.Name
                PID  = $_.IDProcess
                CPU  = [math]::Round($_.PercentProcessorTime,2)
            }
        }
}

# =========================
# SPIKE DETECTION
# =========================
function Update-SpikeDetection($cpuTotal) {

    $cpuHistory.Enqueue($cpuTotal)
    if ($cpuHistory.Count -gt 10) { $cpuHistory.Dequeue() }

    if ($cpuHistory.Count -lt 5) { return }

    $avg = ($cpuHistory | Measure-Object -Average).Average

    # spike condition
    if ($cpuTotal -gt ($avg + 20)) {

        $top = Get-CPUData | Select-Object -First 1

        $spikes.Add([PSCustomObject]@{
            Time = (Get-Date).ToString("HH:mm:ss")
            Process = $top.Name
            CPU = $top.CPU
        })
    }
}

# =========================
# TRACKING
# =========================
function Update-Tracking {

    $now = Get-Date
    $procs = Get-Process -ErrorAction SilentlyContinue

    foreach ($p in $procs) {
        if (-not $running.ContainsKey($p.Id)) {
            $running[$p.Id] = @{
                Name = $p.ProcessName
                PID  = $p.Id
                Start = $now
            }
        }
    }
}

# =========================
# UI UPDATE
# =========================
function RefreshUI {

    $cpu = Get-CPUData

    # CPU GRID
    $cpuGrid.Rows.Clear()
    foreach ($c in $cpu) {
        $cpuGrid.Rows.Add($c.Name, $c.PID, $c.CPU)
    }

    # ACTIVE
    $activeGrid.Rows.Clear()
    foreach ($r in $running.Values) {
        $activeGrid.Rows.Add($r.Name, $r.PID, $r.Start.ToString("HH:mm:ss"))
    }

    # SPIKES
    $spikeGrid.Rows.Clear()
    foreach ($s in $spikes | Select-Object -Last 15) {
        $spikeGrid.Rows.Add($s.Time, $s.Process, $s.CPU)
    }

    # STABILITY SCORE
    $avgCpu = ($cpu | Measure-Object -Property CPU -Average).Average
    $stability = 100 - [math]::Min(100, $avgCpu * 2)

    $summaryBox.Text =
@"
SYSTEM DIAGNOSTICS
========================
Avg CPU Load: $([math]::Round($avgCpu,2))%
Stability Score: $([math]::Round($stability,1)) / 100

Interpretation:
$(if ($stability -gt 80) {"Stable system"} elseif ($stability -gt 50) {"Moderate load"} else {"High instability / spike activity"})
"@

    $label.Text = "Updated: " + (Get-Date).ToString("HH:mm:ss")
}

# =========================
# TIMER
# =========================
$timer = New-Object System.Windows.Forms.Timer
$timer.Interval = 1200

$timer.Add_Tick({

    if ($script:hold) { return }

    $cpu = Get-CPUData
    $totalCpu = ($cpu | Measure-Object -Property CPU -Sum).Sum

    Update-SpikeDetection $totalCpu
    Update-Tracking
    RefreshUI
})

$timer.Start()

# =========================
# RUN
# =========================
[void]$form.ShowDialog() 
