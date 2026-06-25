$vendors = (Select-String -Path C:\NOC\VendorStatusMonitor.ps1 -Pattern '^\s*@\{' -AllMatches) | Out-Null
. C:\NOC\VendorStatusMonitor.ps1  # dot-source to load $Vendors if your script doesn't auto-run (see note below)
$automox = $Vendors | Where-Object { $_.Name -eq 'Automox' } | Select-Object -First 1
$automox.Url
$automox.Url.ToCharArray() | ForEach-Object { '{0} 0x{1:X2}' -f $_, [int][char]$_ }