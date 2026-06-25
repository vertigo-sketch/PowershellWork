# Remediate-Windows365AppReset.ps1
# Purpose: Stop Windows 365 app, remove per-user app data and HKCU\Software\Microsoft\Windows365 for all local user profiles.
# Silent execution with logging to C:\Install\iCapital\Windows365Reset.log

$ErrorActionPreference = 'Stop'

# --- Config ---
$LogDir  = "C:\Install\iCapital"
$LogFile = Join-Path $LogDir "Windows365Reset.log"

# --- Helpers ---
function Ensure-LogPath {
    try {
        if (-not (Test-Path -LiteralPath $LogDir)) {
            New-Item -Path $LogDir -ItemType Directory -Force | Out-Null
        }
        if (-not (Test-Path -LiteralPath $LogFile)) {
            New-Item -Path $LogFile -ItemType File -Force | Out-Null
        }
    } catch {}
}

function Write-Log {
    param([string]$Message)
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    try {
        Add-Content -Path $LogFile -Value "$timestamp`t$Message"
    } catch {}
}

function Stop-Windows365Processes {
    # Best-effort: stop likely process names; if not found, continue
    $procNames = @(
        "Windows365",                    # Primary app process (if present)
        "Win32Bridge.Server",            # UWP bridge (common for Store apps)
        "MicrosoftCorporationII.Windows365" # Sometimes shows as package family
    )

    foreach ($name in $procNames) {
        try {
            Get-Process -Name $name -ErrorAction SilentlyContinue | ForEach-Object {
                Write-Log "Stopping process: $($_.Name) (PID: $($_.Id))"
                Stop-Process -Id $_.Id -Force -ErrorAction SilentlyContinue
            }
        } catch {
            Write-Log "Stop process error for '$name': $($_.Exception.Message)"
        }
    }
}

function Get-UserProfiles {
    Get-CimInstance Win32_UserProfile |
        Where-Object {
            $_.LocalPath -like "C:\Users\*" -and
            -not $_.Special -and
            Test-Path $_.LocalPath
        }
}

function Remove-Windows365PackageData {
    param([string]$ProfilePath)

    $packagesRoot = Join-Path $ProfilePath "AppData\Local\Packages"
    if (-not (Test-Path -LiteralPath $packagesRoot)) {
        Write-Log "No Packages folder for profile: $ProfilePath"
        return
    }

    $targets = Get-ChildItem -LiteralPath $packagesRoot -Directory -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -like "MicrosoftCorporationII.Windows365_*" }

    if (-not $targets -or $targets.Count -eq 0) {
        Write-Log "Windows 365 app data not found for profile: $ProfilePath"
        return
    }

    foreach ($target in $targets) {
        try {
            Write-Log "Removing Windows 365 app data: $($target.FullName)"
            # Retry logic in case files are locked
            $attempt = 0
            $maxAttempts = 3
            do {
                try {
                    Remove-Item -LiteralPath $target.FullName -Recurse -Force -ErrorAction Stop
                    Write-Log "Deleted: $($target.FullName)"
                    break
                } catch {
                    $attempt++
                    Write-Log "Delete attempt $attempt failed ($($target.FullName)): $($_.Exception.Message)"
                    Start-Sleep -Seconds 2
                }
            } while ($attempt -lt $maxAttempts)

            if (Test-Path -LiteralPath $target.FullName) {
                Write-Log "WARNING: Could not delete $($target.FullName) after $maxAttempts attempts."
            }
        } catch {
            Write-Log "Error removing $($target.FullName): $($_.Exception.Message)"
        }
    }
}

function Remove-Windows365HKCU {
    param([string]$ProfilePath)

    # Load the user's hive under HKU\<TempHive>, remove key, then unload
    $hiveFile = Join-Path $ProfilePath "NTUSER.DAT"
    if (-not (Test-Path -LiteralPath $hiveFile)) {
        Write-Log "NTUSER.DAT not found for profile: $ProfilePath"
        return
    }

    # Unique hive name per profile
    $hiveName = "HKU\W365TMP_" + ([System.IO.Path]::GetFileName($ProfilePath))

    try {
        # If loaded already (user signed in), we can target HKU\<SID> directly; otherwise, load NTUSER.DAT
        $loaded = $false
        $sid = (Get-CimInstance Win32_UserProfile | Where-Object { $_.LocalPath -eq $ProfilePath }).SID
        if ($sid -and (Get-ChildItem Registry::HKEY_USERS | Where-Object { $_.Name -match [regex]::Escape($sid) })) {
            $loaded = $true
        }

        if ($loaded) {
            $targetKey = "Registry::HKEY_USERS\$sid\Software\Microsoft\Windows365"
            if (Test-Path -LiteralPath $targetKey) {
                Write-Log "Removing HKU\$sid\Software\Microsoft\Windows365"
                Remove-Item -LiteralPath $targetKey -Recurse -Force -ErrorAction SilentlyContinue
            } else {
                Write-Log "No HKU\$sid\Software\Microsoft\Windows365 key present"
            }
            return
        }

        # Load hive if not already loaded
        Write-Log "Loading hive: $hiveFile -> $hiveName"
        $load = Start-Process -FilePath reg.exe -ArgumentList @("load", $hiveName, $hiveFile) -Wait -PassThru -WindowStyle Hidden
        if ($load.ExitCode -ne 0) {
            Write-Log "ERROR: reg load failed (exit $($load.ExitCode)) for $ProfilePath"
            return
        }

        $targetKey = "Registry::$hiveName\Software\Microsoft\Windows365"
        if (Test-Path -LiteralPath $targetKey) {
            Write-Log "Removing $targetKey"
            Remove-Item -LiteralPath $targetKey -Recurse -Force -ErrorAction SilentlyContinue
        } else
            { Write-Log "No $targetKey key found" }

        # Unload hive
        Write-Log "Unloading hive: $hiveName"
        $unload = Start-Process -FilePath reg.exe -ArgumentList @("unload", $hiveName) -Wait -PassThru -WindowStyle Hidden
        if ($unload.ExitCode -ne 0) {
            Write-Log "WARNING: reg unload returned exit $($unload.ExitCode) for $ProfilePath"
        }
    } catch {
        Write-Log "HKCU cleanup error for $ProfilePath: $($_.Exception.Message)"
    }
}

# --- Execution ---
Ensure-LogPath
Write-Log "=== Windows 365 App Reset started ==="
Stop-Windows365Processes

$userProfiles = Get-UserProfiles
if (-not $userProfiles -or $userProfiles.Count -eq 0) {
    Write-Log "No eligible user profiles found on this host."
} else {
    foreach ($profile in $userProfiles) {
        Write-Log "Processing profile: $($profile.LocalPath) (SID: $($profile.SID))"
        Remove-Windows365PackageData -ProfilePath $profile.LocalPath
        Remove-Windows365HKCU       -ProfilePath $profile.LocalPath
    }
}

Write-Log "=== Windows 365 App Reset completed ==="

# Always exit 0 for remediation scripts (Intune treats errors via log review)
