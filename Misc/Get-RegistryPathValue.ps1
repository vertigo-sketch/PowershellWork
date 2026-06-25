<#
.SYNOPSIS
    Returns all values from a specific registry key.

.PARAMETER KeyPath
    Full registry path, e.g. HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion

.EXAMPLE
    .\Get-RegistryKeyValue.ps1 -KeyPath "HKLM:\Software\MyApp"
#>

param(
    [Parameter(Mandatory = $true)]
    [string]$KeyPath
)

try {
    # Attempt to retrieve registry values
    $item = Get-ItemProperty -Path $KeyPath -ErrorAction Stop

    # Output all non-PowerShell metadata properties
    $item.PSObject.Properties |
        Where-Object { $_.Name -notmatch "^PS" } |
        Select-Object Name, Value
}
catch {
    Write-Error "Failed to read registry key '$KeyPath'. $($_.Exception.Message)"
}