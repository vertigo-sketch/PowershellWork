# Run the command to get the list of installed software
$software = Get-WmiObject -Class Win32_Product | Sort-Object -Property Name

# Extract software details and print them in a formatted table
$software | Format-Table IdentifyingNumber, Name, Version, Vendor, InstallDate, InstallLocation, PackageCache -AutoSize | Out-GridView
