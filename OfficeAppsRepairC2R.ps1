<#
    Office Click-to-Run Deep Repair / Corruption Remediation
    Fixes bad-digest corruption, stale C2R caches, broken updates, failed installs.

    Log: C:\Program Files\iCapital\Logs\OfficeRepair.log
#>

# -----------------------------
#  Logging Setup
# -----------------------------
$LogPath = "C:\Program Files\iCapital\Logs"
$LogFile = Join-Path $LogPath "OfficeRepair.log"

If (!(Test-Path $LogPath)) {
    New-Item -Path $LogPath -ItemType Directory -Force | Out-Null
}

Function Log {
    Param([string]$msg)
    $timestamp = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    Add-Content -Path $LogFile -Value "$timestamp  $msg"
}

Log "=== Office C2R Deep Repair Started ==="

# -----------------------------
#  Stop Click-to-Run Service
# -----------------------------
Try {
    Log "Stopping ClickToRunSvc..."
    Stop-Service -Name ClickToRunSvc -Force -ErrorAction Stop
    Log "ClickToRunSvc stopped."
}
Catch {
    Log "WARNING: Could not stop ClickToRunSvc: $($_.Exception.Message)"
}

# -----------------------------
#  Purge corrupted caches
# -----------------------------
$C2RData = "C:\ProgramData\Microsoft\ClickToRun"
$C2RShared = "C:\Program Files\Common Files\Microsoft Shared\ClickToRun"

Function Safe-Purge($path) {
    if (Test-Path $path) {
        $backup = "$path.bak_$(Get-Date -Format yyyyMMddHHmmss)"
        Log "Renaming $path -> $backup"
        Rename-Item -Path $path -NewName $backup -Force
    } else {
        Log "Path not found: $path"
    }
}

Log "Purging C2R caches..."
Safe-Purge $C2RData
Safe-Purge $C2RShared
Log "Purge complete."

# -----------------------------
#  Restart Service
# -----------------------------
Try {
    Log "Starting ClickToRunSvc..."
    Start-Service -Name ClickToRunSvc -ErrorAction Stop
    Log "ClickToRunSvc started."
}
Catch {
    Log "ERROR: Couldn't start ClickToRunSvc: $($_.Exception.Message)"
}

# -----------------------------
#  Detect actual C2R exe
# -----------------------------
$Candidates = @(
    "$env:ProgramFiles\Common Files\Microsoft Shared\ClickToRun\OfficeC2RClient.exe",
    "$env:ProgramFiles\Common Files\Microsoft Shared\ClickToRun\OfficeClickToRun.exe",
    "${env:ProgramFiles(x86)}\Common Files\Microsoft Shared\ClickToRun\OfficeC2RClient.exe",
    "${env:ProgramFiles(x86)}\Common Files\Microsoft Shared\ClickToRun\OfficeClickToRun.exe"
)

$C2RExe = $Candidates | Where-Object { Test-Path $_ } | Select-Object -First 1

If (-not $C2RExe) {
    Log "FATAL: No Click-to-Run executable found. Cannot continue."
    Exit 1
}

Log "Detected C2R executable: $C2RExe"

# -----------------------------
#  Force a fresh repair/update
# -----------------------------
Log "Invoking ClickToRun repair/update..."

Try {
    # Use Start-Process to avoid PowerShell parsing errors on '/update'
    Start-Process -FilePath $C2RExe -ArgumentList "/update","user" -Wait -NoNewWindow
    Log "Click-to-Run update completed."
}
Catch {
    Log "ERROR running Click-to-Run update: $($_.Exception.Message)"
}

# -----------------------------
#  Finalize
# -----------------------------
Log "=== Office C2R Deep Repair Complete ==="
Exit 0
