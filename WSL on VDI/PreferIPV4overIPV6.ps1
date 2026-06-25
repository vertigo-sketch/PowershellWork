<# 
.SYNOPSIS
  Sets HKLM\SYSTEM\CurrentControlSet\Services\Tcpip6\Parameters\DisabledComponents to 0x20 (DWORD).

.DESCRIPTION
  - Creates a timestamped .reg backup of the Tcpip6\Parameters key before changes
  - Writes structured logs to C:\Program Files\iCapital\Logs
  - Compatible with PowerShell 5.1 (no modern operators)
  - Returns non-zero exit code on failure (useful for Intune detection)
  - Prompts for elevation if not already running as admin

.NOTES
  Value 0x20 prefers IPv4 over IPv6. A reboot is generally required.
#>

#region Helpers
function Write-Log {
    param(
        [string]$Message,
        [ValidateSet('INFO','WARN','ERROR')][string]$Level = 'INFO'
    )
    try {
        $global:LogRoot = 'C:\Program Files\iCapital\Logs'
        if (-not (Test-Path -LiteralPath $global:LogRoot)) {
            New-Item -ItemType Directory -Path $global:LogRoot -Force | Out-Null
        }
        $global:LogFile = Join-Path $global:LogRoot ('IPv6Pref_{0}.log' -f (Get-Date -Format 'yyyyMMdd'))
        $line = ('{0} [{1}] {2}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Level, $Message)
        Add-Content -Path $global:LogFile -Value $line
    } catch {
        Write-Host "Logging failed: $($_.Exception.Message)"
    }
}

function Assert-Elevation {
    $isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    if (-not $isAdmin) {
        Write-Log -Level 'WARN' -Message 'Script not running elevated. Relaunching with elevation...'
        $psi = New-Object System.Diagnostics.ProcessStartInfo
        $psi.FileName = 'powershell.exe'
        $psi.Arguments = '-NoProfile -ExecutionPolicy Bypass -File "' + $PSCommandPath + '"'
        $psi.Verb = 'runas'
        try {
            [System.Diagnostics.Process]::Start($psi) | Out-Null
        } catch {
            Write-Log -Level 'ERROR' -Message ('Elevation launch failed: {0}' -f $_.Exception.Message)
            exit 1
        }
        exit 0
    }
}
#endregion Helpers

#region Start
Write-Log -Message '------------------------'
Write-Log -Message 'Starting IPv6 preference remediation (DisabledComponents = 0x20).'
Assert-Elevation
#endregion Start

try {
    $regPath = 'HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip6\Parameters'
    $valueName = 'DisabledComponents'
    $desiredValue = 0x20  # DWORD (32 decimal)

    # Ensure the key exists
    if (-not (Test-Path -LiteralPath $regPath)) {
        Write-Log -Level 'INFO' -Message ('Registry key not found. Creating: {0}' -f $regPath)
        New-Item -Path $regPath -Force | Out-Null
    }

    # Backup the entire Parameters key to a .reg file
    $backupDir = 'C:\Program Files\iCapital\Logs'
    if (-not (Test-Path -LiteralPath $backupDir)) {
        New-Item -ItemType Directory -Path $backupDir -Force | Out-Null
    }
    $backupFile = Join-Path $backupDir ('Tcpip6_Parameters_Backup_{0}.reg' -f (Get-Date -Format 'yyyyMMdd_HHmmss'))
    $regNativePath = 'HKLM\SYSTEM\CurrentControlSet\Services\Tcpip6\Parameters'
    Write-Log -Message ('Backing up key {0} to {1}' -f $regNativePath, $backupFile)

    $cmd = 'reg.exe export "{0}" "{1}" /y' -f $regNativePath, $backupFile
    $backup = Start-Process -FilePath 'cmd.exe' -ArgumentList ('/c ' + $cmd) -Wait -PassThru
    if ($backup.ExitCode -ne 0) {
        Write-Log -Level 'WARN' -Message ('reg.exe export returned non-zero exit code: {0}' -f $backup.ExitCode)
    }

    # Read current value (if present)
    $currentValue = $null
    try {
        $item = Get-ItemProperty -LiteralPath $regPath -Name $valueName -ErrorAction Stop
        $currentValue = [int]$item.$valueName
        Write-Log -Message ('Current DisabledComponents={0}' -f $currentValue)
    } catch {
        Write-Log -Level 'INFO' -Message 'DisabledComponents not set; will create it.'
    }

    # Set the value to 0x20
    Write-Log -Message ('Setting {0}\{1} to 0x20 (DWORD).' -f $regNativePath, $valueName)
    New-ItemProperty -LiteralPath $regPath -Name $valueName -Value $desiredValue -PropertyType DWord -Force | Out-Null

    # Verify
    $verify = (Get-ItemProperty -LiteralPath $regPath -Name $valueName).$valueName
    if ([int]$verify -eq [int]$desiredValue) {
        Write-Log -Message ('Verification succeeded. DisabledComponents now {0}.' -f $verify)
        Write-Host 'Success: DisabledComponents set to 0x20 (prefer IPv4). A restart is recommended.'
        exit 0
    } else {
        Write-Log -Level 'ERROR' -Message ('Verification failed. Found {0} instead of {1}.' -f $verify, $desiredValue)
        Write-Host 'Error: Verification failed.'
        exit 2
    }
} catch {
    Write-Log -Level 'ERROR' -Message ('Unhandled exception: {0}' -f $_.Exception.Message)
    Write-Host ('Unhandled exception: {0}' -f $_.Exception.Message)
    exit 1
}
