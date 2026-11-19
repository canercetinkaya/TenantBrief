# Changelog

All notable changes to **TenantBrief** are documented in this file.

## [Unreleased]

### Added
- **Sprint 0 Quality & Governance Tooling (`#1`):**
  - `tools/Measure-TenantBriefQuality.ps1` and `tests/Measure-TenantBriefQuality.Tests.ps1` for deterministic Q01–Q15 report quality metrics (including `Q04a`/`Q04b`, `Q08a`/`Q08b`, `Q10a`/`Q10b`).
  - `schemas/tenantbrief-report.schema.json` JSON Schema for `TenantBriefReport-*.json`.
  - `PSScriptAnalyzerSettings.psd1` pinned with `PSScriptAnalyzer 1.25.0` in `.github/workflows/ci.yml`.
  - `docs/improvement/CLAIMS.md` claim-verification audit table.

## [1.0.1] - 2026-11-19

### Security
- **XSS & HTML Encoding Hotfix (`S1.0`):**
  - Switched embedded `{{REPORT_JSON}}` serialization in `Invoke-TenantBriefAssessment` to `ConvertTo-Json -Depth 12 -Compress -EscapeHandling EscapeHtml` and escaped `U+2028` / `U+2029` line/paragraph separators (preventing `</script>` breakout and JSON truncation past Depth 6).
  - Applied `[System.Net.WebUtility]::HtmlEncode()` to `{{TITLE}}`, `{{SUBTITLE}}`, and all dynamic fields in `Export-TenantBriefExecutiveSummary`.
  - Hardened `assets/report-template.html`: added single-quote escaping (`&#39;`) to `esc()` and replaced inline `onclick` string interpolations with `data-*` attributes (`this.dataset.*`).
  - Added Pester regression tests (`tests/Hotfix.XssHtmlEncode.Tests.ps1`) and headless Chromium Playwright E2E XSS verification (`tests/e2e/xss-check.mjs`).

## [1.0.0]

### Breaking Changes
- **Removed legacy `*-ZtLens*` aliases (`9a37886`):** `Connect-ZtLens`, `Invoke-ZtLensAssessment`, `Get-ZtLensFrameworks`, `Get-ZtLensLicenseRoi`, `Get-ZtLensLicenseWaste`, `Get-ZtLensCopilotReadiness`, `Compare-ZtLensReports`, and `Export-ZtLensExecutiveSummary` were removed in v1.0.0. Use the canonical `*-TenantBrief*` cmdlet names instead.

### Added
- `Get-TenantBriefUsageAdoption` executive Usage & Adoption tab (`f76644a`) and automatic `MicrosoftTeams` / `SharePointOnline` connection handling with WAM Device Code fallback (`d41e7ff`).
- Microsoft FastTrack integrations (`e4066f3`): `Import-TenantBriefSharePointRisk`, `Import-TenantBriefPowerPlatformAgents`, extended upstream Microsoft FastTrack `Get-M365CopilotReadiness` JSON ingestion in `Get-TenantBriefCopilotReadiness`, and `Agents Cost Calculator` v2 model.
- Minimum product/license normalization and categorized `Skipped` controls breakdown (`8942ccb`).
