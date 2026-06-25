Get-ChildItem 'HKLM:\SOFTWARE\Microsoft\NET Framework Setup\NDP' -Recurse |
Get-ItemProperty -Name Version -ErrorAction SilentlyContinue |
Where-Object { $_.Version -match '^\d' } |
Select-Object PSChildName, Version