# Check each policy's IsEnforced state and return only the enforced policies
(CiTool -lp -json | ConvertFrom-Json).Policies | Where-Object {$_.IsEnforced -eq "True"} |
Select-Object -Property PolicyID,FriendlyName | Format-List