#

Clear-Host

$Hive = Get-ChildItem -Path HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall

$Hive2 = Get-ChildItem -Path HKLM:\SOFTWARE\Wow6432Node\Microsoft\Windows\CurrentVersion\Uninstall

Write-Host -ForegroundColor Green "x64 Registry Hive - HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall "

$Hive | Get-ItemProperty | Select-Object -Property PSChildName, DisplayName, DisplayVersion, UninstallString | Sort-Object DisplayName | Format-Table -AutoSize -Wrap

Write-Host -ForegroundColor Cyan "x86 Registry Hive - HKEY_LOCAL_MACHINE\SOFTWARE\Wow6432Node\Microsoft\Windows\CurrentVersion\Uninstall"

$Hive2 | Get-ItemProperty | Select-Object -Property PSChildName, DisplayName, DisplayVersion, UninstallString | Sort-Object DisplayName | Format-Table -AutoSize -Wrap