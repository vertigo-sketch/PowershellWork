# Install Microsoft Graph module if needed
Install-Module Microsoft.Graph -Scope CurrentUser -Force -AllowClobber

# Connect to Microsoft Graph
Connect-MgGraph -Scopes "DeviceManagementApps.Read.All", "DeviceManagementApps.ReadWrite.All"

# Get access token
$token = (Get-MgContext).AccessToken
$headers = @{
    Authorization = "Bearer $token"
    "Content-Type" = "application/json"
}

# Get top 10 Windows apps
$windowsApps = Get-MgDeviceAppManagementMobileApp |
    Where-Object { $_.'@odata.type' -match 'win32|windowsStore|lineOfBusiness' } |
    Select-Object -First 10

# Prepare results array
$results = @()

foreach ($app in $windowsApps) {
    $appId = $app.Id
    $appName = $app.DisplayName
    Write-Host "Processing: $appName"

    # --- User Install Status ---
    $userUrl = "https://graph.microsoft.com/beta/deviceAppManagement/mobileApps/$appId/userStatuses"
    $userResponse = Invoke-RestMethod -Uri $userUrl -Headers $headers -Method Get

    foreach ($user in $userResponse.value) {
        $results += [PSCustomObject]@{
            AppName         = $appName
            EntityType      = "User"
            EntityName      = $user.UserName
            InstallStatus   = $user.Status
            LastSync        = $user.LastReportedDateTime
        }
    }

    # --- Device Install Status ---
    $deviceUrl = "https://graph.microsoft.com/beta/deviceAppManagement/mobileApps/$appId/deviceStatuses"
    $deviceResponse = Invoke-RestMethod -Uri $deviceUrl -Headers $headers -Method Get

    foreach ($device in $deviceResponse.value) {
        $results += [PSCustomObject]@{
            AppName         = $appName
            EntityType      = "Device"
            EntityName      = $device.DeviceName
            InstallStatus   = $device.Status
            LastSync        = $device.LastReportedDateTime
        }
    }
}

# Export to CSV
$results | Export-Csv -Path ".\WindowsAppDeploymentStatus.csv" -NoTypeInformation

Write-Host "✅ Export complete: WindowsAppDeploymentStatus.csv"

