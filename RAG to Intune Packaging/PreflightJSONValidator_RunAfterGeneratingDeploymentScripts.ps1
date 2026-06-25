<#
.SYNOPSIS
  Preflight validator for Intune Win32 deployment JSON specs (local payload in Source folder).

.DESCRIPTION
  Validates:
   - Required fields exist
   - fullNameSafe normalization (spaces removed) and filename-safe chars
   - versionToken normalization (spaces => underscore) and filename-safe chars
   - Script names MUST be versioned:
       {fullNameSafe}_{versionToken}_install.ps1
       {fullNameSafe}_{versionToken}_uninstall.ps1
   - packaging.setupFile == install.script.fileName
   - install/uninstall commands contain correct script names
   - packaging tool path exists (IntuneWinAppUtil.exe)
   - Source folder exists; payload files exist inside Source
   - Silent args present; no-reboot policy checks
   - Optional: verify generated scripts exist in Source

.EXITCODES
  0 = success (no errors)
  1 = validation errors found
  2 = unexpected exception

.NOTES
  IntuneWinAppUtil uses -c (source), -s (setup file), -o (output), optional -q (quiet). [1](https://github.com/microsoft/Microsoft-Win32-Content-Prep-Tool)[2](https://learn.microsoft.com/en-us/intune/intune-service/apps/apps-win32-prepare)
  Win32 apps must install silently/non-interactively in Intune. [3](https://learn.microsoft.com/en-us/intune/intune-service/apps/apps-win32-app-management)[2](https://learn.microsoft.com/en-us/intune/intune-service/apps/apps-win32-prepare)
#>

[CmdletBinding()]
param(
  [Parameter(Mandatory)]
  [ValidateNotNullOrEmpty()]
  [string]$SpecPath,

  # Override the source root from the spec (useful for CI staging)
  [string]$SourceRoot,

  # Override tool path from the spec (useful for build agents)
  [string]$ToolPath,

  # If set, require that install/uninstall scripts already exist in the Source folder
  [switch]$RequireScriptsPresent,

  # If set, enforce MSI no-reboot arguments more strictly (REBOOT=ReallySuppress or /norestart)
  [switch]$StrictMsiNoReboot,

  # Optional log file
  [string]$LogPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ----------------------------
# Helpers
# ----------------------------
$errors   = New-Object System.Collections.Generic.List[string]
$warnings = New-Object System.Collections.Generic.List[string]

function Write-Log {
  param(
    [Parameter(Mandatory)][string]$Message,
    [ValidateSet('INFO','WARN','ERROR')][string]$Level = 'INFO'
  )
  $line = "{0} [{1}] {2}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"), $Level, $Message
  Write-Host $line
  if ($LogPath) {
    $dir = Split-Path -Parent $LogPath
    if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    Add-Content -LiteralPath $LogPath -Value $line
  }
}

function Add-Error([string]$Message) {
  $errors.Add($Message) | Out-Null
  Write-Log -Level 'ERROR' -Message $Message
}

function Add-Warn([string]$Message) {
  $warnings.Add($Message) | Out-Null
  Write-Log -Level 'WARN' -Message $Message
}

function Require([bool]$Condition, [string]$Message) {
  if (-not $Condition) { Add-Error $Message }
}

function Require-NotEmpty([object]$Value, [string]$Message) {
  if ($null -eq $Value) { Add-Error $Message; return }
  if ($Value -is [string] -and [string]::IsNullOrWhiteSpace($Value)) { Add-Error $Message; return }
  if ($Value -is [System.Collections.IEnumerable] -and -not ($Value -is [string])) {
    # arrays/lists
    $hasAny = $false
    foreach ($x in $Value) { $hasAny = $true; break }
    if (-not $hasAny) { Add-Error $Message }
  }
}

function Remove-InvalidFileChars([string]$s) {
  if ($null -eq $s) { return $null }
  $invalid = [IO.Path]::GetInvalidFileNameChars()
  foreach ($ch in $invalid) { $s = $s.Replace([string]$ch, '') }
  return $s
}

function Normalize-FullNameSafe([string]$fullName) {
  # Remove spaces entirely (your rule)
  $t = ($fullName ?? '').Trim()
  $t = $t -replace '\s+', ''                      # remove spaces/tabs
  $t = Remove-InvalidFileChars $t
  # Keep only allowed set: letters, digits, dot, underscore, hyphen
  $t = $t -replace '[^A-Za-z0-9._-]', ''
  return $t
}

function Normalize-VersionToken([string]$version) {
  # Option A: spaces => underscore
  $t = ($version ?? '').Trim()
  $t = $t -replace '\s+', '_'                      # spaces to underscore
  $t = Remove-InvalidFileChars $t
  $t = $t -replace '[^A-Za-z0-9._-]', ''           # keep filename-safe
  $t = $t -replace '_{2,}', '_'                    # collapse multiple underscores
  return $t
}

function Test-FileNameSafe([string]$value) {
  if ([string]::IsNullOrWhiteSpace($value)) { return $false }
  return $value -match '^[A-Za-z0-9][A-Za-z0-9._-]*$'
}

function Test-NoRebootArgs([string]$args) {
  if ([string]::IsNullOrWhiteSpace($args)) { return $true } # separate required check elsewhere
  # Disallow obvious restart/shutdown triggers (best-effort)
  return ($args -notmatch '(?i)\b(shutdown|reboot)\b') -and
         ($args -notmatch '(?i)(/forcerestart|/promptrestart|/restart)\b')
}

function Test-MsiNoRebootArgs([string]$args) {
  if ([string]::IsNullOrWhiteSpace($args)) { return $false }
  # Accept common "no reboot" patterns
  return ($args -match '(?i)\b/norestart\b') -or ($args -match '(?i)\bREBOOT=ReallySuppress\b')
}

# ----------------------------
# Load Spec
# ----------------------------
try {
  Require (Test-Path -LiteralPath $SpecPath) "Spec file not found: $SpecPath"
  if ($errors.Count -gt 0) { throw "Spec path invalid." }

  $raw = Get-Content -LiteralPath $SpecPath -Raw
  $spec = $raw | ConvertFrom-Json -Depth 50

  Write-Log "Loaded spec: $SpecPath"

  # ----------------------------
  # Required fields presence
  # ----------------------------
  Require-NotEmpty $spec.schemaVersion "Missing schemaVersion."
  Require-NotEmpty $spec.app          "Missing app object."
  Require-NotEmpty $spec.payload      "Missing payload object."
  Require-NotEmpty $spec.install      "Missing install object."
  Require-NotEmpty $spec.uninstall    "Missing uninstall object."
  Require-NotEmpty $spec.packaging    "Missing packaging object."
  Require-NotEmpty $spec.constraints  "Missing constraints object."
  Require-NotEmpty $spec.logging      "Missing logging object."

  if ($errors.Count -gt 0) { goto Done }

  # ----------------------------
  # App naming normalization checks
  # ----------------------------
  Require-NotEmpty $spec.app.fullName      "app.fullName is required."
  Require-NotEmpty $spec.app.fullNameSafe  "app.fullNameSafe is required."
  Require-NotEmpty $spec.app.version       "app.version is required."
  Require-NotEmpty $spec.app.versionToken  "app.versionToken is required."

  $expectedFullNameSafe = Normalize-FullNameSafe $spec.app.fullName
  $expectedVersionToken = Normalize-VersionToken $spec.app.version

  Require (Test-FileNameSafe $spec.app.fullNameSafe) "app.fullNameSafe contains invalid characters or spaces: '$($spec.app.fullNameSafe)'"
  Require (Test-FileNameSafe $spec.app.versionToken) "app.versionToken contains invalid characters or spaces: '$($spec.app.versionToken)'"

  Require ($spec.app.fullNameSafe -eq $expectedFullNameSafe) "app.fullNameSafe mismatch. Expected '$expectedFullNameSafe' from fullName '$($spec.app.fullName)', got '$($spec.app.fullNameSafe)'."
  Require ($spec.app.versionToken -eq $expectedVersionToken) "app.versionToken mismatch. Expected '$expectedVersionToken' from version '$($spec.app.version)', got '$($spec.app.versionToken)'."

  # ----------------------------
  # Expected filenames (ALWAYS versioned)
  # ----------------------------
  $expectedInstall   = "{0}_{1}_install.ps1"   -f $spec.app.fullNameSafe, $spec.app.versionToken
  $expectedUninstall = "{0}_{1}_uninstall.ps1" -f $spec.app.fullNameSafe, $spec.app.versionToken

  Require-NotEmpty $spec.install.script.fileName "install.script.fileName is required."
  Require-NotEmpty $spec.uninstall.script.fileName "uninstall.script.fileName is required."

  Require ($spec.install.script.fileName -eq $expectedInstall) "Install script name must be '$expectedInstall' but is '$($spec.install.script.fileName)'."
  Require ($spec.uninstall.script.fileName -eq $expectedUninstall) "Uninstall script name must be '$expectedUninstall' but is '$($spec.uninstall.script.fileName)'."

  # ----------------------------
  # Commands must reference correct scripts
  # ----------------------------
  Require-NotEmpty $spec.install.command "install.command is required."
  Require-NotEmpty $spec.uninstall.command "uninstall.command is required."

  Require ($spec.install.command -match [regex]::Escape($spec.install.script.fileName)) "install.command must reference '$($spec.install.script.fileName)'."
  Require ($spec.uninstall.command -match [regex]::Escape($spec.uninstall.script.fileName)) "uninstall.command must reference '$($spec.uninstall.script.fileName)'."

  # ----------------------------
  # Packaging checks (IntuneWinAppUtil inputs)
  # ----------------------------
  Require-NotEmpty $spec.packaging.tool.path "packaging.tool.path is required (IntuneWinAppUtil.exe)."
  Require-NotEmpty $spec.packaging.sourceRoot "packaging.sourceRoot is required."
  Require-NotEmpty $spec.packaging.outputRoot "packaging.outputRoot is required."
  Require-NotEmpty $spec.packaging.setupFile "packaging.setupFile is required."

  $effectiveToolPath = if ($ToolPath) { $ToolPath } else { $spec.packaging.tool.path }
  $effectiveSourceRoot = if ($SourceRoot) { $SourceRoot } else { $spec.packaging.sourceRoot }

  Require (Test-Path -LiteralPath $effectiveToolPath) "IntuneWinAppUtil.exe not found at: $effectiveToolPath"
  Require (Test-Path -LiteralPath $effectiveSourceRoot) "SourceRoot not found: $effectiveSourceRoot"

  # setupFile must equal install script name (your rule)
  Require ($spec.packaging.setupFile -eq $spec.install.script.fileName) "packaging.setupFile must equal install.script.fileName ('$($spec.install.script.fileName)') but is '$($spec.packaging.setupFile)'."

  # ----------------------------
  # Payload must exist in Source folder (local payload model)
  # ----------------------------
  Require-NotEmpty $spec.payload.type "payload.type is required."
  Require-NotEmpty $spec.payload.primaryFile "payload.primaryFile is required."

  $primaryPath = Join-Path -Path $effectiveSourceRoot -ChildPath $spec.payload.primaryFile
  Require (Test-Path -LiteralPath $primaryPath) "Payload primaryFile not found in SourceRoot: $primaryPath"

  if ($spec.payload.additionalFiles) {
    foreach ($f in $spec.payload.additionalFiles) {
      $p = Join-Path -Path $effectiveSourceRoot -ChildPath $f
      Require (Test-Path -LiteralPath $p) "Payload additional file not found in SourceRoot: $p"
    }
  }

  # Optional: scripts present (run this when preflight happens after generation)
  if ($RequireScriptsPresent) {
    $installScriptPath = Join-Path -Path $effectiveSourceRoot -ChildPath $spec.install.script.fileName
    $uninstallScriptPath = Join-Path -Path $effectiveSourceRoot -ChildPath $spec.uninstall.script.fileName
    Require (Test-Path -LiteralPath $installScriptPath) "Install script not found in SourceRoot: $installScriptPath"
    Require (Test-Path -LiteralPath $uninstallScriptPath) "Uninstall script not found in SourceRoot: $uninstallScriptPath"
  }

  # ----------------------------
  # Constraints: silent + no reboot + PS version
  # ----------------------------
  Require ($spec.constraints.silentInstallRequired -eq $true) "constraints.silentInstallRequired must be true (Intune Win32 requires silent/non-interactive installs)."
  Require ($spec.constraints.noReboot -eq $true) "constraints.noReboot must be true (org policy)."
  Require ($spec.constraints.powershellVersion -eq "5.1") "constraints.powershellVersion must be '5.1'."

  # Ensure silent args provided
  Require-NotEmpty $spec.install.behavior.silentArgs "install.behavior.silentArgs is required."
  Require-NotEmpty $spec.uninstall.behavior.uninstallArgs "uninstall.behavior.uninstallArgs is required."

  # Best-effort "no reboot" argument checks
  if (-not (Test-NoRebootArgs $spec.install.behavior.silentArgs)) {
    Add-Error "Install silentArgs appear to include reboot/shutdown triggers: '$($spec.install.behavior.silentArgs)'"
  }
  if (-not (Test-NoRebootArgs $spec.uninstall.behavior.uninstallArgs)) {
    Add-Error "Uninstall uninstallArgs appear to include reboot/shutdown triggers: '$($spec.uninstall.behavior.uninstallArgs)'"
  }

  # MSI stricter checks (recommended if your installs use msiexec)
  $isMsi = ($spec.payload.type -eq "msi") -or ($spec.install.behavior.useMsiExec -eq $true)
  if ($isMsi) {
    if (-not (Test-MsiNoRebootArgs $spec.install.behavior.silentArgs)) {
      $msg = "MSI install args should include '/norestart' or 'REBOOT=ReallySuppress' to honor noReboot. Args: '$($spec.install.behavior.silentArgs)'"
      if ($StrictMsiNoReboot) { Add-Error $msg } else { Add-Warn $msg }
    }
    if (-not (Test-MsiNoRebootArgs $spec.uninstall.behavior.uninstallArgs)) {
      $msg = "MSI uninstall args should include '/norestart' or 'REBOOT=ReallySuppress' to honor noReboot. Args: '$($spec.uninstall.behavior.uninstallArgs)'"
      if ($StrictMsiNoReboot) { Add-Error $msg } else { Add-Warn $msg }
    }
  }

  # Output root: warn if not present (pipeline can create it)
  if (-not (Test-Path -LiteralPath $spec.packaging.outputRoot)) {
    Add-Warn "packaging.outputRoot does not exist yet (pipeline can create it): $($spec.packaging.outputRoot)"
  }

Done:
  # ----------------------------
  # Summary
  # ----------------------------
  Write-Host ""
  Write-Log "Preflight validation complete. Errors: $($errors.Count), Warnings: $($warnings.Count)"

  if ($warnings.Count -gt 0) {
    Write-Host ""
    Write-Log "Warnings:" "WARN"
    $warnings | ForEach-Object { Write-Log " - $_" "WARN" }
  }

  if ($errors.Count -gt 0) {
    Write-Host ""
    Write-Log "Errors:" "ERROR"
    $errors | ForEach-Object { Write-Log " - $_" "ERROR" }
    exit 1
  }

  exit 0
}
catch {
  Write-Log "Unexpected exception: $($_.Exception.Message)" "ERROR"
  Write-Log $_.Exception.ToString() "ERROR"
  exit 2
}