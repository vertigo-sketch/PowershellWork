# Step 1: Kill Acrobat Reader if running
Write-Host "Stopping Acrobat Reader processes..."
Stop-Process -Name "AcroRd32" -Force -ErrorAction SilentlyContinue

# Step 2: Attempt silent uninstall
$productCode = "{AC76BA86-1033-FFFF-7760-BC15014EA700}"
$logPath = "C:\adobeuninstall.log"
Write-Host "Attempting to uninstall Adobe Acrobat Reader..."
Start-Process "msiexec.exe" -ArgumentList "/x $productCode /qn /norestart /l*v $logPath" -Wait

# Step 3: Check if uninstall succeeded
Start-Sleep -Seconds 5
$stillInstalled = Get-WmiObject -Class Win32_Product | Where-Object { $_.IdentifyingNumber -eq $productCode }

if ($stillInstalled) {
    Write-Warning "Uninstall failed."
 
} else {
    Write-Host "Adobe Acrobat Reader successfully uninstalled."
}
