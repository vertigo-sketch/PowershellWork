
Connect-MSGraph

$importCSVPath = $args[0]
$exportCSVPath = $args[1]
$report = @()

try {
    Write-Host "** Converting Intune Device IDs to Azure AD Device IDs **`n" -ForegroundColor Yellow
    $intuneDeviceList = Import-Csv -Path $importCSVPath

    foreach ($device in $intuneDeviceList) {
        $intuneDeviceObj = Get-MgDeviceManagementManagedDevice -managedDeviceId $device.IntuneDeviceID
        Write-Host "Converted $($device.IntuneDeviceID) to $($intuneDeviceObj.azureADDeviceId)"

        $aadDeviceObject = Get-AzureADDevice -Filter "DeviceId eq guid'$($intuneDeviceObj.azureADDeviceId)'"

        $reportItem = [PSCustomObject]@{
            IntuneDeviceId = $device.IntuneDeviceID
            AzureADDeviceId = if ($null -eq $intuneDeviceObj -or $null -eq $intuneDeviceObj.azureADDeviceId) { "Intune device not found" } else { $intuneDeviceObj.azureADDeviceId }
            AzureADObjectId = if ($null -eq $aadDeviceObject -or $null -eq $aadDeviceObject.ObjectId -or $aadDeviceObject.ObjectId -eq "") { "AAD Device not found" } else { $aadDeviceObject.ObjectId }
        }
        $report += $reportItem
        Write-Host "Adding to report: $($reportItem | ConvertTo-Json -Depth 1)" -ForegroundColor Yellow
    }

    $report | Export-Csv -Path $exportCSVPath
    Write-Host "Successfully Converted AAD Device IDs and exported to $exportCSVPath`n" -ForegroundColor DarkGreen
}
catch {
    Write-Host -Message $_
}