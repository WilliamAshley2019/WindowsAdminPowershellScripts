$scriptBlock = {
    [void][System.Threading.Thread]::CurrentThread.SetApartmentState([System.Threading.ApartmentState]::STA)

    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing

    # Create form
    $form = New-Object System.Windows.Forms.Form
    $form.Text = "Mini Task Manager (Running as SYSTEM)"
    $form.Size = New-Object System.Drawing.Size(700, 500)
    $form.StartPosition = "CenterScreen"

    # Create DataGridView to show processes
    $dgv = New-Object System.Windows.Forms.DataGridView
    $dgv.Dock = "Top"
    $dgv.Height = 400
    $dgv.ReadOnly = $true
    $dgv.SelectionMode = 'FullRowSelect'
    $dgv.MultiSelect = $false
    $dgv.AutoSizeColumnsMode = 'Fill'

    # Button: Kill selected process
    $btnKill = New-Object System.Windows.Forms.Button
    $btnKill.Text = "Kill Selected Process"
    $btnKill.Width = 180
    $btnKill.Top = 410
    $btnKill.Left = 10

    # Button: Refresh process list
    $btnRefresh = New-Object System.Windows.Forms.Button
    $btnRefresh.Text = "Refresh Process List"
    $btnRefresh.Width = 180
    $btnRefresh.Top = 410
    $btnRefresh.Left = 200

    # Label to show messages
    $lblStatus = New-Object System.Windows.Forms.Label
    $lblStatus.Text = ""
    $lblStatus.AutoSize = $true
    $lblStatus.Top = 450
    $lblStatus.Left = 10
    $lblStatus.Width = 650
    $lblStatus.ForeColor = 'DarkGreen'

    # Function to load processes into DataGridView
    function Load-ProcessList {
        try {
            $procs = Get-Process | Select-Object Id, ProcessName, CPU, WS -ErrorAction SilentlyContinue

            $dgv.Columns.Clear()
            $dgv.Rows.Clear()

            $dgv.Columns.Add("Id","PID") | Out-Null
            $dgv.Columns.Add("ProcessName","Process Name") | Out-Null
            $dgv.Columns.Add("CPU","CPU") | Out-Null
            $dgv.Columns.Add("WS","Working Set (MB)") | Out-Null

            foreach ($p in $procs) {
                $wsMB = [math]::Round($p.WS / 1MB, 2)
                $cpu = if ($p.CPU) { [math]::Round($p.CPU, 2) } else { 0 }
                $dgv.Rows.Add($p.Id, $p.ProcessName, $cpu, $wsMB)
            }

            $lblStatus.Text = "Process list refreshed at $(Get-Date -Format 'HH:mm:ss')"
        } catch {
            $lblStatus.Text = "Error loading process list: $_"
        }
    }

    # Kill button click event
    $btnKill.Add_Click({
        if ($dgv.SelectedRows.Count -eq 0) {
            [System.Windows.Forms.MessageBox]::Show("Please select a process to kill.", "No Selection", "OK", "Warning")
            return
        }
        $selectedPid = $dgv.SelectedRows[0].Cells["Id"].Value
        $selectedName = $dgv.SelectedRows[0].Cells["ProcessName"].Value
        $confirm = [System.Windows.Forms.MessageBox]::Show("Are you sure you want to kill process '$selectedName' (PID: $selectedPid)?","Confirm Kill","YesNo","Question")
        if ($confirm -eq [System.Windows.Forms.DialogResult]::Yes) {
            try {
                Stop-Process -Id $selectedPid -Force -ErrorAction Stop
                $lblStatus.Text = "Killed process '$selectedName' (PID: $selectedPid) successfully."
                Load-ProcessList
            } catch {
                [System.Windows.Forms.MessageBox]::Show("Failed to kill process: $_", "Error", "OK", "Error")
            }
        }
    })

    # Refresh button click event
    $btnRefresh.Add_Click({
        Load-ProcessList
    })

    # Add controls to form
    $form.Controls.Add($dgv)
    $form.Controls.Add($btnKill)
    $form.Controls.Add($btnRefresh)
    $form.Controls.Add($lblStatus)

    # Load initial list
    Load-ProcessList

    # Show form
    [void]$form.ShowDialog()
}

# Encode the script block to base64 for -EncodedCommand
$encoded = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($scriptBlock.ToString()))

# Launch NSudo as SYSTEM and run the script block
& "C:\Users\ADA\Desktop\tools\nsudo\x64\NSudoLC.exe" -U:S -P:E powershell.exe -NoProfile -ExecutionPolicy Bypass -EncodedCommand $encoded
