# Upstream Issue Draft — `cisagov/ScubaGear` (DO NOT AUTO-SUBMIT)

**Target Repository:** `https://github.com/cisagov/ScubaGear/issues/new`
**Proposed Title:** `[Bug] v2.0.0: Two bugs break non-AAD interactive auth on Turkish (tr-TR) Windows & PowerShell 7 (Utility.psm1:406 ToUpper + ConnectHelpers.psm1:264 WithUseEmbeddedWebView)`
**Labels:** `bug`

---

## Summary

Two independent bugs in `ScubaGear v2.0.0` prevent non-AAD products (`exo`, `securitysuite`, `sharepoint`, `teams`, `powerplatform`, `powerbi`) from authenticating interactively on non-English (specifically `tr-TR`) Windows systems and on PowerShell 7 (.NET Core):

1. **Bug #1 — Turkish-İ locale bug in `ConvertFrom-GraphHashtable` (`Modules/Utility/Utility.psm1:406`):**
   Uses culture-sensitive `.ToUpper()` instead of `.ToUpperInvariant()`. On `tr-TR` systems, `"isInitial"` becomes `"İsInitial"` (U+0130), causing `Connection.psm1:136` (`Where-Object { $_.isInitial }`) to return `$null` and line 138/237/270/389/457 (`$TenantName.split(".")[0]`) to throw `You cannot call a method on a null-valued expression`.
2. **Bug #2 — `WithUseEmbeddedWebView($true)` contradicts its own comment and fails on PowerShell 7 (`Modules/Connection/ConnectHelpers.psm1:260-265`):**
   The comment explicitly states *"this must use the system (default OS) browser instead"*, yet line 264 passes `WithUseEmbeddedWebView($true)` without `.WithWindowsEmbeddedBrowserSupport()`, which fails on PowerShell 7 (.NET Core) with `To enable the embedded webview on Windows, reference Microsoft.Identity.Client.Desktop and call the extension method .WithWindowsEmbeddedBrowserSupport().`

---

## Environment

- **ScubaGear Version:** `2.0.0` (PSGallery)
- **OPA Version:** `1.20.2`
- **OS:** Windows 10 Enterprise (Build 19045, 64-bit), `CurrentCulture = tr-TR`
- **Shells Tested:** PowerShell `7.7.0` (Core) and Windows PowerShell `5.1`
- **Graph Module Tested:** Both `Microsoft.Graph.Authentication 2.40.0` and isolated `2.25.0` (verified both hit Bug #1 identically under `tr-TR`)

---

## Verified Root Causes & Minimal Fixes

### Bug #1: `Modules/Utility/Utility.psm1` line 406

```powershell
# Current (breaks on tr-TR: "isInitial" -> "İsInitial", "id" -> "İd", "isDefault" -> "İsDefault"):
$UpperCamelCase = ($property.key).Substring(0,1).ToUpper() + ($property.key).Substring(1)

# Proposed fix:
$UpperCamelCase = ($property.key).Substring(0,1).ToUpperInvariant() + ($property.key).Substring(1)
```

### Bug #2: `Modules/Connection/ConnectHelpers.psm1` lines 260–265

```powershell
# Embedded web view does not support WebAuthn/FIDO2/passkey ceremonies (no real browser
# context), so this must use the system (default OS) browser instead.
$TokenResult = $MsalApp.AcquireTokenInteractive([string[]]@($Scope)).
    WithPrompt([Microsoft.Identity.Client.Prompt]::SelectAccount).
    WithUseEmbeddedWebView($true).   # <-- Should be $false to match comment & work on PowerShell 7
    ExecuteAsync().GetAwaiter().GetResult()
```

---

## Verification Evidence

- Setting `[System.Threading.Thread]::CurrentThread.CurrentCulture = [System.Globalization.CultureInfo]::InvariantCulture` immediately resolved Bug #1 (`Connection.psm1:138/270/457` passed on both PS 7 and PS 5.1).
- Running in Windows PowerShell 5.1 (`powershell.exe -NoProfile`) with `InvariantCulture` bypassed both bugs and completed `exo`, `sharepoint`, and `teams` end-to-end (OPA Rego + `ScubaResults.json` generated cleanly, even with `Microsoft.Graph.Authentication 2.40.0` installed).
