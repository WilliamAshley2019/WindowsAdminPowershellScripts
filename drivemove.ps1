$Source = "E:\"
$Destination = "G:\"

# Set this manually from Drive Properties → E:\ → General → "Contains: X files"
$totalFiles = 1854327   # <-- put your real number here

# Create log file
$Log = "C:\move_e_to_g.log"
"Starting move operation $(Get-Date)" | Out-File -FilePath $Log

$processed = 0

# Stream file enumeration (FAST, no preloading)
Get-ChildItem -Path $Source -Recurse -File | ForEach-Object {
    $file = $_
    $processed++

    $relativePath = $file.FullName.Substring($Source.Length)
    $destFile = Join-Path $Destination $relativePath

    # Update progress countdown
    $remaining = $totalFiles - $processed
    $percent = [math]::Round(($processed / $totalFiles) * 100, 2)

    Write-Progress -Activity "Moving Files E: → G:" `
                   -Status "Current file: $relativePath  |  Remaining: $remaining" `
                   -PercentComplete $percent

    # Ensure destination folder exists
    $destFolder = Split-Path $destFile
    if (!(Test-Path $destFolder)) {
        New-Item -ItemType Directory -Force -Path $destFolder | Out-Null
    }

    # If destination file does NOT exist — move it
    if (!(Test-Path $destFile)) {
        Move-Item -Path $file.FullName -Destination $destFile
        "Moved: $relativePath" | Out-File -Append -FilePath $Log
        return
    }

    # Compare metadata for identical matches
    $srcInfo = Get-Item $file.FullName
    $destInfo = Get-Item $destFile

    $sameSize = ($srcInfo.Length -eq $destInfo.Length)
    $sameDate = ($srcInfo.LastWriteTime -eq $destInfo.LastWriteTime)

    if ($sameSize -and $sameDate) {
        # Replace because files are identical
        Move-Item -Force -Path $file.FullName -Destination $destFile
        "Replaced (identical metadata): $relativePath" | Out-File -Append -FilePath $Log
    }
    else {
        # Skip because mismatch
        "Skipped (different size/date): $relativePath" | Out-File -Append -FilePath $Log
    }
}

Write-Progress -Activity "Moving Files E: → G:" -Completed -Status "Done"
"Completed move operation $(Get-Date)" | Out-File -Append -FilePath $Log
