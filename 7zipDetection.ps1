# Script to Detect if 7-Zip 64-bit MSI version 24.09 or higher is installed - by RC

function Is-Version-AtLeast {
    param (
        [string]$current,
        [string]$minimum
    )
    return [version]$current -ge [version]$minimum
}

$regPath = "HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall"
$found = $false

$keys = Get-ChildItem -Path $regPath -ErrorAction SilentlyContinue
foreach ($key in $keys) {
    $props = Get-ItemProperty -Path $key.PSPath -ErrorAction SilentlyContinue
    if (-not $props) { continue }

    $displayName = $props.DisplayName
    $version = $props.DisplayVersion
    $uninstallString = $props.UninstallString

    $isMSI = $key.PSChildName -match "^{.*}$" # GUID = MSI

    if ($displayName -match "7-Zip" -and $isMSI) {
        if (Is-Version-AtLeast $version "24.09") {
            Write-Output "7-Zip 64-bit MSI $version detected (valid)"
            $found = $true
            break
        }
    }
}

if ($found) {
    exit 0  # Detection success
} else {
    exit 1  # Detection fail
}
