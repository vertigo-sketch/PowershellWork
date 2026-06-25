$start = Get-Date -Date '4/1/2025 08:00:00'$end   = Get-Date -Date '4/2/2025 1:00:00'
$filter = @{    LogName   = 'Application'    Level     = 1, 2, 3, 4  # Warning and Error    StartTime = $start    EndTime   = $end}
$events = Get-WinEvent -FilterHashtable $filter
# Below to export it to a CSV$events | Export-Csv -Path 'C:\temp\eventviewer.csv' -NoTypeInformation


