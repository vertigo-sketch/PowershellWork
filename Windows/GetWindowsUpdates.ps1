# Get a list of installed Windows updates
Get-HotFix |
Select-Object HotFixID, Description, InstalledOn, InstalledBy |
Out-GridView -Title "Installed Windows Updates"