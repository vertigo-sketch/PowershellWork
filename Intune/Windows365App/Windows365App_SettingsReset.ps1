# --- Config ---
$PreferredLogDir = 'C:\Program Files\iCapital\Logs'
$LogDir = $PreferredLogDir

# --- Ensure log directory (fallback if Program Files isn't writable) ---
try {
    if (-not (Test-Path -LiteralPath $PreferredLogDir)) {
        New-Item -ItemType Directory -Path $PreferredLogDir -Force -ErrorAction Stop | Out-Null
    }
} catch {
    $LogDir = Join-Path $env:LOCALAPPDATA 'iCapital\Logs'
    if (-not (Test-Path -LiteralPath $LogDir)) {
        New-Item -ItemType Directory -Path $LogDir -Force | Out-Null
    }
}

$LogFile = Join-Path $LogDir ("Windows365_Reset_{0:yyyyMMdd_HHmmss}.log" -f (Get-Date))

function Write-Log {
    param(
        [Parameter(Mandatory=$true)][string]$Message,
        [ValidateSet('INFO','WARN','ERROR')][string]$Level = 'INFO'
    )
    $line = "[{0:yyyy-MM-dd HH:mm:ss}] [{1}] {2}" -f (Get-Date), $Level, $Message
    Add-Content -Path $LogFile -Value $line
}

Write-Log "Starting Windows 365 app reset. LogFile='$LogFile' LogDir='$LogDir'"

# Optional: make errors stop the script so they get logged and return proper exit codes
$ErrorActionPreference = 'Stop'

# --- Original logic with logging ---
try {
    $pkg = Get-AppxPackage -Name 'MicrosoftCorporationII.Windows365' -ErrorAction Stop
    if ($pkg) {
        Write-Log ("Package found: {0}" -f $pkg.PackageFullName)

        # If Reset-AppxPackage is missing on the OS, this throws; we catch and log below.
        Reset-AppxPackage -Package $pkg.PackageFullName

        Write-Log 'Windows 365 app reset completed.' 'INFO'
        # Keep a concise console message (optional)
        Write-Host 'Windows 365 app reset completed.'
        exit 0
    } else {
        Write-Log 'Windows 365 app not found for the current user.' 'ERROR'
        Write-Error 'Windows 365 app not found for the current user.'
        exit 1
    }
}
catch {
    Write-Log ("Reset failed: {0}" -f $_.Exception.Message) 'ERROR'
    # If the failure is due to missing cmdlet on older builds, the message will indicate that.
    # You can add a fallback re-register here if desired.
    Write-Error $_.Exception.Message
    exit 1
}
