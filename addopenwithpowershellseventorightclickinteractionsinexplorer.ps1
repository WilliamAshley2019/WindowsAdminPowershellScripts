$pwsh = (Get-Command pwsh.exe).Source

New-Item -Path 'Registry::HKEY_CLASSES_ROOT\Microsoft.PowerShellScript.1\shell\OpenWithPowerShell7' -Force | Out-Null

Set-ItemProperty `
    -Path 'Registry::HKEY_CLASSES_ROOT\Microsoft.PowerShellScript.1\shell\OpenWithPowerShell7' `
    -Name '(default)' `
    -Value 'Open with PowerShell 7'

Set-ItemProperty `
    -Path 'Registry::HKEY_CLASSES_ROOT\Microsoft.PowerShellScript.1\shell\OpenWithPowerShell7' `
    -Name 'Icon' `
    -Value "$pwsh"

New-Item `
    -Path 'Registry::HKEY_CLASSES_ROOT\Microsoft.PowerShellScript.1\shell\OpenWithPowerShell7\command' `
    -Force | Out-Null

Set-ItemProperty `
    -Path 'Registry::HKEY_CLASSES_ROOT\Microsoft.PowerShellScript.1\shell\OpenWithPowerShell7\command' `
    -Name '(default)' `
    -Value "`"$pwsh`" -NoExit -File `"%1`""
