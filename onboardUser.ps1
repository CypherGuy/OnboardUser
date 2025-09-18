# ===============================================================
# Prerequisites (manual setup required before running this script)
# ===============================================================
# 1. Bitwarden API key must be set as environment variables:
#      BW_CLIENTID     = your Bitwarden Client ID
#      BW_CLIENTSECRET = your Bitwarden Client Secret
#
#    Example (one-time setup per machine/user):
#      [System.Environment]::SetEnvironmentVariable("BW_CLIENTID","<your-client-id>","User")
#      [System.Environment]::SetEnvironmentVariable("BW_CLIENTSECRET","<your-client-secret>","User")
#
# 2. You must be signed in with an Azure AD / Microsoft Entra account
#    that has permissions to:
#      - Create users
#      - Assign licenses
#      - Add users to groups
# ===============================================================

# AzureAD module check/install
$global:AzModule = $null

if (-not (Get-Module -ListAvailable -Name AzureAD)) {
    Write-Host "AzureAD module not found. Installing..." -ForegroundColor Yellow
    try {
        Install-Module AzureAD -Force -Scope CurrentUser -ErrorAction Stop
    }
    catch {
        Write-Host "AzureAD module failed to install. Please install manually with 'Install-Module AzureAD' and rerun the script." -ForegroundColor Red
        exit 1
    }

    # Verify install succeeded
    if (-not (Get-Module -ListAvailable -Name AzureAD)) {
        Write-Host "AzureAD module could not be found even after install. Aborting." -ForegroundColor Red
        exit 1
    } else {
        $global:AzModule = "AzureAD"
        Write-Host "AzureAD module installed successfully." -ForegroundColor Green
    }
} else {
    $global:AzModule = "AzureAD"
}

# Bitwarden CLI check/install/verify - bwexe is a variable pointing to the Bitwarden CLI executable
$global:BwExe = $null

if (-not (Get-Command bw -ErrorAction SilentlyContinue)) {
    Write-Host "Bitwarden CLI not found. Installing..." -ForegroundColor Yellow
    winget install Bitwarden.CLI --silent --accept-source-agreements --accept-package-agreements

# Rather then having to reload the terminal to use bw, let's find the path and store it for later

    # Try to locate bw.exe
    $bwExe = Get-ChildItem "$env:LOCALAPPDATA\Microsoft\WinGet\Packages" -Recurse -Filter "bw.exe" -ErrorAction SilentlyContinue | 
             Select-Object -First 1 -ExpandProperty FullName

    if ($bwExe) {
        $global:BwExe = $bwExe
        Write-Host "Found Bitwarden CLI at: $bwExe" -ForegroundColor Green
    }  else {
        Write-Host "Bitwarden CLI was installed but could not be located. Please restart your terminal and rerun the script,or install manually." -ForegroundColor Red
        exit 1
    }
} else {
    # If already in PATH, just use the command
    $global:BwExe = "bw"
}

Import-Module AzureAD

# Connect to Azure AD
Connect-AzureAD

# Generate password - I intend to do this via Bitwarden post-demo
function New-CustomPassword {
    $wordList = @(
        "Apple","Banana","Carrot","Dragon","Eagle","Falcon","Guitar",
        "Hammer","Island","Jungle","Kite","Lemon","Monkey","Needle",
        "Orange","Piano","Plane","Queen","Rocket","Snake","Tiger","Tower","Umbrella",
        "Violet","Wolf","Xylophone","Yak","Zebra","Triangle","Square","Circle","Axe",
        "Bear","Cat","Dog","Lion","Shark","Dolphin","Horse","Fox","Whale",
        "Otter","Rabbit","Cobra","Rhino","Cheetah","Panther","Moose",
        "Chair","Table","Laptop","Phone","Bottle","Camera","Wallet","Ticket","Bridge","Clock",
        "Book","Shield","Helmet","Anchor","Lantern","Compass","Candle","Brush","Drill",
        "Mountain","River","Forest","Desert","Ocean","Valley","Canyon","Harbor","Beach",
        "Storm","Cloud","Sunset","Rainbow","Volcano","Glacier","Prairie","Savanna",
        "Pixel","Orbit","Galaxy","Meteor","Planet","Nebula","Star","Astro","Comet","Nova",
        "Hero","Wizard","Knight","Castle","Crown","Sword","Potion","Treasure","Key"
    )
    $words = Get-Random -InputObject $wordList -Count 3
    $indexForNumber = Get-Random -Minimum 0 -Maximum 3
    $number = Get-Random -Minimum 1 -Maximum 99
    $words[$indexForNumber] = $words[$indexForNumber] + $number
    return ($words -join "-")
}

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
    Write-Host ("[{0}] {1} ({2}) - {3} available" -f $i, $part, $friendly, $available)
}
$SKUChoice = Read-Host "Choose a license number or press enter to leave unlicensed"

# Show Groups
Write-Host "`nAvailable Groups:" -ForegroundColor Yellow
$availableGroups = Get-AzureADGroup | Select-Object DisplayName, ObjectId
for ($i=0; $i -lt $availableGroups.Count; $i++) {
    Write-Host "[$i] $($availableGroups[$i].DisplayName)"
}
$groupChoice = Read-Host "OPTIONAL: Choose a group number"
$GroupId = $null
if ($groupChoice -match '^\d+$') {
    $GroupId = $availableGroups[$groupChoice].ObjectId
    $GroupName = $availableGroups[$groupChoice].DisplayName
}

# Generate password
$generatedPassword = New-CustomPassword
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

# Add to group if chosen
if ($GroupId) {
    Add-AzureADGroupMember -ObjectId $GroupId -RefObjectId $newUser.ObjectId
    Write-Host "Added to group: $GroupName"
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
Write-Host "Hi [Insert recipient name]," -ForegroundColor White
Write-Host "" -ForegroundColor White
Write-Host "I can confirm the account for $FirstName has been created." -ForegroundColor White
Write-Host "" -ForegroundColor White
Write-Host "- Email: $UPN" -ForegroundColor White
Write-Host "- Password: available at the secure link below:" -ForegroundColor White
Write-Host "" -ForegroundColor White
Write-Host "$link" -ForegroundColor Yellow
Write-Host "" -ForegroundColor White
Write-Host "Please note that this link will expire in 3 days and can only be opened up to 4 times. $FirstName will also be required to change the password when they login next." -ForegroundColor White
Write-Host "" -ForegroundColor White
Write-Host "Please let me know if there are any issues!" -ForegroundColor White
Write-Host "" -ForegroundColor White
Write-Host "Thanks," -ForegroundColor White
Write-Host "[Your name]" -ForegroundColor White
