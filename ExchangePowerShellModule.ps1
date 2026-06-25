
# After Connect-ExchangeOnline:
Get-EXOMailbox -ResultSize Unlimited -Filter "RecipientTypeDetails -eq 'UserMailbox' -and AccountDisabled -eq `$false" |
ForEach-Object {
    $u = $_.UserPrincipalName
    try {
        Get-App -Mailbox $u | Select-Object @{n='UserPrincipalName';e={$u}},
            DisplayName, AppId, Enabled, DefaultStateForUser, ProvidedTo, IsMandatory, Version, ProviderName, SourceLocation
    } catch {
        [pscustomobject]@{ UserPrincipalName=$u; DisplayName='[ERROR]'; AppId=$null; Enabled=$null; DefaultStateForUser=$null;
                           ProvidedTo=$null; IsMandatory=$null; Version=$null; ProviderName=$null; SourceLocation=$_.Exception.Message }
    }
} | Export-Csv -NoTypeInformation -Encoding UTF8 -Path ".\MailboxAddins_$(Get-Date -f yyyyMMdd-HHmmss).csv"
