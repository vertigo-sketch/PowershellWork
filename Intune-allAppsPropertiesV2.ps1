
# Enable verbose output
$VerbosePreference = "Continue"

Write-Verbose "Starting Intune App Report generation..."

# Check if Microsoft Graph module is installed; install if missing
if (-not (Get-Module -ListAvailable -Name Microsoft.Graph)) {
    Write-Verbose "Microsoft.Graph module not found. Installing..."
    try {
        Install-Module Microsoft.Graph -Scope CurrentUser -Force
        Write-Verbose "Microsoft.Graph module installed successfully."
    } catch {
        Write-Error "Failed to install Microsoft.Graph module: $_"
        exit
    }
} else {
    Write-Verbose "Microsoft.Graph module already installed."
}

# Import module
Write-Verbose "Importing Microsoft.Graph module..."
Import-Module Microsoft.Graph

# Connect to Microsoft Graph with required scopes
Write-Verbose "Connecting to Microsoft Graph..."
try {
    Connect-MgGraph -Scopes "DeviceManagementApps.Read.All","DeviceManagementApps.ReadWrite.All" -TenantId "<YourTenantID>"
    Write-Verbose "Connected to Microsoft Graph successfully."
} catch {
    Write-Error "Failed to connect to Microsoft Graph: $_"
    exit
}

# Use beta profile for full Intune app details
Write-Verbose "Selecting beta profile for Microsoft Graph..."
Select-MgProfile -Name "beta"

# Retrieve all Intune-managed apps
Write-Verbose "Retrieving all Intune-managed apps..."
try {
    $apps = Get-MgDeviceAppManagementMobileApp -All
    Write-Verbose "Retrieved $($apps.Count) apps."
} catch {
    Write-Error "Failed to retrieve apps: $_"
    exit
}

# Prepare array for app details
$appDetails = @()

# Progress bar for large datasets
$counter = 0
$totalApps = $apps.Count

foreach ($app in $apps) {
    $counter++
    Write-Progress -Activity "Processing apps" -Status "$counter of $totalApps" -PercentComplete (($counter / $totalApps) * 100)
    Write-Verbose "Processing app: $($app.DisplayName) (ID: $($app.Id))"

    $appName = $app.DisplayName
    $appId = $app.Id
    $lastModified = $app.LastModifiedDateTime
    $installCmd = $null
    $uninstallCmd = $null
    $installBehavior = $null
    $detectionRules = ""
    $dependencies = ""

    # If app is Win32 type, capture extra properties safely
    if ($app.'@odata.type' -eq "#microsoft.graph.win32LobApp") {
        Write-Verbose "App is Win32 type. Capturing additional properties..."
        $installCmd = $app.InstallCommandLine
        $uninstallCmd = $app.UninstallCommandLine
        $installBehavior = $app.InstallBehavior
        $detectionRules = if ($app.DetectionRules) { ($app.DetectionRules | ForEach-Object { $_.DisplayName }) -join "; " } else { "" }
        $dependencies = if ($app.DependentAppIds) { ($app.DependentAppIds -join "; ") } else { "" }
    }

    # Get assignments for the app
    Write-Verbose "Retrieving assignments for app: $appName"
    try {
        $assignments = Get-MgDeviceAppManagementMobileAppAssignment -MobileAppId $appId
        if ($assignments.Count -eq 0) {
            Write-Verbose "No assignments found for app: $appName"
        }
    } catch {
        Write-Warning "Failed to retrieve assignments for app: $appName"
        continue
    }

    if ($assignments.Count -eq 0) {
        # Add app even if no assignments
        $appDetails += [PSCustomObject]@{
            AppName          = $appName
            AppId            = $appId
            LastModified     = $lastModified
            AssignmentType   = "None"
            AssignmentStatus = "None"
            InstallCommand   = $installCmd
            UninstallCommand = $uninstallCmd
            InstallBehavior  = $installBehavior
            DetectionRules   = $detectionRules
            Dependencies     = $dependencies
        }
    } else {
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
}

# Dynamic export path in user's profile
$exportPath = Join-Path $env:USERPROFILE "IntuneAppReport.csv"
Write-Verbose "Exporting report to $exportPath..."

try {
    $appDetails | Export-Csv -Path $exportPath -NoTypeInformation
    Write-Host "✅ Report exported successfully to $exportPath"
} catch {
    Write-Error "Failed to export report: $_"
}

Write-Verbose "Script completed."
