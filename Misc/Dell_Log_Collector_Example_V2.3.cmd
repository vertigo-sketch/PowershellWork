@ECHO OFF
CHCP 65001 >nul
COLOR 1f
MODE 300,50
SETLOCAL enabledelayedexpansion

REM ──────────────────────────── set progress counter and total amount of steps ───────────────────────────────────
SET STEP=1
SET TOTAL=59

REM ────────────────────────────────────────── Admin Warning ──────────────────────────────────────────────────────

SET "aw[0]=[105m╔═════════════════════════════════════════════════════════════════════════════════════════════════════════════╗"
SET "aw[1]=║                               LOG COLLECTION WITHOUT ADMIN RIGHTS IN PROGRESS                               ║"
SET "aw[2]=╟─────────────────────────────────────────────────────────────────────────────────────────────────────────────╢"
SET "aw[3]=║                                                                                                             ║"
SET "aw[4]=║ It is recommended to run the Dell Log Collector with admin rights to retrieve ALL necessary log files.      ║"
SET "aw[5]=║ Please stop the log collection and run it again by right clicking and running as administrator if possible. ║"
SET "aw[6]=║                                                                                                             ║"
SET "aw[7]=║ Note:                                                                                                       ║"
SET "aw[8]=║ This collector will continue to gather logs without administrator rights.                                   ║"
SET "aw[9]=║ Logs such dump files, power & sleep reports and advanced settings will not be collected.                    ║"
SET "aw[10]=║                                                                                                             ║"
SET "aw[11]=╚═════════════════════════════════════════════════════════════════════════════════════════════════════════════╝[44m"

REM ────────────────────────────────────────── get SvcTag ─────────────────────────────────────────────────────────
FOR /f "usebackq delims=" %%S in (` POWERSHELL -command "Get-CimInstance -ClassName Win32_BIOS -Property SerialNumber | Select-Object -ExpandProperty SerialNumber" `) DO SET SvcTag=%%S
SET SvcTag=%SvcTag:.=%
SET SvcTag=%SvcTag:/=%
SET SvcTag=%SvcTag:,=%
SET SvcTag=%SvcTag::=%
SET SvcTag=%SvcTag: =%

REM ────────────────────────────────────────── get date / time stamp for file name ────────────────────────────────
SET dtStamp=%DATE%_%TIME% 
SET dtStamp=%dtStamp:.=%
SET dtStamp=%dtStamp:/=%
SET dtStamp=%dtStamp:,=%
SET dtStamp=%dtStamp::=%
SET dtStamp=%dtStamp: =%

REM ────────────────────────────────────────── get platform name ──────────────────────────────────────────────────
FOR /f "usebackq delims=" %%a in (` POWERSHELL -command "Get-WMIObject -class Win32_ComputerSystem | Select-Object -ExpandProperty Model" `) DO SET platform=%%a
SET platform=%platform:.=%
SET platform=%platform:/=%
SET platform=%platform:,=%
SET platform=%platform::=%
SET platform=%platform: =%

REM ────────────────────────────────────────── creating log collection folders ────────────────────────────────────
%SYSTEMDRIVE%
CD %APPDATA%
MD %SvcTag% >nul 2>&1
CD %SvcTag%
MD MemoryDumps >nul 2>&1
MD Logs >nul 2>&1
CD Logs
MD Application >nul 2>&1
MD Dell >nul 2>&1
MD Driver >nul 2>&1
MD Graphics >nul 2>&1
MD Network >nul 2>&1
MD OperatingSystem >nul 2>&1
MD Power >nul 2>&1
MD Security >nul 2>&1
MD Storage >nul 2>&1
MD System >nul 2>&1
MD USB >nul 2>&1

REM ───────────────────────────────────────────── LogCollectorStatus Header ───────────────────────────────────────
SET zippath=%APPDATA%\%SvcTag%
SET zipfile=%platform%_%SvcTag%_%dtStamp%.zip
SET collectorversion=%~n0
TITLE Dell Log Collector %collectorversion:~+27%
SET admincheck=5
net session >nul 2>&1
IF %ERRORLEVEL% == 0 (SET /A admincheck=1) ELSE (SET /A admincheck=0)

ECHO Service Tag: %SvcTag% >> "%ZIPPATH%"\Logs\LogCollectorStatus.txt
POWERSHELL -command "([Console]::Out.Write('Model: '));((Get-WMIObject -class Win32_ComputerSystem | Select-Object Model | Format-List | Out-string).Substring(12).Trim())" >> "%ZIPPATH%"\Logs\LogCollectorStatus.txt
POWERSHELL -command "([Console]::Out.Write('OS Caption: ')); ((Get-WMIObject -class Win32_OperatingSystem | Select-Object Caption| Format-List| Out-string).Substring(14).Trim())" >> "%ZIPPATH%"\Logs\LogCollectorStatus.txt
POWERSHELL -command "([Console]::Out.Write('OS Version: ')); ((Get-WMIObject -class Win32_OperatingSystem | Select-Object Version| Format-List| Out-string).Substring(14).Trim())" >> "%ZIPPATH%"\Logs\LogCollectorStatus.txt
POWERSHELL -command "([Console]::Out.Write('OS Install Date: '));((([WMI]'').ConvertToDateTime((Get-WmiObject Win32_OperatingSystem).InstallDate)| Select-Object Date |Format-List | Out-string).Substring(10).Trim());" >> "%ZIPPATH%"\Logs\LogCollectorStatus.txt
ECHO Log Collection Date: %DATE% >> "%ZIPPATH%"\Logs\LogCollectorStatus.txt
ECHO Version: %collectorversion:~+27% >> "%ZIPPATH%"\Logs\LogCollectorStatus.txt
IF %admincheck% == 1 (ECHO Collector Run As: Administrator >> "%ZIPPATH%"\Logs\LogCollectorStatus.txt) ELSE (ECHO Collector Run As: Standard User >> "%ZIPPATH%"\Logs\LogCollectorStatus.txt)

REM ───────────────────────────────────────────── LOG Collection START ────────────────────────────────────────────
CLS
ECHO ───────────────────────────────────────────── Operating System ────────────────────────────────────────────────  >> "%ZIPPATH%"\Logs\LogCollectorStatus.txt
REM GOTO SKIPOS
CD OperatingSystem
IF %admincheck% == 0 (FOR /L %%n IN (0,1,11) DO (ECHO !aw[%%n]!))
IF %admincheck% == 0 TIMEOUT 10 /NOBREAK >NUL

ECHO ───────────────────────────────────────────── Operating System ────────────────────────────────────────────────
ECHO [%TIME%]: MSinfo32 >> "%ZIPPATH%"\Logs\LogCollectorStatus.txt
ECHO [Log Collection in progress, please wait -  %STEP% of %TOTAL% complete]: MSinfo32 & SET /A STEP=STEP+1 
start msinfo32 /nfo MsInfo32.nfo

ECHO [%TIME%]: Group Policy Objects >> "%ZIPPATH%"\Logs\LogCollectorStatus.txt
ECHO [Log Collection in progress, please wait -  %STEP% of %TOTAL% complete]: Group Policy Objects & SET /A STEP=STEP+1
start /min gpresult /H GPO_List.html

ECHO [%TIME%]: Windows Systeminfo >> "%ZIPPATH%"\Logs\LogCollectorStatus.txt
ECHO [Log Collection in progress, please wait -  %STEP% of %TOTAL% complete]: Windows Systeminfo & SET /A STEP=STEP+1
Systeminfo > SystemInfo.txt

ECHO [%TIME%]: Crash Dump Properties >> "%ZIPPATH%"\Logs\LogCollectorStatus.txt
ECHO [Log Collection in progress, please wait -  %STEP% of %TOTAL% complete]: Crash Dump Properties & SET /A STEP=STEP+1

ECHO [Log Collection in progress, please wait -  %STEP% of %TOTAL% complete]: Capture Minidump Files & SET /A STEP=STEP+1
ECHO ### Note: Dump file location is: \%SvcTag%\MemoryDumps\ ### >> DumpStatus.txt
ECHO. >> DumpStatus.txt
IF EXIST %SYSTEMROOT%\Minidump\*.dmp (
  ECHO [%TIME%]: Minidump^(s^) files found >> "%ZIPPATH%"\Logs\LogCollectorStatus.txt
  ECHO Minidump^(s^) files found: >> DumpStatus.txt
  ECHO ========================== >> DumpStatus.txt
  POWERSHELL -command "Get-ItemProperty -Path %SYSTEMROOT%\minidump\*.dmp" >> DumpStatus.txt
) ELSE (
  ECHO [%TIME%]: Minidump file^(s^) not found >> "%ZIPPATH%"\Logs\LogCollectorStatus.txt
  ECHO no Minidump file^(s^) found >> DumpStatus.txt
)
IF %admincheck% == 1 (XCOPY /s /I /y /q /F %SYSTEMROOT%\minidump\*.dmp "%APPDATA%"\%SvcTag%\MemoryDumps\ >> "%ZIPPATH%"\Logs\LogCollectorStatus.txt 2>nul
) ELSE (  
  ECHO [%TIME%]: Admin privileges required to capture Minidump^(s^) >> "%ZIPPATH%"\Logs\LogCollectorStatus.txt
  ECHO Admin privileges required to capture Minidump^(s^) >> DumpStatus.txt
)

ECHO [Log Collection in progress, please wait -  %STEP% of %TOTAL% complete]: Capture Full Memory Dump file & SET /A STEP=STEP+1
IF EXIST %SYSTEMROOT%\memory.dmp (
  ECHO [%TIME%]:  Full Memory Dump File found >> "%ZIPPATH%"\Logs\LogCollectorStatus.txt
  ECHO. >> DumpStatus.txt
  ECHO Full Memory Dump file found: >> DumpStatus.txt
  ECHO ============================ >> DumpStatus.txt
  POWERSHELL -command "Get-ItemProperty -Path %SYSTEMROOT%\memory.dmp" >> DumpStatus.txt
) ELSE (
  ECHO [%TIME%]: Full Memory Dump File not found >> "%ZIPPATH%"\Logs\LogCollectorStatus.txt
  ECHO no fulldump file found >> DumpStatus.txt
)
IF %admincheck% == 1 (XCOPY /y /q /F %SYSTEMROOT%\memory.dmp "%APPDATA%"\%SvcTag%\MemoryDumps\ >> "%ZIPPATH%"\Logs\LogCollectorStatus.txt 2>nul
) ELSE (  
  ECHO [%TIME%]: Admin privileges required to capture Full Memory Dump file >> "%ZIPPATH%"\Logs\LogCollectorStatus.txt
  ECHO Admin Privileges required to capture Full Memory Dump File >> DumpStatus.txt
)

ECHO [Log Collection in progress, please wait -  %STEP% of %TOTAL% complete]: Services List & SET /A STEP=STEP+1
ECHO [%TIME%]: Services List >> "%ZIPPATH%"\Logs\LogCollectorStatus.txt
ECHO Services (basic details, sorted by status): > Services.txt 
ECHO ====================================== >> Services.txt 
POWERSHELL -command "Get-Service | Sort Status" >> Services.txt
ECHO Services (all details, sorted by status): >> Services.txt 
ECHO ====================================== >> Services.txt 
POWERSHELL -command "Get-Service | Select * | Sort Status" >> Services.txt

ECHO [%TIME%]: Processes List >> "%ZIPPATH%"\Logs\LogCollectorStatus.txt
ECHO [Log Collection in progress, please wait -  %STEP% of %TOTAL% complete]: Processes List & SET /A STEP=STEP+1
POWERSHELL -command "Get-WmiObject -Class Win32_Service | Select-Object -Property Name, ProcessID" > Processes.txt

ECHO [%TIME%]: Windows Hotfix List >> "%ZIPPATH%"\Logs\LogCollectorStatus.txt
ECHO [Log Collection in progress, please wait -  %STEP% of %TOTAL% complete]: Windows Hotfix List & SET /A STEP=STEP+1
POWERSHELL -command "Get-hotfix" > Hotfixes.txt

ECHO [%TIME%]: Task Scheduler Details >> "%ZIPPATH%"\Logs\LogCollectorStatus.txt
ECHO [Log Collection in progress, please wait - %STEP% of %TOTAL% complete]: Task Scheduler Details & SET /A STEP=STEP+1
POWERSHELL -command "Get-ScheduledTask | Select-Object TaskName, State, NextRunTime, LastRunTime | Sort Taskname |Format-Table" > Taskscheduler.txt
ECHO [%TIME%]: Windows Update Log >> "%ZIPPATH%"\Logs\LogCollectorStatus.txt
ECHO [Log Collection in progress, please wait - %STEP% of %TOTAL% complete]: Windows Update Log & SET /A STEP=STEP+1
REM START /min "Windows Update Log" CMD.exe /c "POWERSHELL -command 'Get-WindowsUpdateLog' -LogPath %ZIPPATH%\OperatingSystem\WindowsUpdateLog.txt"
START /min CMD.exe /c "POWERSHELL -command Get-WindowsUpdateLog -LogPath %ZIPPATH%\Logs\OperatingSystem\WindowsUpdateLog.txt"

ECHO [%TIME%]: BCD Information >> "%ZIPPATH%"\Logs\LogCollectorStatus.txt
ECHO [Log Collection in progress, please wait - %STEP% of %TOTAL% complete]: BCD Information & SET /A STEP=STEP+1
IF %admincheck% == 0 (ECHO Admin privileges required for BCD report > BCD.txt) ELSE (bcdedit > BCD.txt)

ECHO [%TIME%]: PNP Devices >> "%ZIPPATH%"\Logs\LogCollectorStatus.txt
ECHO [Log Collection in progress, please wait - %STEP% of %TOTAL% complete]: PNP Devices & SET /A STEP=STEP+1
POWERSHELL -command "Get-CimInstance Win32_PnPEntity > PNP_Devices.txt"

ECHO [%TIME%]: Windows Eventlogs >> "%ZIPPATH%"\Logs\LogCollectorStatus.txt
ECHO [Log Collection in progress, please wait - %STEP% of %TOTAL% complete]: Windows Eventlogs & SET /A STEP=STEP+1
MD EventLogs >nul 2>&1
CD EventLogs
wevtutil epl System /q:"*[System[(Level<=5)]]" System_EventLog.evtx >nul 2>&1
wevtutil epl Application /q:"*[System[(Level<=5)]]" Application_EventLog.evtx >nul 2>&1
CD..

ECHO [Log Collection in progress, please wait - %STEP% of %TOTAL% complete]: Windows Refresh/Upgrade History & SET /A STEP=STEP+1
FOR /f "usebackq delims=" %%a in (` POWERSHELL -command "Test-Path 'HKLM:\SYSTEM\Setup\Source OS*'" `) DO SET source_os_reg_check=%%a
IF %source_os_reg_check% == True ( 
  ECHO [%TIME%]: Windows Refresh/Upgrade History found >> "%ZIPPATH%"\Logs\LogCollectorStatus.txt 
  POWERSHELL -command "(get-itemproperty -path 'HKLM:\SYSTEM\Setup\Source OS*' | SELECT PSChildName, Productname, ReleaseId, DisplayVersion, CurrentBuild)" >> OS_Refresh_Upgrade.txt
  ECHO NOTE: This file only contains past OS versions. The current OS can be seen in MsInfo.nfo or LogCollectorStatus.txt files. >> OS_Refresh_Upgrade.txt
  ) ELSE (
  ECHO [%TIME%]: Windows Refresh/Upgrade History NOT found >> "%ZIPPATH%"\Logs\LogCollectorStatus.txt 
  ECHO Windows refresh/upgrade info NOT found in registry >> OS_Refresh_Upgrade.txt
)
CD..

:SKIPOS

ECHO ───────────────────────────────────────────── Application ───────────────────────────────────────────────────── >> "%ZIPPATH%"\Logs\LogCollectorStatus.txt
REM GOTO SKIPAPP
CD Application

ECHO ───────────────────────────────────────────── Application ─────────────────────────────────────────────────────
ECHO [Log Collection in progress, please wait - %STEP% of %TOTAL% complete]: Installed Apps & SET /A STEP=STEP+1
ECHO [%TIME%]: Installed Apps >> "%ZIPPATH%"\Logs\LogCollectorStatus.txt
POWERSHELL -command "Get-ItemProperty HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\* | Select-Object DisplayName, DisplayVersion, Publisher, InstallDate | Sort-Object InstallDate" > Installed_Apps.txt

ECHO [Log Collection in progress, please wait - %STEP% of %TOTAL% complete]: Installed Appx Packages & SET /A STEP=STEP+1
ECHO [%TIME%]: Installed Appx Packages >> "%ZIPPATH%"\Logs\LogCollectorStatus.txt
POWERSHELL -command "Get-AppxPackage | Select PackageFullName | Sort PackageFullName" > Installed_Appx.txt

ECHO [Log Collection in progress, please wait - %STEP% of %TOTAL% complete]: Startup Processes  & SET /A STEP=STEP+1
ECHO [%TIME%]: Startup Processes >> "%ZIPPATH%"\Logs\LogCollectorStatus.txt
POWERSHELL -command  "Get-CimInstance Win32_StartupCommand | Select-Object Name, command, Location, User | Format-List" > Startup_Processes.txt

ECHO [Log Collection in progress, please wait - %STEP% of %TOTAL% complete]: Provisioning Packages & SET /A STEP=STEP+1
ECHO [%TIME%]: Provisioning Packages >> "%ZIPPATH%"\Logs\LogCollectorStatus.txt
POWERSHELL -command "Get-ProvisioningPackage" > Provisioning_Packages.txt
CD..

:SKIPAPP

ECHO ───────────────────────────────────────────── Dell ──────────────────────────────────────────────────────────── >> "%ZIPPATH%"\Logs\LogCollectorStatus.txt
REM GOTO SKIPDELL
CD Dell

ECHO ───────────────────────────────────────────── Dell ────────────────────────────────────────────────────────────
ECHO [Log Collection in progress, please wait - %STEP% of %TOTAL% complete]: Dell Data Migrate & SET /A STEP=STEP+1
IF EXIST %SYSTEMDRIVE%\ProgramData\DDA\logs (
  ECHO [%TIME%]: Dell Data Migrate Source logs found >> "%ZIPPATH%"\Logs\LogCollectorStatus.txt
  MD Dell_Data_Migrate_Source >nul 2>&1
  CD Dell_Data_Migrate_Source
  XCOPY /s /y /q /F %SYSTEMDRIVE%\ProgramData\DDA\logs\ . >> "%ZIPPATH%"\Logs\LogCollectorStatus.txt 2>nul
  CD..
) ELSE (
  ECHO File %SYSTEMDRIVE%\ProgramData\DDA\logs not found on system > Dell_Data_Migrate_Source_not_found.txt
  ECHO [%TIME%]:  Dell Data Migrate Source Logs NOT found >> "%ZIPPATH%"\Logs\LogCollectorStatus.txt
)

IF EXIST %SYSTEMDRIVE%\ProgramData\Dell\SupportAssist\CDM\Logs (
  MD Dell_Data_Migrate_Destination >nul 2>&1
  CD Dell_Data_Migrate_Destination
  MD logs >nul 2>&1
  CD logs
  ECHO [%TIME%]: Dell Data Migrate Destination found >> "%ZIPPATH%"\Logs\LogCollectorStatus.txt
  XCOPY /s /I /y /q /F %SYSTEMDRIVE%\ProgramData\Dell\SupportAssist\CDM\Logs . >> "%ZIPPATH%"\Logs\LogCollectorStatus.txt 2>nul
  CD..
  CD..
) ELSE (
  ECHO File %SYSTEMDRIVE%\ProgramData\Dell\SupportAssist\CDM\Logs not found on system > Dell_Data_Migrate_Destination_not_found.txt
  ECHO [%TIME%]:  Dell Data Migrate Destination NOT found >> "%ZIPPATH%"\Logs\LogCollectorStatus.txt
)

IF EXIST %SYSTEMDRIVE%\ProgramData\Dell\SupportAssist\CDM\LocalLogs (
  MD Dell_Data_Migrate_Destination >nul 2>&1
  CD Dell_Data_Migrate_Destination
  MD LocalLogs >nul 2>&1
  CD Locallogs
  ECHO [%TIME%]: Dell Data Migrate Destination Local found >> "%ZIPPATH%"\Logs\LogCollectorStatus.txt
  XCOPY /s /y /q /F %SYSTEMDRIVE%\ProgramData\Dell\SupportAssist\CDM\LocalLogs . >> "%ZIPPATH%"\Logs\LogCollectorStatus.txt 2>nul
  CD..
  CD..

) ELSE (
  ECHO File %SYSTEMDRIVE%\ProgramData\Dell\SupportAssist\CDM\LocalLogs NOT found on system >> Dell_Data_Migrate_Destination_not_found.txt
  ECHO [%TIME%]: Dell Data Migrate Destination Local NOT found >> "%ZIPPATH%"\Logs\LogCollectorStatus.txt
)

ECHO [Log Collection in progress, please wait - %STEP% of %TOTAL% complete]: Dell Digital Delivery & SET /A STEP=STEP+1
IF EXIST %SYSTEMDRIVE%\ProgramData\dell\D3\Resources\  (
  MD Dell_Digital_Delivery >nul 2>&1
  CD Dell_Digital_Delivery
  IF EXIST %SYSTEMDRIVE%\ProgramData\dell\D3\Resources\SQLite (
		XCOPY /s /y /q /F %SYSTEMDRIVE%\ProgramData\dell\D3\Resources\SQlite . >> "%ZIPPATH%"\Logs\LogCollectorStatus.txt 2>nul
		ECHO [%TIME%]: Dell Digital Delivery Destination SQlite found >> "%ZIPPATH%"\Logs\LogCollectorStatus.txt
		) ELSE (
		ECHO [%TIME%]: Dell Digital Delivery Destination SQlite NOT found >> "%ZIPPATH%"\Logs\LogCollectorStatus.txt
		)
  IF EXIST %SYSTEMDRIVE%\ProgramData\dell\D3\Resources\Logs\serilog (
		XCOPY /s /y /q /F %SYSTEMDRIVE%\ProgramData\dell\D3\Resources\Logs\serilog . >> "%ZIPPATH%"\Logs\LogCollectorStatus.txt 2>nul
		ECHO [%TIME%]: Dell Digital Delivery Destination Serilog found >> "%ZIPPATH%"\Logs\LogCollectorStatus.txt
		) ELSE (
		ECHO [%TIME%]: Dell Digital Delivery Destination Serilog NOT found >> "%ZIPPATH%"\Logs\LogCollectorStatus.txt
		)
  CD..
) ELSE (
  ECHO File %SYSTEMDRIVE%\ProgramData\dell\D3\Resources\ NOT found on system > Dell_Digital_Delivery_Destination_not_found.txt
  ECHO [%TIME%]:  Dell Digital Delivery NOT found >> "%ZIPPATH%"\Logs\LogCollectorStatus.txt
)

ECHO [Log Collection in progress, please wait - %STEP% of %TOTAL% complete]: Dell Command Update Logs & SET /A STEP=STEP+1
IF EXIST %SYSTEMDRIVE%\ProgramData\Dell\UpdateService\Log (
  MD Dell_Command_Update >nul 2>&1
  CD Dell_Command_Update
  ECHO [%TIME%]:  Dell Command Update Logs found >> "%ZIPPATH%"\Logs\LogCollectorStatus.txt
  XCOPY /s /y /q /F %SYSTEMDRIVE%\ProgramData\Dell\UpdateService\Log . >> "%ZIPPATH%"\Logs\LogCollectorStatus.txt 2>nul
  XCOPY /s /y /q /F %SYSTEMDRIVE%\ProgramData\Dell\UpdateService\UpdatePackage\Log . >> "%ZIPPATH%"\Logs\LogCollectorStatus.txt 2>nul
  CD..
  ) ELSE (
  ECHO File %SYSTEMDRIVE%\ProgramData\Dell\UpdateService\Log not found on system or Admin privileges required >> Dell_Command_Update.txt
  ECHO [%TIME%]: Dell Command Update Logs NOT found or Admin privileges required >> "%ZIPPATH%"\Logs\LogCollectorStatus.txt
)

ECHO [Log Collection in progress, please wait - %STEP% of %TOTAL% complete]: Dell Command Update IgnoreList & SET /A STEP=STEP+1
REG QUERY HKLM\SOFTWARE\DELL\UpdateService\Service\IgnoreList /s /v InstalledUpdateJson >NUL
IF %ERRORLEVEL% == 0 (
  MD Dell_Command_Update >NUL 2>&1
  CD Dell_Command_Update
  ECHO [%TIME%]:  Dell Command Update IgnoreList found >> "%ZIPPATH%"\Logs\LogCollectorStatus.txt
  REG QUERY HKLM\SOFTWARE\DELL\UpdateService\Service\IgnoreList /s /v InstalledUpdateJson >> Update_Ignore_List.txt >NUL
  CD..
  ) ELSE (
  ECHO [%TIME%]: Dell Command Update IgnoreList NOT found >> "%ZIPPATH%"\Logs\LogCollectorStatus.txt
  ECHO Dell Command Update IgnoreList NOT found >> Update_Ignore_List.txt
)

ECHO [Log Collection in progress, please wait - %STEP% of %TOTAL% complete]: Dell Update Package Logs & SET /A STEP=STEP+1
IF EXIST %SYSTEMDRIVE%\ProgramData\Dell\UpdatePackage\Log (
  MD Dell_Update_Package >nul 2>&1
  CD Dell_Update_Package
  ECHO [%TIME%]: Dell Update Package Logs found >> "%ZIPPATH%"\Logs\LogCollectorStatus.txt
  XCOPY /s /y /q /F %SYSTEMDRIVE%\ProgramData\Dell\UpdatePackage\Log . >> "%ZIPPATH%"\Logs\LogCollectorStatus.txt 2>nul
  CD..
) ELSE (
  ECHO File %SYSTEMDRIVE%\ProgramData\Dell\UpdatePackage\Log NOT found on system >> Dell_Update_Package_logs_not_found.txt
  ECHO [%TIME%]:  Dell Update Package Logs NOT found >> "%ZIPPATH%"\Logs\LogCollectorStatus.txt
)

ECHO [Log Collection in progress, please wait - %STEP% of %TOTAL% complete]: Dell Factory Load & SET /A STEP=STEP+1
MD FactoryLoad >nul 2>&1
IF EXIST C:\dell.sdr (
  ECHO [%TIME%]: Dell Factory Load Log found >> "%ZIPPATH%"\Logs\LogCollectorStatus.txt
  XCOPY /y /q /F %SYSTEMDRIVE%\dell.sdr "%APPDATA%"\%SvcTag%\Logs\Dell\FactoryLoad\ >> "%ZIPPATH%"\Logs\LogCollectorStatus.txt 2>nul
) ELSE (
  ECHO [%TIME%]: Dell Factory Load Log NOT found >> "%ZIPPATH%"\Logs\LogCollectorStatus.txt
  ECHO FactoryLoad file dell.sdr NOT found on system >> "%APPDATA%"\%SvcTag%\Logs\Dell\FactoryLoad\Dell_SDR_not_found.txt
)

ECHO [Log Collection in progress, please wait - %STEP% of %TOTAL% complete]: Dell Optimizer Logs & SET /A STEP=STEP+1
FOR /f "usebackq delims=" %%a in (` POWERSHELL -command "Test-Path 'HKLM:\SOFTWARE\DELL\DellOptimizer'" `) DO SET DO_install_check=%%a
FOR /f "usebackq delims=" %%a in (` POWERSHELL -command "((get-itemproperty -path 'HKLM:\SOFTWARE\DELL\DellOptimizer' | SELECT DataFolderName | Format-List | Out-string).substring(21).trim())" `) DO SET DO_path=%%a

IF %DO_install_check% == False (
	ECHO [%TIME%]: Dell Optimizer not found >> "%ZIPPATH%"\Logs\LogCollectorStatus.txt
	ECHO Dell Optimizer not found > .\Dell_Optimizer_not_found.txt
)

IF %DO_install_check% == True (
	ECHO [%TIME%]:  Dell Optimizer found >> "%ZIPPATH%"\Logs\LogCollectorStatus.txt
	MD Dell_Optimizer >nul 2>&1
	CD Dell_Optimizer
	
	ECHO [%TIME%]: Dell Optimizer Service Config Log >> "%ZIPPATH%"\Logs\LogCollectorStatus.txt
	MD Service_config_log >nul 2>&1
	XCOPY /s /I /y /q /F C:\ProgramData\%DO_path%\DellOptimizer\ .\Service_config_log >> "%ZIPPATH%"\Logs\LogCollectorStatus.txt 2>nul
	
    ECHO [%TIME%]: Dell Optimizer UI log >> "%ZIPPATH%"\Logs\LogCollectorStatus.txt
	MD UI_log >nul 2>&1
	XCOPY /s /I /y /q /F %USERPROFILE%\AppData\Local\Packages\DellInc.DellOptimizer_htrsf667h5kn2\LocalState\Logs .\UI_log >> "%ZIPPATH%"\Logs\LogCollectorStatus.txt 2>nul
    
	ECHO [%TIME%]: Dell Optimizer Install Logs >> "%ZIPPATH%"\Logs\LogCollectorStatus.txt
	MD install_log >nul 2>&1
	XCOPY /s /I /y /q /F %USERPROFILE%\AppData\Local\Temp\InstallShield.log .\install_log >> "%ZIPPATH%"\Logs\LogCollectorStatus.txt 2>nul 
	XCOPY /s /I /y /q /F %USERPROFILE%\AppData\Local\Temp\PresenceDetectionValidator_*.log .\install_log >> "%ZIPPATH%"\Logs\LogCollectorStatus.txt 2>nul
	XCOPY /s /I /y /q /F %USERPROFILE%\AppData\Local\Temp\ModularDeploymentValidator_*.log .\install_log >> "%ZIPPATH%"\Logs\LogCollectorStatus.txt 2>nul
	XCOPY /s /I /y /q /F %USERPROFILE%\AppData\Local\Temp\MSI*.log .\install_log >> "%ZIPPATH%"\Logs\LogCollectorStatus.txt 2>nul
	
	ECHO [%TIME%]: Dell Optimizer User Settings Logs >> "%ZIPPATH%"\Logs\LogCollectorStatus.txt
	REM FOR x86 DO Version:	
	IF EXIST "C:\Program Files\Dell\DellOptimizer\do-cli.exe" "C:\Program Files\Dell\DellOptimizer\do-cli.exe" /get >> User_Settings.txt >NUL 2>&1
	REM FOR ARM DO Version:
	IF EXIST "C:\Program Files\Dell\DO-MyDell\DellEnterpriseClientFrameworkSubAgent\do-cli.exe" "C:\Program Files\Dell\DO-MyDell\DellEnterpriseClientFrameworkSubAgent\do-cli.exe" /get >> User_Settings.txt >NUL 2>&1
	CD..
)
CD..

:SKIPDELL

ECHO ───────────────────────────────────────────── Driver ────────────────────────────────────────────────────────── >> "%ZIPPATH%"\Logs\LogCollectorStatus.txt
REM GOTO SKIPDRIVER
CD Driver

ECHO ───────────────────────────────────────────── Driver ──────────────────────────────────────────────────────────
ECHO [Log Collection in progress, please wait - %STEP% of %TOTAL% complete]: Driver Store & SET /A STEP=STEP+1
ECHO [%TIME%]:  Driver Store >> "%ZIPPATH%"\Logs\LogCollectorStatus.txt
DISM /online /get-drivers /all /format:table > Driver_Store.txt

ECHO [Log Collection in progress, please wait - %STEP% of %TOTAL% complete]: Devices in Error State & SET /A STEP=STEP+1
ECHO [%TIME%]:  Devices in Error State >> "%ZIPPATH%"\Logs\LogCollectorStatus.txt
ECHO Devices in a error-state will be listed below (IF applicable): >> Error_State_Drivers.txt
ECHO ============================================================== >> Error_State_Drivers.txt
ECHO. >> Error_State_Drivers.txt
PNPUTIL /enum-devices /problem /ids >> Error_State_Drivers.txt

ECHO [Log Collection in progress, please wait - %STEP% of %TOTAL% complete]: Driver List & SET /A STEP=STEP+1
ECHO [%TIME%]: Driver List >> "%ZIPPATH%"\Logs\LogCollectorStatus.txt
POWERSHELL -command "Get-WmiObject Win32_PnPSignedDriver| select devicename, driverversion, driverdate | Sort-Object devicename" > Driver_List.txt

ECHO [Log Collection in progress, please wait - %STEP% of %TOTAL% complete]: Full Driver Detail & SET /A STEP=STEP+1
ECHO [%TIME%]: Full Driver Detail >> "%ZIPPATH%"\Logs\LogCollectorStatus.txt
POWERSHELL -command "Get-WmiObject Win32_PnPSignedDriver | select *" > Driver_Details.txt
CD..
:SKIPDRIVER

ECHO ───────────────────────────────────────────── Graphics ──────────────────────────────────────────────────────── >> "%ZIPPATH%"\Logs\LogCollectorStatus.txt
REM GOTO SKIPGFX
CD Graphics
ECHO ───────────────────────────────────────────── Graphics ────────────────────────────────────────────────────────
ECHO [Log Collection in progress, please wait - %STEP% of %TOTAL% complete]: DirectX Diagnostic & SET /A STEP=STEP+1
ECHO [%TIME%]: DirectX Diagnostic >> "%ZIPPATH%"\Logs\LogCollectorStatus.txt
dxdiag.exe /t DXdiag.txt

ECHO [Log Collection in progress, please wait - %STEP% of %TOTAL% complete]: Video Adapter/Display Details & SET /A STEP=STEP+1
ECHO [%TIME%]: Video Adapter/Display Details >> "%ZIPPATH%"\Logs\LogCollectorStatus.txt
ECHO Video information (basic details): > Video.txt
ECHO =============================== >> Video.txt
POWERSHELL -command "Get-WmiObject win32_videocontroller | select caption, CurrentHorizontalResolution, CurrentVerticalResolution, CurrentRefreshRate, DriverVersion" >> Video.txt
ECHO Video information (all details): >> Video.txt
ECHO ================================== >> Video.txt
POWERSHELL -command "Get-WmiObject win32_videocontroller | select *" >> Video.txt

ECHO [Log Collection in progress, please wait - %STEP% of %TOTAL% complete]: Monitor Details & SET /A STEP=STEP+1
ECHO [%TIME%]: Monitor Details >> "%ZIPPATH%"\Logs\LogCollectorStatus.txt

ECHO Active Display Information: >> Monitor.txt
ECHO --------------------------- >> Monitor.txt
POWERSHELL -command "Get-CimInstance -Namespace root\wmi -ClassName WmiMonitorID | ForEach-Object {if ($_.UserFriendlyNameLength -gt 0) {($_.ManufacturerName -ne 0  | foreach {[char]$_}) + [char] 10 + 'InstanceName: ' + ($_.InstanceName) + [char] 10 + ($_.UserFriendlyName -ne 0  | foreach {[char]$_}) + [char] 10 + 'Serial: ' + ($_.SerialNumberID -ne 0 | foreach {[char]$_}) + [char] 10 + 'ProdCodeID: ' + ($_.ProductCodeID -ne 0 | foreach {[char]$_}) + [char] 10 + 'WeekOfManufacture:' + $_.WeekOfManufacture + [char] 10 + 'YearOfManufacture:' + $_.YearOfManufacture + [char] 10 + 'DisplayActive:' + $_.Active + [char] 10 -join ''} else{($_.ManufacturerName -ne 0  | foreach {[char]$_}) + [char] 10 + 'InstanceName: ' + ($_.InstanceName)  + [char] 10 + ('No Model (Likely Internal LCD)') + [char] 10 + 'Serial: ' + ($_.SerialNumberID -ne 0 | foreach {[char]$_}) + [char] 10 + 'ProdCodeID: ' + ($_.ProductCodeID -ne 0 | foreach {[char]$_}) + [char] 10 + 'WeekOfManufacture:' + $_.WeekOfManufacture + [char] 10 + 'YearOfManufacture:' + $_.YearOfManufacture + [char] 10 + 'DisplayActive:' + $_.Active + [char] 10 -join ''}}" >> Monitor.txt

ECHO Active Video Output Information: >> Monitor.txt
ECHO -------------------------------- >> Monitor.txt
POWERSHELL -command "Get-CimInstance -Namespace root\wmi -ClassName WmiMonitorConnectionParams | select InstanceName, Active, VideoOutputTechnology | Format-List" >> Monitor.txt

ECHO Video Output Technology Reference: >> Monitor.txt
ECHO ---------------------------------- >> Monitor.txt
ECHO -2 = UNINITIALIZED >> Monitor.txt
ECHO -1 = OTHER >> Monitor.txt
ECHO 4  = DVI >> Monitor.txt
ECHO 5  = HDMI >> Monitor.txt
ECHO 6  = LVDS >> Monitor.txt
ECHO 10 = DISPLAYPORT_EXTERNAL >> Monitor.txt
ECHO 11 = DISPLAYPORT_EMBEDDED >> Monitor.txt
ECHO 12 = UDI_EXTERNAL >> Monitor.txt
ECHO 13 = UDI_EMBEDDED >> Monitor.txt
ECHO 15 = MIRACAST >> Monitor.txt
ECHO XXXXXXXXX = INTERNAL (video output device connects internally to a display device)  >> Monitor.txt
ECHO Reference: https://learn.microsoft.com/en-us/windows-hardware/drivers/ddi/d3dkmdt/ne-d3dkmdt-_d3dkmdt_video_output_technology >> Monitor.txt

ECHO [Log Collection in progress, please wait - %STEP% of %TOTAL% complete]: Display Stream Compression Status & SET /A STEP=STEP+1
ECHO [%TIME%]: Display Stream Compression Status >> "%ZIPPATH%"\Logs\LogCollectorStatus.txt
REG QUERY HKLM\SYSTEM\CurrentControlSet\Control\Class /s /v DPMstDscDisable > Display_Stream_Compression_status.txt

CD..
:SKIPGFX

ECHO ───────────────────────────────────────────── Network ───────────────────────────────────────────────────────── >> "%ZIPPATH%"\Logs\LogCollectorStatus.txt
REM GOTO SKIPNETWORK
CD Network
ECHO ───────────────────────────────────────────── Network ─────────────────────────────────────────────────────────
ECHO [Log Collection in progress, please wait - %STEP% of %TOTAL% complete]: Wireless Report & SET /A STEP=STEP+1
ECHO [%TIME%]: Wireless Report >> "%ZIPPATH%"\Logs\LogCollectorStatus.txt
IF %admincheck% == 0 (ECHO Admin privileges required for Wireless report report > Wireless_Report.txt) ELSE (netsh wlan show wlanreport duration=30 >nul 2>&1 && copy /y %ProgramData%\microsoft\windows\wlanreport\wlan-report-latest.html . >nul && copy /y %ProgramData%\Microsoft\Windows\wlanreport\wlan-report-latest.cab . >nul)

ECHO [Log Collection in progress, please wait - %STEP% of %TOTAL% complete]: Network Interface Overview & SET /A STEP=STEP+1
ECHO [%TIME%]: Network Interface Overview >> "%ZIPPATH%"\Logs\LogCollectorStatus.txt
ipconfig /all > IPConfig_all.txt

ECHO [Log Collection in progress, please wait - %STEP% of %TOTAL% complete]: Current Wired Network Interfaces & SET /A STEP=STEP+1
ECHO [%TIME%]: Current Wired Network Interfaces >> "%ZIPPATH%"\Logs\LogCollectorStatus.txt
netsh lan show interfaces > Current_Wired_Network_Interfaces.txt

ECHO [Log Collection in progress, please wait - %STEP% of %TOTAL% complete]: Current Wired Network Profiles & SET /A STEP=STEP+1
ECHO [%TIME%]: Current Wired Network Profiles >> "%ZIPPATH%"\Logs\LogCollectorStatus.txt
netsh lan show profiles > Wired_Profiles.txt

ECHO [Log Collection in progress, please wait - %STEP% of %TOTAL% complete]: Wired Network Settings & SET /A STEP=STEP+1
ECHO [%TIME%]: Wired Network Settings >> "%ZIPPATH%"\Logs\LogCollectorStatus.txt
netsh lan show settings > Wired_Settings.txt

ECHO [Log Collection in progress, please wait - %STEP% of %TOTAL% complete]: Network Adapter Advanced Properties & SET /A STEP=STEP+1
ECHO [%TIME%]:  Network Adapter Advanced Properties >> "%ZIPPATH%"\Logs\LogCollectorStatus.txt
POWERSHELL -command "Get-NetAdapterAdvancedProperty" > Net_Adapter_Adv_Properties.txt

ECHO [Log Collection in progress, please wait - %STEP% of %TOTAL% complete]: Broadband Adapter Details & SET /A STEP=STEP+1
ECHO [%TIME%]: Broadband Adapter Details >> "%ZIPPATH%"\Logs\LogCollectorStatus.txt
netsh mbn show interfaces > Broadband_Adapter.txt
CD..

:SKIPNETWORK

ECHO ───────────────────────────────────────────── Power ─────────────────────────────────────────────────────────── >> "%ZIPPATH%"\Logs\LogCollectorStatus.txt
REM GOTO SKIPPOWER
CD Power
ECHO ───────────────────────────────────────────── Power ───────────────────────────────────────────────────────────
ECHO [Log Collection in progress, please wait - %STEP% of %TOTAL% complete]: Device Wake Armed & SET /A STEP=STEP+1
ECHO [%TIME%]: Device Wake Armed >> "%ZIPPATH%"\Logs\LogCollectorStatus.txt
powercfg -devicequery wake_armed > Device_Wake_Armed.html

ECHO [Log Collection in progress, please wait - %STEP% of %TOTAL% complete]: Power Schemes List and Settings & SET /A STEP=STEP+1
ECHO [%TIME%]: Power Schemes List and Settings >> "%ZIPPATH%"\Logs\LogCollectorStatus.txt
ECHO Existing Power Schemes: >> Power_Schemes.txt
ECHO ======================= >> Power_Schemes.txt
powercfg /list >> Power_Schemes.txt
ECHO. >> Power_Schemes.txt
ECHO Active Power Scheme Settings: >> Power_Schemes.txt
ECHO ============================= >> Power_Schemes.txt
ECHO. >> Power_Schemes.txt
powercfg /query >> Power_Schemes.txt

ECHO [Log Collection in progress, please wait - %STEP% of %TOTAL% complete]: Available Sleep States & SET /A STEP=STEP+1
ECHO [%TIME%]: Available Sleep States >> "%ZIPPATH%"\Logs\LogCollectorStatus.txt
powercfg /a > Available_Sleepstates.txt

ECHO [Log Collection in progress, please wait - %STEP% of %TOTAL% complete]: Energy Report & SET /A STEP=STEP+1
ECHO [%TIME%]: Energy Report >> "%ZIPPATH%"\Logs\LogCollectorStatus.txt
IF %admincheck% == 0 (ECHO Admin privileges required for energy report > Energy.txt) else (powercfg /energy /output Energy.html >nul 2>&1)

ECHO [Log Collection in progress, please wait - %STEP% of %TOTAL% complete]: Sleep Study Report & SET /A STEP=STEP+1
ECHO [%TIME%]:  Sleep Study Report >> "%ZIPPATH%"\Logs\LogCollectorStatus.txt
IF %admincheck% == 0 (ECHO Admin privileges required for Sleep Study Report > Sleepstudy.txt) else (powercfg /sleepstudy /output Sleepstudy.html >nul 2>&1)

ECHO [Log Collection in progress, please wait - %STEP% of %TOTAL% complete]: Last Wake Trigger & SET /A STEP=STEP+1
ECHO [%TIME%]: Last Wake Trigger >> "%ZIPPATH%"\Logs\LogCollectorStatus.txt
powercfg /lastwake > Lastwake.txt >nul 2>&1

ECHO [Log Collection in progress, please wait - %STEP% of %TOTAL% complete]: Configured Wake Timers & SET /A STEP=STEP+1
ECHO [%TIME%]: Configured Wake Timers >> "%ZIPPATH%"\Logs\LogCollectorStatus.txt
IF %admincheck% == 0 (ECHO Admin privileges required for wake timers report > Waketimers.txt) else (powercfg /waketimers > Waketimers.txt >nul 2>&1)

ECHO [Log Collection in progress, please wait - %STEP% of %TOTAL% complete]: Battery Report & SET /A STEP=STEP+1
ECHO [%TIME%]: Battery Report >> "%ZIPPATH%"\Logs\LogCollectorStatus.txt
powercfg /batteryreport /output Battery_Report.html /duration 14 >nul 2>&1

ECHO [Log Collection in progress, please wait - %STEP% of %TOTAL% complete]: Power Requests Report & SET /A STEP=STEP+1
ECHO [%TIME%]: Power Requests Report >> "%ZIPPATH%"\Logs\LogCollectorStatus.txt
IF %admincheck% == 0 (ECHO Admin privileges required for Power Requests Report > Power_Requests_Report.txt) else (powercfg /requests > Power_Requests.txt >nul 2>&1)

CD..
:SKIPPOWER

ECHO ───────────────────────────────────────────── System ────────────────────────────────────────────────────────── >> "%ZIPPATH%"\Logs\LogCollectorStatus.txt
REM GOTO SKIPSYSTEM
CD System
ECHO ───────────────────────────────────────────── System ──────────────────────────────────────────────────────────
ECHO [Log Collection in progress, please wait - %STEP% of %TOTAL% complete]: Service Tag and Baseboard ID & SET /A STEP=STEP+1
ECHO [%TIME%]: Service Tag and Baseboard ID >> "%ZIPPATH%"\Logs\LogCollectorStatus.txt
POWERSHELL -command  "Get-CimInstance -ClassName Win32_BaseBoard | Format-List" > System_Board.txt

ECHO [Log Collection in progress, please wait - %STEP% of %TOTAL% complete]: Memory Management Status & SET /A STEP=STEP+1
ECHO [%TIME%]: Memory Management Status >> "%ZIPPATH%"\Logs\LogCollectorStatus.txt
IF %admincheck% == 0 (ECHO Admin privileges required for Memory Management Status report > MemoryManagement.txt) else (POWERSHELL -command "Get-mmagent | Out-File MemoryManagement.html")

ECHO [Log Collection in progress, please wait - %STEP% of %TOTAL% complete]: PCIe Device Info & SET /A STEP=STEP+1
ECHO [%TIME%]: PCIe Device Info >> "%ZIPPATH%"\Logs\LogCollectorStatus.txt
POWERSHELL -command "(Get-WMIObject Win32_Bus -Filter 'DeviceID like \"PCI%%\"').GetRelated('Win32_PnPEntity') | foreach { [pscustomobject][ordered]@{Name = $_.Name; ExpressSpecVersion=$_.GetDeviceProperties('DEVPKEY_PciDevice_ExpressSpecVersion').deviceProperties.data;MaxLinkSpeed=$_.GetDeviceProperties('DEVPKEY_PciDevice_MaxLinkSpeed').deviceProperties.data; MaxLinkWidth=$_.GetDeviceProperties('DEVPKEY_PciDevice_MaxLinkWidth').deviceProperties.data; CurrentLinkSpeed=$_.GetDeviceProperties('DEVPKEY_PciDevice_CurrentLinkSpeed').deviceProperties.data; CurrentLinkWidth=$_.GetDeviceProperties('DEVPKEY_PciDevice_CurrentLinkWidth'  ).deviceProperties.data} | Where MaxLinkSpeed } | Format-Table -AutoSize;" >> PCIe_Device_Info.txt

ECHO [Log Collection in progress, please wait - %STEP% of %TOTAL% complete]: BIOS Settings Export & SET /A STEP=STEP+1
POWERSHELL -command "Get-CimInstance -Namespace root\dcim\sysman\biosattributes -ClassName EnumerationAttribute | Select-Object AttributeName, CurrentValue, Defaultvalue, PossibleValue" >nul 2>&1
IF %ERRORLEVEL% == 0 (SET /A biosexportcheck=1) ELSE (SET /A biosexportcheck=0)

IF %admincheck% == 0 (
     ECHO [%TIME%]: BIOS Settings Export failed, Admin Privileges required >> "%ZIPPATH%"\Logs\LogCollectorStatus.txt
     ECHO BIOS Settings Export failed, Admin Privileges required >> BIOS_Settings.txt
     GOTO BIOS_EXPORT_END
     ) 

IF %biosexportcheck% == 0 (
     ECHO [%TIME%]: BIOS Settings Export failed. System Model not supported. >> "%ZIPPATH%"\Logs\LogCollectorStatus.txt
     ECHO BIOS Settings Export failed. System Model not supported. >> BIOS_Settings.txt
     GOTO BIOS_EXPORT_END
     )

POWERSHELL -command "Get-CimInstance -Namespace root\dcim\sysman\biosattributes -ClassName EnumerationAttribute | Select-Object AttributeName, CurrentValue, Defaultvalue, PossibleValue | Sort-Object AttributeName | Out-File BIOS_Settings.txt"
ECHO [%TIME%]: BIOS settings exported >> "%ZIPPATH%"\Logs\LogCollectorStatus.txt

:BIOS_EXPORT_END

CD..
:SKIPSYSTEM

ECHO ───────────────────────────────────────────── Security ──────────────────────────────────────────────────────── >> "%ZIPPATH%"\Logs\LogCollectorStatus.txt
REM GOTO SKIPSECURITY
CD Security
ECHO ───────────────────────────────────────────── Security ────────────────────────────────────────────────────────
ECHO [Log Collection in progress, please wait - %STEP% of %TOTAL% complete]: Bitlocker Status & SET /A STEP=STEP+1
ECHO [%TIME%]: Bitlocker Status >> "%ZIPPATH%"\Logs\LogCollectorStatus.txt
IF %admincheck% == 0 (ECHO Admin Privileges required for Bitlocker Status Report > Bitlocker_Status.txt) else (manage-bde -status > Bitlocker_Status.txt)

ECHO [Log Collection in progress, please wait - %STEP% of %TOTAL% complete]: Bitlocker Protectors & SET /A STEP=STEP+1
ECHO [%TIME%]: Bitlocker Protectors >> "%ZIPPATH%"\Logs\LogCollectorStatus.txt
IF %admincheck% == 0 (ECHO Admin privileges required for bitlocker PCRs report > Bitlocker_PCRs.txt) else (manage-bde %SYSTEMDRIVE% -protectors -get -type TPM > Bitlocker_PCRs.txt)

ECHO [Log Collection in progress, please wait - %STEP% of %TOTAL% complete]: TPM Information & SET /A STEP=STEP+1
ECHO [%TIME%]: TPM Information >> "%ZIPPATH%"\Logs\LogCollectorStatus.txt
IF %admincheck% == 0 (ECHO Admin Privileges required for TPM Information report > tpm.txt) else (POWERSHELL -command "get-tpm" > TPM.txt)
CD..

:SKIPSECURITY

ECHO ───────────────────────────────────────────── Storage ───────────────────────────────────────────────────────── >> "%ZIPPATH%"\Logs\LogCollectorStatus.txt
REM GOTO SKIPSTORAGE
CD Storage
ECHO ───────────────────────────────────────────── Storage ─────────────────────────────────────────────────────────
ECHO [Log Collection in progress, please wait - %STEP% of %TOTAL% complete]: Storage Details & SET /A STEP=STEP+1
ECHO [%TIME%]: Storage Details >> "%ZIPPATH%"\Logs\LogCollectorStatus.txt
POWERSHELL -command  "Get-CimInstance -ClassName Win32_DiskDrive | select * | Format-List" > Disk_Drives.txt
POWERSHELL -command  "Get-CimInstance -ClassName Win32_DiskPartition | Format-List" > Disk_Volumes.txt
CD..

:SKIPSTORAGE

ECHO ───────────────────────────────────────────── USB ───────────────────────────────────────────────────────────── >> "%ZIPPATH%"\Logs\LogCollectorStatus.txt
REM GOTO SKIPUSB
CD USB
ECHO ───────────────────────────────────────────── USB ─────────────────────────────────────────────────────────────
ECHO [Log Collection in progress, please wait - %STEP% of %TOTAL% complete]: USB Devices & SET /A STEP=STEP+1
ECHO [%TIME%]: USB Devices log >> "%ZIPPATH%"\Logs\LogCollectorStatus.txt
POWERSHELL -command "gwmi Win32_USBControllerDevice |%%{[wmi]($_.Dependent)} | Sort Manufacturer,Name,Description,DeviceID | Ft -GroupBy Manufacturer Name,Description,Service,DeviceID" > USB_Devices.txt"
CD..

:SKIPUSB

ECHO ==================================================================================================== >> "%ZIPPATH%"\Logs\LogCollectorStatus.txt

ECHO --------------------------------------------- WAIT for MSINFO32 ----------------------------------------------- >> "%ZIPPATH%"\Logs\LogCollectorStatus.txt

SET /A COUNTER=0
:LOOP
tasklist | find /i "msinfo32" >nul 2>&1
IF ERRORLEVEL 1 (
  ECHO %TIME%: INFO ONLY - MSinfo32 log creation check has finished >> "%ZIPPATH%"\Logs\LogCollectorStatus.txt
  GOTO CONTINUE
) ELSE (
  ECHO [Log Collection in progress]: MSinfo32 Log Creation still in progress, waiting...
  ECHO %TIME%: MSinfo32 log creation still in progress, wait additional 10s >> "%ZIPPATH%"\Logs\LogCollectorStatus.txt
  timeout /T 10 /Nobreak >nul
  SET /A COUNTER=COUNTER+1
  IF %COUNTER% == 3 (
	CHOICE /C yzn /N /T 30 /D y /M "[Log Collection in progress]: MSinfo32 Log Creation not finished yet. Do you want to wait another 30 Seconds? (Y)es, (N)o]: "
	IF ERRORLEVEL 3 (TASKKILL /F /IM msinfo32.exe >nul 2>&1) ELSE (SET COUNTER=0)
	)
  GOTO LOOP
)
:CONTINUE


ECHO --------------------------------------------- WAIT for GPRESULT ----------------------------------------------- >> "%ZIPPATH%"\Logs\LogCollectorStatus.txt

SET /A COUNTER=0
:LOOP2
tasklist | find /i "gpresult" >nul 2>&1
IF ERRORLEVEL 1 (
  ECHO %TIME%: INFO ONLY - Gpresult Log Creation check has finished >> "%ZIPPATH%"\Logs\LogCollectorStatus.txt
  GOTO CONTINUE2
) ELSE (
  ECHO [Log Collection in progress]: Gpresult log creation still in progress, waiting...
  ECHO %TIME%: Gpresult Log Creation still in progress, wait additional 10s >> "%ZIPPATH%"\Logs\LogCollectorStatus.txt
  timeout /T 10 /Nobreak >nul
  SET /A COUNTER=COUNTER+1
  IF %COUNTER% == 3 (
	CHOICE /C yzn /N /T 30 /D y /M "[Log Collection in progress]: Gpresult Log Creation not finished yet. Do you want to wait another 30 Seconds? (Y)es, (N)o]: "
	IF ERRORLEVEL 3 (TASKKILL /F /IM gpresult.exe >nul 2>&1) ELSE (SET COUNTER=0)
	)
  GOTO LOOP2
)
:CONTINUE2

ECHO --------------------------------------------- LOG Collection END ---------------------------------------------- >> "%ZIPPATH%"\Logs\LogCollectorStatus.txt
CD..
CD..
REM ------------------------------------ creating zip file ------------------------------------

ECHO [Log Collection completed]: Creating ZIP file - please wait...

REM ------------------------------------ check for diskspace in script- and destinationpath and cleanup ------------------------------------
ECHO [Log Collection completed]: Check for Diskspace and Cleanup...
SET scriptpath=%~dp0
SET script_drive=%~d0
SET script_drive=%script_drive::=%
SET sys_drive=%SYSTEMDRIVE%
SET sys_drive=%sys_drive::=%

REM ------------------------------------ check for diskspace to create ZIP on APPDATA location ------------------------------------
REM GOTO SKIP_ZIP_CREATION_CHECK
POWERSHELL -NoLogo -NoProfile -Command ^
  $freespace_systemdrive = ([math]::floor(((Get-PSDrive -Name '%sys_drive%').Free)/1MB)); ^
  "$zipfoldersize = ([math]::ceiling((Get-ChildItem -Path '%APPDATA%\%SvcTag%' -Recurse | Measure-Object -Property Length -Sum).Sum/1MB))"; ^
  IF ($freespace_systemdrive -lt $zipfoldersize) { exit $true } else { exit $false }
IF %ERRORLEVEL% == 1 (GOTO NO_ZIP_CREATION)
:SKIP_ZIP_CREATION_CHECK
POWERSHELL.exe -command "Add-Type -AssemblyName "System.IO.Compression.FileSystem"; [System.IO.Compression.ZipFile]::CreateFromDirectory('%APPDATA%\%SvcTag%', '%APPDATA%\%zipfile%')"

REM ------------------------------------ check for diskspace for ZIP in script file location ------------------------------------
REM GOTO SKIP_ZIP_DESTINATION_CHECK
POWERSHELL -NoLogo -NoProfile -Command ^
  $freespace_scriptdrive = ([math]::floor(((Get-PSDrive -Name '%script_drive%').Free)/1MB)); ^
  $zipfilesize = ([math]::ceiling((Get-Item '%APPDATA%\%zipfile%').length/1MB)); ^
  IF ($freespace_scriptdrive -lt $zipfilesize) { exit $true } else { exit $false }
IF %ERRORLEVEL% == 1 (
	RD /S /Q "%ZIPPATH%"
	GOTO NO_ZIP_COPY
) ELSE (
	RD /S /Q "%ZIPPATH%"
	MOVE %zipfile% "%scriptpath%"
)
REM  WRITE-HOST "Free space on script file drive: $freespace_scriptdrive MB"; ^
REM  WRITE-HOST "ZIP File size: $zipfilesize MB"; ^
REM  PAUSE; ^ 
:SKIP_ZIP_DESTINATION_CHECK

REM ------------------------------------ standard finish message ------------------------------------
CLS
COLOR 2f
CLS
REM CLS & ECHO [Log Collection completed]: 
ECHO.
POWERSHELL write-host [Log Collection completed]: -ForegroundColor darkgreen -BackgroundColor white
ECHO.
ECHO The log file %zipfile%  has been successfully stored in:
ECHO %scriptpath%
ECHO.
ECHO Further details about the data collection can be found in the \Logs\LogCollectorStatus.txt file.
ECHO.
ECHO Please send the ZIP file back to Dell. Thank you!
ECHO.
PAUSE
GOTO FINISH

REM ---------------------- not enough space for ZIP file creation finish message ----------------------
:NO_ZIP_CREATION
CLS
COLOR 2f
CLS & ECHO [Log Collection complete]: 
POWERSHELL write-host -back Red Not enough disk space available to create the ZIP file.
ECHO Please free some space, create ZIP file of the Folder %APPDATA%\%SvcTag% and send it back to Dell. Thank you!
ECHO.
PAUSE
%SYSTEMROOT%\explorer.exe /e,%APPDATA%
GOTO FINISH

REM ------------------------- not enough space to copy ZIP file finish message ------------------------
:NO_ZIP_COPY
CLS
COLOR 2f
CLS & ECHO [Log Collection complete]: 
POWERSHELL write-host -back Red Not enough disk space available to move the log ZIP file to %scriptpath%
ECHO The file %zipfile% has been stored in %APPDATA% instead.
ECHO Please send the file back to Dell. Thank you!
ECHO.
PAUSE
%SYSTEMROOT%\explorer.exe /e,%APPDATA%
GOTO FINISH

:FINISH
COLOR
CLS