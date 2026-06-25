# ================================
# Vendor Status Monitor + Teams Alerts
# ================================

$BasePath        = "C:\NOC"
$StatusPath      = "$BasePath\status.json"
$LastStatusPath  = "$BasePath\last-status.json"
$TeamsWebhookUrl = "PASTE_TEAMS_WEBHOOK_URL_HERE"

$Timestamp = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")

$Vendors = @(
    @{ Name="Okta"; Url="https://status.okta.com"; Category="Identity" },
    @{ Name="Microsoft 365"; Url="https://status.cloud.microsoft"; Category="Collaboration" },
    @{ Name="Zoom"; Url="https://www.zoomstatus.com"; Category="Collaboration" },
    @{ Name="GitHub"; Url="https://www.githubstatus.com"; Category="Developer Tools" },
    @{ Name="Palo Alto Networks"; Url="https://status.paloaltonetworks.com"; Category="Security" },
    @{ Name="AWS"; Url="https://health.aws.amazon.com"; Category="Infrastructure" }
)

if (!(Test-Path $BasePath)) {
    New-Item -ItemType Directory -Path $BasePath | Out-Null
}

$Results = @()

foreach ($Vendor in $Vendors) {
    $Latency = $null
    $Reachable = $false
    $HttpCode = $null
    $Status = "Operational"

    try {
        $uri = [System.Uri]$Vendor.Url
        $ping = Test-NetConnection -ComputerName $uri.Host -InformationLevel Quiet -WarningAction SilentlyContinue

        if ($ping) {
            $sw = [System.Diagnostics.Stopwatch]::StartNew()
            $resp = Invoke-WebRequest -Uri $Vendor.Url -UseBasicParsing -TimeoutSec 5
            $sw.Stop()

            $Latency = $sw.ElapsedMilliseconds
            $HttpCode = $resp.StatusCode
            $Reachable = $true

            if ($HttpCode -ge 500) {
                $Status = "Major"
            }
            elseif ($Latency -gt 2000) {
                $Status = "Degraded"
            }
        }
        else {
            $Status = "Critical"
        }
    }
    catch {
        $Status = "Critical"
    }

    $Results += [PSCustomObject]@{
        name       = $Vendor.Name
        category   = $Vendor.Category
        url        = $Vendor.Url
        reachable  = $Reachable
        latency_ms = $Latency
        http_code  = $HttpCode
        status     = $Status
    }
}

# Save current status
$CurrentState = @{
    generated = $Timestamp
    vendors   = $Results
}

$CurrentState | ConvertTo-Json -Depth 5 | Out-File $StatusPath -Encoding UTF8

# ================================
# Status Change Detection
# ================================

if (Test-Path $LastStatusPath) {
    $Previous = Get-Content $LastStatusPath | ConvertFrom-Json

    foreach ($Vendor in $Results) {
        $PrevVendor = $Previous.vendors | Where-Object { $_.name -eq $Vendor.name }

        if ($PrevVendor -and $PrevVendor.status -ne $Vendor.status) {

            # Severity emoji
            $Emoji = switch ($Vendor.status) {
                "Operational" { "✅" }
                "Degraded"    { "⚠️" }
                "Major"       { "🔴" }
                "Critical"    { "⛔" }
            }

            # Teams message
            $TeamsPayload = @{
                "@type" = "MessageCard"
                "@context" = "http://schema.org/extensions"
                "summary" = "Platform Status Change"
                "themeColor" = "FF0000"
                "title" = "$Emoji Platform Status Change"
                "sections" = @(
                    @{
                        "facts" = @(
                            @{ "name" = "Platform"; "value" = $Vendor.name },
                            @{ "name" = "Category"; "value" = $Vendor.category },
                            @{ "name" = "Previous Status"; "value" = $PrevVendor.status },
                            @{ "name" = "Current Status"; "value" = $Vendor.status },
                            @{ "name" = "Latency (ms)"; "value" = ($Vendor.latency_ms ?? "N/A") },
                            @{ "name" = "HTTP Code"; "value" = ($Vendor.http_code ?? "N/A") }
                        )
                        "markdown" = $true
                    }
                )
            }

            Invoke-RestMethod -Method Post `
                -Uri $TeamsWebhookUrl `
                -ContentType "application/json" `
                -Body ($TeamsPayload | ConvertTo-Json -Depth 5)
        }
    }
}

# Persist state for next comparison
$CurrentState | ConvertTo-Json -Depth 5 | Out-File $LastStatusPath -Encoding UTF8
