<#
.SYNOPSIS
    Gets registry values from either:
      - a key path, or
      - a "key path + value name" path.

.DESCRIPTION
    Examples:
      - Key path only:
          HKLM:\Software\MyApp

      - Key path + value name:
          HKLM:\Software\MyApp\InstallPath

    If the full path is not a key but its parent is,
    the leaf segment is treated as the value name.
#>

param(
    [Parameter(Mandatory = $true)]
    [string]$Path
)

# First try: does this path point to a key?
if (Test-Path -Path $Path) {
    try {
        $item = Get-ItemProperty -Path $Path -ErrorAction Stop
        
        # Output all non-PS* properties
        $item.PSObject.Properties |
            Where-Object { $_.Name -notmatch '^PS' } |
            Select-Object @{Name='KeyPath'; Expression={ $Path }},
                          @{Name='ValueName'; Expression={ $_.Name }},
                          @{Name='ValueData'; Expression={ $_.Value }}
    }
    catch {
        Write-Error "Failed to read registry key '$Path'. $($_.Exception.Message)"
    }
}
else {
    # Assume last segment is the value name, parent is the key
    $parentKey = Split-Path -Path $Path -Parent
    $valueName = Split-Path -Path $Path -Leaf

    if (-not (Test-Path -Path $parentKey)) {
        Write-Error "Neither key '$Path' nor parent key '$parentKey' exists."
        return
    }

    try {
        $props = Get-ItemProperty -Path $parentKey -ErrorAction Stop

        if ($props.PSObject.Properties.Name -notcontains $valueName) {
            Write-Error "Key '$parentKey' exists, but value '$valueName' does not."
            return
        }

        [PSCustomObject]@{
            KeyPath   = $parentKey
            ValueName = $valueName
            ValueData = $props.$valueName
        }
    }
    catch {
        Write-Error "Failed to read value '$valueName' from key '$parentKey'. $($_.Exception.Message)"
    }
}