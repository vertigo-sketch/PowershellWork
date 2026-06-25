<#
.SYNOPSIS
Creates a detailed Intune Windows app deployment report using Microsoft Graph PowerShell.

.OUTPUTS
Exports CSV to the path stored in $outputPath
#>

# ==============================
# 1. Settings
# ==============================
# Change this path as needed
$outputPath = "C:\Temp\Intune_Windows_App_Deployment_Report.csv"

# Scopes needed for this script
$scopes = @(
    "DeviceManagementApps.Read.All",
    "DeviceManagementManagedDevices.Read.All",
    "Group.Read.All",
    "User.Read.All"
)

# ==============================
# 2. Connect to Microsoft Graph
# ==============================
Write-Host "Connecting to Microsoft Graph..." -ForegroundColor Cyan
Connect-MgGraph -Scopes $scopes
# Intune often has the richest support on beta; switch to v1.0 if your org prefers that
Select-MgProfile -Name "beta"

$ctx = Get-MgContext
Write-Host "Connected as $($ctx.Account) to tenant $($ctx.TenantId)" -ForegroundColor Green

# ==============================
# 3. Get all mobile apps from Intune
# ==============================
Write-Host "Retrieving Intune mobile apps..." -ForegroundColor Cyan
$allApps = Get-MgDeviceAppManagementMobileApp -All

# Helper: resolve app type in a human-readable way
function Get-AppType {
    param($app)

    switch ($app.AdditionalProperties.'@odata.type') {
        "#microsoft.graph.win32LobApp"           { "Win32" }
        "#microsoft.graph.microsoftStoreApp"     { "Microsoft Store" }
        "#microsoft.graph.windowsUniversalAppX"  { "UWP" }
        "#microsoft.graph.windowsMicrosoftEdgeApp" { "Edge" }
        "#microsoft.graph.windowsMobileMSI"      { "Windows MSI" }
        default                                  { $app.AdditionalProperties.'@odata.type' }
    }
}

# Filter to Windows app types only
$windowsApps = $allApps | Where-Object {
    $type = $_.AdditionalProperties.'@odata.type'
    $type -eq "#microsoft.graph.win32LobApp"          -or
    $type -eq "#microsoft.graph.microsoftStoreApp"    -or
    $type -eq "#microsoft.graph.windowsUniversalAppX" -or
    $type -eq "#microsoft.graph.windowsMicrosoftEdgeApp" -or
    $type -eq "#microsoft.graph.windowsMobileMSI"
}

Write-Host "Total apps found: $($allApps.Count). Windows apps filtered: $($windowsApps.Count)." -ForegroundColor Yellow

if (-not $windowsApps -or $windowsApps.Count -eq 0) {
    Write-Host "No Windows apps found in Intune. Exiting." -ForegroundColor Red
    Disconnect-MgGraph
    return
}

# ==============================
# 4. Cache groups & users (for readable targets)
# ==============================
Write-Host "Caching Azure AD groups and users (for readable targets)..." -ForegroundColor Cyan
$groups = Get-MgGroup -All -Property Id, DisplayName
$users  = Get-MgUser  -All -Property Id, UserPrincipalName, DisplayName

# Quick lookup hashes
$groupHash = @{}
foreach ($g in $groups) { $groupHash[$g.Id] = $g.DisplayName }

$userHash = @{}
foreach ($u in $users) { $userHash[$u.Id] = $u }

# ==============================
# 5. (Optional) Cache managed devices for OS details
# ==============================
Write-Host "Retrieving managed devices (for OS info)..." -ForegroundColor Cyan
$managedDevices = Get-MgDeviceManagementManagedDevice -All -Property Id,DeviceName,OperatingSystem,OsVersion,UserId
$deviceHash = @{}
foreach ($d in $managedDevices) { 
    if ($d.DeviceName) {
        $deviceHash[$d.DeviceName] = $d
    }
}

# ==============================
# 6. Prepare results collection
# ==============================
$results = @()

# ==============================
# 7. Iterate Windows apps, get assignments & install status
# ==============================
foreach ($app in $windowsApps) {

    $appName = $app.DisplayName
    $appId   = $app.Id
    $appType = Get-AppType -app $app

    Write-Host "Processing Windows app: $appName ($appType)..." -ForegroundColor Cyan

    # 7a. Get app assignments
    try {
        $assignments = Get-MgDeviceAppManagementMobileAppAssignment -MobileAppId $appId -ErrorAction Stop
    } catch {
        Write-Warning "Failed to get assignments for app $appName : $_"
        continue
    }

    if (-not $assignments) {
        Write-Host "  No assignments found for this app." -ForegroundColor DarkYellow
        continue
    }

    foreach ($assignment in $assignments) {

        # Determine target type & name
        $targetType = $null
        $targetName = $null

        $target = $assignment.Target

        if ($target.'@odata.type') {
            switch ($target.'@odata.type') {
                "#microsoft.graph.groupAssignmentTarget" {
                    $targetType = "Group"
                    $targetName = $groupHash[$target.GroupId]
                    if (-not $targetName) { $targetName = $target.GroupId }
                }
                "#microsoft.graph.allDevicesAssignmentTarget" {
                    $targetType = "All Devices"
                    $targetName = "All Devices"
                }
                "#microsoft.graph.allUsersAssignmentTarget" {
                    $targetType = "All Users"
                    $targetName = "All Users"
                }
                "#microsoft.graph.exclusionGroupAssignmentTarget" {
                    $targetType = "Exclusion Group"
                    $targetName = $groupHash[$target.GroupId]
                    if (-not $targetName) { $targetName = $target.GroupId }
                }
                default {
                    $targetType = $target.'@odata.type'
                    $targetName = "Unknown target"
                }
            }
        }

        # 7b. Get per-device install status for the app
        try {
            $installStatuses = Get-MgDeviceAppManagementMobileAppInstallStatus -MobileAppId $appId -All -ErrorAction Stop
        } catch {
            Write-Warning "  Failed to get install status for app $appName : $_"
            continue
        }

        foreach ($status in $installStatuses) {

            $deviceName = $status.DeviceName
            $userName   = $status.UserName
            $userId     = $status.UserId

            $state      = $status.InstallState        # installed, failed, notInstalled, unknown, etc.
            $errorCode  = $status.ErrorCode
            $lastSync   = $status.LastSyncDateTime

            # Resolve user UPN if possible
            $userPrincipalName = $null
            if ($userId -and $userHash.ContainsKey($userId)) {
                $userPrincipalName = $userHash[$userId].UserPrincipalName
                if (-not $userName) { $userName = $userHash[$userId].DisplayName }
            }

            # Resolve device OS info from cached managed devices
            $osVersion  = $null
            $osPlatform = $null
            if ($deviceName -and $deviceHash.ContainsKey($deviceName)) {
                $osPlatform = $deviceHash[$deviceName].OperatingSystem
                $osVersion  = $deviceHash[$deviceName].OsVersion
            }

            $results += [PSCustomObject]@{
                AppName           = $appName
                AppId             = $appId
                AppType           = $appType
                AssignmentType    = $assignment.Intent        # available, required, uninstall
                TargetType        = $targetType
                TargetName        = $targetName

                DeviceName        = $deviceName
                UserName          = $userName
                UserPrincipalName = $userPrincipalName

                InstallState      = $state
                ErrorCode         = $errorCode
                LastSyncDateTime  = $lastSync

                OSPlatform        = $osPlatform
                OSVersion         = $osVersion
            }
        } # end foreach install status
    } # end foreach assignment
} # end foreach Windows app

# ==============================
# 8. Export to CSV
# ==============================
if ($results.Count -gt 0) {
    Write-Host "Exporting $($results.Count) records to $outputPath..." -ForegroundColor Cyan
    $results |
        Sort-Object AppName, TargetName, DeviceName |
        Export-Csv -Path $outputPath -NoTypeInformation -Encoding UTF8

    Write-Host "Windows app deployment report created: $outputPath" -ForegroundColor Green
} else {
    Write-Host "No results to export. Check if there are Windows apps with assignments and install status." -ForegroundColor Yellow
}

# ==============================
# 9. Disconnect
# ==============================
Disconnect-MgGraph
Write-Host "Disconnected from Microsoft Graph." -ForegroundColor Green