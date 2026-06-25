
<# 
.SYNOPSIS
  Collect Office (Visio) Click-to-Run installer logs + Intune logs + Event Viewer
.DESCRIPTION
  Gathers relevant logs for troubleshooting Microsoft Visio Plan 2 (C2R) installs.
  Works under SYSTEM or admin. Creates a timestamped ZIP for easy sharing.
.PARAMETER OutputRoot
  Root folder to place the collection and ZIP (default: C:\Program Files\iCapital\Logs).
.PARAMETER HoursBack
  How many hours of Event Viewer logs to collect (default: 48).
.PARAMETER IncludeTemp
  Include common temp/cache locations if present (default: $true).
.EXAMPLE
  .\Collect-VisioInstallerLogs.ps1 -OutputRoot "C:\Logs" -HoursBack 72
#>

param(
    [string]$OutputRoot = "C:\Program Files\iCapital\Logs",
    [int]$HoursBack = 48,
    [bool]$IncludeTemp = $true
)

#region Helpers
function New-SafeDirectory {
    param([string]$Path)
    try {
        if (-not (Test-Path -LiteralPath $Path)) {
            New-Item -ItemType Directory -Path $Path -Force | Out-Null
        }
        return (Resolve-Path -LiteralPath $Path).Path
    } catch {
        throw "Failed to create or access directory '$Path'. Error: $($_.Exception.Message)"
    }
}

function Write-Log {
    param(
        [string]$Message,
        [ValidateSet("INFO","WARN","ERROR")] [string]$Level = "INFO"
    )
    $ts = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss.fff")
    $line = "[$ts][$Level] $Message"
    Write-Output $line
    try { Add-Content -Path $Global:LogFile -Value $line } catch { }
}

function Copy-IfExists {
    param(
        [string]$Source,
        [string]$DestFolder,
        [string[]]$IncludePatterns = @("*.*"),
        [int]$MaxDaysOld = 14
    )
    if (-not (Test-Path -LiteralPath $Source)) { Write-Log "Skip: '$Source' not found." "WARN"; return }
    $items = Get-ChildItem -LiteralPath $Source -File -ErrorAction SilentlyContinue -Force |
             Where-Object { $_.LastWriteTime -ge (Get-Date).AddDays(-$MaxDaysOld) }
    if ($IncludePatterns -and $IncludePatterns.Count -gt 0) {
        $filtered = @()
        foreach ($p in $IncludePatterns) {
            $filtered += $items | Where-Object { $_.Name -like $p }
        }
        $items = $filtered | Select-Object -Unique
    }
    if ($items.Count -eq 0) { Write-Log "No recent files in '$Source' matching $($IncludePatterns -join ', ')." "WARN"; return }
    foreach ($f in $items) {
        try {
            $dest = Join-Path $DestFolder $f.Name
            Copy-Item -LiteralPath $f.FullName -Destination $dest -Force
            Write-Log "Copied: $($f.FullName) -> $dest"
        } catch {
            Write-Log "Copy failed for '$($f.FullName)': $($_.Exception.Message)" "ERROR"
        }
    }
}
#endregion Helpers

#region Initialize
$machine = $env:COMPUTERNAME
$stamp   = Get-Date -Format "yyyyMMdd-HHmmss"
# Fallback if default OutputRoot is not writable under SYSTEM
try {
    $testPath = New-SafeDirectory -Path $OutputRoot
} catch {
    $OutputRoot = Join-Path $env:ProgramData "iCapital\Logs"
    $testPath = New-SafeDirectory -Path $OutputRoot
}
$caseRoot    = New-SafeDirectory -Path (Join-Path $OutputRoot "VisioInstallerLogs_$machine_$stamp")
$filesRoot   = New-SafeDirectory -Path (Join-Path $caseRoot "Files")
$eventsRoot  = New-SafeDirectory -Path (Join-Path $caseRoot "Events")
$Global:LogFile = Join-Path $caseRoot "Collector.log"
Write-Log "Starting collection on $machine. Output: $caseRoot"
#endregion Initialize

#region Collect: Office Click-to-Run logs
$pathsC2R = @(
    "C:\Program Files\Common Files\Microsoft Shared\ClickToRun\Log",
    "C:\ProgramData\Microsoft\Office\ClickToRun\Log"
)
foreach ($p in $pathsC2R) {
    $dest = New-SafeDirectory -Path (Join-Path $filesRoot ("ClickToRun_" + ($p -replace "[:\\]","_")))
    Copy-IfExists -Source $p -DestFolder $dest -IncludePatterns @("*.log","*.txt")
}
#endregion Collect: Office Click-to-Run logs

#region Collect: Intune Management Extension logs
$imePath = "C:\ProgramData\Microsoft\IntuneManagementExtension\Logs"
$imeDest = New-SafeDirectory -Path (Join-Path $filesRoot "IntuneManagementExtension")
Copy-IfExists -Source $imePath -DestFolder $imeDest -IncludePatterns @("*.log","*.txt","*.json")
#endregion Collect: IME logs

#region Collect: Optional temp/cache locations
if ($IncludeTemp) {
    $tempTargets = @(
        "$env:ProgramData\Package Cache",
        "$env:TEMP",
        "$env:WINDIR\Temp"
    )
    foreach ($t in $tempTargets) {
        $dest = New-SafeDirectory -Path (Join-Path $filesRoot ("TempCache_" + ($t -replace "[:\\]","_")))
        Copy-IfExists -Source $t -DestFolder $dest -IncludePatterns @("Office*.log","OfficeClickToRun*.log","setup*.log","MSI*.log")
    }
}
#endregion Collect: Optional temp/cache

#region Collect: Event Viewer (last X hours)
function Export-Events {
    param(
        [string]$LogName,
        [string]$DestFile,
        [int]$Hours = 48
    )
    try {
        $start = (Get-Date).AddHours(-$Hours)
        $events = Get-WinEvent -LogName $LogName -ErrorAction SilentlyContinue |
                  Where-Object { $_.TimeCreated -ge $start }
        if ($null -eq $events -or $events.Count -eq 0) {
            Write-Log "No recent events in '$LogName' (last $Hours hrs)." "WARN"
            return
        }
        $events | Export-Clixml -Path $DestFile
        Write-Log "Exported $($events.Count) events from '$LogName' to '$DestFile'"
    } catch {
        Write-Log "Event export failed for '$LogName': $($_.Exception.Message)" "ERROR"
    }
}

Export-Events -LogName "Application" -DestFile (Join-Path $eventsRoot "Application_Last${HoursBack}hrs.xml") -Hours $HoursBack
Export-Events -LogName "Microsoft Office Alerts" -DestFile (Join-Path $eventsRoot "OfficeAlerts_Last${HoursBack}hrs.xml") -Hours $HoursBack
#endregion Collect: Event Viewer

#region Environment & Registry context (bitness, channel)
$regDest = New-SafeDirectory -Path (Join-Path $caseRoot "Registry")
try {
    $c2rCfg = Get-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Office\ClickToRun\Configuration" -ErrorAction SilentlyContinue
    $c2rCfg | Export-Clixml -Path (Join-Path $regDest "HKLM_Office_ClickToRun_Configuration.xml")
    Write-Log "Exported HKLM:\SOFTWARE\Microsoft\Office\ClickToRun\Configuration"
} catch { Write-Log "Failed to read HKLM ClickToRun Configuration: $($_.Exception.Message)" "ERROR" }

try {
    $c2rCfg32 = Get-ItemProperty -Path "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Office\ClickToRun\Configuration" -ErrorAction SilentlyContinue
    if ($c2rCfg32) {
        $c2rCfg32 | Export-Clixml -Path (Join-Path $regDest "HKLM_WOW6432Node_Office_ClickToRun_Configuration.xml")
        Write-Log "Exported WOW6432Node ClickToRun Configuration"
    }
} catch { Write-Log "Failed to read WOW6432Node ClickToRun Configuration: $($_.Exception.Message)" "ERROR" }
#endregion Environment & Registry

#region ZIP package
$zipName = "VisioInstallerLogs_${machine}_${stamp}.zip"
$zipPath = Join-Path $OutputRoot $zipName
try {
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    [System.IO.Compression.ZipFile]::CreateFromDirectory($caseRoot, $zipPath)
    Write-Log "ZIP created: $zipPath"
} catch {
    Write-Log "Failed to create ZIP: $($_.Exception.Message)" "ERROR"
    # Fallback: Compress-Archive (Windows PowerShell)
    try {
        Compress-Archive -Path "$caseRoot\*" -DestinationPath $zipPath -Force
        Write-Log "ZIP created via Compress-Archive: $zipPath"
    } catch {
        Write-Log "Compress-Archive also failed: $($_.Exception.Message)" "ERROR"
    }
}
#endregion ZIP package

WriteWrite-Log "Collection complete."
