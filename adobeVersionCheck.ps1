# Define the path to the executable
$acrobatPath = "C:\Program Files\Adobe\Acrobat DC\Acrobat\Acrobat.exe"

# Define the target version to compare against
$targetVersion = [version]"25.001.20577"

# Check if the file exists
if (Test-Path $acrobatPath) {
    # Get the file version info
    $fileVersionInfo = [System.Diagnostics.FileVersionInfo]::GetVersionInfo($acrobatPath)
    $currentVersion = [version]$fileVersionInfo.FileVersion

    # Compare versions
    if ($currentVersion -gt $targetVersion) {
        Write-Output "Adobe Acrobat has been updated. Current version: $currentVersion"
    } else {
        Write-Output "Adobe Acrobat is not updated past $targetVersion. Current version: $currentVersion"
    }
} else {
    Write-Output "Acrobat.exe not found at the specified path."
}

