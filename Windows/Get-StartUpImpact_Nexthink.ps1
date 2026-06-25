<#
.SYNOPSIS
Obtains startup application impact information.

.DESCRIPTION
Retrieves information of application impact on login process of last logged in user. Result data is similar to the information in the Startup tab in Windows Task Manager, enhanced by detailed impact of each application.

An issue related to Startup Impact measure was fixed by Microsoft in this [https://support.microsoft.com/en-us/topic/february-15-2022-kb5010415-os-builds-19042-1566-19043-1566-and-19044-1566-preview-5a644b82-83f4-4cc2-a0e7-85f643252386 KB]. Please make sure to install it to properly measure Startup Impact.


.FUNCTIONALITY
On-demand

.INPUTS
ID  Label                           Description
1   ApplicationsToExclude           Parameter is used to remove all processes matching provided name(s) from output. Multiple entries are separated by comma. Does not accept illegal characters. For more information see this [https://docs.microsoft.com/en-us/windows/win32/fileio/naming-a-file article]
2   XMLMaxAgeInDays                 Parameter is used to avoid using files old files. The range goes from 0 (same day) to 60

.OUTPUTS
ID  Label                           Type            Description
1   UserSID                         String          User SID (Security Identifier) to whom the XML file containing the stats belongs
2   LastStartUpAnalysisDate         DateTime        Last time the startup information was updated on the device
3   HighImpactCount                 Int             Number of applications with a high startup impact
4   HighImpactApplications          StringList      Details (CPU time in ms, Disk I/O in MB) of programs with a high startup impact
5   HighImpactActionableApplicationsStringList      Actionable names of programs with a high startup impact
6   HighImpactRemove                StringList      Application names with a high startup impact that can only be removed
7   MediumImpactCount               Int             Number of applications with a medium startup impact
8   MediumImpactApplications        StringList      Details (CPU time in ms, Disk I/O in MB) of programs with a medium startup impact
9   MediumImpactActionableApplicationsStringList      Actionable names of programs with a medium startup impact
10  MediumImpactRemove              StringList      Application names with a medium startup impact that can only be removed
11  LowImpactCount                  Int             Number of applications with a low startup impact
12  LowImpactApplications           StringList      Details (CPU time in ms, Disk I/O in MB) of programs with a low startup impact
13  LowImpactActionableApplications StringList      Actionable names of programs with a low startup impact
14  LowImpactRemove                 StringList      Application names with a low startup impact that can only be removed
15  NotMeasuredImpactApplications   StringList      Applications that were started but whose startup impacts were not measured by Microsoft Windows
16  NotMeasuredImpactActionableApplicationsStringList      Actionable names of programs not measured by Microsoft Windows
17  NotMeasuredImpactRemove         StringList      Application names with a not measured startup impact that can only be removed

.FURTHER INFORMATION
Result data of 'ActionableApplications' output fields can be actioned with this [https://www.nexthink.com/library/application-auto-start-impact/#disable-application-from-startup-menu Remote Action].
Due a known limitation of event tracing logging in Windows, if the number of sessions subscribed to Winlogon provider is 6 or more, DiagPerf is skipped to avoid High CPU, Memory and Disk usage during startup [https://learn.microsoft.com/en-us/windows/win32/etw/about-event-tracing#manifest-based-providers Microsoft Documentation].
If applications appears in the 'actionable' and 'remove' outputs means that the only action able is to remove it completely from startup (it's not possible to undo it).

.NOTES
Context:            LocalSystem
Version:            5.0.2.0 - Improved log management
                    5.0.1.1 - Improved documentation
                    5.0.1.0 - Fixed bug in XMLMaxAgeInDays parameter
                    5.0.0.0 - Added the following outputs 'NotMeasuredImpactRemove', 'LowImpactRemove', 'MediumImpactRemove', 'HighImpactRemove'
                    4.2.3.1 - Added function to check the number of sessions subscribed to Winlogon provider
                    4.2.2.1 - Updated timestamp certificate
                    4.2.2.0 - Improved style and conventions
                    4.2.1.2 - Updated to fix delivery issues
                    4.2.1.1 - Fixed typo in Test-MinimumWindowsVersion
                    4.2.1.0 - Added Microsoft KB Fix in Documentation
                    4.2.0.0 - Added compatibility for Windows 8.1 devices
                    4.1.0.0 - Added compatibility for Azure Domain joined devices
                    4.0.2.0 - Fixed XML file reading
                    4.0.1.0 - Fixed default parameter bug
                    4.0.0.1 - Remote Action re-compilation
                    4.0.0.0 - Added input parameter to remove certain applications from output and split 'Applications' result into new respective impact output 'ActionableApplication'
                    3.1.0.0 - Code refactored and fixed newline bug in ImpactApplications output fields
                    3.0.1.0 - Bugfix of empty application lists result
                    3.0.0.0 - Added new output 'Applications' and minor code refactor
                    2.0.1.0 - Fixed when the command line does not have the expected format and removed compatibility with Windows 7
                    2.0.0.0 - Script returns UserSID instead of UserName
                    1.1.0.0 - Code refactored and performance improvements
                    1.0.0.0 - Initial release
Last Generated:     15 Mar 2023 - 17:01:41
Copyright (C) 2023 Nexthink SA, Switzerland
#>

#
# Input parameters definition
#
param(
    [Parameter(Mandatory = $true)][string]$ApplicationsToExclude,
    [Parameter(Mandatory = $true)][string]$XMLMaxAgeInDays
)

# End of parameters definition

$env:Path = "$env:SystemRoot\system32;$env:SystemRoot;$env:SystemRoot\System32\Wbem;$env:SystemRoot\System32\WindowsPowerShell\v1.0\"

#
# Constants definition
#
New-Variable -Name 'ERROR_EXCEPTION_TYPE' `
    -Value @{Environment = '[Environment error]'
             Input = '[Input error]'
             Internal = '[Internal error]'} `
    -Option ReadOnly -Scope Script
New-Variable -Name 'LOCAL_SYSTEM_IDENTITY' `
    -Value 'S-1-5-18' -Option ReadOnly -Scope Script
New-Variable -Name 'REMOTE_ACTION_DLL_PATH' `
    -Value "$env:NEXTHINK\RemoteActions\nxtremoteactions.dll" `
    -Option ReadOnly -Scope Script
New-Variable -Name 'WINDOWS_VERSIONS' `
    -Value @{Windows7 = '6.1'
             Windows8 = '6.2'
             Windows81 = '6.3'
             Windows10 = '10.0'
             Windows11 = '10.0'} `
    -Option ReadOnly -Scope Script
New-Variable -Name 'XML_RESERVED_MARKUP_CHARACTERS' `
    -Value @{Ampersand = '&'
             EscapedAmpersand = '&amp;'
             Percent = '%'
             EscapedPercent = '&#37;'
             Apostrophe = "'"
             EscapedApostrophe = '&apos;'} `
    -Option ReadOnly -Scope Script

$LOG_REMOTE_ACTION_NAME = 'Get-StartupImpact'
Set-Variable -Name 'LOG_REMOTE_ACTION_NAME' -Option ReadOnly -Scope Script -Force

$REGISTRY_APP_PATH = @{
    MachineRun = @(
        'registry::HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows\CurrentVersion\Run'
        'registry::HKEY_LOCAL_MACHINE\SOFTWARE\Wow6432Node\Microsoft\Windows\CurrentVersion\Run'
    )
    UserRun = 'registry::HKEY_USERS\{0}\SOFTWARE\Microsoft\Windows\CurrentVersion\Run'
    MachineStartupFolder = "$env:PROGRAMDATA\Microsoft\Windows\Start Menu\Programs\Startup"
    UserStartupFolder = @(
        'registry::HKEY_USERS\{0}\Software\Microsoft\Windows\CurrentVersion\Explorer\Shell Folders'
    )
    MachineStartupApproved = @(
        'registry::HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved'
        'registry::HKEY_LOCAL_MACHINE\SOFTWARE\Wow6432Node\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved'
    )
    UserStartupApproved = 'registry::HKEY_USERS:\{0}\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved'
}
Set-Variable -Name 'REGISTRY_APP_PATH' -Option ReadOnly -Scope Script -Force

$FILE_NAME_REGEX = 'S-1-(5|12)-.*_StartupInfo.*\.xml'
Set-Variable -Name 'FILE_NAME_REGEX' -Option ReadOnly -Scope Script -Force

$IMPACT_LEVELS = @(
    'High'
    'Medium'
    'Low'
    'Unknown'
    )
Set-Variable -Name 'IMPACT_LEVELS' -Option ReadOnly -Scope Script -Force

$CPU_HIGH_IMPACT_LEVEL = 1000000
Set-Variable -Name 'CPU_HIGH_IMPACT_LEVEL' -Option ReadOnly -Scope Script -Force

$CPU_MEDIUM_IMPACT_LEVEL = 300000
Set-Variable -Name 'CPU_MEDIUM_IMPACT_LEVEL' -Option ReadOnly -Scope Script -Force

$DISK_USAGE_HIGH_IMPACT_LEVEL = 3MB
Set-Variable -Name 'DISK_USAGE_HIGH_IMPACT_LEVEL' -Option ReadOnly -Scope Script -Force

$DISK_USAGE_MEDIUM_IMPACT_LEVEL = 300KB
Set-Variable -Name 'DISK_USAGE_MEDIUM_IMPACT_LEVEL' -Option ReadOnly -Scope Script -Force

$SPACE_REPLACEMENT = '*'
Set-Variable 'SPACE_REPLACEMENT' -Option ReadOnly -Scope Script -Force

$EXECUTABLE_PATH_REGEX = '(?<Path>^"[^"]*"|\S*) *(?<Parameters>.*)?'
Set-Variable -Name 'EXECUTABLE_PATH_REGEX' -Option ReadOnly -Scope Script -Force

$FOLDERS_WITH_SPACES_REGEX = '(([^><:"\/\\\|\?\* ]+ [^><:"\/\\\|\?\* ]+)+)\\'
Set-Variable -Name 'FOLDERS_WITH_SPACES_REGEX' -Option ReadOnly -Scope Script -Force

$STARTUP_INFO_FOLDER_PATH = "$env:SYSTEMROOT\System32\WDI\LogFiles\StartupInfo"
Set-Variable -Name 'STARTUP_INFO_FOLDER_PATH' -Option ReadOnly -Scope Script -Force

$AUTOLOGGER_KEY = 'registry::HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Control\WMI\Autologger\'
Set-Variable -Name 'AUTOLOGGER_KEY' -Option ReadOnly -Scope Script -Force

$LOGGERS = Get-ChildItem -Path $AUTOLOGGER_KEY
Set-Variable -Name 'LOGGERS' -Option ReadOnly -Scope Script -Force

#
# Invoke Main
#
function Invoke-Main ([hashtable]$InputParameters) {
    Start-NxtLogging -RemoteActionName $LOG_REMOTE_ACTION_NAME

    $startUpImpactEnv = Initialize-StartUpImpactEnv
    $exitCode = 0

    try {
        Add-NexthinkRemoteActionDLL
        Test-RunningAsLocalSystem
        Test-MinimumSupportedOSVersion -WindowsVersion 'Windows81'
        Test-InputParameters -InputParameters $InputParameters

        Initialize-ImpactLevelType

        Invoke-StartUpImpactInfo -StartUpImpactEnv $startUpImpactEnv -Exclude $InputParameters.ApplicationsToExclude -Days $InputParameters.XMLMaxAgeInDays
    } catch {
        Write-StatusMessage -Message $_
        $exitCode = 1
    } finally {
        Update-EngineOutputVariables -StartUpImpactEnv $startUpImpactEnv
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
        throw "$($ERROR_EXCEPTION_TYPE.Environment) Error getting CIM/WMI information. Verify WinMgmt service status and WMI repository consistency. "
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

function Get-RegistryKeyProperty ([string]$Key, [string]$Property) {
    if ([string]::IsNullOrEmpty($Key)) { return }
    if (Test-WOW6432Process) {
        $regSubkey = Get-WOW64RegistrySubKey -Key $Key -Property $Property -ReadOnly
        return $regSubkey.GetValue($Property)
    } else {
        return (Get-ItemProperty -Path $Key `
                                 -Name $Property `
                                 -ErrorAction SilentlyContinue) |
                    Select-Object -ExpandProperty $Property
    }
}

function Test-WOW6432Process {

    return (Test-Path Env:\PROCESSOR_ARCHITEW6432)
}

function Get-WOW64RegistrySubKey ([string]$Key, [switch]$ReadOnly) {
    switch -Regex ($Key) {
        '^HKLM:\\(.*)' { $hive = "LocalMachine" }
        '^HKU:\\(.*)' { $hive = "Users" }
        '^HKCU:\\(.*)' { $hive = "CurrentUser" }
        '^registry::HKEY_LOCAL_MACHINE\\(.*)' { $hive = "LocalMachine" }
        '^registry::HKEY_USERS\\(.*)' { $hive = "Users" }
        '^registry::HKEY_CURRENT_USER\\(.*)' { $hive = "CurrentUser" }
    }

    try {
        $regKey = [Microsoft.Win32.RegistryKey]::OpenBaseKey($hive,[Microsoft.Win32.RegistryView]::Registry64)

        switch ($ReadOnly) {
            $true { return $regKey.OpenSubKey($Matches[1]) }
            $false { return $regKey.OpenSubKey($Matches[1],$true) }
        }
    }
    catch {
         throw 'Error opening registry hive. '
    }
}

function Format-StringValue ([string]$Value) {
    return $Value.Replace('"', '').Replace("'", '').Trim()
}

function Split-SeparatedValue ([string]$Value, [string]$Separator) {
    [string]$formattedString = Format-StringValue -Value $Value
    $valueList = $formattedString.Split($Separator, [stringsplitoptions]::RemoveEmptyEntries)
    [string[]]$result = @()

    if (Test-CollectionNullOrEmpty -Collection $valueList) { return $result }

    foreach ($value in $valueList) {
        $result += $value.Trim()
    }

    return $result
}

function Test-CollectionNullOrEmpty ([psobject[]]$Collection) {
    return $null -eq $Collection -or ($Collection | Measure-Object).Count -eq 0
}

function Edit-StringListResult ([string[]]$StringList) {
    return $(if ($StringList.Count -gt 0) { $StringList } else { '-' })
}

#
# Input parameter validation
#
function Test-InputParameters ([hashtable]$InputParameters) {
    Write-NxtLog -Message "Calling $($MyInvocation.MyCommand)"

    Test-ProcessName `
        -ParamName 'ApplicationsToExclude' `
        -ParamValue $InputParameters.ApplicationsToExclude

    Test-ParamInAllowedRange `
        -ParamName 'XMLMaxAgeInDays' `
        -ParamValue $InputParameters.XMLMaxAgeInDays `
        -LowerLimit 1 `
        -UpperLimit 60
}

function Test-ProcessName ([string]$ParamName, [string]$ParamValue) {
    Write-NxtLog -Message "Calling $($MyInvocation.MyCommand)"

    $regex = '[' + [regex]::Escape('<>:"/\|?*') + ']'
    if ($ParamValue -match $regex) {
        throw "$($ERROR_EXCEPTION_TYPE.Input) Input parameter '$($ParamName)' contains one or more illegal characters. "
    }
}

#
# Environment management
#
function Initialize-StartUpImpactEnv {
    Write-NxtLog -Message "Calling $($MyInvocation.MyCommand)"

    return @{SID = ''
             XmlStartUpFilePath = ''
             XmlStartUpFileTime = Get-Date
             StartUpRegistryPrograms = [psobject[]]@()
             StartUpFolderPrograms = [psobject[]]@()
             AllStartupPrograms = [string[]]@()
             HighImpactResults = [string[]]@()
             HighImpactActionableApplications = [string[]]@()
             MediumImpactResults = [string[]]@()
             MediumImpactActionableApplications = [string[]]@()
             LowImpactResults = [string[]]@()
             LowImpactActionableApplications = [string[]]@()
             NotMeasuredImpactResults = [string[]]@()
             NotMeasuredActionableApplications = [string[]]@()}
}

function Initialize-ImpactLevelType {
    Write-NxtLog -Message "Calling $($MyInvocation.MyCommand)"

    if (-not $('ImpactLevel' -as [type])) {
        Add-Type -TypeDefinition 'public enum ImpactLevel {High, Medium, Low}'
    }
}

function Invoke-StartUpImpactInfo ([hashtable]$StartUpImpactEnv, [string]$Exclude, [int]$Days) {
    Write-NxtLog -Message "Calling $($MyInvocation.MyCommand)"

    Update-EnvironmentInfo -StartUpImpactEnv $startUpImpactEnv -Days $Days
    [psobject]$startUpData = Get-StartUpData -File $startUpImpactEnv.XmlStartUpFilePath
    [psobject[]]$startUpImpact = Measure-StartUpImpact -StartUpImpactEnv $startUpImpactEnv `
                                                       -StartUpData $startUpData
    [psobject[]]$filteredPrograms = Edit-StartUpImpactWithExcludeFilter -StartUpPrograms $startUpImpact `
                                                                        -Exclude $Exclude
    Update-StartUpImpactResults -StartUpImpactEnv $startUpImpactEnv -StartUpImpact $filteredPrograms
}

function Update-EnvironmentInfo ([hashtable]$StartUpImpactEnv, [int]$Days) {
    Write-NxtLog -Message "Calling $($MyInvocation.MyCommand)"

    $fileInfo = Get-XmlStartUpFileInfo -Days $Days
    $StartUpImpactEnv.XmlStartUpFilePath = $fileInfo.FullName
    [string]$StartUpImpactEnv.SID = $fileInfo.SID
    [datetime]$StartUpImpactEnv.XmlStartUpFileTime = $fileInfo.LastWriteTime
    [psobject[]]$StartUpImpactEnv.StartUpRegistryPrograms = Get-StartUpRegistryPrograms -SID $fileInfo.SID
    [psobject[]]$StartUpImpactEnv.StartUpFolderPrograms = Get-StartUpFolderPrograms -SID $fileInfo.SID
}

#
# XML StartUp file management
#
function Get-XmlStartUpFileInfo ([int]$Days) {
    Write-NxtLog -Message "Calling $($MyInvocation.MyCommand)"

    $date = (Get-Date).AddDays(-$Days)
    $file = Get-XmlStartUpFile

    if ($date -gt $file.LastWriteTime){
        throw "$($ERROR_EXCEPTION_TYPE.Environment) Obsolete file. "
    }

    return @{FullName = $file.FullName
             SID = (Get-SIDFromFileName -Name $file.Name)
             LastWriteTime = $file.LastWriteTime.ToUniversalTime()}
}

function Get-XmlStartUpFile {
    Write-NxtLog -Message "Calling $($MyInvocation.MyCommand)"

    $numberOfSession = Get-NumberOfSessions
    $file = Get-ChildItem -Path $STARTUP_INFO_FOLDER_PATH -Force -ErrorAction SilentlyContinue |
                Where-Object { $_.Name -match $FILE_NAME_REGEX } |
                Sort-Object LastWriteTime | Select-Object -Last 1
    if (($null -eq $file) -and ($numberOfSession -ge 6)){
        throw "$($ERROR_EXCEPTION_TYPE.Environment) Winlogon providers exceed the maximum allowed. More info in the Remote Action documentation. "
    }
    if ($null -eq $file) {
        throw "$($ERROR_EXCEPTION_TYPE.Environment) Application startup data does not exist or access is forbidden. "
    }

    return $file
}

function Get-NumberOfSessions {
    Write-NxtLog -Message "Calling $($MyInvocation.MyCommand)"

    $winlogonLoggers = @()

    foreach ($logger in $LOGGERS) {
        $providers = Get-ChildItem -Path ('registry::' + $logger.Name)
        foreach ($provider in $providers) {
            if ($provider.Name -like '*DBE9B383-7CF3-4331-91CC-A3CB16A3B538*') {
                $winlogonLoggers += $logger.Name
            }
        }
    }
    return $winlogonLoggers.Count
}

function Get-SIDFromFileName ([string]$Name) {
    Write-NxtLog -Message "Calling $($MyInvocation.MyCommand)"

    return $(if ($Name -match '^S-1-(5|12)-(1|21)-(\d+-){1,12}\d+') { $Matches[0] })
}

function Get-StartUpRegistryPrograms ([string]$SID) {
    Write-NxtLog -Message "Calling $($MyInvocation.MyCommand)"

    [string[]]$runKeys = Get-StartUpRegistryPaths -SID $SID

    [psobject[]]$result = @()
    foreach ($key in $runKeys | Where-Object { Test-Path -Path $_ }) {
        $result += Get-StartUpApplicationsFromRegistry -Key $key
    }

    return $result
}

function Get-StartUpRegistryPaths ([string]$SID) {
    Write-NxtLog -Message "Calling $($MyInvocation.MyCommand)"

    return $REGISTRY_APP_PATH.MachineRun + ($REGISTRY_APP_PATH.UserRun -f $SID)
}

function Get-StartUpApplicationsFromRegistry ([string]$Key) {
    Write-NxtLog -Message "Calling $($MyInvocation.MyCommand)"

    [psobject[]]$result = @()
    [string[]]$names = Get-RegistryPropertyName -Path $Key
    foreach ($name in $names) {
        $appPath = Get-RegistryKeyProperty -Key $Key -Property $name
        $result += Get-StartupApplicationObject -Name $name -Path ($appPath -replace '"')
    }
    return $result
}

function Get-RegistryPropertyName ([string]$Path) {
    Write-NxtLog -Message "Calling $($MyInvocation.MyCommand)"

    if ([string]::IsNullOrEmpty($Path)) { return }
    return Get-Item -Path $Path -ErrorAction SilentlyContinue |
               Select-Object -ExpandProperty 'Property'
}

function Get-StartupApplicationObject ([string]$Name, [string]$Path) {
    Write-NxtLog -Message "Calling $($MyInvocation.MyCommand)"

    return New-Object -TypeName psobject -Property @{StartupApplicationName = $Name
                                                     StartupApplicationPath = $Path}
}

function Get-StartUpFolderPrograms ([string]$SID) {
    Write-NxtLog -Message "Calling $($MyInvocation.MyCommand)"

    $folderPaths = @(Get-FolderPaths -SID $SID)
    [psobject[]]$result = @()

    foreach ($path in $folderPaths) {
        $startUpItems = Get-AllStartUpFolderExecutables -Path $path
        foreach ($item in $startUpItems) {
            $result += Get-StartUpFolderObject -Path $item
        }
    }

    return $result
}

function Get-FolderPaths ([string]$SID) {
    Write-NxtLog -Message "Calling $($MyInvocation.MyCommand)"

    $result = @($REGISTRY_APP_PATH.MachineStartupFolder)
    $userStartupPath = $REGISTRY_APP_PATH.UserStartupFolder -f $SID
    if (Test-Path -Path $userStartupPath) {
        $targetPath = Get-RegistryKeyProperty -Key $userStartupPath -Property 'Startup'
        $result += $targetPath
    }

    return $result
}

function Get-AllStartUpFolderExecutables ([string]$Path) {
    Write-NxtLog -Message "Calling $($MyInvocation.MyCommand)"

    return @(Get-ChildItem -Path $Path -ErrorAction SilentlyContinue |
                 Select-Object -ExpandProperty FullName)
}

function Get-StartUpFolderObject ([string]$Path) {
    Write-NxtLog -Message "Calling $($MyInvocation.MyCommand)"

    return New-Object –TypeName psobject -Property (Get-ExecutableProperties -Path $Path)
}

function Get-ExecutableProperties ([string]$Path) {
    Write-NxtLog -Message "Calling $($MyInvocation.MyCommand)"

    if ($Path -match '(\.lnk|\.url)') {
        [string]$targetPath = Get-ShortcutPathWithArguments -Name $Path
        $property = 'Name'
    } else {
        $targetPath = $Path
        $property = 'BaseName'
    }

    return @{StartupApplicationName = (Get-Item -Path $Path | Select-Object -ExpandProperty $property)
             StartupApplicationPath = (Format-StringValue -Value $targetPath)}
}

function Get-ShortcutPathWithArguments ([string]$Name) {
    Write-NxtLog -Message "Calling $($MyInvocation.MyCommand)"

    $shell = New-Object -COM wscript.shell
    $shortCut = $shell.CreateShortcut($Name)
    return ('{0} {1}' -f $shortCut.TargetPath, $shortCut.Arguments).Trim()
}

function Get-StartUpData ([string]$File) {
    Write-NxtLog -Message "Calling $($MyInvocation.MyCommand)"

    $processData = @(Import-XmlData -File $File)
    return Group-ProcessData -ProcessData $processData
}

function Import-XmlData ([string]$File) {
    Write-NxtLog -Message "Calling $($MyInvocation.MyCommand)"

    $processes = Read-XmlFile -File $File
    $result = @()
    foreach ($process in $processes) { $result += Get-ObjectFromXmlItem -Item $process }

    return $result
}

function Read-XmlFile ([string]$File) {
    Write-NxtLog -Message "Calling $($MyInvocation.MyCommand)"

    $xmlContent = (Get-Content -Path $File -Force -ErrorAction SilentlyContinue) -as [string]
    if ([string]::IsNullOrEmpty($xmlContent)) {
        throw "$($ERROR_EXCEPTION_TYPE.Internal) Not possible to get the content of $("$File") or content is empty. "
    }
    [xml]$xmlData = (Format-XmlReservedMarkupCharacters -XmlContent $xmlContent) -as [xml]
    return $xmlData.StartupData.Process
}

function Format-XmlReservedMarkupCharacters([string]$XmlContent) {
    Write-NxtLog -Message "Calling $($MyInvocation.MyCommand)"

    $ampersand = "(?<Item>$($XML_RESERVED_MARKUP_CHARACTERS.Ampersand))"
    $replacedAmpersand = "${Item}$($XML_RESERVED_MARKUP_CHARACTERS.EscapedAmpersand)"
    $apostrophe = "(?<Item>$($XML_RESERVED_MARKUP_CHARACTERS.Apostrophe))"
    $replacedApostrophe = "${Item}$($XML_RESERVED_MARKUP_CHARACTERS.EscapedApostrophe)"
    $percent = "(?<Item>$($XML_RESERVED_MARKUP_CHARACTERS.Percent))"
    $replacedPercent = "${Item}$($XML_RESERVED_MARKUP_CHARACTERS.EscapedPercent)"

    $replacedCharactersFile = $XmlContent -replace $ampersand,$replacedAmpersand `
                                          -replace $apostrophe,$replacedApostrophe `
                                          -replace $percent,$replacedPercent

    return $replacedCharactersFile
}

function Get-ObjectFromXmlItem ([psobject]$Item) {
    Write-NxtLog -Message "Calling $($MyInvocation.MyCommand)"

    return New-Object psobject -Property @{Name = [string]$Item.Name
                                           StartTime = [string]$Item.StartTime
                                           CommandLine = [string]$Item.CommandLine.'#cdata-section'
                                           DiskUsageB = [long]$Item.DiskUsage.'#text'
                                           CpuTimsUs = [long]$Item.CpuUsage.'#text'
                                           ParentName = [string]$Item.ParentName
                                           ParentStartTime = [string]$Item.ParentStartTime}
}

function Group-ProcessData ([array]$ProcessData) {
    Write-NxtLog -Message "Calling $($MyInvocation.MyCommand)"

    $processHierarchy = Get-ProcessHierarchy -ProcessData $ProcessData

    $result = @()
    for ($processIndex = 0; $processIndex -lt $ProcessData.Count; $processIndex++) {
        if ($null -ne (Get-ParentProcessIndex -ProcessIndex $processIndex -ProcessData $ProcessData)) { continue }

        $result += New-Object -TypeName psobject -Property (Get-ProcessObjectProperties -Index $processIndex `
                                                                                        -ProcessData $ProcessData `
                                                                                        -Hierarchy $processHierarchy)
    }

    return $result
}

function Get-ProcessHierarchy ([array]$ProcessData) {
    Write-NxtLog -Message "Calling $($MyInvocation.MyCommand)"

    $hierarchy = @{}

    for ($processIndex = 0; $processIndex -lt $ProcessData.Count; $processIndex++) {
        $parentIndex = Get-ParentProcessIndex -ProcessIndex $processIndex -ProcessData $ProcessData
        if ($null -eq $parentIndex) {
            if (-not ($hierarchy.Contains($processIndex))) {
                $hierarchy[$processIndex] = @()
            }
        } else {
            if (-not ($hierarchy.Contains($parentIndex))) { $hierarchy[$parentIndex] = @() }
            $hierarchy[$parentIndex] += $processIndex
        }
    }

    return $hierarchy
}

function Get-ParentProcessIndex ([int]$ProcessIndex, [array]$ProcessData) {
    Write-NxtLog -Message "Calling $($MyInvocation.MyCommand)"

    $parentName = $ProcessData[$ProcessIndex].ParentName
    $parentStartTime = $ProcessData[$ProcessIndex].ParentStartTime

    for ($pIndex = 0; $pIndex -lt $ProcessData.Count; $pIndex++) {
        $process = $ProcessData[$pIndex]
        if (($process.Name -match $parentName -or `
             $process.CommandLine -match $parentName) -and `
            $process.StartTime -eq $parentStartTime) { return $pIndex }
    }
}

function Get-ProcessObjectProperties ([int]$Index, [array]$ProcessData, [hashtable]$Hierarchy) {
    Write-NxtLog -Message "Calling $($MyInvocation.MyCommand)"

    $diskAndCpu = @{DiskUsageB = 0
                    CpuTimsUs = 0}
    Get-ProcessDiskAndCpu -ProcessIndex $Index -ProcessData $ProcessData `
                          -ProcessHierarchy $Hierarchy -DiskAndCpu $diskAndCpu
    return Get-ProcessProperties -DiskAndCpu $diskAndCpu -Process $ProcessData[$Index]
}

function Get-ProcessDiskAndCpu ([int]$ProcessIndex,
                                [array]$ProcessData,
                                [hashtable]$ProcessHierarchy,
                                [hashtable]$DiskAndCpu) {
    Write-NxtLog -Message "Calling $($MyInvocation.MyCommand)"

    if ($null -eq $ProcessData) { return }

    $process = $ProcessData[$ProcessIndex]
    $DiskAndCpu.DiskUsageB += $process.DiskUsageB
    $DiskAndCpu.CpuTimsUs += $process.CpuTimsUs

    foreach ($childIndex in $ProcessHierarchy[$ProcessIndex]) {
        Get-ProcessDiskAndCpu -ProcessIndex $childIndex -ProcessData $ProcessData `
                              -ProcessHierarchy $ProcessHierarchy -DiskAndCpu $DiskAndCpu
    }
}

function Get-ProcessProperties ([hashtable]$DiskAndCpu, [psobject]$Process) {
    Write-NxtLog -Message "Calling $($MyInvocation.MyCommand)"

    return @{CommandLine = $Process.CommandLine
             CommandLineNoQuotes = Format-StringValue -Value $Process.CommandLine
             DiskUsageB = $DiskAndCpu.DiskUsageB
             CpuTimsUs = $DiskAndCpu.CpuTimsUs
             Parent = $Process.ParentName}
}

function Measure-StartUpImpact ([hashtable]$StartUpImpactEnv, [psobject]$StartUpData) {
    Write-NxtLog -Message "Calling $($MyInvocation.MyCommand)"

    [string[]]$disabledApplications = @(Get-DisabledAutoStartApplications -SID $StartUpImpactEnv.SID)
    [psobject[]]$allPrograms = $StartUpImpactEnv.StartUpRegistryPrograms + $StartUpImpactEnv.StartUpFolderPrograms

    [psobject[]]$result = @()
    foreach ($program in $allPrograms) {
        if ([string]::IsNullOrEmpty($program.StartupApplicationPath)) { continue }
        $properties = New-ProcessProperties -DisabledApplications $disabledApplications `
                                            -StartUpData $StartUpData `
                                            -Program $program
        $result += New-Object -TypeName psobject -Property $properties
    }

    return $result
}

function New-ProcessProperties ([string[]]$DisabledApplications, [psobject]$StartUpData, [psobject]$Program) {
    Write-NxtLog -Message "Calling $($MyInvocation.MyCommand)"

    $process = Get-DefaultProcessProperties
    $process.Name = $Program.StartupApplicationName
    $process.IsEnabled = -not ($DisabledApplications.Count -ne 0 -and `
                                $DisabledApplications.Contains($process.Name))
    $process.CommandLine = $Program.StartupApplicationPath

    $volatileProperties = Get-VolatileProcessProperties -StartupData $StartUpData `
                                                        -Path $Program.StartupApplicationPath
    if ($null -ne $volatileProperties) {
        $process.CommandLine = $volatileProperties.CommandLine
        $process.StartedBy = $volatileProperties.StartedBy
        $process.CpuTimsUs = $volatileProperties.CpuTimsUs
        $process.DiskUsageB = $volatileProperties.DiskUsageB
        $process.Impact = $volatileProperties.Impact
        $process.Score = $volatileProperties.Score
    }

    $executablePath = Get-ExecutablePath -CommandLine $process.CommandLine
    $process.Program = $(if ([string]::IsNullOrEmpty($executablePath)) { $process.Name }
                         else { Get-FileDescription -Path $executablePath })
    return $process
}

function Get-DefaultProcessProperties {
    Write-NxtLog -Message "Calling $($MyInvocation.MyCommand)"

    return @{Name = ''
             Program = ''
             CommandLine = ''
             StartedBy = 'Unknown'
             CpuTimsUs = [long]0
             DiskUsageB = [long]0
             IsEnabled = $false
             Impact = 'Unknown'
             Score = [long]0}
}

function Get-VolatileProcessProperties ([psobject]$StartUpData, [string]$Path) {
    Write-NxtLog -Message "Calling $($MyInvocation.MyCommand)"

    $programImpact = $StartUpData |
                         Where-Object { $_.CommandLineNoQuotes -match [regex]::Escape($Path) }
    if ($null -eq $programImpact) { return }
    $result = @{}

    $result.CommandLine = $programImpact | Select-Object -ExpandProperty 'CommandLine' -First 1
    [string]$result.StartedBy = $programImpact | Select-Object -ExpandProperty 'Parent' -First 1
    [long]$result.CpuTimsUs = Get-PropertySum -Object $programImpact -Property 'CpuTimsUs'
    [long]$result.DiskUsageB = Get-PropertySum -Object $programImpact -Property 'DiskUsageB'
    $result.Impact = Get-ImpactFromCpuTimeAndDiskUsage -CpuTimsUs $result.CpuTimsUs `
                                                            -DiskUsageB $result.DiskUsageB
    [long]$result.Score = Get-ImpactScore -CpuTimsUs $result.CpuTimsUs `
                                               -DiskUsageB $result.DiskUsageB
    return $result
}

function Get-DisabledAutoStartApplications ([string]$SID) {
    Write-NxtLog -Message "Calling $($MyInvocation.MyCommand)"

    [string[]]$result = @()
    $approvedSubKeys = Get-ApprovedRegistrySubKeys -SID $SID

    foreach ($subKey in $approvedSubKeys) {
        $name = Get-DisabledApplicationNameFromRegistry -Path $subKey
        if ($null -ne $name) { $result += $name }
    }

   return $result | Select-Object -Unique
}

function Get-DisabledApplicationNameFromRegistry ([string]$Path) {
    Write-NxtLog -Message "Calling $($MyInvocation.MyCommand)"

    [string[]]$result = @()
    $item = Get-ItemProperty -Path $Path -ErrorAction SilentlyContinue

    if ($null -eq $item -or $null -eq $item.PSObject.Properties) { return }

    $propertyValue = $item.PSObject.Properties | Select-Object -Property Name, Value

    foreach ($j in $propertyValue) {
        if (Test-ExpectedRegValueForNameRetrieval -Value $j.Value) { $result += $j.Name }
    }
    return $result | Sort-Object
}

function Test-ExpectedRegValueForNameRetrieval ([psobject]$Value) {
    Write-NxtLog -Message "Calling $($MyInvocation.MyCommand)"

    return ($Value -is [byte[]]) -and ($Value[0] -eq 3 -or $Value[0] -eq 7)
}

function Get-ApprovedRegistrySubKeys ([string]$SID) {
    Write-NxtLog -Message "Calling $($MyInvocation.MyCommand)"

    $startUpApprovedKeys = $REGISTRY_APP_PATH.MachineStartupApproved
    $startUpApprovedKeys += $REGISTRY_APP_PATH.UserStartupApproved -f $SID

    [string[]]$result = @()
    foreach ($item in $startUpApprovedKeys) {
        if (Test-Path -Path $item) {
            $result += Get-ChildItem -Path $item | Select-Object -ExpandProperty Name
        }
    }
    return $result -replace '^HKEY', 'registry::HKEY'
}

function Get-PropertySum ([psobject]$Object, [string]$Property) {
    Write-NxtLog -Message "Calling $($MyInvocation.MyCommand)"

    return ($Object | Select-Object -ExpandProperty $Property |
                Measure-Object -Sum |
                Select-Object -ExpandProperty Sum)
}

function Get-ImpactFromCpuTimeAndDiskUsage ([long]$CpuTimsUs, [long]$DiskUsageB) {
    Write-NxtLog -Message "Calling $($MyInvocation.MyCommand)"

    if ($CpuTimsUs -gt $CPU_HIGH_IMPACT_LEVEL -or $DiskUsageB -gt $DISK_USAGE_HIGH_IMPACT_LEVEL) {
        $impact = [impactlevel]::High
    } elseif ($CpuTimsUs -lt $CPU_MEDIUM_IMPACT_LEVEL -and $DiskUsageB -lt $DISK_USAGE_MEDIUM_IMPACT_LEVEL) {
        $impact = [impactlevel]::Low
    } else {
        $impact = [impactlevel]::Medium
    }

    return [string]$impact
}

function Get-ImpactScore ([long]$CpuTimsUs, [long]$DiskUsageB) {
    Write-NxtLog -Message "Calling $($MyInvocation.MyCommand)"

    return [math]::Abs($DiskUsageB - $CpuTimsUs)
}

function Get-ExecutablePath ([string]$CommandLine) {
    Write-NxtLog -Message "Calling $($MyInvocation.MyCommand)"

    $cleanedCommandLine = Get-CleanedCommandLine -CommandLine $CommandLine

    [void]($cleanedCommandLine -match $EXECUTABLE_PATH_REGEX)
    $path = $Matches.Path.Replace('"', '').Replace($SPACE_REPLACEMENT, ' ')
    if ([string]::IsNullOrEmpty($path) -or (-not (Test-Path -Path $path -IsValid))) {
        return
    }

    return $path
}

function Get-CleanedCommandLine ([string]$CommandLine) {
    Write-NxtLog -Message "Calling $($MyInvocation.MyCommand)"

    $cleanedCommandLine = $CommandLine.Trim().ToLower()

    $folderWithSpaces = $cleanedCommandLine |
                            Select-String $FOLDERS_WITH_SPACES_REGEX -AllMatches
    if ($null -eq $folderWithSpaces) { return $cleanedCommandLine }
    foreach($match in $folderWithSpaces.Matches) {
        $matchValue = $match.Value
        $stringWithoutSpaces = $matchValue.Replace(' ', $SPACE_REPLACEMENT)
        $cleanedCommandLine = $cleanedCommandLine.Replace($matchValue, $stringWithoutSpaces)
    }

    return $cleanedCommandLine
}

function Get-FileDescription ([string]$Path) {
    Write-NxtLog -Message "Calling $($MyInvocation.MyCommand)"

    $executable = $Path.Substring($Path.LastIndexOf('\') + 1)
    if (-not (Test-Path -Path $Path) -or $Path -notmatch '\\.*\.exe.*') { return $executable }

    $description = [diagnostics.fileversioninfo]::GetVersionInfo($Path).FileDescription

    return $(if ([string]::IsNullOrEmpty($description)) { $executable } else { $description })
}

function Edit-StartUpImpactWithExcludeFilter ([psobject[]]$StartUpPrograms, [string]$Exclude) {
    Write-NxtLog -Message "Calling $($MyInvocation.MyCommand)"

    if ([string]::IsNullOrEmpty($Exclude)) { return $StartUpPrograms }

    $filters = Split-SeparatedValue -Value $Exclude -Separator ','
    [psobject[]]$result = @()
    foreach ($program in $StartUpPrograms) {
        $filterMatch = $false
        foreach ($filter in $filters) {
            if ($program.Program -match $filter -or $program.Name -match $filter) {
                $filterMatch = $true
                break
            }
        }
        if (-not $filterMatch) { $result += $program }
    }

    return $result
}

#
# Output management
#
function Update-StartUpImpactResults ([hashtable]$StartUpImpactEnv, [psobject[]]$StartUpImpact) {
    Write-NxtLog -Message "Calling $($MyInvocation.MyCommand)"

    $startupKeys = Get-ApprovedRegistrySubKeys -SID $StartUpImpactEnv.SID
    $runKeys = $REGISTRY_APP_PATH.MachineRun
    $runKeys += $REGISTRY_APP_PATH.UserRun

    foreach ($level in $IMPACT_LEVELS) {
        $disableApplications = @()
        $removeApplications = @()
        $objects = Get-ProgramWithGivenImpactLevel -StartUpImpact $StartUpImpact -ImpactLevel $level

        if (Test-CollectionNullOrEmpty -Collection $objects) { continue }

        foreach ($Application in $objects) {
            if (Get-ItemProperty -Path $startupKeys -Name $Application.Name -ErrorAction SilentlyContinue) {
                $disableApplications += $Application.Name
                continue
            }
            if (Get-ItemProperty -Path $runKeys -Name $Application.Name -ErrorAction SilentlyContinue) {
                $removeApplications += $Application.Name
                continue
            }
        }

        if ($level -eq 'Unknown') {
            $StartUpImpactEnv.NotMeasuredImpactResults = Get-UnknownProgramImpact -ProgramImpact $objects
            $StartUpImpactEnv.NotMeasuredImpactRemove = $removeApplications
            $StartUpImpactEnv.NotMeasuredImpactActionableResults = $objects |
                                                                       Sort-Object -Property IsEnabled -Descending |
                                                                       Select-Object -ExpandProperty Name
        } else {
            $key = $level + 'ImpactResults'
            $statusKey = $level + 'ImpactRemove'
            $actionableKey = $level + 'ImpactActionableResults'
            $StartUpImpactEnv[$key] += Get-KnownProgramImpact -ProgramImpact $objects
            $StartUpImpactEnv[$statusKey] = $removeApplications
            $StartUpImpactEnv[$actionableKey] = $objects.Name
        }
    }
}

function Get-ProgramWithGivenImpactLevel ([psobject[]]$StartUpImpact, [string]$ImpactLevel) {
    Write-NxtLog -Message "Calling $($MyInvocation.MyCommand)"

    [psobject[]]$programImpact = $StartUpImpact | Where-Object { $_.Impact -match $ImpactLevel }

    return $(if (-not (Test-CollectionNullOrEmpty -Collection $programImpact)) {
                 $programImpact | Sort-Object -Property Score -Descending |
                     Select-Object -Property Program, Impact, IsEnabled, DiskUsageB, CpuTimsUs, Name
            })
}

function Get-UnknownProgramImpact ([psobject[]]$ProgramImpact) {
    Write-NxtLog -Message "Calling $($MyInvocation.MyCommand)"

    [string[]]$programImpactList = @()
    if (Test-CollectionNullOrEmpty -Collection $ProgramImpact) { return $programImpactList }

    $sortedProgramImpact = $ProgramImpact | Sort-Object -Property IsEnabled -Descending

    foreach ($item in $sortedProgramImpact) {
        $programState = $(if ($item.IsEnabled) { 'not measured' } else { 'disabled' })
        $programImpactList += ('{0} ({1})' -f ($item.Program).Trim(), $programState)
    }

    return $programImpactList
}

function Get-KnownProgramImpact ([psobject[]]$ProgramImpact) {
    Write-NxtLog -Message "Calling $($MyInvocation.MyCommand)"

    [string[]]$programImpactList = @()

    foreach ($item in $ProgramImpact) {
        $programName = ($item.Program).Trim()
        $cpuTimsUs = Convert-MicroToMilli -Value $item.CpuTimsUs
        $diskUsageMB = Convert-BytesToMB -NumBytes $item.DiskUsageB

        $programImpactList += '{0} ({1}ms; {2}MB)' -f $programName, $cpuTimsUs, $diskUsageMB
    }

    return $programImpactList
}

function Convert-MicroToMilli ([long]$Value) {
    Write-NxtLog -Message "Calling $($MyInvocation.MyCommand)"

    return [math]::Round($Value / 1000)
}

function Convert-BytesToMB ([long]$NumBytes) {
    Write-NxtLog -Message "Calling $($MyInvocation.MyCommand)"

    $diskUsageMB = [math]::Round($NumBytes / 1MB, 1)
    if ($diskUsageMB -eq 0) {
        $diskUsageMB = 0.1
    }
    return $diskUsageMB
}

function Update-EngineOutputVariables ([hashtable]$StartUpImpactEnv) {
    Write-NxtLog -Message "Calling $($MyInvocation.MyCommand)"

    [nxt]::WriteOutputString('UserSID', $StartUpImpactEnv.SID)
    [nxt]::WriteOutputDateTime('LastStartUpAnalysisDate', $StartUpImpactEnv.XmlStartUpFileTime)

    [nxt]::WriteOutputUInt32('HighImpactCount', $StartUpImpactEnv.HighImpactResults.Count)
    [string[]]$highImpactResults = Edit-StringListResult -StringList $StartUpImpactEnv.HighImpactResults
    [nxt]::WriteOutputStringList('HighImpactApplications', $highImpactResults)
    [string[]]$highImpactActionable = Edit-StringListResult -StringList $StartUpImpactEnv.HighImpactActionableResults
    [nxt]::WriteOutputStringList('HighImpactActionableApplications', $highImpactActionable)
    [string[]]$highImpactRemove = Edit-StringListResult -StringList $StartUpImpactEnv.HighImpactRemove
    [nxt]::WriteOutputStringList('HighImpactRemove', $highImpactRemove)

    [nxt]::WriteOutputUInt32('MediumImpactCount', $StartUpImpactEnv.MediumImpactResults.Count)
    [string[]]$mediumImpactResults = Edit-StringListResult -StringList $StartUpImpactEnv.MediumImpactResults
    [nxt]::WriteOutputStringList('MediumImpactApplications', $mediumImpactResults)
    [string[]]$mediumImpactActionable = Edit-StringListResult -StringList $StartUpImpactEnv.MediumImpactActionableResults
    [nxt]::WriteOutputStringList('MediumImpactActionableApplications', $mediumImpactActionable)
    [string[]]$mediumImpactRemove = Edit-StringListResult -StringList $StartUpImpactEnv.MediumImpactRemove
    [nxt]::WriteOutputStringList('MediumImpactRemove', $mediumImpactRemove)

    [nxt]::WriteOutputUInt32('LowImpactCount', $StartUpImpactEnv.LowImpactResults.Count)
    [string[]]$lowImpactResults = Edit-StringListResult -StringList $StartUpImpactEnv.LowImpactResults
    [nxt]::WriteOutputStringList('LowImpactApplications', $LowImpactResults)
    [string[]]$lowImpactActionable = Edit-StringListResult -StringList $StartUpImpactEnv.LowImpactActionableResults
    [nxt]::WriteOutputStringList('LowImpactActionableApplications', $lowImpactActionable)
    [string[]]$lowImpactRemove = Edit-StringListResult -StringList $StartUpImpactEnv.LowImpactRemove
    [nxt]::WriteOutputStringList('LowImpactRemove', $lowImpactRemove)

    [string[]]$notMeasuredImpactResults = Edit-StringListResult -StringList $StartUpImpactEnv.NotMeasuredImpactResults
    [nxt]::WriteOutputStringList('NotMeasuredImpactApplications', $notMeasuredImpactResults)
    [string[]]$notMeasuredImpactActionable = Edit-StringListResult -StringList $StartUpImpactEnv.NotMeasuredImpactActionableResults
    [nxt]::WriteOutputStringList('NotMeasuredImpactActionableApplications', $notMeasuredImpactActionable)
    [string[]]$notMeasuredImpactRemove = Edit-StringListResult -StringList $StartUpImpactEnv.NotMeasuredImpactRemove
    [nxt]::WriteOutputStringList('NotMeasuredImpactRemove', $notMeasuredImpactRemove)
}

#
# Main script flow
#
[environment]::Exit((Invoke-Main -InputParameters $MyInvocation.BoundParameters))

# SIG # Begin signature block
# MIIu8AYJKoZIhvcNAQcCoIIu4TCCLt0CAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCC9/oFjNl34kdu3
# tqeo64sNQzVRCpIjlZpN4/H1JgEPOKCCETswggPFMIICraADAgECAhACrFwmagtA
# m48LefKuRiV3MA0GCSqGSIb3DQEBBQUAMGwxCzAJBgNVBAYTAlVTMRUwEwYDVQQK
# EwxEaWdpQ2VydCBJbmMxGTAXBgNVBAsTEHd3dy5kaWdpY2VydC5jb20xKzApBgNV
# BAMTIkRpZ2lDZXJ0IEhpZ2ggQXNzdXJhbmNlIEVWIFJvb3QgQ0EwHhcNMDYxMTEw
# MDAwMDAwWhcNMzExMTEwMDAwMDAwWjBsMQswCQYDVQQGEwJVUzEVMBMGA1UEChMM
# RGlnaUNlcnQgSW5jMRkwFwYDVQQLExB3d3cuZGlnaWNlcnQuY29tMSswKQYDVQQD
# EyJEaWdpQ2VydCBIaWdoIEFzc3VyYW5jZSBFViBSb290IENBMIIBIjANBgkqhkiG
# 9w0BAQEFAAOCAQ8AMIIBCgKCAQEAxszlc+b71LvlLS0ypt/lgT/JzSVJtnEqw9WU
# NGeiChywX2mmQLHEt7KP0JikqUFZOtPclNY823Q4pErMTSWC90qlUxI47vNJbXGR
# fmO2q6Zfw6SE+E9iUb74xezbOJLjBuUIkQzEKEFV+8taiRV+ceg1v01yCT2+OjhQ
# W3cxG42zxyRFmqesbQAUWgS3uhPrUQqYQUEiTmVhh4FBUKZ5XIneGUpX1S7mXRxT
# LH6YzRoGFqRoc9A0BBNcoXHTWnxV215k4TeHMFYE5RG0KYAS8Xk5iKICEXwnZreI
# t3jyygqoOKsKZMK/Zl2VhMGhJR6HXRpQCyASzEG7bgtROLhLywIDAQABo2MwYTAO
# BgNVHQ8BAf8EBAMCAYYwDwYDVR0TAQH/BAUwAwEB/zAdBgNVHQ4EFgQUsT7DaQP4
# v0cB1JgmGggC72NkK8MwHwYDVR0jBBgwFoAUsT7DaQP4v0cB1JgmGggC72NkK8Mw
# DQYJKoZIhvcNAQEFBQADggEBABwaBpfc15yfPIhmBghXIdshR/gqZ6q/GDJ2QBBX
# wYrzetkRZY41+p78RbWe2UwxS7iR6EMsjrN4ztvjU3lx1uUhlAHaVYeaJGT2imbM
# 3pw3zag0sWmbI8ieeCIrcEPjVUcxYRnvWMWFL04w9qAxFiPI5+JlFjPLvxoboD34
# yl6LMYtgCIktDAZcUrfE+QqY0RVfnxK+fDZjOL1EpH/kJisKxJdpDemM4sAQV7jI
# dhKRVfJIadi8KgJbD0TUIDHb9LpwJl2QYJ68SxcJL7TLHkNoyQcnwdJc9+ohuWgS
# nDycv578gFybY83sR6olJ2egN/MAgn1U16n46S4To3foH0owggauMIIFlqADAgEC
# AhAKGg0bco+UuLdwFCB8KgrEMA0GCSqGSIb3DQEBCwUAMGwxCzAJBgNVBAYTAlVT
# MRUwEwYDVQQKEwxEaWdpQ2VydCBJbmMxGTAXBgNVBAsTEHd3dy5kaWdpY2VydC5j
# b20xKzApBgNVBAMTIkRpZ2lDZXJ0IEVWIENvZGUgU2lnbmluZyBDQSAoU0hBMikw
# HhcNMjAwODE3MDAwMDAwWhcNMjMwODIyMTIwMDAwWjCBwDETMBEGCysGAQQBgjc8
# AgEDEwJDSDEVMBMGCysGAQQBgjc8AgECEwRWYXVkMR0wGwYDVQQPDBRQcml2YXRl
# IE9yZ2FuaXphdGlvbjEYMBYGA1UEBRMPQ0hFLTExMi4wMDAuNTc5MQswCQYDVQQG
# EwJDSDEPMA0GA1UEBxMGUHJpbGx5MRYwFAYDVQQKEw1ORVhUaGluayBTLkEuMQsw
# CQYDVQQLEwJSRDEWMBQGA1UEAxMNTkVYVGhpbmsgUy5BLjCCAiIwDQYJKoZIhvcN
# AQEBBQADggIPADCCAgoCggIBALMbr8k5B4UT7E9+6Skoa3Ihy8v6vSHWa5TfptPn
# B1JQ7Bgsw6EDCI/HrIlcRRF+feXGYPYakJ5ng1ckM22u/FtAmrlhb5VLFOeMiub/
# R5cPQ6IhjdCnTiVPrBbYevCmyHOTdqc74GFygBK+g/ZLZqOWJDkhwVimTNTP1RO/
# Bec3JI3rr0CuIqqGvCt/TucPszVyuKRViw5gvMkawQvfwT8MmLfFkr98lt4BlTZG
# SkoPumES+bJdWMTtdTfZIk+KQv60oWmsWlI/Lxe+m1qInCEDLFnSsQIN+HGkabW5
# UiEJ6bDjZCIB5PhQXjv0WXLTGZqTcbBeBLIAn06L9TIH6oCG87QlrXdysODcaqiQ
# SkAJ7bXQscfWsRHWPrRzU36A2mOxDKERGxH3iPDxfV9NAEb8hdFTfxJRMa+hEAqt
# 6qx4PuUZbu7m8Trh+fHKo5S9bwXkYmi0TDONpYEQmb7+lefcHqLNaIgpfdK5h/0V
# lUlpDwlNGXMfE2aBhNR6L5O99r11Y2qJA1OmMBcPNoY7ljXmdMHu1V9/DE0JK4OY
# VxbnUVMqTf3/VgZxGecYMMfamjv42sPFvMdaCj8C3N4c0d4sWOltJkjCmi5fKw9y
# UGLzUzWOfx9y0aTQn9Sd/y68cBP/Jl/1kws3xP4Orszl5vAFenTQwtOHLgsok0EF
# FuaLAgMBAAGjggH1MIIB8TAfBgNVHSMEGDAWgBSP6H7wbTJqAAUjx3CXajqQ/2vq
# 1DAdBgNVHQ4EFgQUUluozPCIoYByuD4dVBcClbw4638wMgYDVR0RBCswKaAnBggr
# BgEFBQcIA6AbMBkMF0NILVZBVUQtQ0hFLTExMi4wMDAuNTc5MA4GA1UdDwEB/wQE
# AwIHgDATBgNVHSUEDDAKBggrBgEFBQcDAzB7BgNVHR8EdDByMDegNaAzhjFodHRw
# Oi8vY3JsMy5kaWdpY2VydC5jb20vRVZDb2RlU2lnbmluZ1NIQTItZzEuY3JsMDeg
# NaAzhjFodHRwOi8vY3JsNC5kaWdpY2VydC5jb20vRVZDb2RlU2lnbmluZ1NIQTIt
# ZzEuY3JsMEsGA1UdIAREMEIwNwYJYIZIAYb9bAMCMCowKAYIKwYBBQUHAgEWHGh0
# dHBzOi8vd3d3LmRpZ2ljZXJ0LmNvbS9DUFMwBwYFZ4EMAQMwfgYIKwYBBQUHAQEE
# cjBwMCQGCCsGAQUFBzABhhhodHRwOi8vb2NzcC5kaWdpY2VydC5jb20wSAYIKwYB
# BQUHMAKGPGh0dHA6Ly9jYWNlcnRzLmRpZ2ljZXJ0LmNvbS9EaWdpQ2VydEVWQ29k
# ZVNpZ25pbmdDQS1TSEEyLmNydDAMBgNVHRMBAf8EAjAAMA0GCSqGSIb3DQEBCwUA
# A4IBAQAY6IB4PnNczhdemVVidtT8XT0P+/Ej9bbaMImR6HELTcYX19gjksFNUrR6
# /XUPgaj/nSplr5Oj3DJ5JCPo2AVKwY1mUWS2uYoZRinEAodDfESqfTiR1982xp72
# go347GTMnppk2EpduIioi+dcwbbw1Df2nFzI3FcX7H1UIPd8M4p3UAt5WCiVMPHW
# XxrQt5n8jxgLcusvORXZqZOsdTl7HZpsVHnGUY787Ou0IJxuFsiUM64bKGzvNqqt
# YyFyR99ErCTqdZ66uraFilAgjPwaLFzJUw6+aK/wWxKB7Q0piICpeX1X0ILZu56G
# R206VEcmxWILYjQE2NZcT+7vbUzmMIIGvDCCBaSgAwIBAgIQA/G04V86gvEUlniz
# 19hHXDANBgkqhkiG9w0BAQsFADBsMQswCQYDVQQGEwJVUzEVMBMGA1UEChMMRGln
# aUNlcnQgSW5jMRkwFwYDVQQLExB3d3cuZGlnaWNlcnQuY29tMSswKQYDVQQDEyJE
# aWdpQ2VydCBIaWdoIEFzc3VyYW5jZSBFViBSb290IENBMB4XDTEyMDQxODEyMDAw
# MFoXDTI3MDQxODEyMDAwMFowbDELMAkGA1UEBhMCVVMxFTATBgNVBAoTDERpZ2lD
# ZXJ0IEluYzEZMBcGA1UECxMQd3d3LmRpZ2ljZXJ0LmNvbTErMCkGA1UEAxMiRGln
# aUNlcnQgRVYgQ29kZSBTaWduaW5nIENBIChTSEEyKTCCASIwDQYJKoZIhvcNAQEB
# BQADggEPADCCAQoCggEBAKdT+g+ytRPxZM+EgPyugDXRttfHoyysGiys8YSsOjUS
# OpKRulfkxMnzL6hIPLfWbtyXIrpReWGvQy8Nt5u0STGuRFg+pKGWp4dPI37DbGUk
# kFU+ocojfMVC6cR6YkWbfd5jdMueYyX4hJqarUVPrn0fyBPLdZvJ4eGK+AsMmPTK
# PtBFqnoepViTNjS+Ky4rMVhmtDIQn53wUqHv6D7TdvJAWtz6aj0bS612sIxc7ja6
# g+owqEze8QsqWEGIrgCJqwPRFoIgInbrXlQ4EmLh0nAk2+0fcNJkCYAt4radzh/y
# uyHzbNvYsxl7ilCf7+w2Clyat0rTCKA5ef3dvz06CSUCAwEAAaOCA1gwggNUMBIG
# A1UdEwEB/wQIMAYBAf8CAQAwDgYDVR0PAQH/BAQDAgGGMBMGA1UdJQQMMAoGCCsG
# AQUFBwMDMH8GCCsGAQUFBwEBBHMwcTAkBggrBgEFBQcwAYYYaHR0cDovL29jc3Au
# ZGlnaWNlcnQuY29tMEkGCCsGAQUFBzAChj1odHRwOi8vY2FjZXJ0cy5kaWdpY2Vy
# dC5jb20vRGlnaUNlcnRIaWdoQXNzdXJhbmNlRVZSb290Q0EuY3J0MIGPBgNVHR8E
# gYcwgYQwQKA+oDyGOmh0dHA6Ly9jcmwzLmRpZ2ljZXJ0LmNvbS9EaWdpQ2VydEhp
# Z2hBc3N1cmFuY2VFVlJvb3RDQS5jcmwwQKA+oDyGOmh0dHA6Ly9jcmw0LmRpZ2lj
# ZXJ0LmNvbS9EaWdpQ2VydEhpZ2hBc3N1cmFuY2VFVlJvb3RDQS5jcmwwggHEBgNV
# HSAEggG7MIIBtzCCAbMGCWCGSAGG/WwDAjCCAaQwOgYIKwYBBQUHAgEWLmh0dHA6
# Ly93d3cuZGlnaWNlcnQuY29tL3NzbC1jcHMtcmVwb3NpdG9yeS5odG0wggFkBggr
# BgEFBQcCAjCCAVYeggFSAEEAbgB5ACAAdQBzAGUAIABvAGYAIAB0AGgAaQBzACAA
# QwBlAHIAdABpAGYAaQBjAGEAdABlACAAYwBvAG4AcwB0AGkAdAB1AHQAZQBzACAA
# YQBjAGMAZQBwAHQAYQBuAGMAZQAgAG8AZgAgAHQAaABlACAARABpAGcAaQBDAGUA
# cgB0ACAAQwBQAC8AQwBQAFMAIABhAG4AZAAgAHQAaABlACAAUgBlAGwAeQBpAG4A
# ZwAgAFAAYQByAHQAeQAgAEEAZwByAGUAZQBtAGUAbgB0ACAAdwBoAGkAYwBoACAA
# bABpAG0AaQB0ACAAbABpAGEAYgBpAGwAaQB0AHkAIABhAG4AZAAgAGEAcgBlACAA
# aQBuAGMAbwByAHAAbwByAGEAdABlAGQAIABoAGUAcgBlAGkAbgAgAGIAeQAgAHIA
# ZQBmAGUAcgBlAG4AYwBlAC4wHQYDVR0OBBYEFI/ofvBtMmoABSPHcJdqOpD/a+rU
# MB8GA1UdIwQYMBaAFLE+w2kD+L9HAdSYJhoIAu9jZCvDMA0GCSqGSIb3DQEBCwUA
# A4IBAQAZM0oMgTM32602yeTJOru1Gy56ouL0Q0IXnr9OoU3hsdvpgd2fAfLkiNXp
# /gn9IcHsXYDS8NbBQ8L+dyvb+deRM85s1bIZO+Yu1smTT4hAjs3h9X7xD8ZZVnLo
# 62pBvRzVRtV8ScpmOBXBv+CRcHeH3MmNMckMKaIz7Y3ih82JjT8b/9XgGpeLfNpt
# +6jGsjpma3sBs83YpjTsEgGrlVilxFNXqGDm5wISoLkjZKJNu3yBJWQhvs/uQhhD
# l7ulNwavTf8mpU1hS+xGQbhlzrh5ngiWC4GMijuPx5mMoypumG1eYcaWt4q5YS2T
# uOsOBEPX9f6m8GLUmWqlwcHwZJSAMYIdCzCCHQcCAQEwgYAwbDELMAkGA1UEBhMC
# VVMxFTATBgNVBAoTDERpZ2lDZXJ0IEluYzEZMBcGA1UECxMQd3d3LmRpZ2ljZXJ0
# LmNvbTErMCkGA1UEAxMiRGlnaUNlcnQgRVYgQ29kZSBTaWduaW5nIENBIChTSEEy
# KQIQChoNG3KPlLi3cBQgfCoKxDANBglghkgBZQMEAgEFAKCBhDAYBgorBgEEAYI3
# AgEMMQowCKACgAChAoAAMBkGCSqGSIb3DQEJAzEMBgorBgEEAYI3AgEEMBwGCisG
# AQQBgjcCAQsxDjAMBgorBgEEAYI3AgEVMC8GCSqGSIb3DQEJBDEiBCD+y1fdY7O1
# HJQtdTe8E86rm8aBzNDHcNGsJg38UDGjRTANBgkqhkiG9w0BAQEFAASCAgCJVWS7
# HjYTtzGTfZWjJ10BmdSiQDmr9FZLyvpXMRVhSEk7WpBZqIaAS4hUWFnxZbNVmjWh
# fo6i2Gev5D2vVJfw4Q7UAtDfsC8RXMhLlrVcxutZ8yVNoxCAZYFFl2jTAko5Mysu
# a2xmrjtWS+6lM6PIgCvsqmitTqMBxTAAMmTd0emyPEdlOv/66TEz/Pdp5+y/1oMn
# rLSwAaNu5SRQqtSOcHjsfxrkNxvPEOxI0iQkekVAJn1zksBi1vNnHVaEkydWmWcr
# 2odkmvmgNAWgCtLeFcgP6KrahGPsoXMb1dkFrRY1uwUQCJIS59q7C/UGND7ZtXlv
# 44Nn5kHRFfGHHGg/bdwzhnC8xB/Skm4r3R/df7pk3IkPIgs8FWwpuS866X3oMh+x
# yi6WD14yajSUUgqfGXpVGYsf4ASEvZH1X2ySQJ/RQZmec/l3BLI5Vmo1gpUfOOGS
# 8BWJUF6U+KOa2lmW4vgs3GNm1GxGXgsii/GQsfai4j5fIJhiRXl46xMWLd+0D1n6
# KwBL/0QsYZ7mdwYAKDqghDTmJJYJa2WjmyJiaU+nBuW+R/8D6WmF/EC1Gq1lIvyy
# egaSnhwZ4Yc57MZljchfiBoHglVV+GhTQZwG2c0PW+wAfLOW9EPNmX/RbXk4HTqQ
# blNW59jSpHq3QEc+3Lq3A/U8zTUNZIi7HB7vbKGCGdQwghnQBgorBgEEAYI3AwMB
# MYIZwDCCGbwGCSqGSIb3DQEHAqCCGa0wghmpAgEDMQ0wCwYJYIZIAWUDBAIBMIHc
# BgsqhkiG9w0BCRABBKCBzASByTCBxgIBAQYJKwYBBAGgMgIDMDEwDQYJYIZIAWUD
# BAIBBQAEINGEaAq/Agz2SNRoBWSVAGwNSWAjNoXFjRVuiq4ZwvYoAhQOl8croa9V
# q9wU+KTEoNt1TevTqhgPMjAyMzAzMTUxNjAxNDRaMAMCAQGgV6RVMFMxCzAJBgNV
# BAYTAkJFMRkwFwYDVQQKDBBHbG9iYWxTaWduIG52LXNhMSkwJwYDVQQDDCBHbG9i
# YWxzaWduIFRTQSBmb3IgQWR2YW5jZWQgLSBHNKCCFWcwggZYMIIEQKADAgECAhAB
# wpx69HqmAlgOrzKxI7EdMA0GCSqGSIb3DQEBCwUAMFsxCzAJBgNVBAYTAkJFMRkw
# FwYDVQQKExBHbG9iYWxTaWduIG52LXNhMTEwLwYDVQQDEyhHbG9iYWxTaWduIFRp
# bWVzdGFtcGluZyBDQSAtIFNIQTM4NCAtIEc0MB4XDTIyMDQwNjA3NDQxMloXDTMz
# MDUwODA3NDQxMlowUzELMAkGA1UEBhMCQkUxGTAXBgNVBAoMEEdsb2JhbFNpZ24g
# bnYtc2ExKTAnBgNVBAMMIEdsb2JhbHNpZ24gVFNBIGZvciBBZHZhbmNlZCAtIEc0
# MIIBojANBgkqhkiG9w0BAQEFAAOCAY8AMIIBigKCAYEAo96mIRIWErwo4AT3s9Sw
# 0wFoj1O2GFhbcaBe2NZMc+BX8LkMB/eHuSmD/vDVdaFI/z2wHEC8glVoSDoMRus/
# wyyYNM/EmJtwG4YRjV4VfKEN2tZ3fa/sfpwU7KW/KWrriika/g6fLLoWTVhaY3EM
# 2y60cArnRhBC7ntFfP5kRZSv4OtQslJnH3FDN/HiGINAEFeaFdfy8muem8lW22eD
# GHj3ZaQFzOYThRT+X4lnAWH72saDKNaNTt00LBgDAYRI3RZ4JeHWSGmtXDWWIR6g
# w08TABfLwl7ckk0EYsl49d6nsYQKnnQ6gtyAlLcBbauoOZ4aXcF8AQZdkHs+XUoo
# yikQsbNZzwG4ITDH2bX0lyw2rlLHszIjboOm+dQk91b4YXV0TvIGqyKEyP1k5V8V
# pdwndKrS0Om0SHjXmMy7H/jWRsN1dfqeRcaVdWsHB6hE3VZ2KM5KTQJ5a0+R4vys
# neu8iq96a2xkNEbxzHgcvCf0dWinM8k6F36KTkQ+g/O9AgMBAAGjggGeMIIBmjAO
# BgNVHQ8BAf8EBAMCB4AwFgYDVR0lAQH/BAwwCgYIKwYBBQUHAwgwHQYDVR0OBBYE
# FEk7Z7VXopnmdBl6DFksPgjqIHuLMEwGA1UdIARFMEMwQQYJKwYBBAGgMgEeMDQw
# MgYIKwYBBQUHAgEWJmh0dHBzOi8vd3d3Lmdsb2JhbHNpZ24uY29tL3JlcG9zaXRv
# cnkvMAwGA1UdEwEB/wQCMAAwgZAGCCsGAQUFBwEBBIGDMIGAMDkGCCsGAQUFBzAB
# hi1odHRwOi8vb2NzcC5nbG9iYWxzaWduLmNvbS9jYS9nc3RzYWNhc2hhMzg0ZzQw
# QwYIKwYBBQUHMAKGN2h0dHA6Ly9zZWN1cmUuZ2xvYmFsc2lnbi5jb20vY2FjZXJ0
# L2dzdHNhY2FzaGEzODRnNC5jcnQwHwYDVR0jBBgwFoAU6hbGaefjy1dFOTOk8EC+
# 0MO9ZZYwQQYDVR0fBDowODA2oDSgMoYwaHR0cDovL2NybC5nbG9iYWxzaWduLmNv
# bS9jYS9nc3RzYWNhc2hhMzg0ZzQuY3JsMA0GCSqGSIb3DQEBCwUAA4ICAQAIiKTq
# hYgzWGt+/ABVItNvQ2lvfP6+Q4Y3Dp9T2lGe0DzjG5nXUVEZD1GQDtvumkbPfQrg
# xuwVgus+rswD+lntj6VKohk+wl/9FoMxVlIoS1/ERYNh65YMIDCifUXqlm2y/HS4
# /UxhlGqnsOqpvziOmHZ1B6b7pdwLb3V6ZOkw15GQYtDhyxnk6C8niECMh9s/2xWw
# SI3ijZWMJ/OsSYewfOnEpeDZ3L72DRW43mOdfZYrraSulGA30EiZqNu9L070AI+3
# /EjathBAxD8521V3vQs8rDagSpkU4NAxHonSJwpwUN2tb2T6b40a9lD0FhMwDBjO
# 2GhC1VXjWl/AoIG8GbxEsGOKfsArHlVu5x0eE2SZZmQJg+mB5j4r/eR87EO7m281
# YpNkmrtYuK8Ebii7CljjhTkl1OOLFXMBOh3LXZH8nkUuh7XwRpyUw2it+g7rR9mp
# JdaKCtie76yiXqYunFjRvVG/EnLQEZtMz5tSv6fqSpQi/Np0s0XUswnWaERAKh+K
# bNrlaXEAEvjJ3+qYqSpqj9Sa4B+smeHoXT55PEWkDgqGFKAV5ZIggfKCjvOqyZxf
# HEl0/CG1KOCBDf+3f5iDwGDTAcVmzGG8wqQLAzc2mjIlwsXmg5T80Hm/g9O8U7Xj
# /s/hcT4F22KPJL3vU6rynlMMP3xr8OolOF9yqjCCBlkwggRBoAMCAQICDQHsHJJA
# 3v0uQF18R3QwDQYJKoZIhvcNAQEMBQAwTDEgMB4GA1UECxMXR2xvYmFsU2lnbiBS
# b290IENBIC0gUjYxEzARBgNVBAoTCkdsb2JhbFNpZ24xEzARBgNVBAMTCkdsb2Jh
# bFNpZ24wHhcNMTgwNjIwMDAwMDAwWhcNMzQxMjEwMDAwMDAwWjBbMQswCQYDVQQG
# EwJCRTEZMBcGA1UEChMQR2xvYmFsU2lnbiBudi1zYTExMC8GA1UEAxMoR2xvYmFs
# U2lnbiBUaW1lc3RhbXBpbmcgQ0EgLSBTSEEzODQgLSBHNDCCAiIwDQYJKoZIhvcN
# AQEBBQADggIPADCCAgoCggIBAPAC4jAj+uAb4Zp0s691g1+pR1LHYTpjfDkjeW10
# /DHkdBIZlvrOJ2JbrgeKJ+5Xo8Q17bM0x6zDDOuAZm3RKErBLLu5cPJyroz3mVpd
# dq6/RKh8QSSOj7rFT/82QaunLf14TkOI/pMZF9nuMc+8ijtuasSI8O6X9tzzGKBL
# mRwOh6cm4YjJoOWZ4p70nEw/XVvstu/SZc9FC1Q9sVRTB4uZbrhUmYqoMZI78np9
# /A5Y34Fq4bBsHmWCKtQhx5T+QpY78Quxf39GmA6HPXpl69FWqS69+1g9tYX6U5lN
# W3TtckuiDYI3GQzQq+pawe8P1Zm5P/RPNfGcD9M3E1LZJTTtlu/4Z+oIvo9Jev+Q
# sdT3KRXX+Q1d1odDHnTEcCi0gHu9Kpu7hOEOrG8NubX2bVb+ih0JPiQOZybH/LIN
# oJSwspTMe+Zn/qZYstTYQRLBVf1ukcW7sUwIS57UQgZvGxjVNupkrs799QXm4mbQ
# DgUhrLERBiMZ5PsFNETqCK6dSWcRi4LlrVqGp2b9MwMB3pkl+XFu6ZxdAkxgPM8C
# jwH9cu6S8acS3kISTeypJuV3AqwOVwwJ0WGeJoj8yLJN22TwRZ+6wT9Uo9h2ApVs
# ao3KIlz2DATjKfpLsBzTN3SE2R1mqzRzjx59fF6W1j0ZsJfqjFCRba9Xhn4QNx1r
# GhTfAgMBAAGjggEpMIIBJTAOBgNVHQ8BAf8EBAMCAYYwEgYDVR0TAQH/BAgwBgEB
# /wIBADAdBgNVHQ4EFgQU6hbGaefjy1dFOTOk8EC+0MO9ZZYwHwYDVR0jBBgwFoAU
# rmwFo5MT4qLn4tcc1sfwf8hnU6AwPgYIKwYBBQUHAQEEMjAwMC4GCCsGAQUFBzAB
# hiJodHRwOi8vb2NzcDIuZ2xvYmFsc2lnbi5jb20vcm9vdHI2MDYGA1UdHwQvMC0w
# K6ApoCeGJWh0dHA6Ly9jcmwuZ2xvYmFsc2lnbi5jb20vcm9vdC1yNi5jcmwwRwYD
# VR0gBEAwPjA8BgRVHSAAMDQwMgYIKwYBBQUHAgEWJmh0dHBzOi8vd3d3Lmdsb2Jh
# bHNpZ24uY29tL3JlcG9zaXRvcnkvMA0GCSqGSIb3DQEBDAUAA4ICAQB/4ojZV2cr
# Ql+BpwkLusS7KBhW1ky/2xsHcMb7CwmtADpgMx85xhZrGUBJJQge5Jv31qQNjx6W
# 8oaiF95Bv0/hvKvN7sAjjMaF/ksVJPkYROwfwqSs0LLP7MJWZR29f/begsi3n2HT
# tUZImJcCZ3oWlUrbYsbQswLMNEhFVd3s6UqfXhTtchBxdnDSD5bz6jdXlJEYr9yN
# mTgZWMKpoX6ibhUm6rT5fyrn50hkaS/SmqFy9vckS3RafXKGNbMCVx+LnPy7rEze
# +t5TTIP9ErG2SVVPdZ2sb0rILmq5yojDEjBOsghzn16h1pnO6X1LlizMFmsYzeRZ
# N4YJLOJF1rLNboJ1pdqNHrdbL4guPX3x8pEwBZzOe3ygxayvUQbwEccdMMVRVmDo
# fJU9IuPVCiRTJ5eA+kiJJyx54jzlmx7jqoSCiT7ASvUh/mIQ7R0w/PbM6kgnfIt1
# Qn9ry/Ola5UfBFg0ContglDk0Xuoyea+SKorVdmNtyUgDhtRoNRjqoPqbHJhSsn6
# Q8TGV8Wdtjywi7C5HDHvve8U2BRAbCAdwi3oC8aNbYy2ce1SIf4+9p+fORqurNIv
# eiCx9KyqHeItFJ36lmodxjzK89kcv1NNpEdZfJXEQ0H5JeIsEH6B+Q2Up33ytQn1
# 2GByQFCVINRDRL76oJXnIFm2eMakaqoimzCCBUcwggQvoAMCAQICDQHyQEJAzv0i
# 2+lscfwwDQYJKoZIhvcNAQEMBQAwTDEgMB4GA1UECxMXR2xvYmFsU2lnbiBSb290
# IENBIC0gUjMxEzARBgNVBAoTCkdsb2JhbFNpZ24xEzARBgNVBAMTCkdsb2JhbFNp
# Z24wHhcNMTkwMjIwMDAwMDAwWhcNMjkwMzE4MTAwMDAwWjBMMSAwHgYDVQQLExdH
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
# 3GduyYsRtYQUigAZcIN5kZeR1BonvzceMgfYFGM8KEyvAgMBAAGjggEmMIIBIjAO
# BgNVHQ8BAf8EBAMCAQYwDwYDVR0TAQH/BAUwAwEB/zAdBgNVHQ4EFgQUrmwFo5MT
# 4qLn4tcc1sfwf8hnU6AwHwYDVR0jBBgwFoAUj/BLf6guRSSuTVD6Y5qL3uLdG7ww
# PgYIKwYBBQUHAQEEMjAwMC4GCCsGAQUFBzABhiJodHRwOi8vb2NzcDIuZ2xvYmFs
# c2lnbi5jb20vcm9vdHIzMDYGA1UdHwQvMC0wK6ApoCeGJWh0dHA6Ly9jcmwuZ2xv
# YmFsc2lnbi5jb20vcm9vdC1yMy5jcmwwRwYDVR0gBEAwPjA8BgRVHSAAMDQwMgYI
# KwYBBQUHAgEWJmh0dHBzOi8vd3d3Lmdsb2JhbHNpZ24uY29tL3JlcG9zaXRvcnkv
# MA0GCSqGSIb3DQEBDAUAA4IBAQBJrF7Fg/Nay2EqTZdKFSmf5BSQqgn5xHqfNRiK
# CjMVbXKHIk5BP20Knhiu2+Jf/JXRLJgUO47B8DZZefONgc909hik5OFoz+9/ZVlC
# 6cpVObzTxSbucTj61yEDD7dO2VtgakO0fQnQYGHdqu0AXk4yHuCybJ48ssK7mNOQ
# dmpprRrcqInaWE/SwosySs5U+zjpOwcLdQoR2wt8JSfxrCbPEVPm3MbiYTUy9M7d
# g+MZOuvCaKNyAMgkPE64UzyxF6vmNSz500Ip5l9gA6xCYaaxV2ozQt81MYbKPjcr
# 2sTaJPVOEvK2ubdH6rsgrWEWt6Az4y2Jp7yzPAF/IxqACTTpMIIDXzCCAkegAwIB
# AgILBAAAAAABIVhTCKIwDQYJKoZIhvcNAQELBQAwTDEgMB4GA1UECxMXR2xvYmFs
# U2lnbiBSb290IENBIC0gUjMxEzARBgNVBAoTCkdsb2JhbFNpZ24xEzARBgNVBAMT
# Ckdsb2JhbFNpZ24wHhcNMDkwMzE4MTAwMDAwWhcNMjkwMzE4MTAwMDAwWjBMMSAw
# HgYDVQQLExdHbG9iYWxTaWduIFJvb3QgQ0EgLSBSMzETMBEGA1UEChMKR2xvYmFs
# U2lnbjETMBEGA1UEAxMKR2xvYmFsU2lnbjCCASIwDQYJKoZIhvcNAQEBBQADggEP
# ADCCAQoCggEBAMwldpB5BngiFvXAg7aEyiie/QV2EcWtiHL8RgJDx7KKnQRfJMsu
# S+FggkbhUqsMgUdwbN1k0ev1LKMPgj0MK66X17YUhhB5uzsTgHeMCOFJ0mpiLx9e
# +pZo34knlTifBtc+ycsmWQ1z3rDI6SYOgxXG71uL0gRgykmmKPZpO/bLyCiR5Z2K
# YVc3rHQU3HTgOu5yLy6c+9C7v/U9AOEGM+iCK65TpjoWc4zdQQ4gOsC0p6Hpsk+Q
# LjJg6VfLuQSSaGjlOCZgdbKfd/+RFO+uIEn8rUAVSNECMWEZXriX7613t2Saer9f
# wRPvm2L7DWzgVGkWqQPabumDk3F2xmmFghcCAwEAAaNCMEAwDgYDVR0PAQH/BAQD
# AgEGMA8GA1UdEwEB/wQFMAMBAf8wHQYDVR0OBBYEFI/wS3+oLkUkrk1Q+mOai97i
# 3Ru8MA0GCSqGSIb3DQEBCwUAA4IBAQBLQNvAUKr+yAzv95ZURUm7lgAJQayzE4aG
# KAczymvmdLm6AC2upArT9fHxD4q/c2dKg8dEe3jgr25sbwMpjjM5RcOO5LlXbKr8
# EpbsU8Yt5CRsuZRj+9xTaGdWPoO4zzUhw8lo/s7awlOqzJCK6fBdRoyV3XpYKBov
# Hd7NADdBj+1EbddTKJd+82cEHhXXipa0095MJ6RMG3NzdvQXmcIfeg7jLQitChws
# /zyrVQ4PkX4268NXSb7hLi18YIvDQVETI53O9zJrlAGomecsMx86OyXShkDOOyyG
# eMlhLxS67ttVb9+E7gUJTb0o2HLO02JQZR7rkpeDMdmztcpHWD9fMYIDSTCCA0UC
# AQEwbzBbMQswCQYDVQQGEwJCRTEZMBcGA1UEChMQR2xvYmFsU2lnbiBudi1zYTEx
# MC8GA1UEAxMoR2xvYmFsU2lnbiBUaW1lc3RhbXBpbmcgQ0EgLSBTSEEzODQgLSBH
# NAIQAcKcevR6pgJYDq8ysSOxHTALBglghkgBZQMEAgGgggEtMBoGCSqGSIb3DQEJ
# AzENBgsqhkiG9w0BCRABBDArBgkqhkiG9w0BCTQxHjAcMAsGCWCGSAFlAwQCAaEN
# BgkqhkiG9w0BAQsFADAvBgkqhkiG9w0BCQQxIgQgpZIQ1C+L8Zj/b9+Cl0lrXJ+R
# 3Z6V5gHRPyGHnGp1YIAwgbAGCyqGSIb3DQEJEAIvMYGgMIGdMIGaMIGXBCCvgDHt
# bss5FERIlb0LHQzrEpWU214MLG32vnKxJUJH0DBzMF+kXTBbMQswCQYDVQQGEwJC
# RTEZMBcGA1UEChMQR2xvYmFsU2lnbiBudi1zYTExMC8GA1UEAxMoR2xvYmFsU2ln
# biBUaW1lc3RhbXBpbmcgQ0EgLSBTSEEzODQgLSBHNAIQAcKcevR6pgJYDq8ysSOx
# HTANBgkqhkiG9w0BAQsFAASCAYCb6qsLcc+MAw2ybqxVge6IG+th4teXDfvjotsm
# p1cn1fvrbkiWZbpt7YZbxlsq1j1fz+Q+W4og5tDeVvgvPJs3ZytP/uc+2PKftT/9
# cY6kw7kNqtaxh7Fg6dNSXbfY8bs+Hlx8eLJDdMmNk/i4k7gOZCqdwDg9J4CQ0U60
# RQ+RT8nisjiyK3PUWvdToavI8i+7itQdGh3Y5tw6bStvLnwzwOsUHaQHck6W8IZL
# psVKdTJletCDzJrpPdMQFw2VZbeN6OBf5+ePR9fdrcvo2YZBRXJIqqSiSkJ2HaZJ
# 6VmHE6MuBZRIFqHMDIsbqP9PHlGr1+xl6Zyaq9RvN/bNkOWWbxAceXfkrtsSBuNE
# lNzzdVhthh1QSO7jN2TV0Yto6Ix1Zpq8RtjWNtP9Eb6A8aWQCCRrW62BaVQuu5qU
# PFr8V8abdEL+ROaqp3qehwUFNhl9uY7TnjlVDnUlJTFsb1iUBxuFW9eMEZMuZWI5
# ZkZPZk9FcU2luMLTvRnZf58Ljec=
# SIG # End signature block
