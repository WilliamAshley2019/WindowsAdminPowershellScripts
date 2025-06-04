# Run this as Administrator

function Get-FolderPath {
    param (
        [string]$dialogTitle = "Select a folder"
    )

    # Strategy 1: Try FolderBrowserDialog (.NET)
    try {
        Add-Type -AssemblyName System.Windows.Forms
        $dialog = New-Object System.Windows.Forms.FolderBrowserDialog
        $dialog.Description = $dialogTitle
        $dialog.ShowNewFolderButton = $true
        if ($dialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
            return $dialog.SelectedPath
        }
    } catch {
        Write-Warning "Fallback to Shell.Application picker..."
    }

    # Strategy 2: COM Shell.Application
    try {
        $shell = New-Object -ComObject Shell.Application
        $folder = $shell.BrowseForFolder(0, $dialogTitle, 0, 0)
        if ($folder) {
            return $folder.Self.Path
        }
    } catch {
        Write-Warning "Shell.Application picker failed. Final fallback: manual entry."
    }

    # Strategy 3: Manual path input
    $path = Read-Host "$dialogTitle (manual path entry, use tab-completion if needed)"
    while (-not (Test-Path $path)) {
        $path = Read-Host "Path does not exist. Please try again"
    }
    return $path
}

# Prompt for folders using universal GUI/backup
$source = Get-FolderPath -dialogTitle "Select the SOURCE folder to merge from"
$destination = Get-FolderPath -dialogTitle "Select the DESTINATION folder to merge into"

Write-Host "`nYou selected:" -ForegroundColor Cyan
Write-Host "Source:      $source"
Write-Host "Destination: $destination`n"

# Merge folders logic
function Merge-Folders {
    param (
        [string]$source,
        [string]$destination
    )

    Write-Host "Starting merge from `"$source`" to `"$destination`"" -ForegroundColor Cyan

    if (-Not (Test-Path $source)) {
        Write-Warning "Source folder does not exist: $source"
        return
    }

    if (-Not (Test-Path $destination)) {
        Write-Host "Creating destination folder: $destination"
        New-Item -ItemType Directory -Path $destination -Force | Out-Null
    }

    # Copy files, skipping existing
    Get-ChildItem -Path $source -Recurse -Force | ForEach-Object {
        $relativePath = $_.FullName.Substring($source.Length).TrimStart('\')
        $targetPath = Join-Path $destination $relativePath

        if ($_.PSIsContainer) {
            if (-Not (Test-Path $targetPath)) {
                New-Item -ItemType Directory -Path $targetPath -Force | Out-Null
            }
        } else {
            if (-Not (Test-Path $targetPath)) {
                Copy-Item -Path $_.FullName -Destination $targetPath -Force -ErrorAction SilentlyContinue
                Write-Host "Copied: $relativePath" -ForegroundColor Green
            } else {
                Write-Host "Skipped (already exists): $relativePath" -ForegroundColor Yellow
            }
        }
    }

    # Confirm delete
    $confirmation = Read-Host "`nDo you want to delete the now-empty source folder:`n$source ? (Y/N)"
    if ($confirmation -eq "Y" -or $confirmation -eq "y") {
        try {
            Remove-Item -Path $source -Recurse -Force -ErrorAction Stop
            Write-Host "`nSource folder deleted: $source" -ForegroundColor Red
        } catch {
            Write-Warning "Failed to delete source folder. Error: $_"
        }
    } else {
        Write-Host "Source folder NOT deleted." -ForegroundColor Yellow
    }
}

# Run merge
Merge-Folders -source $source -destination $destination

Write-Host "`n✅ Merge complete." -ForegroundColor Magenta
