<#
.SYNOPSIS
    Folder Synchronization Utility with GUI
.DESCRIPTION
    Compare two folders, report differences, and sync with backup/rename options
.AUTHOR
    FolderSync AlphaScript
.VERSION
    2.2
#>

#region Load Assemblies
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName System.IO
#endregion

#region Global Variables
$script:SourceFolder = ""
$script:TargetFolder = ""
$script:CompareResults = $null
$script:SelectedAction = "Compare"
$script:IsProcessing = $false
#endregion

#region Main Form
$form = New-Object System.Windows.Forms.Form
$form.Text = "FolderSync Pro - Folder Comparison Utility"
$form.Size = New-Object System.Drawing.Size(1000, 700)
$form.StartPosition = "CenterScreen"
$form.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::FixedSingle
$form.MaximizeBox = $true
$form.MinimizeBox = $true
$form.BackColor = [System.Drawing.Color]::FromArgb(240, 240, 240)
#endregion

#region Helper Functions
function Show-Progress {
    param([string]$Message, [int]$Percent)
    $script:lblStatus.Text = $Message
    $script:progressBar.Value = $Percent
    $script:progressBar.Visible = $true
    [System.Windows.Forms.Application]::DoEvents()
}

function Reset-Progress {
    $script:lblStatus.Text = "Ready"
    $script:progressBar.Value = 0
    $script:progressBar.Visible = $false
    [System.Windows.Forms.Application]::DoEvents()
}

function Get-RelativePath {
    param([string]$FullPath, [string]$BasePath)
    return $FullPath.Substring($BasePath.Length).TrimStart('\')
}

function Format-FileSize {
    param([long]$Bytes)
    if ($Bytes -eq 0) { return "0 B" }
    if ($Bytes -lt 1KB) { return "$Bytes B" }
    if ($Bytes -lt 1MB) { return "{0:N2} KB" -f ($Bytes / 1KB) }
    if ($Bytes -lt 1GB) { return "{0:N2} MB" -f ($Bytes / 1MB) }
    return "{0:N2} GB" -f ($Bytes / 1GB)
}

function Get-Timestamp {
    return Get-Date -Format "yyyyMMdd_HHmmss"
}

function Validate-Path {
    param([string]$Path)
    
    if ([string]::IsNullOrEmpty($Path)) {
        return $false
    }
    
    # Check if it's a valid path (exists or is a valid path format)
    try {
        $testPath = [System.IO.Path]::GetFullPath($Path)
        return $true
    }
    catch {
        return $false
    }
}

function Normalize-Path {
    param([string]$Path)
    
    try {
        # Expand environment variables if present
        if ($Path -match '%[^%]+%') {
            $Path = [System.Environment]::ExpandEnvironmentVariables($Path)
        }
        
        # Convert to full path
        $fullPath = [System.IO.Path]::GetFullPath($Path)
        return $fullPath
    }
    catch {
        return $Path
    }
}

function Safe-CopyFile {
    param([string]$Source, [string]$Destination, [bool]$BackupOld = $true)
    
    try {
        # Create destination directory if it doesn't exist
        $destDir = Split-Path $Destination -Parent
        if (!(Test-Path $destDir)) {
            New-Item -ItemType Directory -Path $destDir -Force | Out-Null
        }
        
        # Check if target exists and backup if requested
        if ((Test-Path $Destination) -and $BackupOld) {
            $timestamp = Get-Timestamp
            $dir = Split-Path $Destination
            $name = [System.IO.Path]::GetFileNameWithoutExtension($Destination)
            $ext = [System.IO.Path]::GetExtension($Destination)
            $backupName = "$name`_old_$timestamp$ext"
            $backupPath = Join-Path $dir $backupName
            
            # If backup already exists, add number
            $counter = 1
            while (Test-Path $backupPath) {
                $backupName = "$name`_old_$timestamp`_$counter$ext"
                $backupPath = Join-Path $dir $backupName
                $counter++
            }
            
            Move-Item -Path $Destination -Destination $backupPath -Force
            $script:lblStatus.Text = "Backed up: $backupName"
        }
        
        Copy-Item -Path $Source -Destination $Destination -Force
        return $true
    }
    catch {
        $script:lblStatus.Text = "Error: $($_.Exception.Message)"
        return $false
    }
}
#endregion

#region Comparison Engine
function Compare-Folders {
    param(
        [string]$SourcePath,
        [string]$TargetPath,
        [bool]$CompareSize = $true,
        [bool]$CompareDate = $true,
        [bool]$CompareHash = $false
    )
    
    $results = @()
    $sourceFiles = @{}
    $targetFiles = @{}
    
    # Normalize paths
    $SourcePath = Normalize-Path -Path $SourcePath
    $TargetPath = Normalize-Path -Path $TargetPath
    
    # Get source files
    Show-Progress "Scanning source folder..." 10
    $sourceList = Get-ChildItem -Path $SourcePath -File -Recurse -ErrorAction SilentlyContinue
    $total = $sourceList.Count
    $count = 0
    
    foreach ($file in $sourceList) {
        $relative = Get-RelativePath $file.FullName $SourcePath
        $sourceFiles[$relative] = @{
            Name = $file.Name
            Size = $file.Length
            Modified = $file.LastWriteTime
            Created = $file.CreationTime
            FullPath = $file.FullName
            Hash = $null
        }
        $count++
        if ($count % 10 -eq 0) {
            $percent = 10 + [int](($count / $total) * 20)
            Show-Progress "Scanning source: $relative" $percent
        }
    }
    
    # Get target files
    Show-Progress "Scanning target folder..." 35
    $targetList = Get-ChildItem -Path $TargetPath -File -Recurse -ErrorAction SilentlyContinue
    $total = $targetList.Count
    $count = 0
    
    foreach ($file in $targetList) {
        $relative = Get-RelativePath $file.FullName $TargetPath
        $targetFiles[$relative] = @{
            Name = $file.Name
            Size = $file.Length
            Modified = $file.LastWriteTime
            Created = $file.CreationTime
            FullPath = $file.FullName
            Hash = $null
        }
        $count++
        if ($count % 10 -eq 0) {
            $percent = 35 + [int](($count / $total) * 15)
            Show-Progress "Scanning target: $relative" $percent
        }
    }
    
    # Calculate hashes if requested
    if ($CompareHash) {
        Show-Progress "Calculating hashes (this may take a while)..." 55
        
        # Get files that exist in both and are different in size/date
        $toHash = @()
        foreach ($key in $sourceFiles.Keys) {
            if ($targetFiles.ContainsKey($key)) {
                $sizeMatch = $sourceFiles[$key].Size -eq $targetFiles[$key].Size
                $dateMatch = $sourceFiles[$key].Modified -eq $targetFiles[$key].Modified
                if (!$sizeMatch -or !$dateMatch) {
                    $toHash += @{Key=$key; Source=$sourceFiles[$key].FullPath; Target=$targetFiles[$key].FullPath}
                }
            }
        }
        
        $total = $toHash.Count
        $count = 0
        foreach ($item in $toHash) {
            $percent = 55 + [int](($count / $total) * 20)
            Show-Progress "Hashing: $($item.Key)" $percent
            
            $sourceHash = (Get-FileHash -Path $item.Source -Algorithm SHA256 -ErrorAction SilentlyContinue).Hash
            $targetHash = (Get-FileHash -Path $item.Target -Algorithm SHA256 -ErrorAction SilentlyContinue).Hash
            
            $sourceFiles[$item.Key].Hash = $sourceHash
            $targetFiles[$item.Key].Hash = $targetHash
            
            $count++
        }
    }
    
    # Compare and build results
    Show-Progress "Comparing files..." 75
    $allKeys = $sourceFiles.Keys + $targetFiles.Keys | Sort-Object -Unique
    
    $total = $allKeys.Count
    $count = 0
    $resultsList = @()
    
    foreach ($key in $allKeys) {
        $count++
        $percent = 75 + [int](($count / $total) * 20)
        Show-Progress "Processing: $key" $percent
        
        $hasSource = $sourceFiles.ContainsKey($key)
        $hasTarget = $targetFiles.ContainsKey($key)
        
        if (!$hasSource) {
            # Only in target
            $resultsList += [PSCustomObject]@{
                Status = "Only in Target"
                File = $key
                SourceSize = ""
                TargetSize = Format-FileSize $targetFiles[$key].Size
                SourceModified = ""
                TargetModified = $targetFiles[$key].Modified
                Action = "None"
                SourcePath = ""
                TargetPath = $targetFiles[$key].FullPath
            }
        }
        elseif (!$hasTarget) {
            # Only in source
            $resultsList += [PSCustomObject]@{
                Status = "Missing in Target"
                File = $key
                SourceSize = Format-FileSize $sourceFiles[$key].Size
                TargetSize = ""
                SourceModified = $sourceFiles[$key].Modified
                TargetModified = ""
                Action = "Copy to Target"
                SourcePath = $sourceFiles[$key].FullPath
                TargetPath = Join-Path $TargetPath $key
            }
        }
        else {
            # In both - check differences
            $sizeDiff = $sourceFiles[$key].Size -ne $targetFiles[$key].Size
            $dateDiff = $sourceFiles[$key].Modified -ne $targetFiles[$key].Modified
            $hashDiff = $false
            
            if ($CompareHash -and $sourceFiles[$key].Hash -and $targetFiles[$key].Hash) {
                $hashDiff = $sourceFiles[$key].Hash -ne $targetFiles[$key].Hash
            }
            
            if ($sizeDiff -or $dateDiff -or $hashDiff) {
                $action = if ($sizeDiff) { "Size differs" } else { "Date differs" }
                if ($hashDiff) { $action = "Hash differs" }
                
                $resultsList += [PSCustomObject]@{
                    Status = "Different"
                    File = $key
                    SourceSize = Format-FileSize $sourceFiles[$key].Size
                    TargetSize = Format-FileSize $targetFiles[$key].Size
                    SourceModified = $sourceFiles[$key].Modified
                    TargetModified = $targetFiles[$key].Modified
                    Action = "Replace with Backup"
                    SourcePath = $sourceFiles[$key].FullPath
                    TargetPath = $targetFiles[$key].FullPath
                }
            }
            else {
                # Identical
                $resultsList += [PSCustomObject]@{
                    Status = "Identical"
                    File = $key
                    SourceSize = Format-FileSize $sourceFiles[$key].Size
                    TargetSize = Format-FileSize $targetFiles[$key].Size
                    SourceModified = $sourceFiles[$key].Modified
                    TargetModified = $targetFiles[$key].Modified
                    Action = "None"
                    SourcePath = $sourceFiles[$key].FullPath
                    TargetPath = $targetFiles[$key].FullPath
                }
            }
        }
    }
    
    Show-Progress "Complete!" 100
    return $resultsList
}
#endregion

#region Action Functions
function Execute-Sync {
    param(
        [array]$Results,
        [bool]$CopyMissing = $true,
        [bool]$ReplaceChanged = $true,
        [bool]$BackupOld = $true
    )
    
    $success = 0
    $failed = 0
    
    # Filter items that need action
    $itemsToProcess = $Results | Where-Object { 
        ($_.Status -eq "Missing in Target" -and $CopyMissing) -or
        ($_.Status -eq "Different" -and $ReplaceChanged)
    }
    
    $total = $itemsToProcess.Count
    $count = 0
    
    foreach ($item in $itemsToProcess) {
        $count++
        $percent = [int](($count / $total) * 100)
        Show-Progress "Processing: $($item.File) ($count/$total)" $percent
        
        try {
            if ($item.Status -eq "Missing in Target") {
                # Copy missing file
                if (Safe-CopyFile -Source $item.SourcePath -Destination $item.TargetPath -BackupOld $false) {
                    $success++
                    $item.Status = "Copied"
                }
                else {
                    $failed++
                }
            }
            elseif ($item.Status -eq "Different") {
                # Replace with backup
                if (Safe-CopyFile -Source $item.SourcePath -Destination $item.TargetPath -BackupOld $BackupOld) {
                    $success++
                    $item.Status = "Replaced"
                }
                else {
                    $failed++
                }
            }
        }
        catch {
            $failed++
        }
    }
    
    Reset-Progress
    [System.Windows.Forms.MessageBox]::Show(
        "Sync Complete!`n`nSuccess: $success`nFailed: $failed",
        "Sync Results",
        "OK",
        "Information"
    )
    
    # Refresh results grid
    Update-ResultsGrid $Results
}

function Export-Results {
    param(
        [array]$Results,
        [string]$Format = "CSV"
    )
    
    $saveDialog = New-Object System.Windows.Forms.SaveFileDialog
    $saveDialog.Title = "Export Results"
    
    switch ($Format) {
        "CSV" {
            $saveDialog.Filter = "CSV Files (*.csv)|*.csv"
            $saveDialog.FileName = "FolderCompare_$(Get-Timestamp).csv"
        }
        "TXT" {
            $saveDialog.Filter = "Text Files (*.txt)|*.txt"
            $saveDialog.FileName = "FolderCompare_$(Get-Timestamp).txt"
        }
        "JSON" {
            $saveDialog.Filter = "JSON Files (*.json)|*.json"
            $saveDialog.FileName = "FolderCompare_$(Get-Timestamp).json"
        }
        "HTML" {
            $saveDialog.Filter = "HTML Files (*.html)|*.html"
            $saveDialog.FileName = "FolderCompare_$(Get-Timestamp).html"
        }
    }
    
    if ($saveDialog.ShowDialog() -eq "OK") {
        $filePath = $saveDialog.FileName
        
        try {
            switch ($Format) {
                "CSV" {
                    $Results | Export-Csv -Path $filePath -NoTypeInformation
                }
                "TXT" {
                    $Results | Format-Table -AutoSize | Out-File $filePath
                }
                "JSON" {
                    $Results | ConvertTo-Json -Depth 3 | Out-File $filePath
                }
                "HTML" {
                    $html = @"
<!DOCTYPE html>
<html>
<head>
    <title>Folder Comparison Results</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 20px; }
        table { border-collapse: collapse; width: 100%; }
        th, td { border: 1px solid #ddd; padding: 8px; text-align: left; }
        th { background-color: #4CAF50; color: white; }
        tr:nth-child(even) { background-color: #f2f2f2; }
        .Missing { background-color: #ffcccc; }
        .Different { background-color: #ffffcc; }
        .Identical { background-color: #ccffcc; }
        .Target { background-color: #ccccff; }
    </style>
</head>
<body>
    <h1>Folder Comparison Results</h1>
    <p>Generated: $(Get-Date)</p>
    <table>
        <tr>
            <th>Status</th>
            <th>File</th>
            <th>Source Size</th>
            <th>Target Size</th>
            <th>Source Modified</th>
            <th>Target Modified</th>
            <th>Action</th>
        </tr>
"@
                    foreach ($item in $Results) {
                        $class = switch ($item.Status) {
                            "Missing in Target" { "Missing" }
                            "Only in Target" { "Target" }
                            "Different" { "Different" }
                            "Identical" { "Identical" }
                            default { "" }
                        }
                        $html += @"
        <tr class="$class">
            <td>$($item.Status)</td>
            <td>$($item.File)</td>
            <td>$($item.SourceSize)</td>
            <td>$($item.TargetSize)</td>
            <td>$($item.SourceModified)</td>
            <td>$($item.TargetModified)</td>
            <td>$($item.Action)</td>
        </tr>
"@
                    }
                    $html += @"
    </table>
</body>
</html>
"@
                    $html | Out-File $filePath -Encoding UTF8
                }
            }
            
            [System.Windows.Forms.MessageBox]::Show(
                "Results exported successfully!`n`n$filePath",
                "Export Complete",
                "OK",
                "Information"
            )
        }
        catch {
            [System.Windows.Forms.MessageBox]::Show(
                "Error exporting results: $($_.Exception.Message)",
                "Export Error",
                "OK",
                "Error"
            )
        }
    }
}
#endregion

#region GUI Update Functions
function Update-ResultsGrid {
    param([array]$Results)
    
    $script:dataGridView.Rows.Clear()
    
    if ($Results -eq $null -or $Results.Count -eq 0) {
        return
    }
    
    $statusColors = @{
        "Missing in Target" = "LightSalmon"
        "Only in Target" = "LightBlue"
        "Different" = "LightYellow"
        "Identical" = "LightGreen"
        "Copied" = "LightGreen"
        "Replaced" = "LightGreen"
    }
    
    foreach ($item in $Results) {
        $rowIndex = $script:dataGridView.Rows.Add(
            $item.Status,
            $item.File,
            $item.SourceSize,
            $item.TargetSize,
            $item.SourceModified,
            $item.TargetModified,
            $item.Action,
            $item.SourcePath,
            $item.TargetPath
        )
        
        # Color the row based on status
        if ($statusColors.ContainsKey($item.Status)) {
            $script:dataGridView.Rows[$rowIndex].DefaultCellStyle.BackColor = 
                [System.Drawing.Color]::FromName($statusColors[$item.Status])
        }
    }
    
    $script:lblResultCount.Text = "Found $($Results.Count) items"
}

function Update-StatusInfo {
    if ($script:dataGridView.Rows.Count -gt 0) {
        $missing = 0
        $different = 0
        $identical = 0
        $target = 0
        
        foreach ($row in $script:dataGridView.Rows) {
            $status = $row.Cells[0].Value.ToString()
            switch ($status) {
                "Missing in Target" { $missing++ }
                "Only in Target" { $target++ }
                "Different" { $different++ }
                "Identical" { $identical++ }
            }
        }
        
        $script:lblStats.Text = "Missing: $missing | Only in Target: $target | Different: $different | Identical: $identical"
    }
    else {
        $script:lblStats.Text = "No results to display"
    }
}

function Update-FolderPath {
    param(
        [string]$TextBox,
        [string]$Path
    )
    
    # Normalize the path
    $normalizedPath = Normalize-Path -Path $Path
    
    # Update the text box
    $TextBox.Text = $normalizedPath
    
    # Update the global variable
    if ($TextBox -eq $script:txtSource) {
        $script:SourceFolder = $normalizedPath
    }
    elseif ($TextBox -eq $script:txtTarget) {
        $script:TargetFolder = $normalizedPath
    }
}
#endregion

#region Create Controls
# Panel for folder selection
$panelFolder = New-Object System.Windows.Forms.Panel
$panelFolder.Location = New-Object System.Drawing.Point(10, 10)
$panelFolder.Size = New-Object System.Drawing.Size(960, 110)
$panelFolder.BackColor = [System.Drawing.Color]::White
$panelFolder.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle

# Source folder
$lblSource = New-Object System.Windows.Forms.Label
$lblSource.Location = New-Object System.Drawing.Point(10, 15)
$lblSource.Size = New-Object System.Drawing.Size(60, 20)
$lblSource.Text = "Source:"
$lblSource.Font = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)

$txtSource = New-Object System.Windows.Forms.TextBox
$txtSource.Location = New-Object System.Drawing.Point(70, 12)
$txtSource.Size = New-Object System.Drawing.Size(710, 25)
$txtSource.Font = New-Object System.Drawing.Font("Segoe UI", 9)
$txtSource.ReadOnly = $false  # Changed to allow typing
$txtSource.BackColor = [System.Drawing.Color]::White
$txtSource.ContextMenuStrip = New-Object System.Windows.Forms.ContextMenuStrip

# Add context menu for paste
$pasteMenuItem = New-Object System.Windows.Forms.ToolStripMenuItem
$pasteMenuItem.Text = "Paste"
$pasteMenuItem.Add_Click({
    if ([System.Windows.Forms.Clipboard]::ContainsText()) {
        $txtSource.Text = [System.Windows.Forms.Clipboard]::GetText()
    }
})
$txtSource.ContextMenuStrip.Items.Add($pasteMenuItem)

# Add tooltip for source
$tooltip = New-Object System.Windows.Forms.ToolTip
$tooltip.SetToolTip($txtSource, "Type or paste a path, or use Browse button")

$btnSource = New-Object System.Windows.Forms.Button
$btnSource.Location = New-Object System.Drawing.Point(785, 10)
$btnSource.Size = New-Object System.Drawing.Size(80, 30)
$btnSource.Text = "Browse..."
$btnSource.UseVisualStyleBackColor = $true

# Target folder
$lblTarget = New-Object System.Windows.Forms.Label
$lblTarget.Location = New-Object System.Drawing.Point(10, 55)
$lblTarget.Size = New-Object System.Drawing.Size(60, 20)
$lblTarget.Text = "Target:"
$lblTarget.Font = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)

$txtTarget = New-Object System.Windows.Forms.TextBox
$txtTarget.Location = New-Object System.Drawing.Point(70, 52)
$txtTarget.Size = New-Object System.Drawing.Size(710, 25)
$txtTarget.Font = New-Object System.Drawing.Font("Segoe UI", 9)
$txtTarget.ReadOnly = $false  # Changed to allow typing
$txtTarget.BackColor = [System.Drawing.Color]::White

# Add context menu for target paste
$pasteMenuItemTarget = New-Object System.Windows.Forms.ToolStripMenuItem
$pasteMenuItemTarget.Text = "Paste"
$pasteMenuItemTarget.Add_Click({
    if ([System.Windows.Forms.Clipboard]::ContainsText()) {
        $txtTarget.Text = [System.Windows.Forms.Clipboard]::GetText()
    }
})
$txtTarget.ContextMenuStrip = New-Object System.Windows.Forms.ContextMenuStrip
$txtTarget.ContextMenuStrip.Items.Add($pasteMenuItemTarget)

# Add tooltip for target
$tooltip.SetToolTip($txtTarget, "Type or paste a path, or use Browse button")

$btnTarget = New-Object System.Windows.Forms.Button
$btnTarget.Location = New-Object System.Drawing.Point(785, 50)
$btnTarget.Size = New-Object System.Drawing.Size(80, 30)
$btnTarget.Text = "Browse..."
$btnTarget.UseVisualStyleBackColor = $true

# Options checkbox panel
$panelOptions = New-Object System.Windows.Forms.Panel
$panelOptions.Location = New-Object System.Drawing.Point(870, 10)
$panelOptions.Size = New-Object System.Drawing.Size(80, 72)
$panelOptions.BackColor = [System.Drawing.Color]::Transparent

$chkSize = New-Object System.Windows.Forms.CheckBox
$chkSize.Location = New-Object System.Drawing.Point(10, 10)
$chkSize.Size = New-Object System.Drawing.Size(60, 20)
$chkSize.Text = "Size"
$chkSize.Checked = $true

$chkDate = New-Object System.Windows.Forms.CheckBox
$chkDate.Location = New-Object System.Drawing.Point(10, 30)
$chkDate.Size = New-Object System.Drawing.Size(60, 20)
$chkDate.Text = "Date"
$chkDate.Checked = $true

$chkHash = New-Object System.Windows.Forms.CheckBox
$chkHash.Location = New-Object System.Drawing.Point(10, 50)
$chkHash.Size = New-Object System.Drawing.Size(60, 20)
$chkHash.Text = "Hash"
$chkHash.Checked = $false

$panelOptions.Controls.AddRange(@($chkSize, $chkDate, $chkHash))

$panelFolder.Controls.AddRange(@(
    $lblSource, $txtSource, $btnSource,
    $lblTarget, $txtTarget, $btnTarget,
    $panelOptions
))

# Action buttons panel
$panelActions = New-Object System.Windows.Forms.Panel
$panelActions.Location = New-Object System.Drawing.Point(10, 130)
$panelActions.Size = New-Object System.Drawing.Size(960, 50)
$panelActions.BackColor = [System.Drawing.Color]::White
$panelActions.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle

$btnScan = New-Object System.Windows.Forms.Button
$btnScan.Location = New-Object System.Drawing.Point(10, 10)
$btnScan.Size = New-Object System.Drawing.Size(100, 30)
$btnScan.Text = "Scan"
$btnScan.BackColor = [System.Drawing.Color]::FromArgb(0, 120, 215)
$btnScan.ForeColor = [System.Drawing.Color]::White
$btnScan.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$btnScan.Font = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)

$btnSync = New-Object System.Windows.Forms.Button
$btnSync.Location = New-Object System.Drawing.Point(120, 10)
$btnSync.Size = New-Object System.Drawing.Size(100, 30)
$btnSync.Text = "Sync"
$btnSync.BackColor = [System.Drawing.Color]::FromArgb(0, 200, 83)
$btnSync.ForeColor = [System.Drawing.Color]::White
$btnSync.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$btnSync.Font = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)
$btnSync.Enabled = $false

$btnExportCSV = New-Object System.Windows.Forms.Button
$btnExportCSV.Location = New-Object System.Drawing.Point(230, 10)
$btnExportCSV.Size = New-Object System.Drawing.Size(80, 30)
$btnExportCSV.Text = "Export CSV"
$btnExportCSV.UseVisualStyleBackColor = $true
$btnExportCSV.Enabled = $false

$btnExportTXT = New-Object System.Windows.Forms.Button
$btnExportTXT.Location = New-Object System.Drawing.Point(320, 10)
$btnExportTXT.Size = New-Object System.Drawing.Size(80, 30)
$btnExportTXT.Text = "Export TXT"
$btnExportTXT.UseVisualStyleBackColor = $true
$btnExportTXT.Enabled = $false

$btnExportJSON = New-Object System.Windows.Forms.Button
$btnExportJSON.Location = New-Object System.Drawing.Point(410, 10)
$btnExportJSON.Size = New-Object System.Drawing.Size(80, 30)
$btnExportJSON.Text = "Export JSON"
$btnExportJSON.UseVisualStyleBackColor = $true
$btnExportJSON.Enabled = $false

$btnExportHTML = New-Object System.Windows.Forms.Button
$btnExportHTML.Location = New-Object System.Drawing.Point(500, 10)
$btnExportHTML.Size = New-Object System.Drawing.Size(80, 30)
$btnExportHTML.Text = "Export HTML"
$btnExportHTML.UseVisualStyleBackColor = $true
$btnExportHTML.Enabled = $false

$btnClear = New-Object System.Windows.Forms.Button
$btnClear.Location = New-Object System.Drawing.Point(880, 10)
$btnClear.Size = New-Object System.Drawing.Size(70, 30)
$btnClear.Text = "Clear"
$btnClear.UseVisualStyleBackColor = $true

$chkCopyMissing = New-Object System.Windows.Forms.CheckBox
$chkCopyMissing.Location = New-Object System.Drawing.Point(600, 12)
$chkCopyMissing.Size = New-Object System.Drawing.Size(120, 20)
$chkCopyMissing.Text = "Copy Missing"
$chkCopyMissing.Checked = $true

$chkReplaceChanged = New-Object System.Windows.Forms.CheckBox
$chkReplaceChanged.Location = New-Object System.Drawing.Point(720, 12)
$chkReplaceChanged.Size = New-Object System.Drawing.Size(120, 20)
$chkReplaceChanged.Text = "Replace Changed"
$chkReplaceChanged.Checked = $true

$chkBackupOld = New-Object System.Windows.Forms.CheckBox
$chkBackupOld.Location = New-Object System.Drawing.Point(600, 32)
$chkBackupOld.Size = New-Object System.Drawing.Size(200, 20)
$chkBackupOld.Text = "Backup Old Files (_old_*)"
$chkBackupOld.Checked = $true

$panelActions.Controls.AddRange(@(
    $btnScan, $btnSync, $btnExportCSV, $btnExportTXT,
    $btnExportJSON, $btnExportHTML, $btnClear,
    $chkCopyMissing, $chkReplaceChanged, $chkBackupOld
))

# Results grid
$dataGridView = New-Object System.Windows.Forms.DataGridView
$dataGridView.Location = New-Object System.Drawing.Point(10, 190)
$dataGridView.Size = New-Object System.Drawing.Size(960, 400)
$dataGridView.BackgroundColor = [System.Drawing.Color]::White
$dataGridView.BorderStyle = [System.Windows.Forms.BorderStyle]::Fixed3D
$dataGridView.RowHeadersVisible = $false
$dataGridView.AllowUserToAddRows = $false
$dataGridView.AllowUserToDeleteRows = $false
$dataGridView.ReadOnly = $true
$dataGridView.SelectionMode = [System.Windows.Forms.DataGridViewSelectionMode]::FullRowSelect
$dataGridView.AutoSizeColumnsMode = [System.Windows.Forms.DataGridViewAutoSizeColumnsMode]::Fill
$dataGridView.Font = New-Object System.Drawing.Font("Segoe UI", 8)

# Create columns
$colStatus = New-Object System.Windows.Forms.DataGridViewTextBoxColumn
$colStatus.HeaderText = "Status"
$colStatus.Width = 100
$dataGridView.Columns.Add($colStatus) | Out-Null

$colFile = New-Object System.Windows.Forms.DataGridViewTextBoxColumn
$colFile.HeaderText = "File"
$colFile.Width = 300
$dataGridView.Columns.Add($colFile) | Out-Null

$colSourceSize = New-Object System.Windows.Forms.DataGridViewTextBoxColumn
$colSourceSize.HeaderText = "Source Size"
$colSourceSize.Width = 80
$dataGridView.Columns.Add($colSourceSize) | Out-Null

$colTargetSize = New-Object System.Windows.Forms.DataGridViewTextBoxColumn
$colTargetSize.HeaderText = "Target Size"
$colTargetSize.Width = 80
$dataGridView.Columns.Add($colTargetSize) | Out-Null

$colSourceDate = New-Object System.Windows.Forms.DataGridViewTextBoxColumn
$colSourceDate.HeaderText = "Source Modified"
$colSourceDate.Width = 120
$dataGridView.Columns.Add($colSourceDate) | Out-Null

$colTargetDate = New-Object System.Windows.Forms.DataGridViewTextBoxColumn
$colTargetDate.HeaderText = "Target Modified"
$colTargetDate.Width = 120
$dataGridView.Columns.Add($colTargetDate) | Out-Null

$colAction = New-Object System.Windows.Forms.DataGridViewTextBoxColumn
$colAction.HeaderText = "Action"
$colAction.Width = 100
$dataGridView.Columns.Add($colAction) | Out-Null

$colSourcePath = New-Object System.Windows.Forms.DataGridViewTextBoxColumn
$colSourcePath.HeaderText = "Source Path"
$colSourcePath.Visible = $false
$dataGridView.Columns.Add($colSourcePath) | Out-Null

$colTargetPath = New-Object System.Windows.Forms.DataGridViewTextBoxColumn
$colTargetPath.HeaderText = "Target Path"
$colTargetPath.Visible = $false
$dataGridView.Columns.Add($colTargetPath) | Out-Null

# Status bar
$statusBar = New-Object System.Windows.Forms.StatusStrip
$statusBar.Size = New-Object System.Drawing.Size(1000, 22)

$lblResultCount = New-Object System.Windows.Forms.ToolStripStatusLabel
$lblResultCount.Text = "Ready"
$lblResultCount.Spring = $true

$lblStats = New-Object System.Windows.Forms.ToolStripStatusLabel
$lblStats.Text = ""
$lblStats.Spring = $true

$lblStatus = New-Object System.Windows.Forms.ToolStripStatusLabel
$lblStatus.Text = "Ready"
$lblStatus.Spring = $true

$progressBar = New-Object System.Windows.Forms.ToolStripProgressBar
$progressBar.Size = New-Object System.Drawing.Size(150, 16)
$progressBar.Visible = $false

$statusBar.Items.AddRange(@($lblResultCount, $lblStats, $lblStatus, $progressBar))

# Add controls to form
$form.Controls.AddRange(@(
    $panelFolder,
    $panelActions,
    $dataGridView,
    $statusBar
))
#endregion

#region Event Handlers
# Source text box events
$txtSource.Add_TextChanged({
    # Update global variable when text changes
    if ($txtSource.Text -ne "") {
        try {
            $normalized = Normalize-Path -Path $txtSource.Text
            $script:SourceFolder = $normalized
        }
        catch {
            # If path is invalid, just store what was typed
            $script:SourceFolder = $txtSource.Text
        }
    }
})

$txtSource.Add_KeyDown({
    if ($_.KeyCode -eq "Enter") {
        # Validate and normalize the path on Enter key
        try {
            $path = Normalize-Path -Path $txtSource.Text
            if (Test-Path $path) {
                $txtSource.Text = $path
                $script:SourceFolder = $path
                $txtSource.BackColor = [System.Drawing.Color]::FromArgb(220, 255, 220) # Light green
            }
            else {
                $txtSource.BackColor = [System.Drawing.Color]::FromArgb(255, 220, 220) # Light red
                [System.Windows.Forms.MessageBox]::Show(
                    "Path does not exist: $path",
                    "Invalid Path",
                    "OK",
                    "Warning"
                )
            }
        }
        catch {
            $txtSource.BackColor = [System.Drawing.Color]::FromArgb(255, 220, 220)
        }
    }
})

$txtSource.Add_Leave({
    # Validate when focus leaves the text box
    try {
        if ($txtSource.Text -ne "") {
            $path = Normalize-Path -Path $txtSource.Text
            if (Test-Path $path) {
                $txtSource.Text = $path
                $script:SourceFolder = $path
                $txtSource.BackColor = [System.Drawing.Color]::White
            }
        }
    }
    catch {
        # Ignore - user might still be typing
    }
})

# Target text box events
$txtTarget.Add_TextChanged({
    if ($txtTarget.Text -ne "") {
        try {
            $normalized = Normalize-Path -Path $txtTarget.Text
            $script:TargetFolder = $normalized
        }
        catch {
            $script:TargetFolder = $txtTarget.Text
        }
    }
})

$txtTarget.Add_KeyDown({
    if ($_.KeyCode -eq "Enter") {
        try {
            $path = Normalize-Path -Path $txtTarget.Text
            if (Test-Path $path) {
                $txtTarget.Text = $path
                $script:TargetFolder = $path
                $txtTarget.BackColor = [System.Drawing.Color]::FromArgb(220, 255, 220)
            }
            else {
                $txtTarget.BackColor = [System.Drawing.Color]::FromArgb(255, 220, 220)
                [System.Windows.Forms.MessageBox]::Show(
                    "Path does not exist: $path",
                    "Invalid Path",
                    "OK",
                    "Warning"
                )
            }
        }
        catch {
            $txtTarget.BackColor = [System.Drawing.Color]::FromArgb(255, 220, 220)
        }
    }
})

$txtTarget.Add_Leave({
    try {
        if ($txtTarget.Text -ne "") {
            $path = Normalize-Path -Path $txtTarget.Text
            if (Test-Path $path) {
                $txtTarget.Text = $path
                $script:TargetFolder = $path
                $txtTarget.BackColor = [System.Drawing.Color]::White
            }
        }
    }
    catch {
        # Ignore - user might still be typing
    }
})

# Browse buttons
$btnSource.Add_Click({
    $folderDialog = New-Object System.Windows.Forms.FolderBrowserDialog
    $folderDialog.Description = "Select Source Folder"
    $folderDialog.ShowNewFolderButton = $false
    if ($folderDialog.ShowDialog() -eq "OK") {
        $txtSource.Text = $folderDialog.SelectedPath
        $script:SourceFolder = $folderDialog.SelectedPath
        $txtSource.BackColor = [System.Drawing.Color]::White
    }
})

$btnTarget.Add_Click({
    $folderDialog = New-Object System.Windows.Forms.FolderBrowserDialog
    $folderDialog.Description = "Select Target Folder"
    $folderDialog.ShowNewFolderButton = $true
    if ($folderDialog.ShowDialog() -eq "OK") {
        $txtTarget.Text = $folderDialog.SelectedPath
        $script:TargetFolder = $folderDialog.SelectedPath
        $txtTarget.BackColor = [System.Drawing.Color]::White
    }
})

# Scan button
$btnScan.Add_Click({
    if ([string]::IsNullOrEmpty($txtSource.Text) -or [string]::IsNullOrEmpty($txtTarget.Text)) {
        [System.Windows.Forms.MessageBox]::Show(
            "Please select both Source and Target folders.",
            "Missing Folders",
            "OK",
            "Warning"
        )
        return
    }
    
    # Normalize and validate paths
    try {
        $sourcePath = Normalize-Path -Path $txtSource.Text
        $targetPath = Normalize-Path -Path $txtTarget.Text
        
        if (!(Test-Path $sourcePath)) {
            [System.Windows.Forms.MessageBox]::Show(
                "Source folder does not exist: $sourcePath",
                "Invalid Source",
                "OK",
                "Error"
            )
            $txtSource.BackColor = [System.Drawing.Color]::FromArgb(255, 220, 220)
            return
        }
        
        if (!(Test-Path $targetPath)) {
            [System.Windows.Forms.MessageBox]::Show(
                "Target folder does not exist: $targetPath",
                "Invalid Target",
                "OK",
                "Error"
            )
            $txtTarget.BackColor = [System.Drawing.Color]::FromArgb(255, 220, 220)
            return
        }
        
        # Update text boxes with normalized paths
        $txtSource.Text = $sourcePath
        $txtTarget.Text = $targetPath
        $txtSource.BackColor = [System.Drawing.Color]::White
        $txtTarget.BackColor = [System.Drawing.Color]::White
        
        $script:IsProcessing = $true
        $btnScan.Enabled = $false
        $btnSync.Enabled = $false
        $btnExportCSV.Enabled = $false
        $btnExportTXT.Enabled = $false
        $btnExportJSON.Enabled = $false
        $btnExportHTML.Enabled = $false
        
        $results = Compare-Folders `
            -SourcePath $sourcePath `
            -TargetPath $targetPath `
            -CompareSize $chkSize.Checked `
            -CompareDate $chkDate.Checked `
            -CompareHash $chkHash.Checked
        
        $script:CompareResults = $results
        Update-ResultsGrid $results
        Update-StatusInfo
        
        $btnSync.Enabled = $true
        $btnExportCSV.Enabled = $true
        $btnExportTXT.Enabled = $true
        $btnExportJSON.Enabled = $true
        $btnExportHTML.Enabled = $true
        
        Reset-Progress
    }
    catch {
        [System.Windows.Forms.MessageBox]::Show(
            "Error during scan: $($_.Exception.Message)",
            "Scan Error",
            "OK",
            "Error"
        )
        Reset-Progress
    }
    finally {
        $script:IsProcessing = $false
        $btnScan.Enabled = $true
    }
})

# Sync button
$btnSync.Add_Click({
    if ($script:CompareResults -eq $null -or $script:CompareResults.Count -eq 0) {
        [System.Windows.Forms.MessageBox]::Show(
            "No results to sync. Please run a scan first.",
            "No Results",
            "OK",
            "Warning"
        )
        return
    }
    
    $result = [System.Windows.Forms.MessageBox]::Show(
        "This will synchronize files from Source to Target based on your settings.`n`n" +
        "Copy Missing: $($chkCopyMissing.Checked)`n" +
        "Replace Changed: $($chkReplaceChanged.Checked)`n" +
        "Backup Old: $($chkBackupOld.Checked)`n`n" +
        "Continue?",
        "Confirm Sync",
        "YesNo",
        "Question"
    )
    
    if ($result -eq "Yes") {
        $script:IsProcessing = $true
        $btnScan.Enabled = $false
        $btnSync.Enabled = $false
        $btnExportCSV.Enabled = $false
        $btnExportTXT.Enabled = $false
        $btnExportJSON.Enabled = $false
        $btnExportHTML.Enabled = $false
        
        try {
            $results = $script:CompareResults | ForEach-Object { $_ }
            Execute-Sync `
                -Results $results `
                -CopyMissing $chkCopyMissing.Checked `
                -ReplaceChanged $chkReplaceChanged.Checked `
                -BackupOld $chkBackupOld.Checked
            
            $script:CompareResults = $results
            Update-ResultsGrid $results
            Update-StatusInfo
        }
        catch {
            [System.Windows.Forms.MessageBox]::Show(
                "Error during sync: $($_.Exception.Message)",
                "Sync Error",
                "OK",
                "Error"
            )
        }
        finally {
            $script:IsProcessing = $false
            $btnScan.Enabled = $true
            $btnSync.Enabled = $true
            $btnExportCSV.Enabled = $true
            $btnExportTXT.Enabled = $true
            $btnExportJSON.Enabled = $true
            $btnExportHTML.Enabled = $true
        }
    }
})

# Export buttons
$btnExportCSV.Add_Click({
    if ($script:CompareResults -eq $null -or $script:CompareResults.Count -eq 0) {
        [System.Windows.Forms.MessageBox]::Show(
            "No results to export. Please run a scan first.",
            "No Results",
            "OK",
            "Warning"
        )
        return
    }
    Export-Results -Results $script:CompareResults -Format "CSV"
})

$btnExportTXT.Add_Click({
    if ($script:CompareResults -eq $null -or $script:CompareResults.Count -eq 0) {
        [System.Windows.Forms.MessageBox]::Show(
            "No results to export. Please run a scan first.",
            "No Results",
            "OK",
            "Warning"
        )
        return
    }
    Export-Results -Results $script:CompareResults -Format "TXT"
})

$btnExportJSON.Add_Click({
    if ($script:CompareResults -eq $null -or $script:CompareResults.Count -eq 0) {
        [System.Windows.Forms.MessageBox]::Show(
            "No results to export. Please run a scan first.",
            "No Results",
            "OK",
            "Warning"
        )
        return
    }
    Export-Results -Results $script:CompareResults -Format "JSON"
})

$btnExportHTML.Add_Click({
    if ($script:CompareResults -eq $null -or $script:CompareResults.Count -eq 0) {
        [System.Windows.Forms.MessageBox]::Show(
            "No results to export. Please run a scan first.",
            "No Results",
            "OK",
            "Warning"
        )
        return
    }
    Export-Results -Results $script:CompareResults -Format "HTML"
})

$btnClear.Add_Click({
    $script:CompareResults = $null
    $script:dataGridView.Rows.Clear()
    $script:lblResultCount.Text = "Ready"
    $script:lblStats.Text = ""
    $btnSync.Enabled = $false
    $btnExportCSV.Enabled = $false
    $btnExportTXT.Enabled = $false
    $btnExportJSON.Enabled = $false
    $btnExportHTML.Enabled = $false
    Reset-Progress
})
#endregion

#region Application Entry Point
$form.Add_Load({
    $form.Text = "FolderSync Alphascript"
    $script:lblResultCount.Text = "Ready - Type paths or click Browse, then Scan"
})

# Set up keyboard shortcuts
$form.KeyPreview = $true
$form.Add_KeyDown({
    if ($_.Control -and $_.KeyCode -eq "S") {
        $btnScan.PerformClick()
    }
    if ($_.Control -and $_.KeyCode -eq "E") {
        $btnExportCSV.PerformClick()
    }
    if ($_.Control -and $_.KeyCode -eq "V") {
        # Ctrl+V is already handled by the text boxes naturally
    }
})

# Show the form
[System.Windows.Forms.Application]::EnableVisualStyles()
$form.ShowDialog() | Out-Null
#endregion
