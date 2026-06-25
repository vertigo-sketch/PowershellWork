$tls13Path = "HKLM:\SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Protocols\TLS 1.3"

# Check Client-side configuration
$clientPath = "$tls13Path\Client"
if (Test-Path $clientPath) {
    $clientEnabled = (Get-ItemProperty -Path $clientPath -Name "Enabled" -ErrorAction SilentlyContinue).Enabled
    $clientDisabledByDefault = (Get-ItemProperty -Path $clientPath -Name "DisabledByDefault" -ErrorAction SilentlyContinue).DisabledByDefault

    if ($clientEnabled -eq 1 -and $clientDisabledByDefault -ne 1) {
        Write-Host "TLS 1.3 Client is configured to be enabled."
    } elseif ($clientDisabledByDefault -eq 1) {
        Write-Host "TLS 1.3 Client is configured to be disabled by default."
    } else {
        Write-Host "TLS 1.3 Client is not explicitly enabled in the registry."
    }
} else {
    Write-Host "TLS 1.3 Client registry key does not exist."
}

# Check Server-side configuration
$serverPath = "$tls13Path\Server"
if (Test-Path $serverPath) {
    $serverEnabled = (Get-ItemProperty -Path $serverPath -Name "Enabled" -ErrorAction SilentlyContinue).Enabled
    $serverDisabledByDefault = (Get-ItemProperty -Path $serverPath -Name "DisabledByDefault" -ErrorAction SilentlyContinue).DisabledByDefault

    if ($serverEnabled -eq 1 -and $serverDisabledByDefault -ne 1) {
        Write-Host "TLS 1.3 Server is configured to be enabled."
    } elseif ($serverDisabledByDefault -eq 1) {
        Write-Host "TLS 1.3 Server is configured to be disabled by default."
    } else {
        Write-Host "TLS 1.3 Server is not explicitly enabled in the registry."
    }
} else {
    Write-Host "TLS 1.3 Server registry key does not exist."
}