<#
     .Synopsis
      This script adds users to various groups. 
     .Description
      The script uses both MSGraph and Exchange Powershell module, to add users to various groups.    
     .Notes
      NAME:  FullTimeGroups
      AUTHOR: Danny Pires
      LAST EDIT: 11032023
     .Link
       #No Git :(
   #Requires -Version 5.1
#>

Write-Host -ForegroundColor Yellow "You must have the module MSGraph (Microsoft.Graph.Groups) and the module ExchangePowerShell installed."
Write-Host -ForegroundColor Yellow "You will also need to define the path to the CSV, containing the emails of each new hire. Line 19."

#Path to the CSV, containing the emails for new hires. 
$Path = "C:\Users\DanielPires\Downloads\Newhires06282024.csv"

Import-Module ExchangeOnlineManagement
Connect-ExchangeOnline

Import-Module Microsoft.Graph.Groups
Connect-MgGraph -Scopes "User.Read.All", "Group.ReadWrite.All" -NoWelcome

$Users = Import-CSv -Path $Path 

ForEach ($User in $Users){        
        
        $ID = Get-MgUser -UserId $User.UserPrincipalName | Select-Object Id

        #Adds users to LICENSE-E5
        New-MgGroupMember -GroupId '897adb53-370b-4899-90d6-01aeef8cfc2d' -DirectoryObjectId $ID.Id
        #Adds users to Intune-Mobile-Enrollment
        New-MgGroupMember -GroupId '2311129a-8958-495f-be9b-f0b96f725897' -DirectoryObjectId $ID.Id
        #Adds users to Intune-Laptop-Enrollment
        New-MgGroupMember -GroupId '2169eaf7-835a-49d7-8701-de5214ca1719' -DirectoryObjectId $ID.Id
        #Adds users to SSO-Palo Alto Prisma
        New-MgGroupMember -GroupId '16e5f477-5cc9-4fcf-afb8-c2aeb07dccfc' -DirectoryObjectId $ID.Id
        #Adds users to SSO-Palo Alto 
        New-MgGroupMember -GroupId '9f74de60-d7bb-40eb-9c92-ef14cd2ee915' -DirectoryObjectId $ID.Id
        #Adds users to ICN-Users-Full Employees
        New-MgGroupMember -GroupId '8972243c-ce8f-4928-9f3c-80817c0f6fa9' -DirectoryObjectId $ID.Id
        #Adds users to SSO-Confluence
        New-MgGroupMember -GroupId 'f1430f9a-8bc8-483e-96c6-7ad5ea7ff0dc' -DirectoryObjectId $ID.Id
        #Adds users to SSO-Greenhouse
        New-MgGroupMember -GroupId '2c71c671-ec61-415e-8820-5c1de986d2cb' -DirectoryObjectId $ID.Id
        
        #Adds users to CalendarDelegates
        Add-DistributionGroupMember -Identity '8f302f85-2180-4f15-adbe-99c8a5cea906' -Member $User.UserPrincipalName -Confirm:$false -BypassSecurityGroupManagerCheck
        #Adds users to ICN Team
        Add-DistributionGroupMember -Identity '1db0688e-4f10-433d-b31a-2329cf6f0723' -Member $User.UserPrincipalName -Confirm:$false -BypassSecurityGroupManagerCheck
              
        Write-Host -ForegroundColor Green "Group Membershipts for "$User.UserPrincipalName" have been updated."
        }