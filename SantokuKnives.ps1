Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# === ANIME THEME COLORS & SYMBOLS (Cyber/Neon Aesthetic) === #
$theme = @{
    Background  = [System.Drawing.Color]::FromArgb(20, 20, 30)   # Dark Night Sky/Cyber Black
    Foreground  = [System.Drawing.Color]::FromArgb(230, 230, 255) # White Text
    AccentNeon  = [System.Drawing.Color]::FromArgb(0, 255, 255)  # Cyan Neon/Hacker Blue
    AccentPink  = [System.Drawing.Color]::FromArgb(255, 50, 150) # Magenta/Pink Glow
    AccentRed   = [System.Drawing.Color]::FromArgb(255, 100, 100) # Warning Red
    Font        = New-Object System.Drawing.Font("Consolas", 9)
    FontBold    = New-Object System.Drawing.Font("Consolas", 10, [System.Drawing.FontStyle]::Bold)
}

# Define standard measurements
$ButtonWidth = 150
$PaddingLeft = 20

# 🚩 FIX: Adjusted vertical offsets to account for two filter rows
$InputPanelHeight = 170 # Increased panel height to accommodate two rows of controls
$ButtonTopOffset = 38  # Y-position for Browse button (Row 1)
$ButtonBottomOffset = 120 # New Y-position for Slice button (Row 3)
$FilterPanelY = 75     # Y-position for filter panel (Row 2 Start)

# === CREATE FORM === #
$form = New-Object System.Windows.Forms.Form
$form.Text = "💻 斬る File Slicer 💻 v7"
$form.Size = New-Object System.Drawing.Size(900, 650)
$form.StartPosition = "CenterScreen"
$form.BackColor = $theme.Background
$form.ForeColor = $theme.Foreground
$form.Font = $theme.Font
$form.MinimumSize = New-Object System.Drawing.Size(900, 650)

# ===================================================================
# === LAYOUT PANELS ===
# ===================================================================

# 1. Input Panel (Top)
$inputPanel = New-Object System.Windows.Forms.Panel
$inputPanel.Dock = 'Top'
$inputPanel.Height = $InputPanelHeight # <-- Updated Height
$inputPanel.BackColor = $theme.Background

# 2. Status Panel (Bottom)
$statusPanel = New-Object System.Windows.Forms.Panel
$statusPanel.Dock = 'Bottom'
$statusPanel.Height = 30
$statusPanel.BackColor = $theme.Background

# 3. Results Box (Fills the middle)
$txtResults = New-Object System.Windows.Forms.RichTextBox
$txtResults.Text = "▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀"
$txtResults.Dock = 'Fill' 
$txtResults.ReadOnly = $true
$txtResults.BackColor = [System.Drawing.Color]::FromArgb(40, 40, 50)
$txtResults.ForeColor = $theme.Foreground
$txtResults.Font = $theme.Font
$txtResults.WordWrap = $false
$txtResults.BorderStyle = 'FixedSingle'

# 4. Status Box (Inside the Status Panel)
$txtStatus = New-Object System.Windows.Forms.TextBox
$txtStatus.Dock = 'Fill' 
$txtStatus.ReadOnly = $true
$txtStatus.BackColor = $theme.Background
$txtStatus.ForeColor = $theme.AccentNeon
$txtStatus.Font = $theme.Font
$txtStatus.BorderStyle = 'None'
$txtStatus.Text = "準備完了... 🍣"
$statusPanel.Controls.Add($txtStatus)

# ===================================================================
# === INPUT CONTROLS (Row 1: Path) ===
# ===================================================================

# --- Browse Button ---
$btnBrowse = New-Object System.Windows.Forms.Button
$btnBrowse.Text = "参照..."
$btnBrowse.Size = New-Object System.Drawing.Size($ButtonWidth, 29)
$btnBrowse.FlatStyle = 'Flat'
$btnBrowse.BackColor = $theme.AccentPink
$btnBrowse.ForeColor = $theme.Background
$btnBrowse.Anchor = 'Top, Right'
$inputPanel.Controls.Add($btnBrowse)

# --- Path Label ---
$lblPath = New-Object System.Windows.Forms.Label
$lblPath.Text = "対象フォルダ (Target):"
$lblPath.Location = New-Object System.Drawing.Point($PaddingLeft, 15)
$lblPath.AutoSize = $true
$lblPath.ForeColor = $theme.AccentNeon
$inputPanel.Controls.Add($lblPath)

# --- Path Textbox ---
$txtPath = New-Object System.Windows.Forms.TextBox
$txtPath.Width = 500 
$txtPath.Location = New-Object System.Drawing.Point($PaddingLeft, 40)
$txtPath.BorderStyle = 'FixedSingle'
$txtPath.BackColor = $theme.Background
$txtPath.ForeColor = $theme.AccentNeon
$txtPath.Anchor = 'Top, Left, Right'
$inputPanel.Controls.Add($txtPath)

# ===================================================================
# === INPUT CONTROLS (Row 2 & 3: Filters and Search Button) ===
# ===================================================================

# --- Search Button (Now aligned with the bottom of the filter panel) ---
$btnSearch = New-Object System.Windows.Forms.Button
$btnSearch.Text = "切断 ❖"
$btnSearch.Size = New-Object System.Drawing.Size($ButtonWidth, 29)
$btnSearch.BackColor = $theme.AccentNeon
$btnSearch.ForeColor = $theme.Background
$btnSearch.FlatStyle = 'Flat'
$btnSearch.Font = $theme.FontBold
$btnSearch.Anchor = 'Top, Right'
$inputPanel.Controls.Add($btnSearch)

# --- Filters (FlowLayoutPanel) ---
$filterPanel = New-Object System.Windows.Forms.FlowLayoutPanel
$filterPanel.Location = New-Object System.Drawing.Point($PaddingLeft, $FilterPanelY)
$filterPanel.Height = 80 # Doubled height to allow two rows of filters before the button
$filterPanel.FlowDirection = 'LeftToRight'
$filterPanel.WrapContents = $true # Allow wrapping onto the second line
$filterPanel.Anchor = 'Top, Left, Right' 
$inputPanel.Controls.Add($filterPanel)

# Define margins for spacing
$labelMargin = New-Object System.Windows.Forms.Padding(0, 8, 3, 0)
$boxMargin = New-Object System.Windows.Forms.Padding(0, 5, 10, 0)

# --- Min Size ---
$lblSizeMin = New-Object System.Windows.Forms.Label
$lblSizeMin.Text = "最小サイズ (Min MB):"
$lblSizeMin.AutoSize = $true
$lblSizeMin.ForeColor = $theme.AccentPink
$lblSizeMin.Margin = $labelMargin 
$filterPanel.Controls.Add($lblSizeMin) 

$txtSizeMin = New-Object System.Windows.Forms.TextBox
$txtSizeMin.Size = New-Object System.Drawing.Size(80, 25)
$txtSizeMin.BorderStyle = 'FixedSingle'
$txtSizeMin.Margin = $boxMargin 
$txtSizeMin.BackColor = $theme.Background
$txtSizeMin.ForeColor = $theme.AccentPink
$filterPanel.Controls.Add($txtSizeMin) 

# --- Max Size ---
$lblSizeMax = New-Object System.Windows.Forms.Label
$lblSizeMax.Text = "最大サイズ (Max MB):"
$lblSizeMax.AutoSize = $true
$lblSizeMax.ForeColor = $theme.AccentPink
$lblSizeMax.Margin = $labelMargin 
$filterPanel.Controls.Add($lblSizeMax) 

$txtSizeMax = New-Object System.Windows.Forms.TextBox
$txtSizeMax.Size = New-Object System.Drawing.Size(80, 25)
$txtSizeMax.BorderStyle = 'FixedSingle'
$txtSizeMax.Margin = $boxMargin 
$txtSizeMax.BackColor = $theme.Background
$txtSizeMax.ForeColor = $theme.AccentPink
$filterPanel.Controls.Add($txtSizeMax) 

# --- Date Checkbox ---
$chkEnableDate = New-Object System.Windows.Forms.CheckBox
$chkEnableDate.Text = "日付フィルタ (Date Filter):"
$chkEnableDate.AutoSize = $true
$chkEnableDate.ForeColor = $theme.AccentNeon
$chkEnableDate.Margin = $labelMargin
$filterPanel.Controls.Add($chkEnableDate)

# --- Date Time Picker (Calendar) ---
$dtpDate = New-Object System.Windows.Forms.DateTimePicker
$dtpDate.Format = [System.Windows.Forms.DateTimePickerFormat]::Custom
$dtpDate.CustomFormat = 'yyyy-MM-dd'
$dtpDate.Size = New-Object System.Drawing.Size(120, 25)
$dtpDate.Margin = $boxMargin
$dtpDate.Enabled = $false
$dtpDate.CalendarForeColor = $theme.AccentRed
$dtpDate.CalendarTitleBackColor = $theme.Background
$dtpDate.CalendarTitleForeColor = $theme.AccentNeon
$dtpDate.BackColor = $theme.Background
$dtpDate.ForeColor = $theme.AccentNeon
$filterPanel.Controls.Add($dtpDate)

# --- Event to enable/disable calendar ---
$chkEnableDate.Add_Click({
    $dtpDate.Enabled = $chkEnableDate.Checked
})

# ===================================================================
# === ADD PANELS AND RESULTS TO FORM ===
# ===================================================================
$form.Controls.Add($txtResults)
$form.Controls.Add($inputPanel)
$form.Controls.Add($statusPanel)

# ===================================================================
# === FORM LOAD EVENT HANDLER (The layout fix) ===
# ===================================================================

$form.Add_Load({
    # Calculate the X-coordinate for the right-aligned buttons
    $RightX = $form.Width - $ButtonWidth - $PaddingLeft - 15

    # 1. Position the Browse Button (Stays in Row 1)
    $btnBrowse.Location = New-Object System.Drawing.Point($RightX, $ButtonTopOffset)

    # 2. Position the Search Button (Now in Row 3, below the filters)
    $btnSearch.Location = New-Object System.Drawing.Point($RightX, $ButtonBottomOffset)

    # 3. Set the initial width of the Path box
    $txtPath.Width = $btnBrowse.Left - $PaddingLeft - $PaddingLeft

    # 4. Set the initial width of the Filter Panel
    # The filter panel now has room below it for the Slice button
    $filterPanel.Width = $btnSearch.Left - $PaddingLeft
})

# ===================================================================
# === EVENT HANDLERS (SEARCH LOGIC - Unchanged) ===
# ===================================================================

# === FOLDER BROWSER === #
$btnBrowse.Add_Click({
    $dialog = New-Object System.Windows.Forms.FolderBrowserDialog
    $dialog.Description = "Select the folder to slice..."
    if ($dialog.ShowDialog() -eq "OK") {
        $txtPath.Text = $dialog.SelectedPath
    }
})

# === SEARCH BUTTON CLICK EVENT === #
$btnSearch.Add_Click({
    $txtResults.Clear()
    $txtStatus.Text = "プロセス開始... (Starting search...)"
    $form.Refresh()

    $path = $txtPath.Text.Trim()
    $minSize = $txtSizeMin.Text.Trim()
    $maxSize = $txtSizeMax.Text.Trim()
    
    if (-not (Test-Path $path)) {
        [System.Windows.Forms.MessageBox]::Show("対象パスが無効です。", "Error: Invalid Path")
        $txtStatus.Text = "準備完了... 🍣"
        return
    }

    $txtStatus.Text = "切断中 $path ..."
    $form.Refresh()

    $files = Get-ChildItem -Path $path -Recurse -ErrorAction SilentlyContinue -File

    $minSizeBytes = 0
    $maxSizeBytes = [int64]::MaxValue
    
    $dateParsed = $null
    if ($chkEnableDate.Checked) {
        $dateParsed = $dtpDate.Value.Date 
    }

    if ($minSize -match '^\d+(\.\d+)?$') {
        $minSizeBytes = [int64]([double]$minSize * 1MB)
    }
    if ($maxSize -match '^\d+(\.\d+)?$') {
        $maxSizeBytes = [int64]([double]$maxSize * 1MB)
    }

    $count = 0
    $matchCount = 0
    $total = $files.Count
    
    # Write the stylish separator before results
    $txtResults.SelectionColor = $theme.AccentNeon
    $txtResults.AppendText("======================================================================================`r`n")
    $txtResults.SelectionColor = $theme.AccentNeon
    $txtResults.AppendText("ファイル名 (File Name) | サイズ (Size) | 最終更新 (Modified)`r`n")
    $txtResults.SelectionColor = $theme.AccentNeon
    $txtResults.AppendText("======================================================================================`r`n")
    $txtResults.DeselectAll()
    
    foreach ($file in $files) {
        $count++
        if ($count % 100 -eq 0) { 
            $txtStatus.Text = "スキャン中 $count / $total ... (Scanning)"
            $form.Refresh()
        }

        # Apply filters
        if ($file.Length -lt $minSizeBytes) { continue }
        if ($file.Length -gt $maxSizeBytes) { continue }
        if ($dateParsed -ne $null -and $file.LastWriteTime -lt $dateParsed) { continue }

        $matchCount++
        $sizeMB = [math]::Round($file.Length / 1MB, 2)
        
        # === Themed Color Logic ===
        $color = $theme.AccentNeon
        if ($sizeMB -ge 1024) { $color = $theme.AccentRed } 
        elseif ($sizeMB -ge 500) { $color = $theme.AccentPink } 

        # === Write nicely formatted output === #
        $dateString = $file.LastWriteTime.ToString("yyyy/MM/dd HH:mm")
        $line = "{0,10:N2} MB | {1,-20} | {2}`r`n" -f $sizeMB, $dateString, $file.FullName
        $start = $txtResults.TextLength
        $txtResults.AppendText($line)
        $end = $txtResults.TextLength
        
        # Apply color to the Size and Date parts only
        $txtResults.Select($start, 29)
        $txtResults.SelectionColor = $color 
        
        $txtResults.Select($start + 32, $end - ($start + 32))
        $txtResults.SelectionColor = $theme.Foreground
        
        $txtResults.DeselectAll()
    }

    $txtStatus.Text = "検索完了。$matchCount 件のファイルが見つかりました。🍱"
    if ($matchCount -eq 0) {
        $txtResults.SelectionColor = $theme.AccentPink
        $txtResults.AppendText("⚪ 該当するファイルはありません。`r`n")
    }
})

# === SHOW FORM === #
$form.Add_Shown({ $form.Activate() }) 
[void]$form.ShowDialog()
