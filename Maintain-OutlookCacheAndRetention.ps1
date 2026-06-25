<#
.SYNOPSIS
    Detect classic Outlook usage, remove oversized OST caches, and (optionally) apply a 3-month mailbox retention policy via Exchange Online.

.DESCRIPTION
    - Detects classic Win32 Outlook by checking App Paths and Outlook Profiles registry keys.
    - Enumerates .ost files in %LOCALAPPDATA%\Microsoft\Outlook.
    - Deletes any OST whose size >= ThresholdGB (default 50 GB) with SupportsShouldProcess (use -WhatIf first).
    - Gracefully closes Outlook before mutation to avoid file locks.
    - Logs to a central file (default: %ProgramData%\OutlookMaintenance\maintenance.log).
    - Optional: Applies modern MRM retention (Default tag: DeleteAndAllowRecovery at 90 days) and assigns a policy to a mailbox.

.PARAMETER RetentionMode
    'None' (default), 'ExchangeOnline'
    When 'ExchangeOnline' is used, provide -MailboxUPN.

.PARAMETER MailboxUPN
    Mailbox UPN for Exchange retention operations (e.g., first.last@domain.com).

.PARAMETER ThresholdGB
    Size threshold in gigabytes for OST deletion (default: 50).

.PARAMETER LogPath
    Path to the log file. Default: %ProgramData%\OutlookMaintenance\maintenance.log

.EXAMPLE
    # Dry-run (recommended first):
    .\Maintain-OutlookCacheAndRetention.ps1 -WhatIf

.EXAMPLE
    # Delete oversized OSTs if classic Outlook is detected:
    .\Maintain-OutlookCacheAndRetention.ps1 -Confirm:$false

.EXAMPLE
    # Also enforce 3-month retention (requires Exchange admin rights and module):
    .\Maintain-OutlookCacheAndRetention.ps1 -RetentionMode ExchangeOnline -MailboxUPN jmiller@icapitalnetwork.com -Confirm:$false

.NOTES
    - Run elevated when deploying across endpoints.
    - If OST is deleted, Outlook will rebuild the cache on next launch.
    - Exchange Online policy application may take time to fully materialize across the service.
#>

[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [ValidateSet('None','ExchangeOnline')]
    [string]$RetentionMode = 'None',

    [Parameter(Mandatory = $false)]
    [string]$MailboxUPN,

    [Parameter(Mandatory = $false)]
    [int64]$ThresholdGB = 50,

    [Parameter(Mandatory = $false)]
    [string]$LogPath = "$env:ProgramData\OutlookMaintenance\maintenance.log"
)

begin {
    # Ensure logging path
    $logDir = [System.IO.Path]::GetDirectoryName($LogPath)
    if (-not [string]:: -and -not (Test-Path -LiteralPath $logDir)) {
        New-Item -ItemType Directory -Path $logDir -Force | Out-Null
    }

    function Write-Log {
        param(
            [Parameter(Mandatory=$true)][string]$Message,
            [ValidateSet('INFO','WARN','ERROR')][string]$Level = 'INFO'
        )
        $stamp = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
        $line = "$stamp [$Level] $Message"
        $line | Add-Content -LiteralPath $LogPath
        Write-Verbose $line
        if ($Level -eq 'ERROR') { Write-Warning $Message }
    }

    function Test-IsClassicOutlook {
        try {
            $appPathKey = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths\OUTLOOK.EXE'
            $profilesKey = 'HKCU:\Software\Microsoft\Office\16.0\Outlook\Profiles'
            $classicExeExists = Test-Path -LiteralPath $appPathKey
            $profilesExist    = Test-Path -LiteralPath $profilesKey

            # Another strong indicator: presence of OST directory
            $ostDir = Join-Path $env:LOCALAPPDATA 'Microsoft\Outlook'
            $ostDirExists = Test-Path -LiteralPath $ostDir

            # New Outlook (Store app) runs as olk.exe; classic is OUTLOOK.EXE
            $classicProcRunning = Get-Process -Name 'OUTLOOK' -ErrorAction SilentlyContinue

            return ($classicExeExists -and $profilesExist) -or $classicProcRunning -or $ostDirExists
        }
        catch {
            Write-Log "Failed while detecting Outlook: $($_.Exception.Message)" 'WARN'
            return $false
        }
    }

    function Get-OstFiles {
        $dir = Join-Path $env:LOCALAPPDATA 'Microsoft\Outlook'
        if (Test-Path -LiteralPath $dir) {
            Get-ChildItem -LiteralPath $dir -Filter '*.ost' -File -Force -ErrorAction SilentlyContinue
        }
    }

    function Stop-OutlookIfRunning {
        try {
            $proc = Get-Process -Name 'OUTLOOK' -ErrorAction SilentlyContinue
            if ($proc) {
                Write-Log "Attempting to close classic Outlook gracefully."
                try {
                    # Try COM first (works on Windows PowerShell and PS7 on Windows)
                    $outlookApp = [Runtime.InteropServices.Marshal]::GetActiveObject('Outlook.Application') 2>$null
                    if ($outlookApp) { $outlookApp.Quit() }
                }
                catch { }

                Start-Sleep -Seconds 3
                $stillRunning = Get-Process -Name 'OUTLOOK' -ErrorAction SilentlyContinue
                if ($stillRunning) {
                    Write-Log "Outlook still running; stopping process." 'WARN'
                    Stop-Process -Name 'OUTLOOK' -Force -ErrorAction SilentlyContinue
                    Start-Sleep -Seconds 2
                }
            }
        }
        catch {
            Write-Log "Could not stop Outlook: $($_.Exception.Message)" 'WARN'
        }
    }

    function Remove-OversizedOst {
        param(
            [Parameter(Mandatory=$true)][int64]$ThresholdBytes
        )
        $deleted = @()
        $files = Get-OstFiles
        if (-not $files) {
            Write-Log "No OST files found under %LOCALAPPDATA%\Microsoft\Outlook."
            return $deleted
        }

        foreach ($f in $files) {
            try {
                $size = $f.Length
                Write-Log ("Found OST: {0} size {1:N0} bytes (~{2:N2} GB)" -f $f.FullName, $size, ($size/1GB))
                if ($size -ge $ThresholdBytes) {
                    if ($PSCmdlet.ShouldProcess($f.FullName, "Delete oversized OST (>= $([math]:: GB)")) {
                        Remove-Item -LiteralPath $f.FullName -Force -ErrorAction Stop
                        Write-Log "Deleted oversized OST: $($f.FullName)"
                        $deleted += $f.FullName
                    }
                }
            }
            catch {
                Write-Log "Failed to process $($f.FullName): $($_.Exception.Message)" 'ERROR'
            }
        }
        return $deleted
    }

    function Ensure-ExchangeOnlineModule {
        if (-not (Get-Module -ListAvailable -Name ExchangeOnlineManagement)) {
            throw "ExchangeOnlineManagement module is required. Install-Module ExchangeOnlineManagement (run as admin)."
        }
    }

    function Set-ExchangeRetention90Days {
        param(
            [Parameter(Mandatory=$true)][string]$MailboxUPN
        )
        Ensure-ExchangeOnlineModule
        Write-Log "Connecting to Exchange Online as $MailboxUPN..."
        Connect-ExchangeOnline -UserPrincipalName $MailboxUPN -ShowBanner:$false

        $tagName   = 'Default-DeleteAndRecover-90d'
        $policyName= 'Policy-Default-DeleteAndRecover-90d'

        # Create default tag if not present (Type All ==> default tag)
        $tag = Get-RetentionPolicyTag -Identity $tagName -ErrorAction SilentlyContinue
        if (-not $tag) {
            Write-Log "Creating retention tag $tagName (DeleteAndAllowRecovery, 90 days) ..."
            $tag = New-RetentionPolicyTag -Name $tagName -Type All -RetentionEnabled:$true `
                   -AgeLimitForRetention 90 -RetentionAction DeleteAndAllowRecovery
        }

        # Create policy if not present
        $policy = Get-RetentionPolicy -Identity $policyName -ErrorAction SilentlyContinue
        if (-not $policy) {
            Write-Log "Creating retention policy $policyName and linking tag $tagName ..."
            $policy = New-RetentionPolicy -Name $policyName -RetentionPolicyTagLinks $tagName
        }
        else {
            # Ensure link exists
            $links = ($policy.RetentionPolicyTagLinks -split ',').Trim()
            if ($links -notcontains $tagName) {
                Write-Log "Adding tag $tagName to policy $policyName ..."
                Set-RetentionPolicy -Identity $policyName -RetentionPolicyTagLinks ($links + $tagName)
            }
        }

        # Assign to mailbox
        Write-Log "Assigning retention policy $policyName to mailbox $MailboxUPN ..."
        Set-Mailbox -Identity $MailboxUPN -RetentionPolicy $policyName

        Write-Log "Retention policy applied. Note: policy application can take time to fully process."
        Disconnect-ExchangeOnline -Confirm:$false | Out-Null
    }
}

process {
    Write-Log "=== Maintain-OutlookCacheAndRetention start ==="
    $thresholdBytes = $ThresholdGB * 1GB

    $isClassic = Test-IsClassicOutlook
    if (-not $isClassic) {
        Write-Log "Classic Outlook not detected. No OST maintenance required."
    }
    else {
        Write-Log "Classic Outlook detected; beginning OST maintenance."
        Stop-OutlookIfRunning
        $deleted = Remove-OversizedOst -ThresholdBytes $thresholdBytes
        if ($deleted.Count -gt 0) {
            Write-Log ("Deleted {0} oversized OST file(s)." -f $deleted.Count)
        }
        else {
            Write-Log "No OST files exceeded the configured threshold."
        }
    }

    if ($RetentionMode -eq 'ExchangeOnline') {
        if ([string]:: {
            Write-Log "RetentionMode=ExchangeOnline requires -MailboxUPN." 'ERROR'
        }
        else {
            if ($PSCmdlet.ShouldProcess($MailboxUPN, "Apply 3-month Delete-and-Recover default retention policy")) {
                try {
                    Set-ExchangeRetention90Days -MailboxUPN $MailboxUPN
                }
                catch {
                    Write-Log "Exchange Online retention operation failed: $($_.Exception.Message)" 'ERROR'
                }
            }
        }
    }
    else {
        Write-Log "Retention mode: None (no mailbox policy changes requested)."
    }
}

end {
    Write-Log "=== Maintain-OutlookCacheAndRetention end ==="
}
