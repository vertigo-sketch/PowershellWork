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
$Path = "C:\Temp\NewHires.csv"

Import-Module Microsoft.Graph.Groups
Connect-MgGraph -Scopes "User.Read.All", "Group.ReadWrite.All" -NoWelcome

$Users = Import-CSv -Path $Path 

ForEach ($User in $Users){     
    
        $ID = Get-MgUser -Filter "DisplayName eq '$User.DisplayName'" | select UserPrincipalName
        #Get-MgUser -UserId $User.UserPrincipalName | Select-Object Id

        #Adds users to SSO-Mirador VPN
        New-MgGroupMember -GroupId 'e74fb95a-c9ae-44a3-9d15-86e55755a0da' -DirectoryObjectId $ID.Id
        #Adds users to Intune Conditional Access MFA Exception
        New-MgGroupMember -GroupId 'c3e7f7ca-559a-4d2b-8a9c-db5491c3d14e' -DirectoryObjectId $ID.Id
           
        Write-Host -ForegroundColor Green "Group Membershipts for "$User.UserPrincipalName" have been updated."
        }