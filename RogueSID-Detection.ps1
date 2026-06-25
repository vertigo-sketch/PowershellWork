# Script to detect SID S-1-15-2-3369430996-2513662863-3899666564-3660743878-3172642495-3364753512-1137801083 on systems - by RC

# Base path
$BasePath = "C:\"

# SID string
$SidToCheck = "S-1-15-2-3369430996-2513662863-3899666564-3660743878-3172642495-3364753512-1137801083"

# Convert to SecurityIdentifier object
$SidObject = New-Object System.Security.Principal.SecurityIdentifier($SidToCheck)

function Test-FolderForSID {
    param (
        [string]$Path,
        [string]$Sid
    )
    try {
        $Acl = Get-Acl -Path $Path
        foreach ($Rule in $Acl.Access) {
            $RuleSid = try {
                $Rule.IdentityReference.Translate([System.Security.Principal.SecurityIdentifier])
            } catch { $null }

            if ($RuleSid -and $RuleSid.Value -eq $Sid) {
                return $true
            }
        }
    } catch {
        Write-Warning "Skipping: $Path - Access Denied or Error"
    }
    return $false
}

$Results = @()
$RootMatches = @()

# ---------------------------
# Phase 1: Check C:\ only (no recursion)
# ---------------------------
if (Test-FolderForSID -Path $BasePath -Sid $SidToCheck) {
    $Obj = [PSCustomObject]@{ Folder = $BasePath; SID = $SidToCheck }
    $Results += $Obj
    $Obj | Format-Table -AutoSize
}

# ---------------------------
# Phase 2: Check each top-level folder, recurse only if match
# ---------------------------
$TopLevelFolders = Get-ChildItem -Path $BasePath -Directory -Force -ErrorAction SilentlyContinue

for ($i = 0; $i -lt $TopLevelFolders.Count; $i++) {
    $Folder = $TopLevelFolders[$i].FullName
    Write-Progress -Activity "Checking top-level folders" -Status $Folder -PercentComplete (($i / $TopLevelFolders.Count) * 100)

    if (Test-FolderForSID -Path $Folder -Sid $SidToCheck) {
        $Obj = [PSCustomObject]@{ Folder = $Folder; SID = $SidToCheck }
        $Results += $Obj
        $Obj | Format-Table -AutoSize

        # Now recurse into subfolders of this top-level folder
        $SubFolders = Get-ChildItem -Path $Folder -Directory -Recurse -Force -ErrorAction SilentlyContinue
        $j = 0
        foreach ($Sub in $SubFolders) {
            $j++
            if ($j % 50 -eq 0) {
                Write-Progress -Activity "Scanning subfolders of $Folder" -Status $Sub.FullName -PercentComplete (($j / $SubFolders.Count) * 100)
            }
            if (Test-FolderForSID -Path $Sub.FullName -Sid $SidToCheck) {
                $Obj = [PSCustomObject]@{ Folder = $Sub.FullName; SID = $SidToCheck }
                $Results += $Obj
                $Obj | Format-Table -AutoSize
            }
        }
        Write-Progress -Activity "Scanning subfolders of $Folder" -Completed
    }
}

Write-Progress -Activity "Checking top-level folders" -Completed

# ---------------------------
# Final deduplicated summary
# ---------------------------
if ($Results.Count -gt 0) {
    $Results | Sort-Object Folder -Unique | Format-Table -AutoSize
}
else {
    Write-Output "No folders were found with SID $SidToCheck"
}
