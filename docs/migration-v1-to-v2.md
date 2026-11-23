# Migrating TenantBrief Reports from v1.x to v2.0.0

TenantBrief **v2.0.0** introduces JSON Schema v2 (`SchemaVersion: "2.0.0"`) and removes the deprecated `Finding.Impact` alias that was retained in `v1.2.0` for backward compatibility.

## Summary of Breaking Changes

| Area | v1.x | v2.0.0 | Action Required |
| --- | --- | --- | --- |
| Root `SchemaVersion` | Omitted | Required (`"2.0.0"`) | Update JSON schema validators or consumers that enforce strict root keys. |
| `Finding.Impact` | Deprecated string alias of `UserImpact` | **Removed** | Replace all references to `Finding.Impact` with `Finding.UserImpact` (end-user disruption) or `Finding.Risk` (security risk severity). |

## Non-Breaking Guarantees

- **Exported PowerShell Cmdlets:** All 12 exported functions and their parameters remain unchanged.
- **Cross-Version Drift Comparison (`Compare-TenantBriefReports`):** You can continue passing a historical `v1.x` `TenantBriefReport-*.json` as `-BaselineJsonPath` (or `-PreviousReportJson`) alongside a `v2.0.0` report as `-CurrentJsonPath`. Matching uses `Id` / `CanonicalId`, `Status`, and `Risk`, none of which changed.
- **Quality Audit Tool (`tools/Measure-TenantBriefQuality.ps1`):** Reads `UserImpact` first and falls back to `Impact` when auditing archived `v1.x` JSON files.

## Consumer Migration Examples

### PowerShell
```powershell
# Before (v1.x)
$report.Findings | Where-Object { $_.Impact -in @('High', 'Yüksek') }

# After (v2.0.0)
$report.Findings | Where-Object { $_.UserImpact -in @('High', 'Yüksek') }
```

### jq
```bash
# Before (v1.x)
jq '.Findings[] | {id: .Id, risk: .Risk, impact: .Impact}' TenantBriefReport-EN.json

# After (v2.0.0)
jq '.Findings[] | {id: .Id, risk: .Risk, userImpact: .UserImpact}' TenantBriefReport-EN.json
```

### Schema Validation
```powershell
Get-Content ./TenantBriefReport-TR.json -Raw -Encoding UTF8 |
    Test-Json -SchemaFile ./schemas/tenantbrief-report.schema.json
```
