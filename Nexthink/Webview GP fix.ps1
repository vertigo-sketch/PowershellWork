# Webview GP Sign in Loop fix
$RegistryPath = "HKLM:\SOFTWARE\WOW6432Node\Microsoft\EdgeUpdate\Clients"
$KeyToDelete = "{F3017226-FE2A-4295-8BDF-00C3A9A7E4C5}"

Write-Host "Starting registry key deletion process..."
Write-Host "Target Path: $RegistryPath\$KeyToDelete"

try {
    # Check if the key exists
    if (Test-Path -Path (Join-Path $RegistryPath $KeyToDelete)) {
        Write-Host "Registry key found. Attempting to delete..."
        
        # Remove the key
        Remove-Item -Path (Join-Path $RegistryPath $KeyToDelete) -Recurse -Force
        
        Write-Host "SUCCESS: Registry key '$KeyToDelete' deleted from '$RegistryPath'."
    } else {
        Write-Host "INFO: Registry key '$KeyToDelete' does not exist at '$RegistryPath'."
    }
} catch {
    Write-Host "ERROR: Failed to delete registry key. Details: $($_.Exception.Message)"
}

Write-Host "Process completed."
