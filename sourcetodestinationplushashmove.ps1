# --- Configuration ---
$source = Read-Host "Enter the source folder path"
$destination = Read-Host "Enter the destination folder path"
$hashFolder = "C:\DriveHashes"
$outputCsv = Join-Path $hashFolder "$($destination[0])_hashes.csv"

# Ensure folders exist
foreach ($path in @($destination, $hashFolder)) {
    if (!(Test-Path $path)) {
        New-Item -ItemType Directory -Path $path -Force | Out-Null
        Write-Host "Created: $path"
    }
}

# Load previous hashes for resume
$existingHashes = @{}
if (Test-Path $outputCsv) {
    Import-Csv $outputCsv | ForEach-Object {
        $existingHashes[$_.RelativePath] = $_.Hash
    }
    Write-Host "Loaded previous hash index: $($existingHashes.Count) entries"
}

# Gather files to copy (exclude already hashed)
$allFiles = Get-ChildItem -Path $source -Recurse -File
$filesToProcess = $allFiles | Where-Object {
    $rel = $_.FullName.Substring($source.Length).TrimStart('\','/')
    -not $existingHashes.ContainsKey($rel)
}
$total = $filesToProcess.Count

# Collection for new hashes since last write
$newHashesBuffer = @()

# Timestamp to track last write time
$lastWriteTime = Get-Date

# Interval (seconds) between writing hashes to CSV
$writeIntervalSec = 30

# Function to flush new hashes buffer to CSV
function Flush-HashesToCsv {
    param (
        [Parameter(Mandatory)]
        [array]$hashBuffer
    )

    if ($hashBuffer.Count -eq 0) { return }

    if (Test-Path $outputCsv) {
        $hashBuffer | Export-Csv -Append -Path $outputCsv -NoTypeInformation
    } else {
        $hashBuffer | Export-Csv -Path $outputCsv -NoTypeInformation
    }

    $hashBuffer.Clear()
    Write-Host "Flushed hashes to CSV at $(Get-Date -Format 'HH:mm:ss')"
}

# Progress function
function Show-Progress {
    param($current, $total)
    $percent = [math]::Round(($current / $total) * 100, 2)
    Write-Progress -Activity "Moving and hashing files" -Status "$current of $total ($percent%)" -PercentComplete $percent
}

# Processing files sequentially
$counter = 0
foreach ($file in $filesToProcess) {
    $rel = $file.FullName.Substring($source.Length).TrimStart('\','/')
    $dstFile = Join-Path $destination $rel
    $dstDir = Split-Path -Path $dstFile -Parent

    if (!(Test-Path $dstDir)) {
        New-Item -ItemType Directory -Path $dstDir -Force | Out-Null
    }

    try {
        Copy-Item -Path $file.FullName -Destination $dstFile -Force

        $srcSize = (Get-Item $file.FullName).Length
        $dstSize = (Get-Item $dstFile).Length

        if ($srcSize -eq $dstSize) {
            $hash = (Get-FileHash -Path $dstFile -Algorithm SHA256).Hash

            $newHashesBuffer += [PSCustomObject]@{
                RelativePath = $rel
                Size = $dstSize
                Hash = $hash
            }

            Remove-Item -Path $file.FullName -Force
            Write-Host "Moved ${rel}"
        }
        else {
            Write-Host "Copied but size mismatch: ${rel}"
        }

        if ($dstSize -gt 1GB) { Start-Sleep -Seconds 3 } else { Start-Sleep -Milliseconds 250 }
    }
    catch {
        Write-Host "Error copying ${rel}: $_"
    }

    $counter++
    Show-Progress -current $counter -total $total

    # Check if it's time to flush hashes to CSV
    $now = Get-Date
    if (($now - $lastWriteTime).TotalSeconds -ge $writeIntervalSec) {
        Flush-HashesToCsv -hashBuffer $newHashesBuffer
        $lastWriteTime = $now
    }
}

# Final flush of any remaining hashes
Flush-HashesToCsv -hashBuffer $newHashesBuffer

Write-Host "`n✅ File move and hash operation complete!"
