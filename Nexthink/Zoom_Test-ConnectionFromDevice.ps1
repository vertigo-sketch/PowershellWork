<#
.SYNOPSIS
Verifies if connection from target device to provided domain/port is possible.

.DESCRIPTION
Performs connection test using ICMP protocol, and also the TCP connection to target destination. Allows a destination in a IPv4 or domain name format. Please be aware that the port must be specified.

.FUNCTIONALITY
On-demand

.INPUTS
ID  Label                           Description
1   MaximumDelayInSeconds           Maximum random delay set to avoid overloading target destination with too many connections. Provide number of seconds less than 600
2   Destination                     Destination name, accepted values are IPv4 addresses and domain names. Port can be optionally specified after a colon. Examples are "192.168.1.1", "www.nexthink.com:443", "www.google.com:80"
3   TimeoutInMilliseconds           Default value of tested connection timeout. Should be adjusted, depending on the performance of tested network route. Provide number of milliseconds between (1000, 60000)

.OUTPUTS
ID  Label                           Type            Description
1   ReachableOverICMP               Bool            Result of a connection test using ICMP protocol from a device to given destination
2   ReachableOverTCP                Bool            Result of a connection test using TCP protocol from a device to given destination
3   ResponseTime                    Millisecond     Time in milliseconds that a web request takes to reach the caller
4   PacketLoss                      Ratio           Percentage of packets that are lost during a client/server two way communication

.FURTHER INFORMATION
Connection is performed using system account. In scenarios with web proxy authentication test may result in fail due to denied access.

.NOTES
Context:            LocalSystem
Version:            2.0.4.2 - Updated description for 'Destination' output parameter and refactored code
                    2.0.4.1 - Updated description
                    2.0.4.0 - Remote Action code enhancement
                    2.0.3.1 - Removed the default execution triggers for API and Manual
                    2.0.2.1 - Fixed typo on documentation
                    2.0.2.0 - Updated output datatypes
                    2.0.1.0 - Fixed constant format issue
                    2.0.0.0 - Added new outputs and adapted the Remote Action to parametrization
                    1.0.2.0 - Fixed documentation
                    1.0.1.0 - Fixed issue with incorrect connection test result
                    1.0.0.0 - Initial release
Last Generated:     22 Sep 2025 - 08:07:34
Copyright (C) 2025 Nexthink SA, Switzerland
#>

#
# Input parameters definition
#
param(
    [Parameter(Mandatory = $true)][string]$MaximumDelayInSeconds,
    [Parameter(Mandatory = $true)][string]$Destination,
    [Parameter(Mandatory = $true)][string]$TimeoutInMilliseconds
)
# End of parameters definition

$env:Path = "$env:SystemRoot\system32;$env:SystemRoot;$env:SystemRoot\System32\Wbem;$env:SystemRoot\System32\WindowsPowerShell\v1.0\"

#
# Constants definition
#
$ERROR_EXCEPTION_TYPE = @{Environment = '[Environment error]'
    Input = '[Input error]'
    Internal = '[Internal error]'
}
Set-Variable -Name 'ERROR_EXCEPTION_TYPE' -Option ReadOnly -Scope Script -Force

$LOCAL_SYSTEM_IDENTITY = 'S-1-5-18'
Set-Variable -Name 'LOCAL_SYSTEM_IDENTITY' -Option ReadOnly -Scope Script -Force

$MAX_SCRIPT_DELAY_SEC = 600
Set-Variable -Name 'MAX_SCRIPT_DELAY_SEC' -Option ReadOnly -Scope Script -Force

$PORT_FORMAT_REGEX = "^\d{1,5}$"
Set-Variable -Name 'PORT_FORMAT_REGEX' -Option ReadOnly -Scope Script -Force

$PORT_REGEX = "^([1-9]|[1-5]?[\d]{2,4}|6[1-4][\d]{3}|65[1-4][\d]{2}|655[1-2][\d]|6553[1-5])$"
Set-Variable -Name 'PORT_REGEX' -Option ReadOnly -Scope Script -Force

$REMOTE_ACTION_DLL_PATH = "$env:NEXTHINK\RemoteActions\nxtremoteactions.dll"
Set-Variable -Name 'REMOTE_ACTION_DLL_PATH' -Option ReadOnly -Scope Script -Force

$WINDOWS_VERSIONS = @{Windows7 = '6.1'
    Windows8 = '6.2'
    Windows81 = '6.3'
    Windows10 = '10.0'
    Windows11 = '10.0'
}
Set-Variable -Name 'WINDOWS_VERSIONS' -Option ReadOnly -Scope Script -Force


$LOG_REMOTE_ACTION_NAME = 'Test-ConnectionFromDevice'
Set-Variable -Name 'LOG_REMOTE_ACTION_NAME' -Option ReadOnly -Scope Script -Force

$MIN_TIMEOUT_MS = 1000
Set-Variable -Name 'MIN_TIMEOUT_MS' -Option ReadOnly -Scope Script -Force

$MAX_TIMEOUT_MS = 60000
Set-Variable -Name 'MAX_TIMEOUT_MS' -Option ReadOnly -Scope Script -Force

$CONNECTION_PING_COUNT = 10
Set-Variable -Name 'CONNECTION_PING_COUNT' -Option ReadOnly -Scope Script -Force

#
# Invoke Main
#
function Invoke-Main ([hashtable]$InputParameters) {
    Start-NxtLogging -RemoteActionName $LOG_REMOTE_ACTION_NAME

    $exitCode = 0
    [hashtable]$outputs = Initialize-Output

    try {
        Add-NexthinkRemoteActionDLL

        Test-RunningAsLocalSystem
        Test-MinimumSupportedOSVersion -WindowsVersion 'Windows10'
        Test-InputParameters -InputParameters $InputParameters

        $outputs = Update-Connection -InputParameters $InputParameters
    } catch {
        Write-StatusMessage -Message $_
        $exitCode = 1
    } finally {
        Update-EngineOutputVariables -Outputs $outputs
        Stop-NxtLogging -Result $exitCode
    }

    return $exitCode
}

#
# Template functions
#
function Start-NxtLogging ([string]$RemoteActionName) {
    if (Test-PowerShellVersion -MinimumVersion 5) {
        $logFile = "$(Get-LogPath)$RemoteActionName.log"

        Start-NxtLogRotation -LogFile $logFile
        Start-Transcript -Path $logFile -Append | Out-Null
        Write-NxtLog -Message "Running Remote Action $RemoteActionName"
    }
}

function Test-PowerShellVersion ([int]$MinimumVersion) {
    if ((Get-Host).Version.Major -ge $MinimumVersion) {
        return $true
    }
}

function Get-LogPath {

    if (Confirm-CurrentUserIsLocalSystem) {
        return "$env:ProgramData\Nexthink\RemoteActions\Logs\"
    }
    return "$env:LocalAppData\Nexthink\RemoteActions\Logs\"
}

function Confirm-CurrentUserIsLocalSystem {

    $currentIdentity = Get-CurrentIdentity
    return $currentIdentity -eq $LOCAL_SYSTEM_IDENTITY
}

function Get-CurrentIdentity {

    return [security.principal.windowsidentity]::GetCurrent().User.ToString()
}

function Start-NxtLogRotation ([string]$LogFile) {
    if (Test-Path -Path $LogFile) {
        $logSize = (Get-Item -Path $LogFile).Length
        if ($logSize -gt 1000000) {
            Remove-Item -Path "$($LogFile).001" -Force -ErrorAction SilentlyContinue
            Rename-Item -Path $LogFile -NewName "$($LogFile).001" -Force
        }
    }
}

function Write-NxtLog ([string]$Message, [object]$Object) {
    if (Test-PowerShellVersion -MinimumVersion 5) {
        $currentDate = Get-Date -Format 'yyyy/MM/dd hh:mm:ss'
        if ($Object) {
            $jsonObject = $Object | ConvertTo-Json -Compress -Depth 100
            Write-Information -MessageData "$currentDate - $Message $jsonObject"
        } else {
            Write-Information -MessageData "$currentDate - $Message"
        }
    }
}

function Add-NexthinkRemoteActionDLL {

    if (-not (Test-Path -Path $REMOTE_ACTION_DLL_PATH)) {
        throw "$($ERROR_EXCEPTION_TYPE.Environment) Nexthink Remote Action DLL not found. "
    }
    Add-Type -Path $REMOTE_ACTION_DLL_PATH
}

function Test-RunningAsLocalSystem {

    if (-not (Confirm-CurrentUserIsLocalSystem)) {
        throw "$($ERROR_EXCEPTION_TYPE.Environment) This script must be run as LocalSystem. "
    }
}

function Test-MinimumSupportedOSVersion ([string]$WindowsVersion, [switch]$SupportedWindowsServer) {
    $currentOSInfo = Get-OSVersionType
    $OSVersion = $currentOSInfo.Version -as [version]

    $supportedWindows = $WINDOWS_VERSIONS.$WindowsVersion -as [version]

    if (-not ($currentOSInfo)) {
        throw "$($ERROR_EXCEPTION_TYPE.Environment) This script could not return OS version. "
    }

    if ( $SupportedWindowsServer -eq $false -and $currentOSInfo.ProductType -ne 1) {
        throw "$($ERROR_EXCEPTION_TYPE.Environment) This script is not compatible with Windows Servers. "
    }

    if ( $OSVersion -lt $supportedWindows) {
        throw "$($ERROR_EXCEPTION_TYPE.Environment) This script is compatible with $WindowsVersion and later only. "
    }
}

function Get-OSVersionType {

    return Get-WindowsManagementData -Class Win32_OperatingSystem | Select-Object -Property Version,ProductType
}

function Get-WindowsManagementData ([string]$Class, [string]$Namespace = 'root/cimv2') {
    try {
        $query = [wmisearcher] "Select * from $Class"
        $query.Scope.Path = "$Namespace"
        $query.Get()
    } catch {
        throw "$($ERROR_EXCEPTION_TYPE.Environment) Error getting CIM/WMI information for class '$Class' in namespace '$Namespace'. Verify WinMgmt service status and WMI repository consistency."
    }
}

function Write-StatusMessage ([psobject]$Message) {
    $exceptionMessage = $Message.ToString()

    if ($Message.InvocationInfo.ScriptLineNumber) {
        $version = Get-ScriptVersion
        if (-not [string]::IsNullOrEmpty($version)) {
            $scriptVersion = "Version: $version. "
        }

        $errorMessageLine = $scriptVersion + "Line '$($Message.InvocationInfo.ScriptLineNumber)': "
    }

    $host.ui.WriteErrorLine($errorMessageLine + $exceptionMessage)
}

function Get-ScriptVersion {

    $scriptContent = Get-Content $MyInvocation.ScriptName | Out-String
    if ($scriptContent -notmatch '<#[\r\n]{2}.SYNOPSIS[^\#\>]*(.NOTES[^\#\>]*)\#>') { return }

    $helpBlock = $Matches[1].Split([environment]::NewLine)

    foreach ($line in $helpBlock) {
        if ($line -match 'Version:') {
            return $line.Split(':')[1].Split('-')[0].Trim()
        }
    }
}

function Stop-NxtLogging ([string]$Result) {
    if (Test-PowerShellVersion -MinimumVersion 5) {
        if ($Result -eq 0) {
            Write-NxtLog -Message 'Remote Action execution was successful'
        } else {
            Write-NxtLog -Message 'Remote Action execution failed'
        }
        Stop-Transcript | Out-Null
    }
}

function Test-ParamInAllowedRange ([string]$ParamName, [string]$ParamValue, [int]$LowerLimit, [int]$UpperLimit) {
    Test-ParamIsInteger -ParamName $ParamName -ParamValue $ParamValue
    $intValue = $ParamValue -as [int]
    if ($intValue -lt $LowerLimit -or $intValue -gt $UpperLimit) {
        throw "$($ERROR_EXCEPTION_TYPE.Input) Error in parameter '$ParamName'. It must be between [$LowerLimit, $UpperLimit]. "
    }
}

function Test-ParamIsInteger ([string]$ParamName, [string]$ParamValue) {
    $intValue = $ParamValue -as [int]
    if ([string]::IsNullOrEmpty($ParamValue) -or $null -eq $intValue) {
        throw "$($ERROR_EXCEPTION_TYPE.Input) Error in parameter '$ParamName'. '$ParamValue' is not an integer. "
    }
}

function Test-PortInRange ([string]$ParamName, [string]$ParamValue) {
    if ($ParamValue -notmatch $PORT_FORMAT_REGEX) { throw "$($ERROR_EXCEPTION_TYPE.Input) Error in parameter '$ParamName'. Invalid port '$ParamValue', unexpected format. " }
    if ($ParamValue -notmatch $PORT_REGEX) { throw "$($ERROR_EXCEPTION_TYPE.Input) Error in parameter '$ParamName'. Invalid port '$ParamValue', not in range (1-65535)" }
}

function Test-IsValidIpOrDomain ([string]$ParamName, [string]$ParamValue) {
    if (-not (Test-IPAddressInRange -Value $ParamValue) -and `
        -not (Test-DomainNameString -Value $ParamValue)) {
        throw "$($ERROR_EXCEPTION_TYPE.Input) Error in parameter $ParamName. '$ParamValue' is not a valid IP or Domain Name. "
    }
}

function Test-IPAddressInRange ([string]$Value) {
    $ipFormatRegex = "^(\-?(\d){1,3}\.){3}\-?(\d){1,3}$"
    $ipv4RangeRegex = "^((?:25[0-5]|2[0-4]\d|[01]?\d{1,2})\.){3}(?:25[0-5]|2[0-4]\d|[01]?\d{1,2})$"

    return $Value -match $ipFormatRegex -and `
           $Value -match $ipv4RangeRegex
}

function Test-DomainNameString ([string]$Value) {
    $domainNameRegex = "^[A-Za-z]([A-Za-z\d]|[A-Za-z\d][\-\.][A-Za-z\d])+[A-Za-z\d]\.[A-Za-z\d]+$"

    return $Value -match $domainNameRegex
}

function Wait-RandomTime ([int]$MaximumDelayInSeconds) {
    if ($MaximumDelayInSeconds -gt 0) {
        $seconds = Get-Random -Minimum 0 -Maximum $MaximumDelayInSeconds
        Start-Sleep -Seconds $seconds
    }
}

function Get-PingStatistics ([string]$Address, [int]$PingCount) {
    [psobject[]]$connectionTestResults = Test-Connection -ComputerName $Address `
                                                         -Count $PingCount `
                                                         -ErrorAction SilentlyContinue

    $average = ($connectionTestResults | Measure-Object -Property ResponseTime -Average).Average
    return @{RoundTripTime = [timespan]::FromMilliseconds($average)
             PacketLossPercentage = 1 - ($connectionTestResults.Length / $PingCount)}
}

function Test-ICMPConnection ([string]$Destination, [int]$Timeout) {
    try {
        $ping = New-Object -TypeName 'net.networkinformation.ping'
        $response = $ping.Send($Destination, $Timeout)
        return $response.Status -eq 'Success'
    } catch {
        return $false
    } finally { $ping.Dispose() }
}

function Test-TCPConnection ([string]$Destination, [int]$Port, [int]$Timeout) {
    try {
        $tcpClient = New-Object -TypeName 'net.sockets.tcpclient'
        $iar = $tcpClient.BeginConnect($Destination, $Port, $null, $null)
        [void]$iar.AsyncWaitHandle.WaitOne($Timeout)

        return $tcpClient.Connected
    } catch {
        return $false
    } finally { $tcpClient.Close() }
}

#
# Input parameter validation
#
function Test-InputParameters ([hashtable]$InputParameters) {
    Write-NxtLog -Message "Calling function $($MyInvocation.MyCommand)"

    Test-ParamInAllowedRange `
        -ParamName 'MaximumDelayInSeconds' `
        -ParamValue $InputParameters.MaximumDelayInSeconds `
        -LowerLimit 0 `
        -UpperLimit $MAX_SCRIPT_DELAY_SEC
    Test-DomainParameter `
        -ParamName 'Destination' `
        -ParamValue $InputParameters.Destination
    Test-ParamInAllowedRange `
        -ParamName 'TimeoutInMilliseconds' `
        -ParamValue $InputParameters.TimeoutInMilliseconds `
        -LowerLimit $MIN_TIMEOUT_MS `
        -UpperLimit $MAX_TIMEOUT_MS
}

function Test-DomainParameter ([string]$ParamName, [string]$ParamValue) {
    Write-NxtLog -Message "Calling function $($MyInvocation.MyCommand)"

    if ([string]::IsNullOrEmpty($ParamValue)) {
        throw "$($ERROR_EXCEPTION_TYPE.Internal)Error on parameter '$ParamName'. Cannot be null or empty. "
    }

    Test-IPDomainPortString -ParamName $ParamName -ParamValue $ParamValue
}

function Test-IPDomainPortString ([string]$ParamName, [string]$ParamValue) {
    Write-NxtLog -Message "Calling function $($MyInvocation.MyCommand)"

    $item = $ParamValue.Split(':')
    if ($item.Count -gt 2) {
        throw "$($ERROR_EXCEPTION_TYPE.Internal) Error on parameter '$ParamName'. Unable to split expected ip/domain:port of item '$ParamValue'. "
    }
    if ($item.Count -eq 2) {
        Test-PortInRange -ParamName $ParamName -ParamValue $item[1]
    }
    Test-IsValidIpOrDomain -ParamName $ParamName -ParamValue $item[0]
}

#
# Invoke-Connection
#
function Initialize-Output {
    Write-NxtLog -Message "Calling function $($MyInvocation.MyCommand)"

    return @{
        ICMP            = $false
        TCP             = $false
        ResponseTime    = [timespan]::FromMilliseconds(0)
        PacketLoss      = [float]0
    }
}

function Update-Connection ([hashtable]$InputParameters) {
    Write-NxtLog -Message "Calling function $($MyInvocation.MyCommand)"
    $output = Initialize-Output
    
    try {
        Wait-RandomTime -MaximumDelayInSeconds $InputParameters.MaximumDelayInSeconds

        $connection = Get-HostnameAndPort -Destination $InputParameters.Destination

        $connectionStatus = Get-ConnectionStatus -Connection $connection `
                                                -Timeout $InputParameters.TimeoutInMilliseconds
        if ($connectionStatus.ICMPConnection) {
            $connectionStatistics = Get-PingStatistics -Address $Connection.Hostname -PingCount $CONNECTION_PING_COUNT

            $output.ResponseTime = $connectionStatistics.RoundTripTime
            $output.PacketLoss = $connectionStatistics.PacketLossPercentage
        }

        $output.ICMP = $connectionStatus.ICMPConnection
        $output.TCP = $connectionStatus.TCPConnection
    }
    catch {
        throw "$($ERROR_EXCEPTION_TYPE.Internal) An error occurred while testing connection from the device to $($InputParameters.Destination) : $($_.Exception.Message)"
    }
    return $output
}

function Get-HostnameAndPort ([string]$Destination) {
    Write-NxtLog -Message "Calling function $($MyInvocation.MyCommand)"

    $connection = @{Hostname = [string]::Empty
                    Port = [string]::Empty}

    $hostname = $Destination
    $port = $null
    if ($Destination -match ':') {
        $hostname, $port = $Destination.Split(':')
    }

    $connection.Hostname = $hostname
    $connection.Port = $port

    return $connection
}

function Get-ConnectionStatus ([hashtable]$Connection, [string]$Timeout) {
    Write-NxtLog -Message "Calling function $($MyInvocation.MyCommand)"

    $connectionStatus = @{ICMPConnection = $false
                          TCPConnection = $false}
    $connectionStatus.ICMPConnection = Test-ICMPConnection -Destination $Connection.Hostname `
                                                           -Timeout $Timeout
    if ($null -ne $Connection.Port) {
        $connectionStatus.TCPConnection = Test-TCPConnection -Destination $Connection.Hostname `
                                                             -Port $Connection.Port `
                                                             -Timeout $Timeout
    }

    return $connectionStatus
}

#
# Nexthink Output management
#
function Update-EngineOutputVariables ([hashtable]$Outputs) {
    Write-NxtLog -Message "Calling function $($MyInvocation.MyCommand)"

    [nxt]::WriteOutputBool('ReachableOverICMP', $Outputs.ICMP)
    [nxt]::WriteOutputBool('ReachableOverTCP', $Outputs.TCP)
    [nxt]::WriteOutputDuration('ResponseTime', $Outputs.ResponseTime)
    [nxt]::WriteOutputRatio('PacketLoss', $Outputs.PacketLoss)
}

#
# Main script flow
#
[environment]::Exit((Invoke-Main -InputParameters $MyInvocation.BoundParameters))
# SIG # Begin signature block
# MIIumAYJKoZIhvcNAQcCoIIuiTCCLoUCAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCBLEryJ1SRvLbv8
# NAuo4IRRIm8Qiz7b715FI09fW6UQuKCCFAQwggWQMIIDeKADAgECAhAFmxtXno4h
# MuI5B72nd3VcMA0GCSqGSIb3DQEBDAUAMGIxCzAJBgNVBAYTAlVTMRUwEwYDVQQK
# EwxEaWdpQ2VydCBJbmMxGTAXBgNVBAsTEHd3dy5kaWdpY2VydC5jb20xITAfBgNV
# BAMTGERpZ2lDZXJ0IFRydXN0ZWQgUm9vdCBHNDAeFw0xMzA4MDExMjAwMDBaFw0z
# ODAxMTUxMjAwMDBaMGIxCzAJBgNVBAYTAlVTMRUwEwYDVQQKEwxEaWdpQ2VydCBJ
# bmMxGTAXBgNVBAsTEHd3dy5kaWdpY2VydC5jb20xITAfBgNVBAMTGERpZ2lDZXJ0
# IFRydXN0ZWQgUm9vdCBHNDCCAiIwDQYJKoZIhvcNAQEBBQADggIPADCCAgoCggIB
# AL/mkHNo3rvkXUo8MCIwaTPswqclLskhPfKK2FnC4SmnPVirdprNrnsbhA3EMB/z
# G6Q4FutWxpdtHauyefLKEdLkX9YFPFIPUh/GnhWlfr6fqVcWWVVyr2iTcMKyunWZ
# anMylNEQRBAu34LzB4TmdDttceItDBvuINXJIB1jKS3O7F5OyJP4IWGbNOsFxl7s
# Wxq868nPzaw0QF+xembud8hIqGZXV59UWI4MK7dPpzDZVu7Ke13jrclPXuU15zHL
# 2pNe3I6PgNq2kZhAkHnDeMe2scS1ahg4AxCN2NQ3pC4FfYj1gj4QkXCrVYJBMtfb
# BHMqbpEBfCFM1LyuGwN1XXhm2ToxRJozQL8I11pJpMLmqaBn3aQnvKFPObURWBf3
# JFxGj2T3wWmIdph2PVldQnaHiZdpekjw4KISG2aadMreSx7nDmOu5tTvkpI6nj3c
# AORFJYm2mkQZK37AlLTSYW3rM9nF30sEAMx9HJXDj/chsrIRt7t/8tWMcCxBYKqx
# YxhElRp2Yn72gLD76GSmM9GJB+G9t+ZDpBi4pncB4Q+UDCEdslQpJYls5Q5SUUd0
# viastkF13nqsX40/ybzTQRESW+UQUOsxxcpyFiIJ33xMdT9j7CFfxCBRa2+xq4aL
# T8LWRV+dIPyhHsXAj6KxfgommfXkaS+YHS312amyHeUbAgMBAAGjQjBAMA8GA1Ud
# EwEB/wQFMAMBAf8wDgYDVR0PAQH/BAQDAgGGMB0GA1UdDgQWBBTs1+OC0nFdZEzf
# Lmc/57qYrhwPTzANBgkqhkiG9w0BAQwFAAOCAgEAu2HZfalsvhfEkRvDoaIAjeNk
# aA9Wz3eucPn9mkqZucl4XAwMX+TmFClWCzZJXURj4K2clhhmGyMNPXnpbWvWVPjS
# PMFDQK4dUPVS/JA7u5iZaWvHwaeoaKQn3J35J64whbn2Z006Po9ZOSJTROvIXQPK
# 7VB6fWIhCoDIc2bRoAVgX+iltKevqPdtNZx8WorWojiZ83iL9E3SIAveBO6Mm0eB
# cg3AFDLvMFkuruBx8lbkapdvklBtlo1oepqyNhR6BvIkuQkRUNcIsbiJeoQjYUIp
# 5aPNoiBB19GcZNnqJqGLFNdMGbJQQXE9P01wI4YMStyB0swylIQNCAmXHE/A7msg
# dDDS4Dk0EIUhFQEI6FUy3nFJ2SgXUE3mvk3RdazQyvtBuEOlqtPDBURPLDab4vri
# RbgjU2wGb2dVf0a1TD9uKFp5JtKkqGKX0h7i7UqLvBv9R0oN32dmfrJbQdA75PQ7
# 9ARj6e/CVABRoIoqyc54zNXqhwQYs86vSYiv85KZtrPmYQ/ShQDnUBrkG5WdGaG5
# nLGbsQAe79APT0JsyQq87kP6OnGlyE0mpTX9iV28hWIdMtKgK1TtmlfB2/oQzxm3
# i0objwG2J5VT6LaJbVu8aNQj6ItRolb58KaAoNYes7wPD1N1KarqE3fk3oyBIa0H
# EEcRrYc9B9F1vM/zZn4wggawMIIEmKADAgECAhAIrUCyYNKcTJ9ezam9k67ZMA0G
# CSqGSIb3DQEBDAUAMGIxCzAJBgNVBAYTAlVTMRUwEwYDVQQKEwxEaWdpQ2VydCBJ
# bmMxGTAXBgNVBAsTEHd3dy5kaWdpY2VydC5jb20xITAfBgNVBAMTGERpZ2lDZXJ0
# IFRydXN0ZWQgUm9vdCBHNDAeFw0yMTA0MjkwMDAwMDBaFw0zNjA0MjgyMzU5NTla
# MGkxCzAJBgNVBAYTAlVTMRcwFQYDVQQKEw5EaWdpQ2VydCwgSW5jLjFBMD8GA1UE
# AxM4RGlnaUNlcnQgVHJ1c3RlZCBHNCBDb2RlIFNpZ25pbmcgUlNBNDA5NiBTSEEz
# ODQgMjAyMSBDQTEwggIiMA0GCSqGSIb3DQEBAQUAA4ICDwAwggIKAoICAQDVtC9C
# 0CiteLdd1TlZG7GIQvUzjOs9gZdwxbvEhSYwn6SOaNhc9es0JAfhS0/TeEP0F9ce
# 2vnS1WcaUk8OoVf8iJnBkcyBAz5NcCRks43iCH00fUyAVxJrQ5qZ8sU7H/Lvy0da
# E6ZMswEgJfMQ04uy+wjwiuCdCcBlp/qYgEk1hz1RGeiQIXhFLqGfLOEYwhrMxe6T
# SXBCMo/7xuoc82VokaJNTIIRSFJo3hC9FFdd6BgTZcV/sk+FLEikVoQ11vkunKoA
# FdE3/hoGlMJ8yOobMubKwvSnowMOdKWvObarYBLj6Na59zHh3K3kGKDYwSNHR7Oh
# D26jq22YBoMbt2pnLdK9RBqSEIGPsDsJ18ebMlrC/2pgVItJwZPt4bRc4G/rJvmM
# 1bL5OBDm6s6R9b7T+2+TYTRcvJNFKIM2KmYoX7BzzosmJQayg9Rc9hUZTO1i4F4z
# 8ujo7AqnsAMrkbI2eb73rQgedaZlzLvjSFDzd5Ea/ttQokbIYViY9XwCFjyDKK05
# huzUtw1T0PhH5nUwjewwk3YUpltLXXRhTT8SkXbev1jLchApQfDVxW0mdmgRQRNY
# mtwmKwH0iU1Z23jPgUo+QEdfyYFQc4UQIyFZYIpkVMHMIRroOBl8ZhzNeDhFMJlP
# /2NPTLuqDQhTQXxYPUez+rbsjDIJAsxsPAxWEQIDAQABo4IBWTCCAVUwEgYDVR0T
# AQH/BAgwBgEB/wIBADAdBgNVHQ4EFgQUaDfg67Y7+F8Rhvv+YXsIiGX0TkIwHwYD
# VR0jBBgwFoAU7NfjgtJxXWRM3y5nP+e6mK4cD08wDgYDVR0PAQH/BAQDAgGGMBMG
# A1UdJQQMMAoGCCsGAQUFBwMDMHcGCCsGAQUFBwEBBGswaTAkBggrBgEFBQcwAYYY
# aHR0cDovL29jc3AuZGlnaWNlcnQuY29tMEEGCCsGAQUFBzAChjVodHRwOi8vY2Fj
# ZXJ0cy5kaWdpY2VydC5jb20vRGlnaUNlcnRUcnVzdGVkUm9vdEc0LmNydDBDBgNV
# HR8EPDA6MDigNqA0hjJodHRwOi8vY3JsMy5kaWdpY2VydC5jb20vRGlnaUNlcnRU
# cnVzdGVkUm9vdEc0LmNybDAcBgNVHSAEFTATMAcGBWeBDAEDMAgGBmeBDAEEATAN
# BgkqhkiG9w0BAQwFAAOCAgEAOiNEPY0Idu6PvDqZ01bgAhql+Eg08yy25nRm95Ry
# sQDKr2wwJxMSnpBEn0v9nqN8JtU3vDpdSG2V1T9J9Ce7FoFFUP2cvbaF4HZ+N3HL
# IvdaqpDP9ZNq4+sg0dVQeYiaiorBtr2hSBh+3NiAGhEZGM1hmYFW9snjdufE5Btf
# Q/g+lP92OT2e1JnPSt0o618moZVYSNUa/tcnP/2Q0XaG3RywYFzzDaju4ImhvTnh
# OE7abrs2nfvlIVNaw8rpavGiPttDuDPITzgUkpn13c5UbdldAhQfQDN8A+KVssIh
# dXNSy0bYxDQcoqVLjc1vdjcshT8azibpGL6QB7BDf5WIIIJw8MzK7/0pNVwfiThV
# 9zeKiwmhywvpMRr/LhlcOXHhvpynCgbWJme3kuZOX956rEnPLqR0kq3bPKSchh/j
# wVYbKyP/j7XqiHtwa+aguv06P0WmxOgWkVKLQcBIhEuWTatEQOON8BUozu3xGFYH
# Ki8QxAwIZDwzj64ojDzLj4gLDb879M4ee47vtevLt/B3E+bnKD+sEq6lLyJsQfmC
# XBVmzGwOysWGw/YmMwwHS6DTBwJqakAwSEs0qFEgu60bhQjiWQ1tygVQK+pKHJ6l
# /aCnHwZ05/LWUpD9r4VIIflXO7ScA+2GRfS0YW6/aOImYIbqyK+p/pQd52MbOoZW
# eE4wgge4MIIFoKADAgECAhACvga1cVUua0qjYNIMkYePMA0GCSqGSIb3DQEBCwUA
# MGkxCzAJBgNVBAYTAlVTMRcwFQYDVQQKEw5EaWdpQ2VydCwgSW5jLjFBMD8GA1UE
# AxM4RGlnaUNlcnQgVHJ1c3RlZCBHNCBDb2RlIFNpZ25pbmcgUlNBNDA5NiBTSEEz
# ODQgMjAyMSBDQTEwHhcNMjMwOTE0MDAwMDAwWhcNMjYwODIxMjM1OTU5WjCBwDET
# MBEGCysGAQQBgjc8AgEDEwJDSDEVMBMGCysGAQQBgjc8AgECEwRWYXVkMR0wGwYD
# VQQPDBRQcml2YXRlIG9yZ2FuaXphdGlvbjEYMBYGA1UEBRMPQ0hFLTExMi4wMDAu
# NTc5MQswCQYDVQQGEwJDSDEPMA0GA1UEBxMGUHJpbGx5MRYwFAYDVQQKEw1ORVhU
# aGluayBTLkEuMQswCQYDVQQLEwJSRDEWMBQGA1UEAxMNTkVYVGhpbmsgUy5BLjCC
# AiIwDQYJKoZIhvcNAQEBBQADggIPADCCAgoCggIBANM3yHlWUbz0fHTvbWuhEUfo
# Ou0HcK8celAhz1jdU3NQaK9Tnbnwibk2NLKGj+s9JWikFsldRZS14HkC7DfozrEW
# uBCl+Maf71taZEc6taHH1CctjQGjvJhcvhIM45zJOI9fLbj4TcEaXEy0s1EhPjl2
# Bb8Uyhy1IHFsx1si3mDzDcypjzNpVePfXjzOHlhHwG5/I8/E8RysSD6pald5HVRe
# ziHg9/vqkTPkL32qo890fjjAsNAZ2gXoMtpqqjfeY2RdLeoNhO+kKuS95loA5czH
# zgKPglueL8oakJK9OR74uo0bD/xunO02vvJA+GFqnILNUNgUX/E/Uw/CPUMc7E0o
# nSvHPZLUIbau9Njqd6aeBMzEghBeejnf/Y8Ahi563hKW2ZM3yaJQPXwPojoIjfRc
# XNdTRSSOR4q0m1yTISLhsRXI+XPjHrkOeeXTfMApqE+RQeaCwZbYPvQwtxRYke0g
# MSPLRyDkFwQbpSocw7myiJV+p26+T2WUg/LK3r5SnQpEw49CnS1sHG1jbM9ssb6E
# wEsNNue0x1XdqaNVGdsT5epGhfR6TxrtEqNvefF+nUu+yBjb0d66PMSSwOIJbRoa
# 1Kg1q+KlaJBN1LbTHUP8sTv7/t/ofW13QFfwdckRycWafAy8iOYuwjnzddTyXVC1
# vBaZ+u327PqpK97lc7qJAgMBAAGjggICMIIB/jAfBgNVHSMEGDAWgBRoN+Drtjv4
# XxGG+/5hewiIZfROQjAdBgNVHQ4EFgQUs7iS8dQBTVrtGBBi9ocXapndpWwwPQYD
# VR0gBDYwNDAyBgVngQwBAzApMCcGCCsGAQUFBwIBFhtodHRwOi8vd3d3LmRpZ2lj
# ZXJ0LmNvbS9DUFMwDgYDVR0PAQH/BAQDAgeAMBMGA1UdJQQMMAoGCCsGAQUFBwMD
# MIG1BgNVHR8Ega0wgaowU6BRoE+GTWh0dHA6Ly9jcmwzLmRpZ2ljZXJ0LmNvbS9E
# aWdpQ2VydFRydXN0ZWRHNENvZGVTaWduaW5nUlNBNDA5NlNIQTM4NDIwMjFDQTEu
# Y3JsMFOgUaBPhk1odHRwOi8vY3JsNC5kaWdpY2VydC5jb20vRGlnaUNlcnRUcnVz
# dGVkRzRDb2RlU2lnbmluZ1JTQTQwOTZTSEEzODQyMDIxQ0ExLmNybDCBlAYIKwYB
# BQUHAQEEgYcwgYQwJAYIKwYBBQUHMAGGGGh0dHA6Ly9vY3NwLmRpZ2ljZXJ0LmNv
# bTBcBggrBgEFBQcwAoZQaHR0cDovL2NhY2VydHMuZGlnaWNlcnQuY29tL0RpZ2lD
# ZXJ0VHJ1c3RlZEc0Q29kZVNpZ25pbmdSU0E0MDk2U0hBMzg0MjAyMUNBMS5jcnQw
# CQYDVR0TBAIwADANBgkqhkiG9w0BAQsFAAOCAgEAoKQOMPvdwc7Zh5uaQJiyzPRK
# VfuMI9TSMkHfHEmLkQswsqhY/+foHs6sJHKTzVYD9VDS10a4MdT/v6FOK+MzXMYQ
# P+AO5GEpc/TWzT82sQBkbrTnykoBj8ZMe52feccPpcYdPNt5Su7pHNX+BjP1tlRj
# i2zOTJ7YMjgVI9QDp3iNvA4DPv3An1CXllaYJtWWdks9SBQapcX555fGEwF0MQPf
# ACxI0yagKO3XoxVNpO8dThzQrT3rIIDWc4HOMN7OMugrgrWJAGdStNOzcLXQ1hhu
# dq8q9O0+xmROvG3cQSBaZdf2P2DBVxCUBu623RVqjkA5SkvWzKYfCe5eD6Nyhcq7
# slWcI8CP8ndTkck4p8Y0L2iZpX9yCSZj1rsIF3d/T8vmvpLdgdobu7J7aokUhotX
# wWDwULGetIEFvUbT5emb3WOTThlNKmEzUYd4cKjrV0Qa1FlqksmYQiHxpvElIRk9
# aE1erwpp7guN8z5zTauG9Bm3fMtuJofYqasoTAeIlySEGdp0pi8s3EICVMaF3Wzv
# 2AmgnDCWjNsn+1j720bHlQezKROF+skJutdpOeE/B362R0Ss8zhsIDqw6MuNl+jF
# CUDh7E0V0MkT0mHpIRxX7izL/IwCo4ZOOMg5KHVBR+Am1N0jow7wbmV/qqnHXrxd
# yWyWjSwFe92qiyMGOowxghnqMIIZ5gIBATB9MGkxCzAJBgNVBAYTAlVTMRcwFQYD
# VQQKEw5EaWdpQ2VydCwgSW5jLjFBMD8GA1UEAxM4RGlnaUNlcnQgVHJ1c3RlZCBH
# NCBDb2RlIFNpZ25pbmcgUlNBNDA5NiBTSEEzODQgMjAyMSBDQTECEAK+BrVxVS5r
# SqNg0gyRh48wDQYJYIZIAWUDBAIBBQCggYQwGAYKKwYBBAGCNwIBDDEKMAigAoAA
# oQKAADAZBgkqhkiG9w0BCQMxDAYKKwYBBAGCNwIBBDAcBgorBgEEAYI3AgELMQ4w
# DAYKKwYBBAGCNwIBFTAvBgkqhkiG9w0BCQQxIgQgAbLzq/5hRDUWTN6yE0+n36I4
# f2Far3q+74FF+xm1MZowDQYJKoZIhvcNAQEBBQAEggIAmDtzoBTp9sgU/UuArhtT
# ZXVgZqS1TYVmn1JaWc6Vl89fvHHuFO6pjPHFPXBrTf5ZTes9Xvk82zEzEAESwkE0
# WELnmFEViiVl0IVYKhHEY4fdgsdEh7Kz8+HthwWzDuuSSn5yiPTLMrat47nHfn6z
# F4Fmfh+iJ+r6qm/z4gW0NwqC22+JYV0AEgTCqOS1eEECiyK/90FvZSWX6iPBBeH0
# s3E8e6onWhewUCKYJijRvAOLphugTJYN8E4Suv3xUd9LfgbzqZ1Jm965FrIb/T46
# nAjOslQiXd4/PX7Q4pmnpZ0i8xaRQWhZviWueJ5wjTqOroJqgZP9waApqGZrWh7X
# TZIeFYgKuAOTu/R9mFiQvpfkiCR+r4Rc1ta5UTt8SQAqxxF6A3THZHaUVU6CT/HG
# N0mPdw7ax4Xts+rOQN3Gg54NpCwb20hZbzzlYdTqefEqCQz0MNA73Lbp0/Opceqy
# YbxDLrWLKKWvaWOemweZ6a2Nq/sMmn9iNNnfMPQJVXyEwietirvBKu6ohV93dI0A
# oUG/rgWR1zl0q+i42GrJNzdxPx49y5bxrP72Nbm7fwm7u6ad38hvdrQPpKSqMkaj
# E8DWzbiwPK2cpXu4OpfpuTgNYIdHjx3ZQOn+ZgXX3owGrYj/l/MtDGuYy474MpA+
# gv7z4p+3Nlht274K41+NvDyhgha3MIIWswYKKwYBBAGCNwMDATGCFqMwghafBgkq
# hkiG9w0BBwKgghaQMIIWjAIBAzENMAsGCWCGSAFlAwQCATCB3AYLKoZIhvcNAQkQ
# AQSggcwEgckwgcYCAQEGCSsGAQQBoDICAzAxMA0GCWCGSAFlAwQCAQUABCDg4dZ1
# Bx+6th4XOJlJNuofzUTFbCbq+/uW1URZczhT7gIUTGLyOjjK4jm95WGOdrkHl4iX
# cd0YDzIwMjUwOTIyMDYwNzM3WjADAgEBoFekVTBTMQswCQYDVQQGEwJCRTEZMBcG
# A1UECgwQR2xvYmFsU2lnbiBudi1zYTEpMCcGA1UEAwwgR2xvYmFsc2lnbiBUU0Eg
# Zm9yIEFkdmFuY2VkIC0gRzSgghJKMIIGYjCCBEqgAwIBAgIQAQMy4WW/m3hD4Jl1
# lGN3CzANBgkqhkiG9w0BAQwFADBbMQswCQYDVQQGEwJCRTEZMBcGA1UEChMQR2xv
# YmFsU2lnbiBudi1zYTExMC8GA1UEAxMoR2xvYmFsU2lnbiBUaW1lc3RhbXBpbmcg
# Q0EgLSBTSEEzODQgLSBHNDAeFw0yNTA0MTExNDQ3MDFaFw0zNDEyMTAwMDAwMDBa
# MFMxCzAJBgNVBAYTAkJFMRkwFwYDVQQKDBBHbG9iYWxTaWduIG52LXNhMSkwJwYD
# VQQDDCBHbG9iYWxzaWduIFRTQSBmb3IgQWR2YW5jZWQgLSBHNDCCAaIwDQYJKoZI
# hvcNAQEBBQADggGPADCCAYoCggGBAL4lejlDGK511tWzocib1iaenoAWN1mu9Ocn
# g7gqw8zEOq8sty7ryNq/wwWveWzXNhLatjNeMQ0n8+E9A4EbszvuRGgmnjPkyPUm
# JS/gkNkDR/QmZV1BxLysCQEhPewZIEYvQB9sZb3VM2W94iCkRMVacCMtRKq2RsqA
# eeo8vjtsyGm4MgpXSOIJBHM6r4FzKBZy+RsTtzj0Rjg36eklI/nsMLaCIKD+E7dg
# Cl77Yvhvhbx8Gzevdk/vY1H8EQCXBZa6JNtfR6DaLDwsh8gxTczI5sRdI3ymYpNo
# v8ymVwBzun3KW4Msk0BMIn25fcxvb501hIIfKpnXAZEKzaPQGDDxlkx7PNdUzXw+
# eF6eVzJYeToLRXOamOHYrSX++ML0COvPq2sg/GeXlHL1eMb/UhjKKU0rxtig1sjD
# MHswGoQYSfS2zNzW1NoeHRFCgS/OsJ6VgWLclzFIFpGTzArZiKlu8Zabb+XIO8lA
# Px9dQU/6AC0MTpVxG9VJrDCQy0oYTwIDAQABo4IBqDCCAaQwDgYDVR0PAQH/BAQD
# AgeAMBYGA1UdJQEB/wQMMAoGCCsGAQUFBwMIMB0GA1UdDgQWBBTZN7YzRW6PNQfO
# 96mzCv2gqcj5gjBWBgNVHSAETzBNMAgGBmeBDAEEAjBBBgkrBgEEAaAyAR4wNDAy
# BggrBgEFBQcCARYmaHR0cHM6Ly93d3cuZ2xvYmFsc2lnbi5jb20vcmVwb3NpdG9y
# eS8wDAYDVR0TAQH/BAIwADCBkAYIKwYBBQUHAQEEgYMwgYAwOQYIKwYBBQUHMAGG
# LWh0dHA6Ly9vY3NwLmdsb2JhbHNpZ24uY29tL2NhL2dzdHNhY2FzaGEzODRnNDBD
# BggrBgEFBQcwAoY3aHR0cDovL3NlY3VyZS5nbG9iYWxzaWduLmNvbS9jYWNlcnQv
# Z3N0c2FjYXNoYTM4NGc0LmNydDAfBgNVHSMEGDAWgBTqFsZp5+PLV0U5M6TwQL7Q
# w71lljBBBgNVHR8EOjA4MDagNKAyhjBodHRwOi8vY3JsLmdsb2JhbHNpZ24uY29t
# L2NhL2dzdHNhY2FzaGEzODRnNC5jcmwwDQYJKoZIhvcNAQEMBQADggIBAGYfzwRh
# xCcMMGOdFylYezH0PcaS6ABq/E3xefhnLFLxh09UMeb2gE/XPDuBDaOR1ArLelps
# wVILQvkpBswzfheaZ0j/w+cjq/E03In7HD88F9WRn72NxokSBVMOdpEGqyWdZyeI
# cv1Db2Eprmb2vIwiuMNes5/frxqDRf2w724UX07LumLYVRNDtH4dIl7qlqyfd+cn
# 3e6s/uWNJGOyF0Yk9U3w6ibkAVmo9W2JqSMRycQ8cC7svE/kuq3GgzscSOZoqzn3
# MKakNLDjVpu9z7Gh36RrulCrqVFdvZDAghLPFiXGxVc+7JyslVqFybbCOkzUvME0
# 8bvdxwRjIMDBgPSSQGrhGsKRGdzn9MP3VJ9QpHCuAr29v3n4tGSdo7N53HM+0WBY
# gmesiKzGajy79/4pROfkamQQzM+iergtga0cNaq9hK8npbrChB0NSA+qBpTxggf0
# mczlUveZF+IF6IW4+NJxBb2/pUFfyfSqg3PR+G3D+gTSkAg/dcS0Dk5f0Jjq0uqk
# TjA4w0L3qd4FjZNd0sNtATCIIWT7FN6nsMSNBtWSPXXmR3U98AfG0/517/SBxiCg
# AvOWx0hmDTCdpUJfR3vak2OxBlZRQxfudAg80Gy8XJ2x5XlbTcBayAHhD2jtm91F
# dEglFFxSM05mS/AJeDEw29LVZTlRsGBMYx6QMIIGWTCCBEGgAwIBAgINAewckkDe
# /S5AXXxHdDANBgkqhkiG9w0BAQwFADBMMSAwHgYDVQQLExdHbG9iYWxTaWduIFJv
# b3QgQ0EgLSBSNjETMBEGA1UEChMKR2xvYmFsU2lnbjETMBEGA1UEAxMKR2xvYmFs
# U2lnbjAeFw0xODA2MjAwMDAwMDBaFw0zNDEyMTAwMDAwMDBaMFsxCzAJBgNVBAYT
# AkJFMRkwFwYDVQQKExBHbG9iYWxTaWduIG52LXNhMTEwLwYDVQQDEyhHbG9iYWxT
# aWduIFRpbWVzdGFtcGluZyBDQSAtIFNIQTM4NCAtIEc0MIICIjANBgkqhkiG9w0B
# AQEFAAOCAg8AMIICCgKCAgEA8ALiMCP64BvhmnSzr3WDX6lHUsdhOmN8OSN5bXT8
# MeR0EhmW+s4nYluuB4on7lejxDXtszTHrMMM64BmbdEoSsEsu7lw8nKujPeZWl12
# rr9EqHxBJI6PusVP/zZBq6ct/XhOQ4j+kxkX2e4xz7yKO25qxIjw7pf23PMYoEuZ
# HA6HpybhiMmg5ZninvScTD9dW+y279Jlz0ULVD2xVFMHi5luuFSZiqgxkjvyen38
# DljfgWrhsGweZYIq1CHHlP5CljvxC7F/f0aYDoc9emXr0VapLr37WD21hfpTmU1b
# dO1yS6INgjcZDNCr6lrB7w/Vmbk/9E818ZwP0zcTUtklNO2W7/hn6gi+j0l6/5Cx
# 1PcpFdf5DV3Wh0MedMRwKLSAe70qm7uE4Q6sbw25tfZtVv6KHQk+JA5nJsf8sg2g
# lLCylMx75mf+pliy1NhBEsFV/W6RxbuxTAhLntRCBm8bGNU26mSuzv31BebiZtAO
# BSGssREGIxnk+wU0ROoIrp1JZxGLguWtWoanZv0zAwHemSX5cW7pnF0CTGA8zwKP
# Af1y7pLxpxLeQhJN7Kkm5XcCrA5XDAnRYZ4miPzIsk3bZPBFn7rBP1Sj2HYClWxq
# jcoiXPYMBOMp+kuwHNM3dITZHWarNHOPHn18XpbWPRmwl+qMUJFtr1eGfhA3HWsa
# FN8CAwEAAaOCASkwggElMA4GA1UdDwEB/wQEAwIBhjASBgNVHRMBAf8ECDAGAQH/
# AgEAMB0GA1UdDgQWBBTqFsZp5+PLV0U5M6TwQL7Qw71lljAfBgNVHSMEGDAWgBSu
# bAWjkxPioufi1xzWx/B/yGdToDA+BggrBgEFBQcBAQQyMDAwLgYIKwYBBQUHMAGG
# Imh0dHA6Ly9vY3NwMi5nbG9iYWxzaWduLmNvbS9yb290cjYwNgYDVR0fBC8wLTAr
# oCmgJ4YlaHR0cDovL2NybC5nbG9iYWxzaWduLmNvbS9yb290LXI2LmNybDBHBgNV
# HSAEQDA+MDwGBFUdIAAwNDAyBggrBgEFBQcCARYmaHR0cHM6Ly93d3cuZ2xvYmFs
# c2lnbi5jb20vcmVwb3NpdG9yeS8wDQYJKoZIhvcNAQEMBQADggIBAH/iiNlXZytC
# X4GnCQu6xLsoGFbWTL/bGwdwxvsLCa0AOmAzHznGFmsZQEklCB7km/fWpA2PHpby
# hqIX3kG/T+G8q83uwCOMxoX+SxUk+RhE7B/CpKzQss/swlZlHb1/9t6CyLefYdO1
# RkiYlwJnehaVSttixtCzAsw0SEVV3ezpSp9eFO1yEHF2cNIPlvPqN1eUkRiv3I2Z
# OBlYwqmhfqJuFSbqtPl/KufnSGRpL9KaoXL29yRLdFp9coY1swJXH4uc/LusTN76
# 3lNMg/0SsbZJVU91naxvSsguarnKiMMSME6yCHOfXqHWmc7pfUuWLMwWaxjN5Fk3
# hgks4kXWss1ugnWl2o0et1sviC49ffHykTAFnM57fKDFrK9RBvARxx0wxVFWYOh8
# lT0i49UKJFMnl4D6SIknLHniPOWbHuOqhIKJPsBK9SH+YhDtHTD89szqSCd8i3VC
# f2vL86VrlR8EWDQKie2CUOTRe6jJ5r5IqitV2Y23JSAOG1Gg1GOqg+pscmFKyfpD
# xMZXxZ22PLCLsLkcMe+97xTYFEBsIB3CLegLxo1tjLZx7VIh/j72n585Gq6s0i96
# ILH0rKod4i0UnfqWah3GPMrz2Ry/U02kR1l8lcRDQfkl4iwQfoH5DZSnffK1CfXY
# YHJAUJUg1ENEvvqglecgWbZ4xqRqqiKbMIIFgzCCA2ugAwIBAgIORea7A4Mzw4Vl
# SOb/RVEwDQYJKoZIhvcNAQEMBQAwTDEgMB4GA1UECxMXR2xvYmFsU2lnbiBSb290
# IENBIC0gUjYxEzARBgNVBAoTCkdsb2JhbFNpZ24xEzARBgNVBAMTCkdsb2JhbFNp
# Z24wHhcNMTQxMjEwMDAwMDAwWhcNMzQxMjEwMDAwMDAwWjBMMSAwHgYDVQQLExdH
# bG9iYWxTaWduIFJvb3QgQ0EgLSBSNjETMBEGA1UEChMKR2xvYmFsU2lnbjETMBEG
# A1UEAxMKR2xvYmFsU2lnbjCCAiIwDQYJKoZIhvcNAQEBBQADggIPADCCAgoCggIB
# AJUH6HPKZvnsFMp7PPcNCPG0RQssgrRIxutbPK6DuEGSMxSkb3/pKszGsIhrxbaJ
# 0cay/xTOURQh7ErdG1rG1ofuTToVBu1kZguSgMpE3nOUTvOniX9PeGMIyBJQbUJm
# L025eShNUhqKGoC3GYEOfsSKvGRMIRxDaNc9PIrFsmbVkJq3MQbFvuJtMgamHvm5
# 66qjuL++gmNQ0PAYid/kD3n16qIfKtJwLnvnvJO7bVPiSHyMEAc4/2ayd2F+4OqM
# PKq0pPbzlUoSB239jLKJz9CgYXfIWHSw1CM69106yqLbnQneXUQtkPGBzVeS+n68
# UARjNN9rkxi+azayOeSsJDa38O+2HBNXk7besvjihbdzorg1qkXy4J02oW9UivFy
# Vm4uiMVRQkQVlO6jxTiWm05OWgtH8wY2SXcwvHE35absIQh1/OZhFj931dmRl4QK
# bNQCTXTAFO39OfuD8l4UoQSwC+n+7o/hbguyCLNhZglqsQY6ZZZZwPA1/cnaKI0a
# EYdwgQqomnUdnjqGBQCe24DWJfncBZ4nWUx2OVvq+aWh2IMP0f/fMBH5hc8zSPXK
# bWQULHpYT9NLCEnFlWQaYw55PfWzjMpYrZxCRXluDocZXFSxZba/jJvcE+kNb7gu
# 3GduyYsRtYQUigAZcIN5kZeR1BonvzceMgfYFGM8KEyvAgMBAAGjYzBhMA4GA1Ud
# DwEB/wQEAwIBBjAPBgNVHRMBAf8EBTADAQH/MB0GA1UdDgQWBBSubAWjkxPioufi
# 1xzWx/B/yGdToDAfBgNVHSMEGDAWgBSubAWjkxPioufi1xzWx/B/yGdToDANBgkq
# hkiG9w0BAQwFAAOCAgEAgyXt6NH9lVLNnsAEoJFp5lzQhN7craJP6Ed41mWYqVuo
# PId8AorRbrcWc+ZfwFSY1XS+wc3iEZGtIxg93eFyRJa0lV7Ae46ZeBZDE1ZXs6Kz
# O7V33EByrKPrmzU+sQghoefEQzd5Mr6155wsTLxDKZmOMNOsIeDjHfrYBzN2VAAi
# KrlNIC5waNrlU/yDXNOd8v9EDERm8tLjvUYAGm0CuiVdjaExUd1URhxN25mW7xoc
# BFymFe944Hn+Xds+qkxV/ZoVqW/hpvvfcDDpw+5CRu3CkwWJ+n1jez/QcYF8AOiY
# rg54NMMl+68KnyBr3TsTjxKM4kEaSHpzoHdpx7Zcf4LIHv5YGygrqGytXm3ABdJ7
# t+uA/iU3/gKbaKxCXcPu9czc8FB10jZpnOZ7BN9uBmm23goJSFmH63sUYHpkqmlD
# 75HHTOwY3WzvUy2MmeFe8nI+z1TIvWfspA9MRf/TuTAjB0yPEL+GltmZWrSZVxyk
# zLsViVO6LAUP5MSeGbEYNNVMnbrt9x+vJJUEeKgDu+6B5dpffItKoZB0JaezPkvI
# LFa9x8jvOOJckvB595yEunQtYQEgfn7R8k8HWV+LLUNS60YMlOH1Zkd5d9VUWx+t
# JDfLRVpOoERIyNiwmcUVhAn21klJwGW45hpxbqCo8YLoRT5s1gLXCmeDBVrJpBAx
# ggNJMIIDRQIBATBvMFsxCzAJBgNVBAYTAkJFMRkwFwYDVQQKExBHbG9iYWxTaWdu
# IG52LXNhMTEwLwYDVQQDEyhHbG9iYWxTaWduIFRpbWVzdGFtcGluZyBDQSAtIFNI
# QTM4NCAtIEc0AhABAzLhZb+beEPgmXWUY3cLMAsGCWCGSAFlAwQCAaCCAS0wGgYJ
# KoZIhvcNAQkDMQ0GCyqGSIb3DQEJEAEEMCsGCSqGSIb3DQEJNDEeMBwwCwYJYIZI
# AWUDBAIBoQ0GCSqGSIb3DQEBCwUAMC8GCSqGSIb3DQEJBDEiBCC5NNoiTMOYv9pH
# 0ME1J2Jn7gnFpfJwJzMzHn/JrGH5+jCBsAYLKoZIhvcNAQkQAi8xgaAwgZ0wgZow
# gZcEIJGSR5tiNbl2Jr+2AW14CJGDcgPYc5HAbBuOPXf/4sc3MHMwX6RdMFsxCzAJ
# BgNVBAYTAkJFMRkwFwYDVQQKExBHbG9iYWxTaWduIG52LXNhMTEwLwYDVQQDEyhH
# bG9iYWxTaWduIFRpbWVzdGFtcGluZyBDQSAtIFNIQTM4NCAtIEc0AhABAzLhZb+b
# eEPgmXWUY3cLMA0GCSqGSIb3DQEBCwUABIIBgHWcGn3lBrZsI8cbr/sXj04qDHAO
# 6KrE2tW8ohApojls6QezETW6Obj3lzkuzPseSoQi93khMJ2I8FjOVgO1jnblhxQ2
# mkS2R//xvQ7rEDpWmKSAlELYvmgzKh1WgOzpLZKbX1g9uxOuTQLJF7XRTCONYdtW
# xPrmVVydOzBhn6Fo9BpRxknFGbZrjuNahPC8i3Hv9dLKwno6EJw8pMsZidW4doan
# Qbp0+eA+oMX7kDgkJmPts/3yCJel/3Z6Ssw5TgK3KiKX25+Eaq63eGBVA2HqPTFS
# FivBr/FFRTcN4bXwF26KxSjzwJLSbbb59JvFQ4UuYmdg3QUkVLB/pZMjMerQmLCs
# ngY0xPSpNOvYhjBZmiefoGCyjrQS8/zI6fqev/m7j9da5IPknURc7AcDtA4gvLII
# pW0ba17SDH63qJFT88ehtEHjKcX0PoXvnghJoQgF018iNT/F+NpuoKP3at2pj/ff
# /W5VUn/PMLvs9JauWCWaZTv7pPK2PppAu/C+4Q==
# SIG # End signature block
