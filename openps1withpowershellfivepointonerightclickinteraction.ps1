$pwsh = "$env:WINDIR\System32\WindowsPowerShell\v1.0\powershell.exe"

New-Item -Path 'Registry::HKEY_CLASSES_ROOT\Microsoft.PowerShellScript.1\shell\OpenWithWindowsPowerShell' -Force | Out-Null

Set-ItemProperty `
    -Path 'Registry::HKEY_CLASSES_ROOT\Microsoft.PowerShellScript.1\shell\OpenWithWindowsPowerShell' `
    -Name '(default)' `
    -Value 'Open with Windows PowerShell 5.1'

Set-ItemProperty `
    -Path 'Registry::HKEY_CLASSES_ROOT\Microsoft.PowerShellScript.1\shell\OpenWithWindowsPowerShell' `
    -Name 'Icon' `
    -Value "$pwsh"

New-Item `
    -Path 'Registry::HKEY_CLASSES_ROOT\Microsoft.PowerShellScript.1\shell\OpenWithWindowsPowerShell\command' `
    -Force | Out-Null

Set-ItemProperty `
    -Path 'Registry::HKEY_CLASSES_ROOT\Microsoft.PowerShellScript.1\shell\OpenWithWindowsPowerShell\command' `
    -Name '(default)' `
    -Value "`"$pwsh`" -NoExit -File `"%1`""
