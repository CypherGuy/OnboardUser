* Note: This is using the outdated AzureAD module. I will release a similar script that uses MS Graph in due course, with plans to make a GUI as well.

# Azure AD User Onboarding Automation (PowerShell)

This PowerShell script automates the **end-to-end onboarding process for new Azure AD / Microsoft Entra users**, including:

* Creating a new Azure AD user
* Assigning licenses and groups
* Generating a secure password via **Bitwarden CLI**
* Automatically sending a **Bitwarden Send** link (3-day expiry, 4 max views) for password delivery

Perfect for MSPs or IT admins who regularly onboard new staff and want a secure, repeatable workflow. In due course I intend to modify this to use MS Graph, but this is standard PowerShell for now.

---

## Features

* Automatic Azure AD user creation
* Select verified domain interactively
* Auto-fetch available licenses and groups
* Optional license assignment
* Group membership assignment
* Auto-generate secure password (Bitwarden passphrase style)
* Send password via expiring Bitwarden Send link
* Clean terminal summary + ready-to-send email template to send to whoever you need

---

## Prerequisites

Before running this script, make sure the following manual setup steps are complete.

### 1. Bitwarden Setup

You must have a Bitwarden account and API credentials.

#### Required Environment Variables:

```powershell
[System.Environment]::SetEnvironmentVariable("BW_CLIENTID","<your-client-id>","User")
[System.Environment]::SetEnvironmentVariable("BW_CLIENTSECRET","<your-client-secret>","User")
```

You can find these in your Bitwarden web vault under
**Settings → Developer Tools → API Key**.

#### Verify Bitwarden CLI is installed:

```powershell
bw --version
```

If not installed, the script will attempt to install it using `winget`.

---

### 2. Azure AD / Microsoft Entra Permissions

You must be signed in with an account that has permissions to:

* Create users
* Assign licenses
* Add users to groups

The script will automatically prompt for authentication via:

```powershell
Connect-AzureAD
```

---

## Dependencies

The script checks for and installs required modules if missing:

| Dependency             | Description                                                 | Install Command                                    |
| ---------------------- | ----------------------------------------------------------- | -------------------------------------------------- |
| `AzureAD`              | PowerShell module for Microsoft Entra (Azure AD) management | `Install-Module AzureAD -Force -Scope CurrentUser` |
| `Bitwarden CLI` (`bw`) | Used for password generation and secure Send links          | `winget install Bitwarden.CLI`                     |

---

## Usage

1. **Open PowerShell as Administrator**

2. **Run the script**:

   ```powershell
   .\Create-AADUser.ps1
   ```

3. **Follow prompts interactively:**

   * Enter First & Last Name
   * Choose verified domain
   * Optionally select a license
   * Optionally assign to groups
   * Confirm Bitwarden unlock (first use only)

4. After completion, the script will output:

   * User Principal Name (UPN)
   * Generated password
   * Bitwarden Send link (auto-copied)
   * License assigned
   * Group(s) added
   * Email template ready to send

---

## Example Output

```plaintext
User onboarded successfully!
UPN: john.doe@contoso.com
Password: Brave-Dolphin-82
Bitwarden Send link: https://send.bitwarden.com/#/example-link
License: ENTERPRISEPACK (Office 365 E3)
Group: Staff Accounts

--- Email to Send ---

Hi [Insert recipient name],

I can confirm the account for John has been created.

- Email: john.doe@contoso.com
- Password: available at the secure link below:

https://send.bitwarden.com/#/example-link

Please note that this link will expire in 3 days and can only be opened up to 4 times.  
John will also be required to change the password when they log in next.

Thanks,  
[Your name]
```

---

## Notes

* Whilst the password here is shown, this is mainly for easy viewing when making a user on-call. You can remove the line of code that prints it no problem if you'd prefer.
* You may need to restart PowerShell after the first module/CLI installation.
* Supports multiple domains and dynamic license availability filtering.

---

## License Mapping Reference

| SKU                   | Friendly Name                   |
| --------------------- | ------------------------------- |
| FLOW_FREE             | Power Automate Free             |
| DEVELOPERPACK_E5      | Microsoft 365 Developer E5      |
| ENTERPRISEPREMIUM     | Office 365 E5                   |
| ENTERPRISEPACK        | Office 365 E3                   |
| STANDARDPACK          | Office 365 E1                   |
| O365_BUSINESS_PREMIUM | Microsoft 365 Business Standard |
| M365_BUSINESS_PREMIUM | Microsoft 365 Business Premium  |
| EXCHANGESTANDARD      | Exchange Online Plan 1          |
| EXCHANGEENTERPRISE    | Exchange Online Plan 2          |
| POWER_BI_PRO          | Power BI Pro                    |

---

## Author

**Kabir Ghai**
📧 My website and contact info: [kabirghai.com](https://kabirghai.com)
