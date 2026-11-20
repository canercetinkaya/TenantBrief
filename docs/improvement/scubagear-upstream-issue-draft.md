# Upstream Issue Draft — `cisagov/ScubaGear` (DO NOT AUTO-SUBMIT)

**Target Repository:** `https://github.com/cisagov/ScubaGear/issues/new`
**Proposed Title:** `[Bug] v2.0.0 Connect-Tenant fails on non-AAD products with "null-valued expression" ($TenantName.split) when Microsoft.Graph.Authentication 2.40.0 is loaded`
**Labels:** `bug`

---

## Description

When running `ScubaGear v2.0.0` in a clean PowerShell 7.7.0 or Windows PowerShell 5.1 session on a machine that also has `Microsoft.Graph.Authentication v2.40.0` installed (e.g., required by Microsoft `ZeroTrustAssessment v3.1.0`), authentication succeeds for `aad` but fails for all 6 non-AAD products (`exo`, `securitysuite`, `sharepoint`, `teams`, `powerplatform`, `powerbi`) with:

```text
ERROR: Authentication failed for product: exo
WARNING: Error establishing a connection with exo: You cannot call a method on a null-valued expression.
at Connect-Tenant, ...\ScubaGear\2.0.0\Modules\Connection\Connection.psm1: line 138
```

The same null-valued expression error repeats at `Connection.psm1:237` (`powerplatform`), `:270` (`sharepoint`), `:389` (`powerbi`), `:457` (`teams`), and `:138` (`securitysuite`).

## Environment

- **ScubaGear Version:** `2.0.0`
- **OPA Version:** `1.20.2`
- **Microsoft.Graph.Authentication Loaded:** `2.40.0` (ScubaGear warns: `CRITICAL: Microsoft.Graph.Authentication - will load 2.40.0 [ABOVE MAX: 2.25.0]`)
- **OS:** Windows 10 Enterprise (Build 19045, 64-bit)
- **Tested Shells:** Both clean `pwsh -NoProfile` (`7.7.0`) and clean `powershell.exe -NoProfile` (`5.1`)
- **Graph Scopes Verified Present:** `Organization.Read.All`, `Directory.Read.All` (and `GET https://graph.microsoft.com/beta/organization` returns `verifiedDomains` with `isInitial = true`)

## Reproduction Steps

```powershell
pwsh -NoProfile -Command "Import-Module ScubaGear; Invoke-SCuBA -ProductNames exo,sharepoint,teams -LogIn:`$true -OutPath `$env:TEMP\scuba-repro"
```

## Root Cause Analysis (`Modules/Connection/Connection.psm1` L135–138)

```powershell
$OrgDetails = (Invoke-GraphDirectly -Commandlet Get-MgBetaOrganization -M365Environment $M365Environment).Value
$InitialDomain = $OrgDetails.VerifiedDomains | Where-Object { $_.isInitial }
$TenantName = $InitialDomain.Name
$InitialDomainPrefix = $TenantName.split(".")[0]
```

With `Microsoft.Graph.Authentication 2.40.0`, `$InitialDomain.Name` evaluates to `$null` (either due to hashtable/PSObject key normalization in `ConvertFrom-GraphHashtable` or `$OrgDetails` array/property shape), causing `$TenantName.split(".")[0]` to throw `You cannot call a method on a null-valued expression` across all 6 non-AAD providers.

## Expected Behavior

1. `Connect-Tenant` should safely resolve the initial `.onmicrosoft.com` domain (e.g., handling both `Hashtable` and `PSCustomObject` keys case-insensitively and guarding against `$null` `$TenantName` with an actionable error message), and/or
2. Support `Microsoft.Graph.Authentication >= 2.40.0` in `RequiredVersions.ps1` so ScubaGear 2.0.0 can coexist side-by-side with `Microsoft ZeroTrustAssessment v3.1.0` on the same workstation.
