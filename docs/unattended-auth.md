# Unattended (Zero-Popup) Certificate Authentication Guide

This guide documents **verified certificate-based (app-only)** authentication parameters for every assessment engine orchestrated by **TenantBrief**, together with the **least-privilege read-only permissions** required.

> **When to use Unattended vs. Interactive:**
> - **One-off or client engagements:** Prefer interactive `Connect-TenantBrief` (`Quick` default) or `Connect-TenantBrief -Profile Full` + `-ScubaInteractiveLogin` — leaves zero app registrations or certificates in the tenant.
> - **Scheduled / recurring self-audits (`Compare-TenantBriefReports`):** Configure a dedicated certificate-backed Entra ID App Registration once for zero-popup execution.

---

## 1. Verified Engine Certificate Support Matrix

Parameters below were verified directly against the installed module manifests (`ZeroTrustAssessment v3.1.0`, `ScubaGear v2.0.0`, `ExchangeOnlineManagement v3.10.1`, `Maester`).

| Engine / Module | Certificate Auth Supported? | Verified Parameters | Notes & Constraints |
| --- | --- | --- | --- |
| **Microsoft Graph (`Connect-MgGraph`)** | Yes | `-ClientId`, `-TenantId`, `-CertificateThumbprint` (or `-Certificate`) | Powers License ROI, Copilot Readiness, Usage/Adoption, and Maester Graph checks. |
| **ZeroTrustAssessment (`Connect-ZtAssessment`)** | Yes | `-TenantId`, `-ClientId`, `-Certificate` (`[X509Certificate2]`) | Pass `-Service Graph,ExchangeOnline,SecurityCompliance` (or add `Azure` / `SharePointOnline`). |
| **CISA ScubaGear 2.0 (`Invoke-SCuBA`)** | Yes (partial on PowerPlatform/PowerBI) | `-LogIn:$true`, `-AppID`, `-CertificateThumbprint`, `-Organization 'contoso.onmicrosoft.com'` | Supports `aad`, `exo`, `securitysuite`, `sharepoint`, `teams`. `powerplatform` requires `New-PowerAppManagementApp`; `powerbi` requires tenant Service Principal API setting. |
| **Microsoft ORCA (`ExchangeOnlineManagement`)** | Yes | `Connect-ExchangeOnline -AppId '<AppId>' -CertificateThumbprint '<Thumb>' -Organization 'contoso.onmicrosoft.com'` | ORCA reuses the active Exchange Online app-only session. |
| **Maester (`Connect-Maester` / `Invoke-Maester`)** | Yes | Reuses active `Connect-MgGraph` session; `Connect-Maester` also exposes `-TenantId`, `-GraphClientId`, `-SharePointClientId`, `-SharePointCertificateThumbprint` | Runs EIDSCA, CIS M365, and XSPM checks against the active app-only Graph/EXO/SPO sessions. |
| **Microsoft Teams (`Connect-MicrosoftTeams`)** | Yes | `-ApplicationId`, `-TenantId`, `-CertificateThumbprint` | Requires `Global Reader` or `Teams Reader` directory role assigned to the Service Principal. |

---

## 2. Least-Privilege Read-Only Permissions

Assign **only read-only permissions** to the Entra ID App Registration (never grant `.ReadWrite.*` or `Directory.ReadWrite.All`):

### Microsoft Graph (Application Permissions — Admin Consent Required)
- `AuditLog.Read.All`
- `DeviceManagementConfiguration.Read.All`
- `DeviceManagementManagedDevices.Read.All`
- `Directory.Read.All`
- `IdentityRiskyUser.Read.All`
- `Organization.Read.All`
- `Policy.Read.All`
- `Policy.Read.ConditionalAccess`
- `Reports.Read.All`
- `RoleManagement.Read.All`
- `SecurityEvents.Read.All`
- `SharePointTenantSettings.Read.All`
- `UserAuthenticationMethod.Read.All`

### Office 365 Exchange Online (Application Permission + RBAC Role)
- API Permission: `Exchange.ManageAsApp` (`Office 365 Exchange Online` resource)
- Entra ID Directory Role assigned to the Service Principal: **`Global Reader`** (or **`View-Only Organization Management`** in Exchange Online RBAC)

### SharePoint Online (Optional — only if `sharepoint` scope is enabled)
- SharePoint API Permission: `Sites.Read.All` (Application)

### Power Platform (Optional — only if `powerplatform` scope is enabled in ScubaGear)
- Register the app once via `New-PowerAppManagementApp -ApplicationId '<AppId>'` (requires Power Platform Administrator).

---

## 3. End-to-End Unattended Execution Pattern

```powershell
# Code Class: Read-only audit (Unattended) | Replace placeholders with your tenant/app values
$tenantId     = '<Tenant-GUID>'
$orgDomain    = 'contoso.onmicrosoft.com'
$appId        = '<App-Client-GUID>'
$thumbprint   = '<Cert-Thumbprint>'
$cert         = Get-Item "Cert:\CurrentUser\My\$thumbprint"
$outDir       = "$HOME\TenantBriefReport\unattended"

Import-Module .\TenantBrief.psd1 -Force

# 1. Connect Graph + ZeroTrustAssessment + Exchange Online using certificate (0 popups)
Connect-MgGraph -ClientId $appId -TenantId $tenantId -CertificateThumbprint $thumbprint -NoWelcome
Connect-ExchangeOnline -AppId $appId -CertificateThumbprint $thumbprint -Organization $orgDomain -ShowBanner:$false
Connect-ZtAssessment -TenantId $tenantId -ClientId $appId -Certificate $cert -Service Graph, ExchangeOnline

# 2. Run ScubaGear 2.0 non-interactively (under InvariantCulture) and feed JSON to TenantBrief
$scubaOut = Join-Path $outDir 'raw-scuba'
New-Item -ItemType Directory -Path $scubaOut -Force | Out-Null
[System.Threading.Thread]::CurrentThread.CurrentCulture = [System.Globalization.CultureInfo]::InvariantCulture
Invoke-SCuBA -ProductNames @('aad','securitysuite','exo','sharepoint','teams') `
    -LogIn:$true -AppID $appId -CertificateThumbprint $thumbprint -Organization $orgDomain `
    -OutPath $scubaOut -Quiet

# 3. Generate TenantBrief HTML, JSON & Executive PDF Brief with zero interactive prompts
Invoke-TenantBriefAssessment `
    -OutputPath $outDir `
    -InputScubaJsonPath $scubaOut `
    -Language en `
    -Framework All `
    -NoBrowser
```

## 4. Operational Hygiene & Rollback
- **Certificate rotation:** Use short-lived certificates (<= 12 months) stored in Windows Certificate Store (`CurrentUser\My`) or Azure Key Vault; never commit `.pfx` files to Git.
- **Revocation / cleanup:** Removing the Enterprise Application or revoking its certificate immediately revokes all read-only access with zero impact on production workloads.
