#requires -RunAsAdministrator

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# Enable DPI awareness for crisp text on high-res screens
Add-Type @"
using System.Runtime.InteropServices;
public class DPI {
    [DllImport("user32.dll")]
    public static extern bool SetProcessDPIAware();
}
"@
[DPI]::SetProcessDPIAware()

# Hosts file path
$hostsPath = "$env:SystemRoot\System32\drivers\etc\hosts"

# Microsoft endpoints to manage
$endpoints = @{
    "Windows Update" = @(
        "download.microsoft.com",
        "windowsupdate.microsoft.com",
        "update.microsoft.com",
        "dl.delivery.mp.microsoft.com",
        "fe3.delivery.mp.microsoft.com",
        "tlu.dl.delivery.mp.microsoft.com"
    )
    "Telemetry & Data Collection" = @(
        "v10c.vortex-win.data.microsoft.com",
        "v20.vortex-win.data.microsoft.com",
        "settings-win.data.microsoft.com",
        "watson.microsoft.com",
        "watson.telemetry.microsoft.com",
        "reports.wes.df.telemetry.microsoft.com",
        "telemetry.microsoft.com",
        "telecommand.telemetry.microsoft.com"
    )
    "Activation & Licensing" = @(
        "sls.microsoft.com",
        "validation.sls.microsoft.com",
        "licensing.mp.microsoft.com",
        "purchase.mp.microsoft.com"
    )
    "Microsoft Store & Apps" = @(
        "storeedgefd.dsx.mp.microsoft.com",
        "login.live.com",
        "account.live.com",
        "store.microsoft.com"
    )
    "Defender & Security" = @(
        "wdcp.microsoft.com",
        "wdcpalt.microsoft.com",
        "smartscreen.microsoft.com",
        "wd-prod-cp-us-west-1-fe.westus.cloudapp.azure.com"
    )
    "Diagnostics & Feedback" = @(
        "feedback.windows.com",
        "feedback.microsoft-hohm.com",
        "oca.telemetry.microsoft.com",
        "sqm.telemetry.microsoft.com"
    )
}

function Get-CurrentBlockStatus {
    $content = Get-Content $hostsPath -Raw -ErrorAction SilentlyContinue
    $status = @{}
    foreach ($category in $endpoints.Keys) {
        foreach ($domain in $endpoints[$category]) {
            $status[$domain] = $content -match "^\s*0\.0\.0\.0\s+$domain" -or $content -match "^\s*127\.0\.0\.1\s+$domain"
        }
    }
    return $status
}

function Backup-HostsFile {
    $backupPath = "$hostsPath.backup.$(Get-Date -Format 'yyyyMMdd-HHmmss')"
    Copy-Item $hostsPath $backupPath -Force
    return $backupPath
}

function Update-HostsFile {
    param($domainsToBlock, $domainsToUnblock)
    
    $content = Get-Content $hostsPath
    $newContent = @()
    
    foreach ($line in $content) {
        $matched = $false
        foreach ($domain in $domainsToUnblock) {
            if ($line -match "^\s*(0\.0\.0\.0|127\.0\.0\.1)\s+$domain") {
                $newContent += "# [UNBLOCKED] " + $line.Trim()
                $matched = $true
                break
            }
        }
        if (-not $matched) {
            $newContent += $line
        }
    }
    
    $existingLines = $newContent -join "`n"
    foreach ($domain in $domainsToBlock) {
        if ($existingLines -notmatch "0\.0\.0\.0\s+$domain" -and $existingLines -notmatch "127\.0\.0\.1\s+$domain") {
            $newContent += "0.0.0.0 $domain # [BLOCKED by Hosts Manager]"
        }
    }
    
    $newContent | Set-Content $hostsPath -Force
    ipconfig /flushdns | Out-Null
}

function Test-WindowsUpdateHealth {
    param($outputCallback)
    
    # Check critical Windows Update services
    $outputCallback.Invoke("=== WINDOWS UPDATE SERVICES ===`n")
    
    $services = @(
        @{Name="wuauserv"; DisplayName="Windows Update"},
        @{Name="BITS"; DisplayName="Background Intelligent Transfer Service"},
        @{Name="cryptsvc"; DisplayName="Cryptographic Services"},
        @{Name="TrustedInstaller"; DisplayName="Windows Modules Installer"},
        @{Name="AppIDSvc"; DisplayName="Application Identity"}
    )
    
    foreach ($svc in $services) {
        try {
            $outputCallback.Invoke("  Checking $($svc.DisplayName)...")
            $service = Get-Service -Name $svc.Name -ErrorAction Stop
            $status = $service.Status
            $startType = $service.StartType
            $outputCallback.Invoke(" [$status] (StartType: $startType)`n")
            
            if ($status -ne "Running" -and $svc.Name -in @("wuauserv", "BITS", "cryptsvc")) {
                $outputCallback.Invoke("    WARN: Should be running for Updates`n")
            }
        } catch {
            $outputCallback.Invoke(" ERROR - $($_.Exception.Message)`n")
        }
        Start-Sleep -Milliseconds 50
    }
    
    # Check network connectivity
    $outputCallback.Invoke("`n=== NETWORK CONNECTIVITY ===`n")
    
    $updateServers = @("download.microsoft.com", "windowsupdate.microsoft.com", "update.microsoft.com")
    foreach ($server in $updateServers) {
        try {
            $outputCallback.Invoke("  Pinging $server... ")
            $test = Test-NetConnection -ComputerName $server -InformationLevel Quiet -WarningAction SilentlyContinue -ErrorAction Stop
            if ($test) {
                $outputCallback.Invoke("SUCCESS`n")
            } else {
                $outputCallback.Invoke("FAILED`n")
            }
        } catch {
            $outputCallback.Invoke("FAILED (Network Error)`n")
        }
        Start-Sleep -Milliseconds 100
    }
    
    # Check hosts file for blocks
    $outputCallback.Invoke("`n=== HOSTS FILE ANALYSIS ===`n")
    
    try {
        $hostsContent = Get-Content $hostsPath -Raw
        $blockedUpdateDomains = @()
        foreach ($domain in $updateServers) {
            if ($hostsContent -match "^\s*(0\.0\.0\.0|127\.0\.0\.1)\s+$domain") {
                $blockedUpdateDomains += $domain
            }
        }
        if ($blockedUpdateDomains.Count -gt 0) {
            $outputCallback.Invoke("  WARNING: BLOCKED Windows Update domains found:`n")
            $blockedUpdateDomains | ForEach-Object { 
                $outputCallback.Invoke("    - $_`n")
            }
            $outputCallback.Invoke("  ACTION: Uncheck these domains and click Apply Changes`n")
        } else {
            $outputCallback.Invoke("  OK - No Windows Update domains are blocked`n")
        }
    } catch {
        $outputCallback.Invoke("  ERROR checking hosts file: $($_.Exception.Message)`n")
    }
    
    $outputCallback.Invoke("`n=== DIAGNOSTICS COMPLETE ===`n")
}

# === CREATE MAIN FORM ===
$form = New-Object System.Windows.Forms.Form
$form.Text = "Windows 11 Update with Hosts File Manager"
$form.Size = New-Object System.Drawing.Size(1400, 850)
$form.MinimumSize = New-Object System.Drawing.Size(1200, 600)
$form.StartPosition = "CenterScreen"
$form.AutoScaleMode = [System.Windows.Forms.AutoScaleMode]::Dpi
$form.Font = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Regular)
$form.BackColor = [System.Drawing.Color]::FromArgb(240, 240, 245)

# === MAIN TABLE LAYOUT ===
$mainTable = New-Object System.Windows.Forms.TableLayoutPanel
$mainTable.Dock = [System.Windows.Forms.DockStyle]::Fill
$mainTable.ColumnCount = 2
$mainTable.RowCount = 5
$mainTable.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent, 30))) | Out-Null
$mainTable.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent, 70))) | Out-Null

# Row Heights
$mainTable.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Absolute, 115))) | Out-Null
$mainTable.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Absolute, 65))) | Out-Null
$mainTable.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Absolute, 80))) | Out-Null
$mainTable.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Percent, 100))) | Out-Null
$mainTable.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Absolute, 120))) | Out-Null
$mainTable.Padding = New-Object System.Windows.Forms.Padding(0)
$form.Controls.Add($mainTable)

# === ROW 0: TITLE PANEL ===
$titlePanel = New-Object System.Windows.Forms.Panel
$titlePanel.Dock = [System.Windows.Forms.DockStyle]::Fill
$titlePanel.BackColor = [System.Drawing.Color]::FromArgb(0, 120, 215)
$titlePanel.Padding = New-Object System.Windows.Forms.Padding(20, 10, 20, 10)

# Right Side Panel for Update Buttons
$headerRightPanel = New-Object System.Windows.Forms.Panel
$headerRightPanel.Dock = [System.Windows.Forms.DockStyle]::Right
$headerRightPanel.Width = 350
$headerRightPanel.BackColor = [System.Drawing.Color]::Transparent
$titlePanel.Controls.Add($headerRightPanel)

# Left Side Panel for Text
$headerLeftPanel = New-Object System.Windows.Forms.Panel
$headerLeftPanel.Dock = [System.Windows.Forms.DockStyle]::Fill
$headerLeftPanel.BackColor = [System.Drawing.Color]::Transparent
$titlePanel.Controls.Add($headerLeftPanel)

# Title Text
$titleLabel = New-Object System.Windows.Forms.Label
$titleLabel.Dock = [System.Windows.Forms.DockStyle]::Top
$titleLabel.AutoSize = $true
$titleLabel.Font = New-Object System.Drawing.Font("Segoe UI", 18, [System.Drawing.FontStyle]::Bold)
$titleLabel.Text = "🛡️ Windows 11 Update"
$titleLabel.ForeColor = [System.Drawing.Color]::White
$titleLabel.Padding = New-Object System.Windows.Forms.Padding(0, 10, 0, 0)
$headerLeftPanel.Controls.Add($titleLabel)

$subTitleLabel = New-Object System.Windows.Forms.Label
$subTitleLabel.Dock = [System.Windows.Forms.DockStyle]::Top
$subTitleLabel.AutoSize = $true
$subTitleLabel.Font = New-Object System.Drawing.Font("Segoe UI", 14, [System.Drawing.FontStyle]::Regular)
$subTitleLabel.Text = "with Hosts File Manager - 25H2"
$subTitleLabel.ForeColor = [System.Drawing.Color]::FromArgb(200, 230, 255)
$subTitleLabel.Padding = New-Object System.Windows.Forms.Padding(2, 0, 0, 0)
$headerLeftPanel.Controls.Add($subTitleLabel)

# HEADER BUTTONS
$btnOpenWU = New-Object System.Windows.Forms.Button
$btnOpenWU.Width = 160
$btnOpenWU.Height = 40
$btnOpenWU.Location = New-Object System.Drawing.Point(10, 30)
$btnOpenWU.Text = "⚙️ Open Settings"
$btnOpenWU.Font = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)
$btnOpenWU.BackColor = [System.Drawing.Color]::White
$btnOpenWU.ForeColor = [System.Drawing.Color]::FromArgb(0, 120, 215)
$btnOpenWU.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$btnOpenWU.Cursor = [System.Windows.Forms.Cursors]::Hand
$btnOpenWU.Add_Click({ Start-Process "ms-settings:windowsupdate" })
$headerRightPanel.Controls.Add($btnOpenWU)

$btnCheckWU = New-Object System.Windows.Forms.Button
$btnCheckWU.Width = 160
$btnCheckWU.Height = 40
$btnCheckWU.Location = New-Object System.Drawing.Point(180, 30)
$btnCheckWU.Text = "🔎 Check Updates"
$btnCheckWU.Font = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)
$btnCheckWU.BackColor = [System.Drawing.Color]::FromArgb(255, 200, 100)
$btnCheckWU.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$btnCheckWU.Cursor = [System.Windows.Forms.Cursors]::Hand
$btnCheckWU.Add_Click({ 
    # USOClient StartInteractiveScan opens WU settings and starts scanning
    Start-Process "usoclient.exe" -ArgumentList "StartInteractiveScan" 
})
$headerRightPanel.Controls.Add($btnCheckWU)

$mainTable.Controls.Add($titlePanel, 0, 0)
$mainTable.SetColumnSpan($titlePanel, 2)

# === ROW 1: STATUS PANEL ===
$statusPanel = New-Object System.Windows.Forms.Panel
$statusPanel.Dock = [System.Windows.Forms.DockStyle]::Fill
$statusPanel.BackColor = [System.Drawing.Color]::White
$statusPanel.Padding = New-Object System.Windows.Forms.Padding(20, 15, 20, 15)

$statusLabel = New-Object System.Windows.Forms.Label
$statusLabel.Dock = [System.Windows.Forms.DockStyle]::Fill
$statusLabel.AutoSize = $false
$statusLabel.Font = New-Object System.Drawing.Font("Segoe UI", 11, [System.Drawing.FontStyle]::Bold)
$statusLabel.TextAlign = [System.Drawing.ContentAlignment]::MiddleLeft
$statusPanel.Controls.Add($statusLabel)

$mainTable.Controls.Add($statusPanel, 0, 1)
$mainTable.SetColumnSpan($statusPanel, 2)

# === ROW 2: INFO PANEL ===
$infoPanel = New-Object System.Windows.Forms.Panel
$infoPanel.Dock = [System.Windows.Forms.DockStyle]::Fill
$infoPanel.BackColor = [System.Drawing.Color]::FromArgb(255, 250, 205)
$infoPanel.Padding = New-Object System.Windows.Forms.Padding(20, 15, 20, 15)

$infoLabel = New-Object System.Windows.Forms.Label
$infoLabel.Dock = [System.Windows.Forms.DockStyle]::Fill
$infoLabel.AutoSize = $false
$infoLabel.Font = New-Object System.Drawing.Font("Segoe UI", 9)
$infoLabel.Text = "ℹ️ Checked items will be BLOCKED (redirected to 0.0.0.0 in hosts file)`n   Backups are created automatically. DNS cache is flushed after applying changes."
$infoPanel.Controls.Add($infoLabel)

$mainTable.Controls.Add($infoPanel, 0, 2)
$mainTable.SetColumnSpan($infoPanel, 2)

# === ROW 3: LEFT SIDE - SCROLLABLE CONTENT PANEL ===
$contentPanel = New-Object System.Windows.Forms.Panel
$contentPanel.Dock = [System.Windows.Forms.DockStyle]::Fill
$contentPanel.Padding = New-Object System.Windows.Forms.Padding(20)
$contentPanel.BackColor = [System.Drawing.Color]::FromArgb(240, 240, 245)

$checkboxPanel = New-Object System.Windows.Forms.Panel
$checkboxPanel.Dock = [System.Windows.Forms.DockStyle]::Fill
$checkboxPanel.AutoScroll = $true
$checkboxPanel.BackColor = [System.Drawing.Color]::White
$checkboxPanel.Padding = New-Object System.Windows.Forms.Padding(20)
$contentPanel.Controls.Add($checkboxPanel)

$mainTable.Controls.Add($contentPanel, 0, 3)

# === ROW 3: RIGHT SIDE - DIAGNOSTICS PANEL ===
$diagnosticOuterPanel = New-Object System.Windows.Forms.Panel
$diagnosticOuterPanel.Dock = [System.Windows.Forms.DockStyle]::Fill
$diagnosticOuterPanel.Padding = New-Object System.Windows.Forms.Padding(10, 20, 20, 20)
$diagnosticOuterPanel.BackColor = [System.Drawing.Color]::FromArgb(240, 240, 245)

$diagnosticMainPanel = New-Object System.Windows.Forms.Panel
$diagnosticMainPanel.Dock = [System.Windows.Forms.DockStyle]::Fill
$diagnosticMainPanel.BackColor = [System.Drawing.Color]::FromArgb(250, 250, 255)
$diagnosticMainPanel.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle
$diagnosticOuterPanel.Controls.Add($diagnosticMainPanel)

# Diagnostic title
$diagTitlePanel = New-Object System.Windows.Forms.Panel
$diagTitlePanel.Dock = [System.Windows.Forms.DockStyle]::Top
$diagTitlePanel.Height = 60
$diagTitlePanel.BackColor = [System.Drawing.Color]::FromArgb(70, 130, 180)
$diagTitlePanel.Padding = New-Object System.Windows.Forms.Padding(15, 10, 15, 10)
$diagnosticMainPanel.Controls.Add($diagTitlePanel)

$diagTitle = New-Object System.Windows.Forms.Label
$diagTitle.Dock = [System.Windows.Forms.DockStyle]::Fill
$diagTitle.Text = "🔍 PowerShell Diagnostics"
$diagTitle.Font = New-Object System.Drawing.Font("Segoe UI", 12, [System.Drawing.FontStyle]::Bold)
$diagTitle.ForeColor = [System.Drawing.Color]::White
$diagTitle.TextAlign = [System.Drawing.ContentAlignment]::MiddleLeft
$diagTitlePanel.Controls.Add($diagTitle)

# Diagnostic text output
$diagTextPanel = New-Object System.Windows.Forms.Panel
$diagTextPanel.Dock = [System.Windows.Forms.DockStyle]::Fill
$diagTextPanel.Padding = New-Object System.Windows.Forms.Padding(10)
$diagnosticMainPanel.Controls.Add($diagTextPanel)

$diagText = New-Object System.Windows.Forms.TextBox
$diagText.Multiline = $true
$diagText.ScrollBars = "Vertical"
$diagText.Dock = [System.Windows.Forms.DockStyle]::Fill
$diagText.ReadOnly = $true
$diagText.Font = New-Object System.Drawing.Font("Consolas", 9)
$diagText.BackColor = [System.Drawing.Color]::FromArgb(1, 36, 86)
$diagText.ForeColor = [System.Drawing.Color]::White
$diagText.Text = "PS> # PowerShell Diagnostic Console`n"
$diagText.Text += "PS> # Click 'Run Diagnostics' or use quick actions below`n`n"
$diagTextPanel.Controls.Add($diagText)

# Diagnostic buttons
$diagButtonPanel = New-Object System.Windows.Forms.Panel
$diagButtonPanel.Dock = [System.Windows.Forms.DockStyle]::Bottom
$diagButtonPanel.Height = 200
$diagButtonPanel.Padding = New-Object System.Windows.Forms.Padding(10)
$diagnosticMainPanel.Controls.Add($diagButtonPanel)

# Create button table for organized layout
$diagBtnTable = New-Object System.Windows.Forms.TableLayoutPanel
$diagBtnTable.Dock = [System.Windows.Forms.DockStyle]::Fill
$diagBtnTable.ColumnCount = 1
$diagBtnTable.RowCount = 5
$diagBtnTable.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Percent, 20))) | Out-Null
$diagBtnTable.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Percent, 20))) | Out-Null
$diagBtnTable.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Percent, 20))) | Out-Null
$diagBtnTable.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Percent, 20))) | Out-Null
$diagBtnTable.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Percent, 20))) | Out-Null
$diagButtonPanel.Controls.Add($diagBtnTable)

# HELPER FUNCTION FOR REAL-TIME UI UPDATES
$WriteConsole = {
    param($text)
    $diagText.AppendText($text)
    $diagText.SelectionStart = $diagText.Text.Length
    $diagText.ScrollToCaret()
    $diagText.Refresh()
    [System.Windows.Forms.Application]::DoEvents()
}

$runDiagButton = New-Object System.Windows.Forms.Button
$runDiagButton.Dock = [System.Windows.Forms.DockStyle]::Fill
$runDiagButton.Margin = New-Object System.Windows.Forms.Padding(0, 0, 0, 3)
$runDiagButton.Font = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)
$runDiagButton.Text = "▶ Run Full Diagnostics"
$runDiagButton.BackColor = [System.Drawing.Color]::FromArgb(255, 200, 100)
$runDiagButton.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$runDiagButton.Cursor = [System.Windows.Forms.Cursors]::Hand
$runDiagButton.Add_Click({
    $diagText.Clear()
    $WriteConsole.Invoke("PS> # Running Full Windows Update Diagnostics...`n`n")
    try {
        Test-WindowsUpdateHealth -outputCallback $WriteConsole
        $WriteConsole.Invoke("`n`nPS> # Diagnostics complete. Use buttons below for actions.`n")
    } catch {
        $WriteConsole.Invoke("`nERROR: $($_.Exception.Message)`n")
    }
})
$diagBtnTable.Controls.Add($runDiagButton, 0, 0)

$startServicesButton = New-Object System.Windows.Forms.Button
$startServicesButton.Dock = [System.Windows.Forms.DockStyle]::Fill
$startServicesButton.Margin = New-Object System.Windows.Forms.Padding(0, 0, 0, 3)
$startServicesButton.Font = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)
$startServicesButton.Text = "🔧 Start WU Services"
$startServicesButton.BackColor = [System.Drawing.Color]::FromArgb(144, 238, 144)
$startServicesButton.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$startServicesButton.Cursor = [System.Windows.Forms.Cursors]::Hand
$startServicesButton.Add_Click({
    $WriteConsole.Invoke("`nPS> # Starting Windows Update services...`n")
    $services = @("wuauserv", "BITS", "cryptsvc")
    foreach ($svc in $services) {
        try {
            $WriteConsole.Invoke("PS> Start-Service $svc... ")
            Start-Service $svc -ErrorAction Stop
            $WriteConsole.Invoke("STARTED`n")
        } catch {
            $WriteConsole.Invoke("ERROR: $($_.Exception.Message)`n")
        }
    }
    $WriteConsole.Invoke("PS> # Service start complete`n`n")
})
$diagBtnTable.Controls.Add($startServicesButton, 0, 1)

$resetWUButton = New-Object System.Windows.Forms.Button
$resetWUButton.Dock = [System.Windows.Forms.DockStyle]::Fill
$resetWUButton.Margin = New-Object System.Windows.Forms.Padding(0, 0, 0, 3)
$resetWUButton.Font = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)
$resetWUButton.Text = "🔄 Reset WU Components"
$resetWUButton.BackColor = [System.Drawing.Color]::FromArgb(173, 216, 230)
$resetWUButton.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$resetWUButton.Cursor = [System.Windows.Forms.Cursors]::Hand
$resetWUButton.Add_Click({
    $result = [System.Windows.Forms.MessageBox]::Show(
        "This will EMERGENCY FORCE STOP services, clear caches, and restart. Continue?",
        "Confirm Reset",
        [System.Windows.Forms.MessageBoxButtons]::YesNo,
        [System.Windows.Forms.MessageBoxIcon]::Warning
    )
    if ($result -eq [System.Windows.Forms.DialogResult]::Yes) {
        $WriteConsole.Invoke("`nPS> # Resetting Windows Update components...`n")
        
        # EMERGENCY FORCE STOP LOGIC using Taskkill
        $services = @("wuauserv", "BITS", "cryptsvc")
        foreach ($svc in $services) {
            $WriteConsole.Invoke("PS> Force killing service: $svc... ")
            try {
                # Stop-Service -Force waits. Taskkill does not.
                $processInfo = Start-Process "taskkill.exe" -ArgumentList "/F /FI `"SERVICES eq $svc`"" -NoNewWindow -PassThru -Wait
                $WriteConsole.Invoke("KILLED`n")
            } catch {
                $WriteConsole.Invoke("IGNORED (Not running)`n")
            }
        }

        $WriteConsole.Invoke("PS> Clearing SoftwareDistribution... ")
        Start-Sleep -Milliseconds 500 # Give file system a moment to release locks
        Remove-Item "C:\Windows\SoftwareDistribution" -Recurse -Force -ErrorAction SilentlyContinue
        $WriteConsole.Invoke("DONE`n")
        
        foreach ($svc in $services) {
            $WriteConsole.Invoke("PS> Start-Service $svc... ")
            Start-Service $svc -ErrorAction SilentlyContinue
            $WriteConsole.Invoke("STARTED`n")
        }
        
        $WriteConsole.Invoke("PS> # Reset complete. Try Windows Update now.`n`n")
    }
})
$diagBtnTable.Controls.Add($resetWUButton, 0, 2)

$flushDNSButton = New-Object System.Windows.Forms.Button
$flushDNSButton.Dock = [System.Windows.Forms.DockStyle]::Fill
$flushDNSButton.Margin = New-Object System.Windows.Forms.Padding(0, 0, 0, 3)
$flushDNSButton.Font = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)
$flushDNSButton.Text = "🌐 Flush DNS Cache"
$flushDNSButton.BackColor = [System.Drawing.Color]::FromArgb(255, 228, 196)
$flushDNSButton.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$flushDNSButton.Cursor = [System.Windows.Forms.Cursors]::Hand
$flushDNSButton.Add_Click({
    $WriteConsole.Invoke("`nPS> ipconfig /flushdns`n")
    try {
        $output = ipconfig /flushdns 2>&1
        $WriteConsole.Invoke(($output -join "`n") + "`n")
        $WriteConsole.Invoke("PS> # DNS cache flushed successfully`n`n")
    } catch {
        $WriteConsole.Invoke("ERROR: $($_.Exception.Message)`n`n")
    }
})
$diagBtnTable.Controls.Add($flushDNSButton, 0, 3)

$clearButton = New-Object System.Windows.Forms.Button
$clearButton.Dock = [System.Windows.Forms.DockStyle]::Fill
$clearButton.Margin = New-Object System.Windows.Forms.Padding(0, 0, 0, 0)
$clearButton.Font = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)
$clearButton.Text = "🗑️ Clear Console"
$clearButton.BackColor = [System.Drawing.Color]::White
$clearButton.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$clearButton.Cursor = [System.Windows.Forms.Cursors]::Hand
$clearButton.Add_Click({
    $diagText.Clear()
    $diagText.Text = "PS> # Console cleared. Ready for commands.`n`n"
})
$diagBtnTable.Controls.Add($clearButton, 0, 4)

$mainTable.Controls.Add($diagnosticOuterPanel, 1, 3)

# === POPULATE CHECKBOXES USING FLOW LAYOUT ===
$flowLayout = New-Object System.Windows.Forms.FlowLayoutPanel
$flowLayout.Dock = [System.Windows.Forms.DockStyle]::Top
$flowLayout.FlowDirection = [System.Windows.Forms.FlowDirection]::TopDown
$flowLayout.AutoSize = $true
$flowLayout.AutoSizeMode = [System.Windows.Forms.AutoSizeMode]::GrowAndShrink
$flowLayout.WrapContents = $false
$checkboxPanel.Controls.Add($flowLayout)

$checkboxes = @{}
$currentStatus = Get-CurrentBlockStatus

foreach ($category in $endpoints.Keys) {
    # Category header
    $categoryPanel = New-Object System.Windows.Forms.Panel
    $categoryPanel.Width = 920
    $categoryPanel.Height = 50
    $categoryPanel.Margin = New-Object System.Windows.Forms.Padding(0, 15, 0, 8)
    $categoryPanel.BackColor = [System.Drawing.Color]::FromArgb(230, 230, 250)
    
    $categoryLabel = New-Object System.Windows.Forms.Label
    $categoryLabel.Dock = [System.Windows.Forms.DockStyle]::Fill
    $categoryLabel.AutoSize = $false
    $categoryLabel.Font = New-Object System.Drawing.Font("Segoe UI", 12, [System.Drawing.FontStyle]::Bold)
    $categoryLabel.Text = "  📁 $category"
    $categoryLabel.TextAlign = [System.Drawing.ContentAlignment]::MiddleLeft
    $categoryLabel.Padding = New-Object System.Windows.Forms.Padding(10, 0, 0, 0)
    $categoryPanel.Controls.Add($categoryLabel)
    
    $flowLayout.Controls.Add($categoryPanel)
    
    # Add domain checkboxes
    foreach ($domain in $endpoints[$category]) {
        $checkbox = New-Object System.Windows.Forms.CheckBox
        $checkbox.Width = 920
        # FIXED: Increased Height to 48 and added padding to stop text clipping
        $checkbox.Height = 48
        $checkbox.Margin = New-Object System.Windows.Forms.Padding(20, 4, 0, 4)
        $checkbox.Padding = New-Object System.Windows.Forms.Padding(4, 0, 0, 0)
        $checkbox.Text = $domain
        $checkbox.Checked = $currentStatus[$domain]
        $checkbox.Font = New-Object System.Drawing.Font("Segoe UI", 10)
        $checkbox.AutoSize = $false
        $checkbox.TextAlign = [System.Drawing.ContentAlignment]::MiddleLeft
        $flowLayout.Controls.Add($checkbox)
        $checkboxes[$domain] = $checkbox
    }
}

# === ROW 4: BUTTON PANEL ===
$buttonOuterPanel = New-Object System.Windows.Forms.Panel
$buttonOuterPanel.Dock = [System.Windows.Forms.DockStyle]::Fill
$buttonOuterPanel.BackColor = [System.Drawing.Color]::FromArgb(245, 245, 245)
$buttonOuterPanel.Padding = New-Object System.Windows.Forms.Padding(20, 15, 20, 15)

# Button table layout
$buttonTable = New-Object System.Windows.Forms.TableLayoutPanel
$buttonTable.Dock = [System.Windows.Forms.DockStyle]::Fill
$buttonTable.ColumnCount = 4
$buttonTable.RowCount = 2
$buttonTable.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent, 25))) | Out-Null
$buttonTable.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent, 25))) | Out-Null
$buttonTable.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent, 25))) | Out-Null
$buttonTable.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent, 25))) | Out-Null
$buttonTable.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Percent, 50))) | Out-Null
$buttonTable.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Percent, 50))) | Out-Null
$buttonOuterPanel.Controls.Add($buttonTable)

# Preset buttons (Row 0)
$updateButton = New-Object System.Windows.Forms.Button
$updateButton.Dock = [System.Windows.Forms.DockStyle]::Fill
$updateButton.Margin = New-Object System.Windows.Forms.Padding(0, 0, 5, 5)
$updateButton.Font = New-Object System.Drawing.Font("Segoe UI", 10, [System.Drawing.FontStyle]::Bold)
$updateButton.Text = "🔄 Update Mode"
$updateButton.BackColor = [System.Drawing.Color]::FromArgb(144, 238, 144)
$updateButton.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$updateButton.Cursor = [System.Windows.Forms.Cursors]::Hand
$updateButton.Add_Click({
    foreach ($domain in $checkboxes.Keys) {
        $isUpdateDomain = $endpoints["Windows Update"] -contains $domain -or 
                          $endpoints["Activation & Licensing"] -contains $domain
        $checkboxes[$domain].Checked = -not $isUpdateDomain
    }
    [System.Windows.Forms.MessageBox]::Show("Update Mode Applied!`n`nAllows: Windows Update & Activation`nBlocks: Telemetry, Store, Diagnostics", "Mode Applied", 0, 64)
})
$buttonTable.Controls.Add($updateButton, 0, 0)

$lockdownButton = New-Object System.Windows.Forms.Button
$lockdownButton.Dock = [System.Windows.Forms.DockStyle]::Fill
$lockdownButton.Margin = New-Object System.Windows.Forms.Padding(5, 0, 5, 5)
$lockdownButton.Font = New-Object System.Drawing.Font("Segoe UI", 10, [System.Drawing.FontStyle]::Bold)
$lockdownButton.Text = "🔒 Full Lockdown"
$lockdownButton.BackColor = [System.Drawing.Color]::FromArgb(255, 160, 160)
$lockdownButton.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$lockdownButton.Cursor = [System.Windows.Forms.Cursors]::Hand
$lockdownButton.Add_Click({
    foreach ($checkbox in $checkboxes.Values) { $checkbox.Checked = $true }
    [System.Windows.Forms.MessageBox]::Show("Full Lockdown Applied!`n`n⚠️ WARNING: Blocks ALL endpoints including Windows Updates!", "Mode Applied", 0, 48)
})
$buttonTable.Controls.Add($lockdownButton, 1, 0)

$clearAllButton = New-Object System.Windows.Forms.Button
$clearAllButton.Dock = [System.Windows.Forms.DockStyle]::Fill
$clearAllButton.Margin = New-Object System.Windows.Forms.Padding(5, 0, 5, 5)
$clearAllButton.Font = New-Object System.Drawing.Font("Segoe UI", 10, [System.Drawing.FontStyle]::Bold)
$clearAllButton.Text = "✓ Allow All"
$clearAllButton.BackColor = [System.Drawing.Color]::FromArgb(173, 216, 230)
$clearAllButton.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$clearAllButton.Cursor = [System.Windows.Forms.Cursors]::Hand
$clearAllButton.Add_Click({ foreach ($checkbox in $checkboxes.Values) { $checkbox.Checked = $false } })
$buttonTable.Controls.Add($clearAllButton, 2, 0)

$refreshButton = New-Object System.Windows.Forms.Button
$refreshButton.Dock = [System.Windows.Forms.DockStyle]::Fill
$refreshButton.Margin = New-Object System.Windows.Forms.Padding(5, 0, 0, 5)
$refreshButton.Font = New-Object System.Drawing.Font("Segoe UI", 10, [System.Drawing.FontStyle]::Bold)
$refreshButton.Text = "🔃 Refresh Status"
$refreshButton.BackColor = [System.Drawing.Color]::White
$refreshButton.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$refreshButton.Cursor = [System.Windows.Forms.Cursors]::Hand
$refreshButton.Add_Click({
    $currentStatus = Get-CurrentBlockStatus
    foreach ($domain in $checkboxes.Keys) { $checkboxes[$domain].Checked = $currentStatus[$domain] }
    $blockedCount = ($currentStatus.Values | Where-Object { $_ }).Count
    $totalCount = $currentStatus.Count
    $statusLabel.Text = "🔒 Currently blocking $blockedCount of $totalCount endpoints"
    [System.Windows.Forms.MessageBox]::Show("Status refreshed from hosts file!", "Refreshed", 0, 64)
})
$buttonTable.Controls.Add($refreshButton, 3, 0)

# Action buttons (Row 1)
$applyButton = New-Object System.Windows.Forms.Button
$applyButton.Dock = [System.Windows.Forms.DockStyle]::Fill
$applyButton.Margin = New-Object System.Windows.Forms.Padding(0, 5, 5, 0)
$applyButton.Font = New-Object System.Drawing.Font("Segoe UI", 11, [System.Drawing.FontStyle]::Bold)
$applyButton.Text = "✅ Apply Changes to Hosts File"
$applyButton.BackColor = [System.Drawing.Color]::FromArgb(0, 120, 215)
$applyButton.ForeColor = [System.Drawing.Color]::White
$applyButton.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$applyButton.Cursor = [System.Windows.Forms.Cursors]::Hand
$applyButton.Add_Click({
    $domainsToBlock = @(); $domainsToUnblock = @()
    foreach ($domain in $checkboxes.Keys) {
        if ($checkboxes[$domain].Checked) { $domainsToBlock += $domain }
        else { $domainsToUnblock += $domain }
    }
    try {
        $backupPath = Backup-HostsFile
        Update-HostsFile -domainsToBlock $domainsToBlock -domainsToUnblock $domainsToUnblock
        [System.Windows.Forms.MessageBox]::Show("✅ Changes Applied Successfully!`n`nBlocked: $($domainsToBlock.Count) domains`nUnblocked: $($domainsToUnblock.Count) domains`n`nBackup: $backupPath`nDNS cache flushed.", "Success", 0, 64)
        $currentStatus = Get-CurrentBlockStatus
        foreach ($domain in $checkboxes.Keys) { $checkboxes[$domain].Checked = $currentStatus[$domain] }
        $blockedCount = ($currentStatus.Values | Where-Object { $_ }).Count
        $totalCount = $currentStatus.Count
        $statusLabel.Text = "🔒 Currently blocking $blockedCount of $totalCount endpoints"
    } catch {
        [System.Windows.Forms.MessageBox]::Show("❌ Error: $($_.Exception.Message)`n`nTry running as Administrator or check if the hosts file is read-only.", "Error", 0, 16)
    }
})
$buttonTable.Controls.Add($applyButton, 0, 1)
$buttonTable.SetColumnSpan($applyButton, 3)

$cancelButton = New-Object System.Windows.Forms.Button
$cancelButton.Dock = [System.Windows.Forms.DockStyle]::Fill
$cancelButton.Margin = New-Object System.Windows.Forms.Padding(5, 5, 0, 0)
$cancelButton.Font = New-Object System.Drawing.Font("Segoe UI", 11, [System.Drawing.FontStyle]::Bold)
$cancelButton.Text = "❌ Close"
$cancelButton.BackColor = [System.Drawing.Color]::White
$cancelButton.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$cancelButton.Cursor = [System.Windows.Forms.Cursors]::Hand
$cancelButton.Add_Click({ $form.Close() })
$buttonTable.Controls.Add($cancelButton, 3, 1)

$mainTable.Controls.Add($buttonOuterPanel, 0, 4)
$mainTable.SetColumnSpan($buttonOuterPanel, 2)

# === UPDATE INITIAL STATUS ===
$blockedCount = ($currentStatus.Values | Where-Object { $_ }).Count
$totalCount = $currentStatus.Count
if ($blockedCount -eq 0) {
    $statusLabel.ForeColor = [System.Drawing.Color]::Green
    $statusLabel.Text = "✓ All endpoints currently allowed (no blocks active)"
} elseif ($blockedCount -eq $totalCount) {
    $statusLabel.ForeColor = [System.Drawing.Color]::Red
    $statusLabel.Text = "🔒 Full lockdown: All $totalCount endpoints blocked"
} else {
    $statusLabel.ForeColor = [System.Drawing.Color]::OrangeRed
    $statusLabel.Text = "🔒 Currently blocking $blockedCount of $totalCount endpoints"
}

# Show form
[void]$form.ShowDialog()
