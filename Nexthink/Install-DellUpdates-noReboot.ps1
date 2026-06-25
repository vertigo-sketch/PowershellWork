<#
.SYNOPSIS
  Ensures Dell Command | Update (DCU) 5.6.0 is installed, scans for applicable updates,
  writes a list of available updates, and applies BIOS/Firmware/Drivers with reboot disabled.
  Apply phase is blocked unless the device is on AC power.
  If BIOS/Firmware updates are applicable (or list cannot be reliably parsed), BitLocker is
  suspended reliably before applying, with verification.

.REQUIREMENTS
  - PowerShell 5.1 compatible
  - Run as Admin or SYSTEM
  - Internet access to download DCU installer and update payloads

#>

[CmdletBinding()]
param(
  [string]$WorkingRoot = "C:\ProgramData\Dell\DCU-Automation",

  # DCU 5.6.0 Universal app (provided link)
  [string]$DcuDownloadUrl = "https://dl.dell.com/FOLDER13922692M/1/Dell-Command-Update-Windows-Universal-Application_2WT0J_WIN64_5.6.0_A00.EXE",

  # Dell-published SHA-256 for this exact package (5.6.0 A00)
  [string]$ExpectedDcuSha256 = "e09b7fdf8ba5a19a837a95e1183e5a79c006be2f433909e177e24fd704c26aa1",

  # BitLocker suspension reboot count (0-15). Default 2 to cover typical BIOS/firmware reboot cycle.
  [ValidateRange(0,15)]
  [int]$BitLockerRebootCount = 2
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# -----------------------------
# Logging
# -----------------------------
if (-not (Test-Path $WorkingRoot)) { New-Item -Path $WorkingRoot -ItemType Directory -Force | Out-Null }
$Stamp   = Get-Date -Format "yyyyMMdd-HHmmss"
$LogFile = Join-Path $WorkingRoot "DCU-$Stamp.log"

function Write-Log {
  param(
    [Parameter(Mandatory)][string]$Message,
    [ValidateSet("INFO","WARN","ERROR")][string]$Level = "INFO"
  )
  $line = "{0} [{1}] {2}" -f (Get-Date -Format "s"), $Level, $Message
  $line | Tee-Object -FilePath $LogFile -Append
}

function Exec-Process {
  param(
    [Parameter(Mandatory)][string]$FilePath,
    [string]$Arguments = "",
    [int]$TimeoutSeconds = 7200
  )

  Write-Log "Running: $FilePath $Arguments"
  $p = Start-Process -FilePath $FilePath -ArgumentList $Arguments -NoNewWindow -PassThru

  if (-not $p.WaitForExit($TimeoutSeconds * 1000)) {
    try { $p.Kill() } catch {}
    throw "Timeout after $TimeoutSeconds seconds: $FilePath $Arguments"
  }

  Write-Log "ExitCode: $($p.ExitCode)"
  return $p.ExitCode
}

function Get-FileSha256 {
  param([Parameter(Mandatory)][string]$Path)
  return (Get-FileHash -Path $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Find-DCUCli {
  $candidates = @(
    "C:\Program Files\Dell\CommandUpdate\dcu-cli.exe",
    "C:\Program Files (x86)\Dell\CommandUpdate\dcu-cli.exe"
  )
  return ($candidates | Where-Object { Test-Path $_ } | Select-Object -First 1)
}

# -----------------------------
# AC Power Enforcement
# -----------------------------
function Test-OnACPower {
  # Returns $true if on AC power OR no battery present; $false if on battery and discharging.
  try {
    $bats = @(Get-CimInstance -ClassName Win32_Battery -ErrorAction Stop)
    if ($bats.Count -eq 0) { return $true } # desktop/no-battery => OK

    foreach ($b in $bats) {
      if ($b.BatteryStatus -eq 1) { return $false } # discharging
    }
    return $true
  }
  catch {
    try {
      Add-Type -AssemblyName System.Windows.Forms | Out-Null
      $ps = [System.Windows.Forms.SystemInformation]::PowerStatus
      if ($ps.PowerLineStatus -eq [System.Windows.Forms.PowerLineStatus]::Online)  { return $true }
      if ($ps.PowerLineStatus -eq [System.Windows.Forms.PowerLineStatus]::Offline) { return $false }
    } catch {}
    return $false # fail-safe
  }
}

function Get-PowerStateSummary {
  try {
    $bats = @(Get-CimInstance -ClassName Win32_Battery -ErrorAction Stop)
    if ($bats.Count -eq 0) { return "No battery detected (treating as AC power OK)." }
    return (($bats | ForEach-Object { "BatteryStatus=$($_.BatteryStatus)" }) -join "; ")
  } catch {
    return "Power state could not be reliably determined."
  }
}

# -----------------------------
# BitLocker: Reliable suspend + verification
# -----------------------------
function Get-BitLockerSuspendCount {
  param([Parameter(Mandatory)][string]$DriveLetter) # e.g. "C:"

  try {
    $vol = Get-CimInstance -Namespace "ROOT/CIMV2/Security/MicrosoftVolumeEncryption" `
                           -ClassName "Win32_EncryptableVolume" `
                           -Filter ("DriveLetter='{0}'" -f $DriveLetter) -ErrorAction Stop
    if (-not $vol) { return $null }

    $res = Invoke-CimMethod -InputObject $vol -MethodName "GetSuspendCount" -ErrorAction Stop
    # Returns object with SuspendCount
    return $res.SuspendCount
  } catch {
    return $null
  }
}

function Test-BitLockerCmdletsAvailable {
  return [bool](Get-Command -Name Get-BitLockerVolume -ErrorAction SilentlyContinue)
}

function Suspend-BitLockerReliable {
  param(
    [Parameter(Mandatory)][string]$DriveLetter,   # e.g. "C:"
    [Parameter(Mandatory)][int]$RebootCount
  )

  Write-Log "BitLocker: preparing to suspend on $DriveLetter (RebootCount=$RebootCount)."

  # If BitLocker cmdlets exist, prefer them
  if (Test-BitLockerCmdletsAvailable) {
    try {
      $blv = Get-BitLockerVolume -MountPoint ($DriveLetter + "\") -ErrorAction Stop
      if ($blv.ProtectionStatus -ne "On") {
        Write-Log "BitLocker: ProtectionStatus is not 'On' for $DriveLetter (status=$($blv.ProtectionStatus)). Skipping suspend." "WARN"
        return $true
      }

      Suspend-BitLocker -MountPoint ($DriveLetter + "\") -RebootCount $RebootCount -ErrorAction Stop | Out-Null

      # Verify via WMI suspend count
      Start-Sleep -Seconds 2
      $count = Get-BitLockerSuspendCount -DriveLetter $DriveLetter
      if ($null -ne $count -and $count -gt 0) {
        Write-Log "BitLocker: suspension verified on $DriveLetter (SuspendCount=$count)."
        return $true
      }

      # Secondary verification via Get-BitLockerVolume
      $blv2 = Get-BitLockerVolume -MountPoint ($DriveLetter + "\") -ErrorAction Stop
      if ($blv2.ProtectionStatus -eq "Off") {
        Write-Log "BitLocker: suspension inferred on $DriveLetter (ProtectionStatus=Off)."
        return $true
      }

      Write-Log "BitLocker: suspend attempted but verification did not confirm. Will fall back to manage-bde." "WARN"
    } catch {
      Write-Log "BitLocker: Suspend-BitLocker path failed: $($_.Exception.Message). Will try manage-bde fallback." "WARN"
    }
  } else {
    Write-Log "BitLocker: native BitLocker cmdlets not available; using manage-bde fallback." "WARN"
  }

  # Fallback: manage-bde protectors disable (common on systems lacking BitLocker module)
  try {
    $manageBde = Join-Path $env:SystemRoot "System32\manage-bde.exe"
    if (-not (Test-Path $manageBde)) {
      Write-Log "BitLocker: manage-bde.exe not found; cannot suspend BitLocker reliably." "ERROR"
      return $false
    }

    $args = "-protectors -disable $DriveLetter -RebootCount $RebootCount"
    $code = Exec-Process -FilePath $manageBde -Arguments $args -TimeoutSeconds 300

    Start-Sleep -Seconds 2
    $count2 = Get-BitLockerSuspendCount -DriveLetter $DriveLetter
    if ($null -ne $count2 -and $count2 -gt 0) {
      Write-Log "BitLocker: manage-bde suspension verified on $DriveLetter (SuspendCount=$count2)."
      return $true
    }

    Write-Log "BitLocker: manage-bde ran (exit=$code) but verification did not confirm suspension." "ERROR"
    return $false
  } catch {
    Write-Log "BitLocker: manage-bde fallback failed: $($_.Exception.Message)" "ERROR"
    return $false
  }
}

function Suspend-OSDriveBitLockerIfNeeded {
  param(
    [bool]$AssumeFirmwareOrBios,
    [int]$RebootCount
  )

  if (-not $AssumeFirmwareOrBios) {
    Write-Log "BitLocker: BIOS/Firmware not detected; no suspension required."
    return $true
  }

  $osDrive = ($env:SystemDrive).TrimEnd("\") # usually "C:"
  Write-Log "BitLocker: BIOS/Firmware detected (or unknown). Suspending OS drive $osDrive."

  return (Suspend-BitLockerReliable -DriveLetter $osDrive -RebootCount $RebootCount)
}

# -----------------------------
# DCU: install and configuration
# -----------------------------
function Ensure-DCUInstalled {
  $dcuCli = Find-DCUCli
  if ($dcuCli) {
    Write-Log "DCU CLI found: $dcuCli"
    return $dcuCli
  }

  Write-Log "DCU CLI not found. Will download and install DCU 5.6.0."
  $installerPath = Join-Path $WorkingRoot "DCU-5.6.0.exe"

  try { [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 } catch {}

  Write-Log "Downloading: $DcuDownloadUrl -> $installerPath"
  try {
    Start-BitsTransfer -Source $DcuDownloadUrl -Destination $installerPath -ErrorAction Stop
  } catch {
    Invoke-WebRequest -Uri $DcuDownloadUrl -OutFile $installerPath -UseBasicParsing
  }

  if (-not (Test-Path $installerPath)) { throw "Download failed: $installerPath not found." }

  $actualSha = Get-FileSha256 -Path $installerPath
  Write-Log "Downloaded SHA256: $actualSha"
  if ($actualSha -ne $ExpectedDcuSha256.ToLowerInvariant()) {
    throw "SHA-256 mismatch. Expected $ExpectedDcuSha256 but got $actualSha"
  }
  Write-Log "SHA-256 verified successfully."

  Write-Log "Installing DCU silently..."
  $installExit = Exec-Process -FilePath $installerPath -Arguments "/s" -TimeoutSeconds 1800
  Write-Log "Installer exit code: $installExit"

  Start-Sleep -Seconds 10
  $dcuCli = Find-DCUCli
  if (-not $dcuCli) { throw "DCU install completed but dcu-cli.exe still not found." }

  Write-Log "DCU CLI found after install: $dcuCli"
  return $dcuCli
}

function Configure-DCUForBitLocker {
  param([Parameter(Mandatory)][string]$DcuCli)

  # Best-effort DCU config to autosuspend BitLocker
  try {
    Write-Log "Configuring DCU: autoSuspendBitLocker=enable (best-effort)."
    Exec-Process -FilePath $DcuCli -Arguments "/configure -autoSuspendBitLocker=enable" -TimeoutSeconds 600 | Out-Null
    return $true
  } catch {
    Write-Log "DCU /configure autoSuspendBitLocker failed: $($_.Exception.Message)" "WARN"
    return $false
  }
}

# -----------------------------
# Scan parsing helpers
# -----------------------------
function Get-UpdatesFromReport {
  param([Parameter(Mandatory)][string]$ReportPath)

  $result = [ordered]@{
    Parsed           = $false
    Updates          = @()
    HasBIOSOrFirmware = $false
  }

  if (-not (Test-Path $ReportPath)) { return [pscustomobject]$result }

  try {
    [xml]$xml = Get-Content -Path $ReportPath -ErrorAction Stop
    $updates = @($xml.updates.update)

    if ($updates.Count -gt 0) {
      $result.Parsed = $true
      $result.Updates = $updates

      foreach ($u in $updates) {
        $t = [string]$u.type
        if ($t -match 'BIOS' -or $t -match 'Firmware') {
          $result.HasBIOSOrFirmware = $true
          break
        }
      }
    }
  } catch {
    # leave defaults
  }

  return [pscustomobject]$result
}

# -----------------------------
# 0) Ensure Dell hardware
# -----------------------------
try {
  $cs = Get-CimInstance -ClassName Win32_ComputerSystem
  if ($cs.Manufacturer -notmatch "Dell") {
    Write-Log "Manufacturer is not Dell ($($cs.Manufacturer)). Exiting with success."
    exit 0
  }
  Write-Log "Dell system detected: $($cs.Model)"
} catch {
  Write-Log "Unable to determine manufacturer/model: $($_.Exception.Message)" "WARN"
}

# -----------------------------
# 1) Ensure DCU installed
# -----------------------------
$dcuCli = Ensure-DCUInstalled

# -----------------------------
# 2) Configure DCU (best-effort)
# -----------------------------
Configure-DCUForBitLocker -DcuCli $dcuCli | Out-Null

# -----------------------------
# 3) Scan and generate update list
# -----------------------------
$ScanLog    = Join-Path $WorkingRoot "Scan-$Stamp.log"
$ReportFile = Join-Path $WorkingRoot "ApplicableUpdates-$Stamp.xml"
$ListFile   = Join-Path $WorkingRoot "UpdateList-$Stamp.txt"

$scanArgs = @(
  "/scan",
  "-outputLog=`"$ScanLog`"",
  "-report=`"$ReportFile`""
) -join " "

Write-Log "Starting DCU scan..."
$scanExit = Exec-Process -FilePath $dcuCli -Arguments $scanArgs -TimeoutSeconds 3600

$scanInfo = Get-UpdatesFromReport -ReportPath $ReportFile

"Scan Time: $(Get-Date -Format s)" | Out-File -FilePath $ListFile -Encoding UTF8
"DCU CLI: $dcuCli"                 | Out-File -FilePath $ListFile -Append -Encoding UTF8
"Scan Exit Code: $scanExit"        | Out-File -FilePath $ListFile -Append -Encoding UTF8
"Report Parsed: $($scanInfo.Parsed)"| Out-File -FilePath $ListFile -Append -Encoding UTF8
""                                 | Out-File -FilePath $ListFile -Append -Encoding UTF8

if ($scanInfo.Parsed -and $scanInfo.Updates.Count -gt 0) {
  "Available Updates (includes BIOS/Firmware/Drivers):" | Out-File -FilePath $ListFile -Append -Encoding UTF8
  foreach ($u in $scanInfo.Updates) {
    $type    = [string]$u.type
    $name    = [string]$u.name
    $version = [string]$u.version
    $urgency = [string]$u.urgency
    "{0} | {1} | Version: {2} | Urgency: {3}" -f $type, $name, $version, $urgency |
      Out-File -FilePath $ListFile -Append -Encoding UTF8
  }
  Write-Log "Parsed report. Total updates: $($scanInfo.Updates.Count). BIOS/Firmware present: $($scanInfo.HasBIOSOrFirmware)"
} else {
  "Unable to parse report or no updates listed in XML. Review scan log: $ScanLog" |
    Out-File -FilePath $ListFile -Append -Encoding UTF8
  Write-Log "Report not parsed or contained no updates. Will assume BIOS/Firmware MAY be present for safety." "WARN"
}

Write-Log "Update list written to: $ListFile"

# -----------------------------
# 4) Require AC power BEFORE applying updates
# -----------------------------
$powerSummary = Get-PowerStateSummary
Write-Log "Power check: $powerSummary"

if (-not (Test-OnACPower)) {
  Write-Log "Device is NOT on AC power. Skipping update installation (AC adapter required)." "WARN"
  $marker = Join-Path $WorkingRoot "LastRunStatus.txt"
  "$(Get-Date -Format s) - SKIPPED: Not on AC power" | Out-File -FilePath $marker -Encoding UTF8
  exit 0
}

Write-Log "AC power detected (or no battery present). Proceeding with update installation."

# -----------------------------
# 5) Reliable BitLocker suspend (only when BIOS/Firmware is detected OR report is unknown)
# -----------------------------
$assumeBiosOrFirmware = $false
if ($scanInfo.Parsed) {
  $assumeBiosOrFirmware = [bool]$scanInfo.HasBIOSOrFirmware
} else {
  # If we can't parse the list, assume BIOS/FW might be included to prevent recovery-key prompts.
  $assumeBiosOrFirmware = $true
}

if (-not (Suspend-OSDriveBitLockerIfNeeded -AssumeFirmwareOrBios $assumeBiosOrFirmware -RebootCount $BitLockerRebootCount)) {
  Write-Log "BitLocker suspension failed or could not be verified. Aborting apply for safety." "ERROR"
  $marker = Join-Path $WorkingRoot "LastRunStatus.txt"
  "$(Get-Date -Format s) - FAILED: BitLocker suspend not verified" | Out-File -FilePath $marker -Encoding UTF8
  exit 1
}

# -----------------------------
# 6) Apply updates (BIOS/Firmware/Drivers) - NEVER reboot
# -----------------------------
$ApplyLog = Join-Path $WorkingRoot "Apply-$Stamp.log"

$applyArgs = @(
  "/applyUpdates",
  "-reboot=disable",
  "-outputLog=`"$ApplyLog`""
) -join " "

Write-Log "Applying updates with reboot DISABLED..."
$applyExit = Exec-Process -FilePath $dcuCli -Arguments $applyArgs -TimeoutSeconds 14400

Write-Log "Apply completed. ExitCode=$applyExit"
Write-Log "Artifacts:"
Write-Log "  Scan Log : $ScanLog"
Write-Log "  Apply Log: $ApplyLog"
Write-Log "  Report   : $ReportFile"
Write-Log "  List     : $ListFile"

$marker = Join-Path $WorkingRoot "LastRunStatus.txt"
"$(Get-Date -Format s) - COMPLETED: Apply exit code $applyExit" | Out-File -FilePath $marker -Encoding UTF8

exit $applyExit
