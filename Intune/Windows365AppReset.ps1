<#
.SYNOPSIS
Deletes the Windows 365 package folder for the currently signed-in user and logs actions to C:\Install\iCapital.

.NOTES
- No hardcoded username; uses $env:LOCALAPPDATA
- Creates C:\Install\iCapital if it doesn't exist
- Logs both to console and to file
#>

#========================
# Region: Logging Setup
#========================
# Normalize/assume the intended log folder path
$LogDir = "C:\Install\iCapital"
try {
    if (-not (Test-Path -LiteralPath $LogDir)) {
        New-Item -ItemType Directory -Path $LogDir -Force | Out-Null
    }
} catch {
    Write-Host "Failed to create or access log directory at '$LogDir': $($_.Exception.Message)" -ForegroundColor Red
    throw
}

# Create a timestamped log file
$TimeStamp = Get-Date -Format "yyyyMMdd_HHmmss"
$LogFile   = Join-Path $LogDir "Windows365_App_Reset.log"

# Simple logger that writes to both console and file
function Write-Log {
    param(
        [Parameter(Mandatory)][string]$Message,
        [ValidateSet('Info','Warn','Error','Success')][string]$Level = 'Info'
    )
    $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $line = "[$ts][$Level] $Message"

    # Console coloring
    switch ($Level) {
        'Info'    { Write-Host $line -ForegroundColor Cyan }
        'Warn'    { Write-Host $line -ForegroundColor Yellow }
        'Error'   { Write-Host $line -ForegroundColor Red }
        'Success' { Write-Host $line -ForegroundColor Green }
        default   { Write-Host $line }
    }

    # Append to log file
    try {
        Add-Content -LiteralPath $LogFile -Value $line
    } catch {
        Write-Host "Failed to write to log file '$LogFile': $($_.Exception.Message)" -ForegroundColor Red
    }
}

Write-Log -Message "Log file initialized at '$LogFile'." -Level Info

#========================
# Region: Configuration
#========================
$TargetFolder = Join-Path $env:LOCALAPPDATA "Packages\MicrosoftCorporationII.Windows365_8wekyb3d8bbwe"
Write-Log -Message "Target folder: $TargetFolder" -Level Info

#========================
# Region: Pre-checks
#========================
if (-not (Test-Path -LiteralPath $TargetFolder)) {
    Write-Log -Message "Folder does not exist. Nothing to delete." -Level Warn
    Write-Log -Message "Script completed with no action required." -Level Success
    return
}

# Attempt to stop likely related processes to avoid file locks
$possibleProcesses = @(
    "Windows365", "RemoteDesktop", "msrdcw", "Win32RemoteDesktop", "W365"
)

foreach ($p in $possibleProcesses) {
    $procs = Get-Process -Name $p -ErrorAction SilentlyContinue
    foreach ($proc in $procs) {
        try {
            Write-Log -Message "Stopping process: $($proc.ProcessName) (PID $($proc.Id))" -Level Warn
            $proc | Stop-Process -Force -ErrorAction Stop
        } catch {
            Write-Log -Message "Failed to stop process $($proc.ProcessName): $($_.Exception.Message)" -Level Warn
        }
    }
}

#========================
# Region: Delete
#========================
$deleted = $false

try {
    Write-Log -Message "Deleting folder..." -Level Info
    Remove-Item -LiteralPath $TargetFolder -Recurse -Force -ErrorAction Stop
    $deleted = $true
    Write-Log -Message "Folder deleted successfully." -Level Success
} catch {
    Write-Log -Message "Error deleting folder: $($_.Exception.Message)" -Level Error

    # Fallback: clear attributes and retry once
    try {
        Write-Log -Message "Clearing read-only attributes and retrying..." -Level Warn
        Get-ChildItem -LiteralPath $TargetFolder -Recurse -Force -ErrorAction SilentlyContinue | ForEach-Object {
            try { $_.Attributes = 'Normal' } catch {}
        }
        Remove-Item -LiteralPath $TargetFolder -Recurse -Force -ErrorAction Stop
        $deleted = $true
        Write-Log -Message "Folder deleted successfully on retry." -Level Success
    } catch {
        Write-Log -Message "Retry failed: $($_.Exception.Message)" -Level Error
        Write-Log -Message "If the app is still running, close it and run again. You may also try running PowerShell as Administrator." -Level Warn
    }
}

#========================
# Region: Verification
#========================
if ($deleted -and -not (Test-Path -LiteralPath $TargetFolder)) {
    Write-Log -Message "Verified: folder no longer exists." -Level Success
} else {
    Write-Log -Message "Folder still present after attempts." -Level Error
}

Write-Log -Message "Log saved to: $LogFile" -Level Info
