<#
.SYNOPSIS
    Combines all .h and .cpp files in a directory into a single .txt file.
.DESCRIPTION
    Reads all C++ source and header files recursively, preserving exact formatting, 
    spacing, and encoding, and appends them to a single text file.
#>

param(
    [Parameter(Position=0)]
    [string]$SourceFolder
)

# Default target folder
$defaultPath = "ENTER YOUR SOURCE LOCATION HERE"

# Prompt for folder if not provided inline
if ([string]::IsNullOrWhiteSpace($SourceFolder)) {
    $SourceFolder = Read-Host "Enter the target folder path (Press Enter to use default: $defaultPath)"
    if ([string]::IsNullOrWhiteSpace($SourceFolder)) {
        $SourceFolder = $defaultPath
    }
}

# Validate the folder exists
if (-not (Test-Path -Path $SourceFolder -PathType Container)) {
    Write-Error "The folder '$SourceFolder' does not exist. Please check the path and try again."
    exit 1
}

# Define output file path (places it in the root of the target folder)
$outputFileName = "CombinedSourceCode.txt"
$outputPath = Join-Path -Path $SourceFolder -ChildPath $outputFileName

# Get all .h and .cpp files recursively, sorted by path for consistent output
$files = Get-ChildItem -Path $SourceFolder -Include *.h, *.cpp -Recurse -File | Sort-Object FullName

if ($files.Count -eq 0) {
    Write-Warning "No .h or .cpp files found in '$SourceFolder'."
    exit 0
}

Write-Host "Found $($files.Count) source files. Combining into $outputPath ..." -ForegroundColor Cyan

# Initialize/Clear the output file using UTF-8 encoding
[System.IO.File]::WriteAllText($outputPath, "", [System.Text.Encoding]::UTF8)

foreach ($file in $files) {
    # Calculate relative path for a clean header
    $relativePath = $file.FullName.Substring($SourceFolder.Length).TrimStart('\', '/')
    
    # Create a visual separator so you can easily find specific files in the combined text
    $header = "`r`n// =========================================================================`r`n// FILE: $relativePath`r`n// =========================================================================`r`n"
    
    # Read the exact content of the file. 
    # Using .NET IO methods ensures exact preservation of spacing, line endings, and JUCE's UTF-8 encoding.
    $content = [System.IO.File]::ReadAllText($file.FullName, [System.Text.Encoding]::UTF8)
    
    # Append header and content to the output file
    [System.IO.File]::AppendAllText($outputPath, $header + $content, [System.Text.Encoding]::UTF8)
}

Write-Host "Successfully created: $outputPath" -ForegroundColor Green
