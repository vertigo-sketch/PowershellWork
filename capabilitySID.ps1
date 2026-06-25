# PowerShell Script to Identify a Capability SID
$targetSid = "S-1-15-2-3369430996-2513662863-3899666564-3660743878-3172642495-3364753512-1137801083"
$capabilityPath = "HKLM:\SOFTWARE\Microsoft\SecurityManager\CapabilityClasses\AllCachedCapabilities"

# Get all capability entries
$capabilities = Get-ChildItem -Path $capabilityPath

# Search for the SID
foreach ($cap in $capabilities) {
    $sid = (Get-ItemProperty -Path $cap.PSPath).SID
    if ($sid -eq $targetSid) {
        Write-Host "Found matching capability:"
        Write-Host "Registry Key: $($cap.Name)"
        Write-Host "SID: $sid"
        break
    }
}

# If not found
if (-not ($capabilities | Where-Object { (Get-ItemProperty -Path $_.PSPath).SID -eq $targetSid })) {
    Write-Host "Capability SID not found in registry."
}
