
# Install Microsoft Graph module if not already installed
Install-Module Microsoft.Graph -Scope CurrentUser -Force

# Import module
Import-Module Microsoft.Graph

# Connect to Microsoft Graph with required scopes
Connect-MgGraph -Scopes "DeviceManagementApps.Read.All","DeviceManagementApps.ReadWrite.All"

# Use beta profile for full Intune app details
Select-MgProfile -Name "beta"

# Retrieve all Intune-managed apps
$apps = Get-MgDeviceAppManagementMobileApp -All

# Prepare array for app details
$appDetails = @()

foreach ($app in $apps) {
    $appName = $app.DisplayName
    $appId = $app.Id
    $lastModified = $app.LastModifiedDateTime
    $installCmd = $null
    $uninstallCmd = $null
    $installBehavior = $null
    $detectionRules = @()
    $dependencies = @()

    # If app is Win32 type, capture extra properties
    if ($app.'@odata.type' -eq "#microsoft.graph.win32LobApp") {
        $installCmd = $app.InstallCommandLine
        $uninstallCmd = $app.UninstallCommandLine
        $installBehavior = $app.InstallBehavior
        $detectionRules = ($app.DetectionRules | ForEach-Object { $_.DisplayName }) -join "; "
        $dependencies = ($app.DependentAppIds -join "; ")
    }

    # Get assignments for the app
    $assignments = Get-MgDeviceAppManagementMobileAppAssignment -MobileAppId $appId
    foreach ($assignment in $assignments) {
        $appDetails += [PSCustomObject]@{
            AppName          = $appName
            AppId            = $appId
            LastModified     = $lastModified
            AssignmentType   = $assignment.Intent
            AssignmentStatus = $assignment.Target.'@odata.type'
            InstallCommand   = $installCmd
            UninstallCommand = $uninstallCmd
            InstallBehavior  = $installBehavior
            DetectionRules   = $detectionRules
            Dependencies     = $dependencies
        }
    }
}

# Export to CSV
$exportPath = "C:\IntuneAppReport.csv"
$appDetails | Export-Csv -Path $exportPath -NoTypeInformation

Write-Host "✅ Report exported to $exportPath"
