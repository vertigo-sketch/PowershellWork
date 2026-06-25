
<#
.SYNOPSIS
    Network Connection Diagnostic Script
.DESCRIPTION
    Tests various network connectivity issues that could cause connection failures
    similar to those observed in Nexthink monitoring data.
.AUTHOR
    IT Diagnostics Team
.VERSION
    1.0
#>

param(
    [string[]]$TestHosts = @("nexthink.com", "microsoft.com", "google.com"),
    [int[]]$TestPorts = @(443, 80, 53, 1194, 500, 4500, 1723),
    [string]$LogPath = "C:\Temp\NetworkDiagnostics_$(Get-Date -Format 'yyyyMMdd_HHmmss').txt",
    [int]$TimeoutSeconds = 10,
    [switch]$Detailed
)

# Initialize results
$Results = @()
$StartTime = Get-Date

Write-Host "=== Network Connection Diagnostics ===" -ForegroundColor Cyan
Write-Host "Started: $StartTime" -ForegroundColor Green
Write-Host "Log file: $LogPath" -ForegroundColor Yellow
Write-Host ""

# Function to log results
function Write-Log {
    param([string]$Message, [string]$Level = "INFO")
    $Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $LogEntry = "[$Timestamp] [$Level] $Message"
    Write-Host $LogEntry
    Add-Content -Path $LogPath -Value $LogEntry
}

# Function to test TCP connection
function Test-TCPConnection {
    param(
        [string]$Hostname,
        [int]$Port,
        [int]$Timeout = 5000
    )
    
    try {
        $tcpClient = New-Object System.Net.Sockets.TcpClient
        $connect = $tcpClient.BeginConnect($Hostname, $Port, $null, $null)
        $wait = $connect.AsyncWaitHandle.WaitOne($Timeout, $false)
        
        if ($wait) {
            try {
                $tcpClient.EndConnect($connect)
                $result = @{
                    Success = $true
                    Error = $null
                    ResponseTime = $null
                }
            }
            catch {
                $result = @{
                    Success = $false
                    Error = $_.Exception.Message
                    ResponseTime = $null
                }
            }
        }
        else {
            $result = @{
                Success = $false
                Error = "Connection timeout"
                ResponseTime = $null
            }
        }
        
        $tcpClient.Close()
        return $result
    }
    catch {
        return @{
            Success = $false
            Error = $_.Exception.Message
            ResponseTime = $null
        }
    }
}

# Function to test DNS resolution
function Test-DNSResolution {
    param([string]$Hostname)
    
    try {
        $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
        $dnsResult = [System.Net.Dns]::GetHostAddresses($Hostname)
        $stopwatch.Stop()
        
        return @{
            Success = $true
            IPAddresses = $dnsResult | ForEach-Object { $_.IPAddressToString }
            ResponseTime = $stopwatch.ElapsedMilliseconds
            Error = $null
        }
    }
    catch {
        return @{
            Success = $false
            IPAddresses = @()
            ResponseTime = $null
            Error = $_.Exception.Message
        }
    }
}

# Function to test SSL certificate
function Test-SSLCertificate {
    param(
        [string]$Hostname,
        [int]$Port = 443
    )
    
    try {
        $tcpClient = New-Object System.Net.Sockets.TcpClient
        $tcpClient.Connect($Hostname, $Port)
        
        $sslStream = New-Object System.Net.Security.SslStream($tcpClient.GetStream())
        $sslStream.AuthenticateAsClient($Hostname)
        
        $cert = $sslStream.RemoteCertificate
        $cert2 = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2($cert)
        
        $result = @{
            Success = $true
            Subject = $cert2.Subject
            Issuer = $cert2.Issuer
            ValidFrom = $cert2.NotBefore
            ValidTo = $cert2.NotAfter
            IsValid = $cert2.NotAfter -gt (Get-Date)
            Error = $null
        }
        
        $sslStream.Close()
        $tcpClient.Close()
        
        return $result
    }
    catch {
        return @{
            Success = $false
            Subject = $null
            Issuer = $null
            ValidFrom = $null
            ValidTo = $null
            IsValid = $false
            Error = $_.Exception.Message
        }
    }
}

# System Information
Write-Log "=== SYSTEM INFORMATION ===" "INFO"
$computerInfo = Get-ComputerInfo -Property WindowsProductName, WindowsVersion, TotalPhysicalMemory
Write-Log "OS: $($computerInfo.WindowsProductName) $($computerInfo.WindowsVersion)"
Write-Log "RAM: $([math]::Round($computerInfo.TotalPhysicalMemory/1GB, 2)) GB"
Write-Log "Computer: $env:COMPUTERNAME"
Write-Log "User: $env:USERNAME"
Write-Log ""

# Network Adapter Information
Write-Log "=== NETWORK ADAPTERS ===" "INFO"
$adapters = Get-NetAdapter | Where-Object { $_.Status -eq "Up" }
foreach ($adapter in $adapters) {
    $ipConfig = Get-NetIPAddress -InterfaceIndex $adapter.InterfaceIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue
    if ($ipConfig) {
        Write-Log "Adapter: $($adapter.Name) - $($ipConfig.IPAddress)"
    }
}
Write-Log ""

# DNS Configuration
Write-Log "=== DNS CONFIGURATION ===" "INFO"
$dnsServers = Get-DnsClientServerAddress -AddressFamily IPv4 | Where-Object { $_.ServerAddresses.Count -gt 0 }
foreach ($dns in $dnsServers) {
    Write-Log "Interface: $($dns.InterfaceAlias) - DNS: $($dns.ServerAddresses -join ', ')"
}
Write-Log ""

# Firewall Status
Write-Log "=== WINDOWS FIREWALL STATUS ===" "INFO"
try {
    $firewallProfiles = Get-NetFirewallProfile
    foreach ($profile in $firewallProfiles) {
        Write-Log "Profile: $($profile.Name) - Enabled: $($profile.Enabled)"
    }
}
catch {
    Write-Log "Could not retrieve firewall status: $($_.Exception.Message)" "WARN"
}
Write-Log ""

# Proxy Configuration
Write-Log "=== PROXY CONFIGURATION ===" "INFO"
try {
    $proxySettings = Get-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings"
    if ($proxySettings.ProxyEnable -eq 1) {
        Write-Log "Proxy Enabled: Yes"
        Write-Log "Proxy Server: $($proxySettings.ProxyServer)"
        if ($proxySettings.ProxyOverride) {
            Write-Log "Proxy Bypass: $($proxySettings.ProxyOverride)"
        }
    } else {
        Write-Log "Proxy Enabled: No"
    }
}
catch {
    Write-Log "Could not retrieve proxy settings: $($_.Exception.Message)" "WARN"
}
Write-Log ""

# VPN Connection Status
Write-Log "=== VPN CONNECTIONS ===" "INFO"
try {
    $vpnConnections = Get-VpnConnection -ErrorAction SilentlyContinue
    if ($vpnConnections) {
        foreach ($vpn in $vpnConnections) {
            Write-Log "VPN: $($vpn.Name) - Status: $($vpn.ConnectionStatus) - Server: $($vpn.ServerAddress)"
        }
    } else {
        Write-Log "No VPN connections configured"
    }
}
catch {
    Write-Log "Could not retrieve VPN connections: $($_.Exception.Message)" "WARN"
}
Write-Log ""

# Test DNS Resolution
Write-Log "=== DNS RESOLUTION TESTS ===" "INFO"
foreach ($TargetHost in $TestHosts) {
    Write-Host "Testing DNS resolution for $TargetHost..." -ForegroundColor Yellow
    $dnsTest = Test-DNSResolution -Hostname $TargetHost
    
    if ($dnsTest.Success) {
        Write-Log "DNS OK: $TargetHost -> $($dnsTest.IPAddresses -join ', ') ($($dnsTest.ResponseTime)ms)" "INFO"
    } else {
        Write-Log "DNS FAIL: $TargetHost - $($dnsTest.Error)" "ERROR"
    }
}
Write-Log ""

# Test TCP Connections
Write-Log "=== TCP CONNECTION TESTS ===" "INFO"
$connectionTests = @()

foreach ($TargetHost in $TestHosts) {
    foreach ($port in $TestPorts) {
        Write-Host "Testing TCP connection to ${TargetHost}:${port}..." -ForegroundColor Yellow
        
        $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
        $tcpTest = Test-TCPConnection -Hostname $TargetHost -Port $port -Timeout ($TimeoutSeconds * 1000)
        $stopwatch.Stop()
        
        $testResult = [PSCustomObject]@{
            Host = $TargetHost
            Port = $port
            Success = $tcpTest.Success
            ResponseTime = $stopwatch.ElapsedMilliseconds
            Error = $tcpTest.Error
        }
        
        $connectionTests += $testResult
        
        if ($tcpTest.Success) {
            Write-Log "TCP OK: ${TargetHost}:${port} ($($stopwatch.ElapsedMilliseconds)ms)" "INFO"
        } else {
            Write-Log "TCP FAIL: ${TargetHost}:${port} - $($tcpTest.Error)" "ERROR"
        }
    }
}
Write-Log ""

# Test SSL Certificates (for HTTPS hosts)
Write-Log "=== SSL CERTIFICATE TESTS ===" "INFO"
foreach ($TargetHost in $TestHosts) {
    Write-Host "Testing SSL certificate for $TargetHost..." -ForegroundColor Yellow
    $sslTest = Test-SSLCertificate -Hostname $TargetHost -Port 443
    
    if ($sslTest.Success) {
        $validStatus = if ($sslTest.IsValid) { "Valid" } else { "EXPIRED" }
        Write-Log "SSL OK: $TargetHost - $($sslTest.Subject) - $validStatus until $($sslTest.ValidTo)" "INFO"
    } else {
        Write-Log "SSL FAIL: $TargetHost - $($sslTest.Error)" "ERROR"
    }
}
Write-Log ""

# Network Route Tests
Write-Log "=== NETWORK ROUTE TESTS ===" "INFO"
foreach ($TargetHost in $TestHosts) {
    Write-Host "Testing route to $TargetHost..." -ForegroundColor Yellow
    try {
        $route = Test-NetConnection -ComputerName $TargetHost -Port 443 -InformationLevel Detailed -WarningAction SilentlyContinue
        if ($route.TcpTestSucceeded) {
            Write-Log "ROUTE OK: $TargetHost - $($route.RemoteAddress) via $($route.InterfaceAlias)" "INFO"
        } else {
            Write-Log "ROUTE FAIL: $TargetHost - Could not establish route" "ERROR"
        }
    }
    catch {
        Write-Log "ROUTE ERROR: $TargetHost - $($_.Exception.Message)" "ERROR"
    }
}
Write-Log ""

# Summary Statistics
Write-Log "=== SUMMARY STATISTICS ===" "INFO"
$totalTests = $connectionTests.Count
$successfulTests = ($connectionTests | Where-Object { $_.Success }).Count
$failedTests = $totalTests - $successfulTests
$successRate = if ($totalTests -gt 0) { [math]::Round(($successfulTests / $totalTests) * 100, 2) } else { 0 }

Write-Log "Total connection tests: $totalTests"
Write-Log "Successful connections: $successfulTests"
Write-Log "Failed connections: $failedTests"
Write-Log "Success rate: $successRate%"

if ($failedTests -gt 0) {
    Write-Log ""
    Write-Log "=== FAILED CONNECTIONS DETAIL ===" "ERROR"
    $failedConnections = $connectionTests | Where-Object { -not $_.Success }
    foreach ($failed in $failedConnections) {
        Write-Log "FAILED: $($failed.Host):$($failed.Port) - $($failed.Error)" "ERROR"
    }
}

# Performance Analysis
if ($Detailed) {
    Write-Log ""
    Write-Log "=== PERFORMANCE ANALYSIS ===" "INFO"
    $slowConnections = $connectionTests | Where-Object { $_.Success -and $_.ResponseTime -gt 1000 }
    if ($slowConnections) {
        Write-Log "Slow connections (>1000ms):"
        foreach ($slow in $slowConnections) {
            Write-Log "SLOW: $($slow.Host):$($slow.Port) - $($slow.ResponseTime)ms" "WARN"
        }
    } else {
        Write-Log "No slow connections detected"
    }
}

# Recommendations
Write-Log ""
Write-Log "=== RECOMMENDATIONS ===" "INFO"

if ($failedTests -gt ($totalTests * 0.1)) {
    Write-Log "HIGH FAILURE RATE DETECTED ($successRate% success)" "WARN"
    Write-Log "- Check network connectivity and DNS resolution"
    Write-Log "- Verify firewall and proxy settings"
    Write-Log "- Contact network administrator if issues persist"
}

$dnsFailures = $TestHosts | ForEach-Object { Test-DNSResolution -Hostname $_ } | Where-Object { -not $_.Success }
if ($dnsFailures) {
    Write-Log "DNS RESOLUTION ISSUES DETECTED" "WARN"
    Write-Log "- Try alternative DNS servers (8.8.8.8, 1.1.1.1)"
    Write-Log "- Flush DNS cache: ipconfig /flushdns"
}

$EndTime = Get-Date
$Duration = $EndTime - $StartTime
Write-Log ""
Write-Log "=== DIAGNOSTIC COMPLETE ===" "INFO"
Write-Log "Duration: $($Duration.TotalSeconds) seconds"
Write-Log "Results saved to: $LogPath"

# Open log file
if (Test-Path $LogPath) {
    Write-Host ""
    Write-Host "Opening log file..." -ForegroundColor Green
    Start-Process notepad.exe -ArgumentList $LogPath
}
