#Requires -Version 5.1
<#
.SYNOPSIS
  Vendor status poller with logging + Teams alerting on status changes.
.DESCRIPTION
  - Tests vendor endpoints on a schedule
  - Writes status.json (for HTML dashboard)
  - Persists last-status.json to detect changes
  - Sends Teams alerts only when status changes
  - Logs to text + JSONL + transcript
.NOTES
  Sign this script with an Authenticode code signing cert using Sign-VendorStatusMonitor.ps1.
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ---------------------------
# Config
# ---------------------------
$BasePath   = "C:\NOC"
$DataPath   = Join-Path $BasePath "data"
$LogPath    = Join-Path $BasePath "logs"
$TxPath     = Join-Path $BasePath "transcripts"

$StatusFile     = Join-Path $DataPath "status.json"
$LastStatusFile = Join-Path $DataPath "last-status.json"

# Teams Incoming Webhook URL (channel connector)
$TeamsWebhookUrl = "PASTE_TEAMS_WEBHOOK_URL_HERE"

# Thresholds
$TimeoutSec      = 8
$DegradedLatency = 2000   # ms
$WarnHttpMin     = 400
$MajorHttpMin    = 500

# Log retention
$KeepTranscriptDays = 14
$KeepLogDays        = 30

# Vendors (your list) – categorized for NOC grouping
$Vendors = @(
  # Identity / Access
  @{ Name="Okta"; Url="https://status.okta.com/"; Category="Identity" },
  @{ Name="Microsoft Entra (portal)"; Url="https://entra.microsoft.com/#view/Microsoft_AAD_DXP/ScenarioHealthSummary.ReactView"; Category="Identity" },

  # Collaboration / Productivity
  @{ Name="Microsoft Cloud Status"; Url="https://status.cloud.microsoft/"; Category="Collaboration" },
  @{ Name="M365 Connectivity"; Url="https://connectivity.office.com/status"; Category="Collaboration" },
  @{ Name="Webex"; Url="https://status.webex.com/commercial/status?lang=en_US"; Category="Collaboration" },
  @{ Name="Zoom"; Url="https://www.zoomstatus.com/"; Category="Collaboration" },

  # Dev / Work Management
  @{ Name="Atlassian"; Url="https://status.atlassian.com/"; Category="Dev & Work Mgmt" },
  @{ Name="Asana"; Url="https://status.asana.com/"; Category="Dev & Work Mgmt" },
  @{ Name="Monday.com"; Url="https://status.monday.com/"; Category="Dev & Work Mgmt" },
  @{ Name="Lucid"; Url="https://status.lucid.co/"; Category="Dev & Work Mgmt" },
  @{ Name="GitHub"; Url="https://www.githubstatus.com/"; Category="Dev & Work Mgmt" },

  # Endpoint / Ops
  @{ Name="Automox"; Url="https://status.automox.us/"; Category="Endpoint & Ops" },
  @{ Name="TeamViewer"; Url="https://status.teamviewer.com/"; Category="Endpoint & Ops" },
  @{ Name="Nexthink (Statuspage)"; Url="https://rxw-nxt.statuspage.io/#"; Category="Endpoint & Ops" },

  # Security
  @{ Name="Palo Alto Networks"; Url="https://status.paloaltonetworks.com/"; Category="Security" },
  @{ Name="Proofpoint"; Url="https://proofpointstatus.com/"; Category="Security" },
  @{ Name="Wiz"; Url="https://status.wiz.io/"; Category="Security" },

  # Infrastructure / Network
  @{ Name="AWS (Health Dashboard)"; Url="https://health.aws.amazon.com"; Category="Infrastructure" },
  @{ Name="Azure Status"; Url="https://azure.status.microsoft/en-us/status"; Category="Infrastructure" },
  @{ Name="Meraki"; Url="https://status.meraki.net/"; Category="Infrastructure" },

  # SaaS / Business Apps
  @{ Name="1Password"; Url="https://status.1password.com/"; Category="SaaS Apps" },
  @{ Name="Adobe"; Url="https://status.adobe.com/"; Category="SaaS Apps" },
  @{ Name="Freshservice Updates"; Url="https://updates.freshservice.com/"; Category="SaaS Apps" },
  @{ Name="Genesys Cloud"; Url="https://status.mypurecloud.com/"; Category="SaaS Apps" },
  @{ Name="LinkedIn"; Url="https://www.linkedin-status.com/"; Category="SaaS Apps" },
  @{ Name="Salesforce"; Url="https://status.salesforce.com/current"; Category="SaaS Apps" },

  # Internal / Custom
  @{ Name="ServiceNow (iCapital test)"; Url="https://icapitaltest.service-now.com/esc?id=service_status"; Category="Internal" },
  @{ Name="Splunk System Status"; Url="https://www.splunk.com/en_us/products/system-status.html"; Category="Internal" }
)

# ---------------------------
# Helpers
# ---------------------------
function Ensure-Folder {
  param([string]$Path)
  if (-not (Test-Path $Path)) { New-Item -ItemType Directory -Path $Path | Out-Null }
}

function Write-Log {
  param(
    [Parameter(Mandatory)] [ValidateSet("INFO","WARN","ERROR")] [string]$Level,
    [Parameter(Mandatory)] [string]$Message,
    [hashtable]$Data
  )
  $ts = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss.fff")
  $line = "[$ts] [$Level] $Message"
  Add-Content -Path (Join-Path $LogPath "VendorStatusMonitor.log") -Value $line -Encoding UTF8

  $evt = [ordered]@{
    ts     = $ts
    level  = $Level
    msg    = $Message
    data   = $Data
  }
  ($evt | ConvertTo-Json -Depth 8 -Compress) |
    Add-Content -Path (Join-Path $LogPath "VendorStatusMonitor.jsonl") -Encoding UTF8
}

function Rotate-OldFiles {
  param([string]$Folder, [int]$KeepDays)
  if (-not (Test-Path $Folder)) { return }
  Get-ChildItem -Path $Folder -File -ErrorAction SilentlyContinue |
    Where-Object { $_.LastWriteTime -lt (Get-Date).AddDays(-$KeepDays) } |
    ForEach-Object {
      try { Remove-Item -LiteralPath $_.FullName -Force -ErrorAction Stop }
      catch { }
    }
}

function Get-StatusColor {
  param([string]$Status)
  switch ($Status) {
    "Operational" { "2EB886" } # green
    "Degraded"    { "F2C744" } # yellow
    "Major"       { "E02F44" } # red
    "Critical"    { "6E0B14" } # dark red
    default       { "808080" }
  }
}

function Get-StatusEmoji {
  param([string]$Status)
  switch ($Status) {
    "Operational" { "✅" }
    "Degraded"    { "⚠️" }
    "Major"       { "🔴" }
    "Critical"    { "⛔" }
    default       { "❔" }
  }
}

function Send-TeamsAlert {
  param(
    [Parameter(Mandatory)] [pscustomobject]$Vendor,
    [Parameter(Mandatory)] [string]$PreviousStatus
  )

  if ([string]::IsNullOrWhiteSpace($TeamsWebhookUrl) -or $TeamsWebhookUrl -like "PASTE_*") {
    Write-Log -Level "WARN" -Message "Teams webhook not configured; skipping alert." -Data @{ vendor=$Vendor.name }
    return
  }

  $emoji = Get-StatusEmoji -Status $Vendor.status
  $color = Get-StatusColor -Status $Vendor.status
  $title = "$emoji Status change: $($Vendor.name) ($($Vendor.category))"

  $facts = @(
    @{ name="Platform"; value=$Vendor.name },
    @{ name="Category"; value=$Vendor.category },
    @{ name="Previous"; value=$PreviousStatus },
    @{ name="Current"; value=$Vendor.status },
    @{ name="Reachable"; value=($Vendor.reachable) },
    @{ name="HTTP"; value=($Vendor.http_code ?? "N/A") },
    @{ name="Latency (ms)"; value=($Vendor.latency_ms ?? "N/A") }
  )

  $payload = @{
    "@type"    = "MessageCard"
    "@context" = "http://schema.org/extensions"
    "summary"  = "Vendor status change"
    "themeColor" = $color
    "title"    = $title
    "sections" = @(
      @{
        "markdown" = $true
        "text"     = "[$($Vendor.url)]($($Vendor.url))"
        "facts"    = $facts
      }
    )
  }

  try {
    Invoke-RestMethod -Method Post -Uri $TeamsWebhookUrl -ContentType "application/json" -Body ($payload | ConvertTo-Json -Depth 8)
    Write-Log -Level "INFO" -Message "Teams alert sent." -Data @{ vendor=$Vendor.name; from=$PreviousStatus; to=$Vendor.status }
  }
  catch {
    Write-Log -Level "ERROR" -Message "Failed to send Teams alert." -Data @{ vendor=$Vendor.name; error=$_.Exception.Message }
  }
}

function Test-Vendor {
  param([hashtable]$Vendor)

  $url = $Vendor.Url
  $u = [System.Uri]$url
  $hostName = $u.Host

  $reachable = $false
  $latency = $null
  $http = $null
  $status = "Operational"
  $errorMsg = $null

  # TCP check (works even if ICMP is blocked)
  $tcpOk = $false
  try {
    $tcpOk = Test-NetConnection -ComputerName $hostName -Port 443 -InformationLevel Quiet -WarningAction SilentlyContinue
  } catch { $tcpOk = $false }

  if (-not $tcpOk) {
    return [pscustomobject]@{
      name=$Vendor.Name; category=$Vendor.Category; url=$url
      reachable=$false; latency_ms=$null; http_code=$null
      status="Critical"; error="TCP 443 unreachable"
    }
  }

  # HTTP check (fast HEAD first, fallback GET if needed)
  try {
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    try {
      $r = Invoke-WebRequest -Uri $url -Method Head -UseBasicParsing -TimeoutSec $TimeoutSec -MaximumRedirection 2
    } catch {
      $r = Invoke-WebRequest -Uri $url -UseBasicParsing -TimeoutSec $TimeoutSec -MaximumRedirection 2
    }
    $sw.Stop()

    $latency = $sw.ElapsedMilliseconds
    $http = [int]$r.StatusCode
    $reachable = $true

    if ($http -ge $MajorHttpMin) { $status = "Major" }
    elseif ($http -ge $WarnHttpMin) { $status = "Degraded" }
    elseif ($latency -ge $DegradedLatency) { $status = "Degraded" }
    else { $status = "Operational" }
  }
  catch {
    $status = "Critical"
    $errorMsg = $_.Exception.Message
  }

  [pscustomobject]@{
    name=$Vendor.Name; category=$Vendor.Category; url=$url
    reachable=$reachable; latency_ms=$latency; http_code=$http
    status=$status; error=$errorMsg
  }
}

# ---------------------------
# Main
# ---------------------------
Ensure-Folder $BasePath
Ensure-Folder $DataPath
Ensure-Folder $LogPath
Ensure-Folder $TxPath

Rotate-OldFiles -Folder $TxPath  -KeepDays $KeepTranscriptDays
Rotate-OldFiles -Folder $LogPath -KeepDays $KeepLogDays

$runId = [guid]::NewGuid().ToString()
$txFile = Join-Path $TxPath ("VendorStatusMonitor_{0}_{1}.txt" -f (Get-Date -Format "yyyyMMdd_HHmmss"), $env:COMPUTERNAME)

Start-Transcript -Path $txFile -IncludeInvocationHeader | Out-Null  # documented transcript logging [6](https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.host/start-transcript?view=powershell-7.5)
Write-Log -Level "INFO" -Message "Run started." -Data @{ runId=$runId; computer=$env:COMPUTERNAME; user=$env:USERNAME }

try {
  $results = foreach ($v in $Vendors) {
    $res = Test-Vendor -Vendor $v
    Write-Log -Level "INFO" -Message "Checked vendor." -Data @{ runId=$runId; vendor=$res.name; status=$res.status; http=$res.http_code; latency=$res.latency_ms }
    $res
  }

  $current = @{
    generated = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    runId     = $runId
    vendors   = $results
  }

  $current | ConvertTo-Json -Depth 8 | Out-File -FilePath $StatusFile -Encoding UTF8

  # Change detection + Teams alerts
  if (Test-Path $LastStatusFile) {
    $prev = Get-Content $LastStatusFile -Raw | ConvertFrom-Json
    foreach ($r in $results) {
      $old = $prev.vendors | Where-Object { $_.name -eq $r.name } | Select-Object -First 1
      if ($null -ne $old -and $old.status -ne $r.status) {
        Write-Log -Level "WARN" -Message "Status changed." -Data @{ vendor=$r.name; from=$old.status; to=$r.status; runId=$runId }
        Send-TeamsAlert -Vendor $r -PreviousStatus $old.status
      }
    }
  }

  $current | ConvertTo-Json -Depth 8 | Out-File -FilePath $LastStatusFile -Encoding UTF8

  Write-Log -Level "INFO" -Message "Run completed successfully." -Data @{ runId=$runId; vendors=$results.Count }
}
catch {
  Write-Log -Level "ERROR" -Message "Run failed." -Data @{ runId=$runId; error=$_.Exception.Message }
  throw
}
finally {
  Stop-Transcript | Out-Null
}

# --- SIGNATURE WILL BE APPENDED BELOW BY Set-AuthenticodeSignature ---