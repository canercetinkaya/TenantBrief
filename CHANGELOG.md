# Changelog

All notable changes to **TenantBrief** are documented in this file.

## [Unreleased]

### Breaking Changes
- **Removed legacy `*-ZtLens*` aliases (`9a37886`):** `Connect-ZtLens`, `Invoke-ZtLensAssessment`, `Get-ZtLensFrameworks`, `Get-ZtLensLicenseRoi`, `Get-ZtLensLicenseWaste`, `Get-ZtLensCopilotReadiness`, `Compare-ZtLensReports`, and `Export-ZtLensExecutiveSummary` were removed in v1.0.x. Use the canonical `*-TenantBrief*` cmdlet names instead.

### Added
- `Get-TenantBriefUsageAdoption` executive Usage & Adoption tab (`f76644a`) and automatic `MicrosoftTeams` / `SharePointOnline` connection handling with WAM Device Code fallback (`d41e7ff`).
- Microsoft FastTrack integrations (`e4066f3`): `Import-TenantBriefSharePointRisk`, `Import-TenantBriefPowerPlatformAgents`, extended `Get-M365CopilotReadiness` signals, and `Agents Cost Calculator` v2 model.
- Minimum product/license normalization and categorized `Skipped` controls breakdown (`8942ccb`).
