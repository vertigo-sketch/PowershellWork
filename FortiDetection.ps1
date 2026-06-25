# Script to Detect if FortiDLP Agent version 12.1.0 or higher is installed - by RC

function Is-Version-AtLeast {
    param (
        [string]$current,
        [string]$minimum
    )
    return [version]$current -ge [version]$minimum
}

$regPaths = @(
    "HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall",
    "HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall"
)

$found = $false
$detectedVersion = $null

foreach ($regPath in $regPaths) {
    $keys = Get-ChildItem -Path $regPath -ErrorAction SilentlyContinue
    foreach ($key in $keys) {
        $props = Get-ItemProperty -Path $key.PSPath -ErrorAction SilentlyContinue
        if (-not $props) { continue }

        $displayName = $props.DisplayName
        $version = $props.DisplayVersion

        if ($displayName -match "FortiDLP Agent") {
            $detectedVersion = $version
            if (Is-Version-AtLeast $version "12.1.0") {
                Write-Output "✅ FortiDLP Agent version $version is installed and meets the minimum version requirement (12.1.0)"
                $found = $true
                break
            } else {
                Write-Output "⚠️ FortiDLP Agent version $version is installed but is below the required version (12.1.0)"
                $found = $false
                break
            }
        }
    }

    if ($found -or $detectedVersion) { break }
}

if (-not $detectedVersion) {
    Write-Output "❌ FortiDLP Agent is not installed"
    exit 1
}

if ($found) {
    exit 0
} else {
    exit 1
}
