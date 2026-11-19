# Changelog

All notable changes to **TenantBrief** are documented in this file.

## [Unreleased]

### Added
- **Sprint 0 Quality & Governance Tooling (`#1`):**
  - `tools/Measure-TenantBriefQuality.ps1` and `tests/Measure-TenantBriefQuality.Tests.ps1` for deterministic Q01–Q15 report quality metrics (including `Q04a`/`Q04b`, `Q08a`/`Q08b`, `Q10a`/`Q10b`).
  - `schemas/tenantbrief-report.schema.json` JSON Schema for `TenantBriefReport-*.json`.
  - `PSScriptAnalyzerSettings.psd1` pinned with `PSScriptAnalyzer 1.25.0` in `.github/workflows/ci.yml`.
  - `docs/improvement/CLAIMS.md` claim-verification audit table.
- **Sprint 1 Data Model & Real Cross-Engine Correlation (`S1.1–S1.7`):**
  - `data/control-crosswalk.json`: 42 upstream-verified canonical controls mapping ZeroTrustAssessment, CISA ScubaGear 2.0 (including `scuba-baseline-policy-migrations.csv`), Maester (`MT.*`, `CIS.M365.*`, `EIDSCA.*`), and Microsoft ORCA.
  - Crosswalk-only correlation in `New-TenantBriefCorrelatedTests` with `CanonicalId`, `SourceStatuses`, `StatusConflict`, pre-correlation framework scorecards, and separate `Summary.UniqueControls` / `Summary.SourceControls`.
  - Status ranking `Failed (4) > Error (3) > Investigate (2) > Skipped/Planned (1) > Passed (0)` and separation of upstream `Planned` controls into `PlannedFindings` (`Q11 = 0`).
  - Canonical 6-pillar normalization (`Pillar`/`PrimaryPillar`/`DomainPillar`, `EngineLabel`, ScubaGear 2.0 `MS.SECURITYSUITE.*` support) and source/ID-based portal & least-privilege role routing.
  - ORCA `ChiValue` (`ORCACHI` enum) risk mapping (`Critical`/`High`/`Medium`/`Low`), `Critical` risk filter/badge in `assets/report-template.html` and schema, and optional offline `-InputScubaJsonPath` / `-InputOrcaJsonPath` parameters.
  - New `UserImpact` field separating end-user disruption impact from security `Risk`.
- **Sprint 2 Coverage, Preflight & Operational Safety (`S2.1–S2.7`):**
  - ScubaGear 2.0 multi-product execution (`aad, securitysuite, exo, powerplatform, sharepoint, teams, powerbi`) with `ScubaProducts` (`Requested`/`Executed`/`Skipped`) recorded in `run-manifest.json`.
  - New exported read-only preflight cmdlet `Test-TenantBriefPrerequisites` and `"Scope & Blind Spots"` report card.
  - `-AutoFixDependencies` safety gate on `Connect-TenantBrief` and `Invoke-TenantBriefBaselineCollections` (zero unrequested `Install-Module` / `Remove-Item` calls by default).
  - Clarified optional EntraFalcon JSON ingestion in `TenantBrief.psd1` and `docs/improvement/CLAIMS.md` (`Q15 = 0`).
  - Upstream `Planned` collapsible list (`plannedUpstreamCard`), `Error` permission action card (`errorActionCard` + `ErrorRemedy`), and structured `Diagnostics` (`Severity` + `Remedy`).
  - Deterministic `PriorityScore` (0–100) weighted prioritization configured via `data/scoring.json`.
- **Sprint 3 Turkish Localization Quality (`S3.1–S3.6`):**
  - Externalized UI/portal/role dictionaries in `data/i18n/{tr,en}.json` (zero Turkish portal strings in EN reports).
  - Single-source-of-truth Turkish glossary (`data/i18n/glossary-tr.json`), CI denylist (`tests/i18n-denylist.txt`), and `ConvertTo-TenantBriefTurkish` wired as post-processor (`Q09 = 0`).
  - Migrated `data/tr-translation-cache.json` to `Source|TestId` schema (`tools/Migrate-TranslationCache.ps1`, 0 loss) and added 259 machine translations (`Reviewed = false`) with `Summary.UnreviewedTranslations` counter (`Q08a < 5`, `Q08b < 5`).
  - Sentence-boundary remediation extraction without mid-word ellipsis (`...`) or `Learn`/`öğrenin` artifacts, plus language-aware `Remediation` field (`RemediationTr` retained for backward compatibility, `Q10 = 0`).
- **Sprint 4 Scoring, Dynamic Roadmap & Executive Narrative (`S4.1–S4.4`):**
  - Copilot Readiness L1 maturity gate on `COP-LIC-01` fail and `0.5` Warning weight configured in `data/scoring.json` (`Q13 = 0`).
  - Dynamic 30-60-90 Roadmap phases with `PriorityScore`-ordered `FindingIds[]` and category-driven `Focus` text.
  - Enhanced `Export-TenantBriefExecutiveSummary`: Test/Lab tenant banner (`UserCount < 25`), `N/A`/`Uygulanamaz` ROI when no SKUs are present, Secure Score, active high-severity SecOps incidents, and Copilot maturity cards.
  - Documented pre-correlation per-source framework scoring rule in `README.md`.
- **Sprint 5 Application Security, Privacy & Release Hygiene (`S5.1–S5.5`):**
  - Strict offline `Content-Security-Policy` meta tags added to `assets/report-template.html` and `Export-TenantBriefExecutiveSummary`.
  - Deep `-Anonymize` masking via `Protect-TenantBriefSensitiveText` across finding fields (`Title`, `Result`, `Description`, `SkippedReason`, `Remediation`, `RemediationTr`, `ErrorRemedy`), `PlannedFindings`, and `MfaCoverageDesc` (stripping UPNs/emails, GUIDs, and tenant domains).
  - `-TranslatorKey` now accepts `[SecureString]` (with `[string]` backward compatibility), never logs or persists keys, and strips UPNs/GUIDs/tenant domains via `Protect-TenantBriefSensitiveText` before calling Azure AI Translator.
  - Added `SECURITY.md` and documented Translator data flow and privacy guarantees in `README.md`.
- **Sprint 6 Architecture, Modularization & Blocking CI (`S6.1–S6.4`):**
  - Added 4-engine TR/EN golden-file regression snapshots (`tests/fixtures/raw/*`, `tests/golden/*.normalized.json`, `tests/Sprint6.GoldenFile.Tests.ps1`) before refactoring.
  - Split monolithic `TenantBrief.psm1` (4,278 lines) into 35 clean files under `Public/` (12 cmdlets) and `Private/{Import,Correlation,Scoring,Render}/` (23 helpers) with deterministic `LicenseROI.Gaps` tie-break sorting and identical 12-cmdlet export surface.
  - Upgraded `.github/workflows/ci.yml` to a Windows + Ubuntu matrix with Pester JaCoCo code coverage artifact, blocking PSScriptAnalyzer v1.25.0 gate, blocking JSON Schema (`Test-Json`) check, and blocking Q01–Q15 quality gate.
  - Replaced hot `+=` array loops with `List[object]`, compiled Turkish glossary regex (`ConvertTo-TenantBriefTurkish`), and batched module lookup in `Test-TenantBriefPrerequisites`.

### Deprecated
- **`Finding.Impact`:** Retained for one release for backward compatibility; use `Finding.UserImpact` instead.

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
