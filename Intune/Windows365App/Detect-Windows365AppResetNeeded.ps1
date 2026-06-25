# Detect-Windows365AppResetNeeded.ps1
# Purpose: Detect if any local user profile on the host has Windows 365 app data present.
# Intune rule: Exit 0 => Compliant; Exit 1 => Non-compliant

# Avoid global silence; suppress only where needed
$ErrorActionPreference = 'Stop'

function Get-TargetPackageFolders {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$ProfilePath
    )

    $packagesRoot = Join-Path -Path $ProfilePath -ChildPath "AppData\Local\Packages"

    if (Test-Path -LiteralPath $packagesRoot) {
        try {
            # Filter at the provider for performance and reliability
            Get-ChildItem -LiteralPath $packagesRoot -Directory -Filter 'MicrosoftCorporationII.Windows365_*' -ErrorAction SilentlyContinue
        }
        catch {
            # Return nothing if access denied or other errors
            @()
        }
    }
    else {
        @()
    }
}

# Enumerate user profiles (exclude special/system)
# NOTE: Run as SYSTEM for best results—user context may not access other profiles.
$profiles = @()
try {
    $profiles = Get-CimInstance Win32_UserProfile | Where-Object {
        $_.LocalPath -like 'C:\Users\*' -and -not $_.Special -and (Test-Path -LiteralPath $_.LocalPath)
    }
}
catch {
    # If CIM fails, safest is to mark compliant rather than throw
    exit 0
}

$found = $false

foreach ($p in $profiles) {
    $pkgFolders = Get-TargetPackageFolders -ProfilePath $p.LocalPath
    if (@($pkgFolders).Count -gt 0) {
        $found = $true
        break
    }
}

if ($found) {
    exit 1  # Non-compliant (reset needed)
}
else {
    exit 0  # Compliant
}
