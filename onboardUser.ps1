# To do:
#	- Multiple groups
# 
# ===============================================================
# Prerequisites (manual setup required before running this script)
# ===============================================================
# 1. Bitwarden API key must be set as environment variables:
#      BW_CLIENTID     = your Bitwarden Client ID
#      BW_CLIENTSECRET = your Bitwarden Client Secret
#
#    Then run these commands - You only need to do this once:
#      [System.Environment]::SetEnvironmentVariable("BW_CLIENTID","<your-client-id>","User")
#      [System.Environment]::SetEnvironmentVariable("BW_CLIENTSECRET","<your-client-secret>","User")
#
# 2. You must be signed in with an Azure AD / Microsoft Entra account
#    that has permissions to:
#      - Create users
#      - Assign licenses
#      - Add users to groups
#
# Note: If either the AzureAD or the bw modules aren't installed, the script will install them but you may need to restart the terminal and rerun the script.
# ===============================================================

# AzureAD module check/install
$global:AzModule = $null

if (-not (Get-Module -ListAvailable AzureAD)) {
    Write-Host "Installing AzureAD module..."
    Install-Module AzureAD -Force -Scope CurrentUser
}else {
    $global:AzModule = "AzureAD"
}

# Bitwarden CLI check/install/verify - bwexe is a variable pointing to the Bitwarden CLI executable
$global:BwExe = $null

if (-not (Get-Command bw -ErrorAction SilentlyContinue)) {
    Write-Host "Installing Bitwarden CLI..."
    winget install Bitwarden.CLI --accept-source-agreements --accept-package-agreements
    Write-Host "'bw' has just been installed and thus would likely be unavailable to use until the terminal is restarted"
} else {
    # If already in PATH, just use the command
    $global:BwExe = "bw"
}

Import-Module AzureAD

# Connect to Azure AD
Connect-AzureAD

# Mapping table for friendly license names
$SKUNames = @{
    "FLOW_FREE"              = "Power Automate Free"
    "DEVELOPERPACK_E5"       = "Microsoft 365 Developer E5"
    "ENTERPRISEPREMIUM"      = "Office 365 E5"
    "ENTERPRISEPACK"         = "Office 365 E3"
    "STANDARDPACK"           = "Office 365 E1"
    "O365_BUSINESS_PREMIUM"  = "Microsoft 365 Business Standard"
    "M365_BUSINESS_PREMIUM"  = "Microsoft 365 Business Premium"
    "EXCHANGESTANDARD"       = "Exchange Online Plan 1"
    "EXCHANGEENTERPRISE"     = "Exchange Online Plan 2"
    "POWER_BI_PRO"           = "Power BI Pro"
}

$FirstName     = Read-Host "Enter First Name"
$LastName      = Read-Host "Enter Last Name"
$DisplayName   = "$FirstName $LastName"

# Prefix + domain
$UPNPrefix = Read-Host "Enter UPN prefix (e.g. john.doe)"
$domains = @(Get-AzureADDomain | Where-Object { $_.IsVerified -eq $true } | Select-Object -ExpandProperty Name)

Write-Host "`nAvailable Domains:" -ForegroundColor Yellow
for ($i=0; $i -lt $domains.Count; $i++) {
    Write-Host "[$i] $($domains[$i])"
}

$domainChoice = Read-Host "Choose a domain number"
$chosenDomain = $domains[$domainChoice]

if (-not $chosenDomain) {
    throw "Invalid domain choice. Please rerun the script."
}
$UPN = "$UPNPrefix@$chosenDomain"

$MailNickname  = Read-Host "OPTIONAL: Enter Mail Nickname (Must be one word - default is $UPNPrefix)"
if ([string]::IsNullOrWhiteSpace($MailNickname)) { $MailNickname = "$UPNPrefix" }

$UserLocation = Read-Host "OPTIONAL: Enter User Location (default GB)" 
if ([string]::IsNullOrWhiteSpace($UserLocation)) { $UserLocation = "GB" }

# Show Licences in a nice way (only those with available seats)
Write-Host "`nAvailable Licences:" -ForegroundColor Yellow
$availableSKUs = Get-AzureADSubscribedSku | Where-Object {
    $_.PrepaidUnits.Enabled -gt $_.ConsumedUnits
} | Select-Object SkuPartNumber, SkuId, `
    @{Name="Available";Expression={$_.PrepaidUnits.Enabled - $_.ConsumedUnits}}

for ($i=0; $i -lt $availableSKUs.Count; $i++) {
    $part = $availableSKUs[$i].SkuPartNumber
    $friendly = $SKUNames[$part]
    if (-not $friendly) { $friendly = "Unknown / Unmapped" }
    $available = $availableSKUs[$i].Available

    Write-Host "[$i] $part ($friendly) - $available available"
}
$SKUChoice = Read-Host "Choose a license number or press enter to leave unlicensed"

# Show Groups
Write-Host "`nAvailable Groups:" -ForegroundColor Yellow
$availableGroups = Get-AzureADGroup | Select-Object DisplayName, ObjectId
for ($i=0; $i -lt $availableGroups.Count; $i++) {
    Write-Host "[$i] $($availableGroups[$i].DisplayName)"
}
$groupChoice = Read-Host "OPTIONAL: Enter a comma-seperated list of groups to add $FirstName to"
$GroupId = $null
$numbers = @($groupChoice -split "," | ForEach-Object { [int]$_ })
$GroupIdList = New-Object System.Collections.Generic.List[string]
$GroupNameList = New-Object System.Collections.Generic.List[string]
foreach ($n in $numbers) {
$GroupIdList.Add($availableGroups[$n].ObjectId)
$GroupNameList.Add($availableGroups[$n].DisplayName)

}

# Generate password
$generatedPassword = & $BwExe generate --passphrase --words 3 --separator "-" --capitalize --includeNumber
$passwordProfile = New-Object -TypeName Microsoft.Open.AzureAD.Model.PasswordProfile
$passwordProfile.Password = $generatedPassword
$passwordProfile.ForceChangePasswordNextLogin = $true

# Create user
$newUser = New-AzureADUser -DisplayName $DisplayName `
    -GivenName $FirstName `
    -Surname $LastName `
    -UserPrincipalName $UPN `
    -MailNickname $MailNickname `
    -PasswordProfile $passwordProfile `
    -AccountEnabled $true

# Set usage location
Set-AzureADUser -ObjectId $newUser.ObjectId -UsageLocation $UserLocation

# Add to groups
foreach ($GroupId in $GroupIdList) {
    Add-AzureADGroupMember -ObjectId $GroupId -RefObjectId $newUser.ObjectId
    Write-Host "$FirstName Added to group with ID: $GroupId."
}


if (-not [string]::IsNullOrWhiteSpace($SKUChoice)) {
# Find the license
$SKUId = $availableSKUs[$SKUChoice].SKUId
$SKUPartNumber = $availableSKUs[$SKUChoice].SkuPartNumber
$SKUFriendlyName = $SKUNames[$SKUPartNumber]

# Assign license
$license = New-Object -TypeName Microsoft.Open.AzureAD.Model.AssignedLicense
$license.SkuId = $SKUId
$licenses = New-Object -TypeName Microsoft.Open.AzureAD.Model.AssignedLicenses
$licenses.AddLicenses = $license
Set-AzureADUserLicense -ObjectId $newUser.ObjectId -AssignedLicenses $licenses
}

# Ensure Bitwarden is unlocked
if (-not $env:BW_SESSION) {
    $BW_SESSION = & $BwExe unlock --raw
    $env:BW_SESSION = $BW_SESSION
} else {
    $BW_SESSION = $env:BW_SESSION
}

# Push password to Bitwarden Send (3 days, 4 max clicks)
$linkJson = & $BwExe send -n "$FirstName $LastName" -d 3 -a 4 --hidden --session $BW_SESSION "$generatedPassword"

# Parse JSON and extract just the URL
$link = ($linkJson | ConvertFrom-Json).accessUrl

# Output summary
Write-Host "`nUser onboarded successfully!" -ForegroundColor Green
Write-Host "UPN: $UPN"
Write-Host "Password: $generatedPassword"
Write-Host "Bitwarden Send link: $link"
Write-Host "License: $SKUPartNumber ($SKUFriendlyName)"
if ($GroupName) { Write-Host "Group: $GroupName" }
Write-Host "Template:"
Write-Host "`n--- Email to Send ---" -ForegroundColor Cyan
Write-Host "Hi [Insert recipient name],"
Write-Host ""
Write-Host "I can confirm the account for $FirstName has been created."
Write-Host ""
Write-Host "- Email: $UPN"
Write-Host "- Password: available at the secure link below:"
Write-Host ""
Write-Host "$link" -ForegroundColor Yellow
Write-Host ""
Write-Host "Please note that this link will expire in 3 days and can only be opened up to 4 times. $FirstName will also be required to change the password when they login next."
Write-Host ""
Write-Host "Please let me know if there are any issues!"
Write-Host ""
Write-Host "Thanks,"
Write-Host "[Your name]"
