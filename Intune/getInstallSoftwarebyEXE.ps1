$q="`""
 Get-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths\*"  |
 Where-Object {$_."(default)" -ne $null} |
 Select-Object @{ expression={$_.PSChildName}; label='Program'} ,@{ expression={$q + $_."(default)" +$q}; label='CommandLine'}