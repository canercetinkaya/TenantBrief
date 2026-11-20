# Changelog

All notable changes to **TenantBrief** are documented in this file.

## [Unreleased]

## [2.0.2] - 2026-11-20

### Fixed
- **ScubaGear v2.0.0 Turkish-`İ` (`tr-TR`) & PowerShell 7 MSAL Bypass (`Private/Import/Invoke-TenantBriefBaselineCollections.ps1`):**
  - Wrapped in-process `Invoke-SCuBA` calls in `InvariantCulture` (`try/finally` restoring `CurrentCulture`), bypassing `ScubaGear v2.0.0` `Modules/Utility/Utility.psm1:406` (`"isInitial".Substring(0,1).ToUpper()` producing `"İsInitial"` on `tr-TR` systems).
  - When `-ScubaInteractiveLogin` is specified on Windows (`powershell.exe` available), automatically executes `Invoke-SCuBA -LogIn:$true` in an isolated Windows PowerShell 5.1 (`powershell.exe -NoProfile`) subprocess under `InvariantCulture` with dynamic `PSModulePath` forwarding (zero changes to user modules), bypassing `ScubaGear v2.0.0` `Modules/Connection/ConnectHelpers.psm1:264` (`WithUseEmbeddedWebView($true)` failing on PowerShell 7 / .NET Core).
  - Updated `docs/improvement/scubagear-upstream-issue-draft.md` with both verified root causes and added regression tests in `tests/V202.ScubaCultureAndSubprocess.Tests.ps1`.

### Added
- **Monthly Upstream Maintenance Check (`S8.1`):**
  - `data/upstream-versions.json`: Pinned verified versions (`ZeroTrustAssessment 3.1.0`, `ScubaGear 2.0.0`, `ORCA 2.8.1`, `Maester 2.3.0`, `EntraFalcon V20261108 [ASSUMPTION]`).
  - `tools/Invoke-TenantBriefUpstreamCheck.ps1`: Read-only monthly upstream version & sandboxed (`Save-Module` + detached `git worktree` in `%TEMP%`) compatibility check enforcing all 7 monthly/daily attempt lock rules, deduplicated `upstream` GitHub issue creation, and built-in Windows notifications (zero `Install-Module` / `Remove-Item`).
  - `tools/Register-TenantBriefUpstreamCheck.ps1`: User-level (`RunLevel Limited`, 10-min logon delay, network-only, battery-allowed, 1h limit) Windows Scheduled Task installer/uninstaller (`-Unregister`).
  - `tests/S8.1.UpstreamCheck.Tests.ps1`: 9 offline mocked Pester tests covering all 7 lock rules (`-Now` injected), issue deduplication, and AST safety.

## [2.0.1] - 2026-11-20

### Fixed
- **ScubaGear 2.0 Partial Coverage Diagnostics & `-ScubaInteractiveLogin`:** Added optional `-ScubaInteractiveLogin` switch to `Invoke-TenantBriefAssessment` (`Invoke-SCuBA -LogIn:$true` for all 7 products; default remains `-LogIn:$false` without extra prompts). When `ScubaProducts.Skipped.Count > 0`, TenantBrief now emits a `Warning` + `Remedy` in `Diagnostics` and displays an `"X/7 ürün tarandı"` / `"X/7 products scanned"` badge on the `CISA_SCuBA` framework card and in `Export-TenantBriefExecutiveSummary`. Documented ScubaGear 2.0 non-interactive certificate authentication (`-AppID`, `-CertificateThumbprint`, `-Organization`) in `README.md`.
- **Q12 ScubaGear Product Metric (`tools/Measure-TenantBriefQuality.ps1`):** Fixed false inflation (`Q12 = 8` on the 1035 dataset) where correlated ZeroTrust+ScubaGear findings had their ZeroTrust `Category` names counted as ScubaGear products. `Q12` now extracts only canonical ScubaGear 2.0 product codes (`AAD`, `SECURITYSUITE`, `EXO`, `POWERPLATFORM`, `SHAREPOINT`, `TEAMS`, `POWERBI` — max 7) from `SCUBA-MS.<PRODUCT>.*` IDs / `CorrelatedIds` and normalizes legacy `DEFENDER` to `SECURITYSUITE`. Added regression test in `tests/Measure-TenantBriefQuality.Tests.ps1`.
- **PSScriptAnalyzer Regression Cleanup (`92 -> 83`, below `84` baseline):** Restored UTF-8 BOM on 6 split Unicode `.ps1` files (`PSUseBOMForUnicodeEncodedFile`, -6) and removed 3 unused variables in `Public/Invoke-TenantBriefAssessment.ps1` (`medRiskFailed`, `lowRiskFailed`, `baseScore`, -3). Tightened blocking CI ceiling in `.github/workflows/ci.yml` from `95` to `84`.
- **Translation Cache Count Clarification:** Clarified exact provenance of all 619 entries in `data/tr-translation-cache.json`: **360** migrated from pre-Sprint-3 legacy cache (`Source = "machine"`, `Reviewed = false`) + **259** newly added machine translations in Sprint 3 (`Source = "machine"`, `Reviewed = false`), **0** live Azure Translator API entries, **0** human-reviewed (`Reviewed = true`).

### Known Limitations
- **`ScubaGear v2.0.0` + `Microsoft.Graph.Authentication 2.40.0` Upstream Incompatibility:** Verified in both clean `pwsh 7.7.0` and `powershell.exe 5.1` sessions: when `Microsoft.Graph.Authentication 2.40.0` (used by `ZeroTrustAssessment v3.1.0`) is present, `ScubaGear v2.0.0` (`ABOVE MAX: 2.25.0`) fails `Connect-Tenant` (`Connection.psm1:138/270/457`: `You cannot call a method on a null-valued expression` on `$TenantName.split(".")[0]`) for `exo`, `securitysuite`, `sharepoint`, `teams`, `powerplatform`, and `powerbi`; only `aad` succeeds (`Q12 = 1`). An upstream issue draft is prepared in `docs/improvement/scubagear-upstream-issue-draft.md`.

## [2.0.0] - 2026-11-20

### BREAKING CHANGES
- **Removed `Finding.Impact` (`V2.1`):** The deprecated `Finding.Impact` alias has been removed from `TenantBriefReport-*.json`, `assets/report-template.html`, and `schemas/tenantbrief-report.schema.json`. Use `Finding.UserImpact` (end-user/business disruption impact) and `Finding.Risk` (security risk severity).
- **JSON Schema v2 (`V2.2`):** Added mandatory root `SchemaVersion` (`"2.0.0"`) to `TenantBriefReport-*.json` and `schemas/tenantbrief-report.schema.json`.

### Added
- **Migration Guide (`V2.3`):** Added `docs/migration-v1-to-v2.md` with PowerShell/`jq` upgrade examples and cross-version comparison notes.
- **Cross-Version & v2 Regression Tests (`V2.4`):** Added `tests/V2.BreakingSchemaMigration.Tests.ps1` verifying `SchemaVersion = "2.0.0"`, absence of `Finding.Impact`, and v1.x→v2.0.0 `Compare-TenantBriefReports` compatibility; updated `tests/golden/*.normalized.json` snapshots to Schema v2.

## [1.2.0] - 2026-11-19

### Security
- **`-Anonymize` `TenantName` Leak Fix:** Previous releases did not redact `TenantName` values appearing inside finding `Result`, `Description`, or policy/rule names when `-Anonymize` was enabled. `Protect-TenantBriefSensitiveText` and `Invoke-TenantBriefAssessment` now redact `TenantName` (alongside UPNs/emails, GUIDs, `*.onmicrosoft.com`, `*.sharepoint.com`, and tenant domain/prefix). **Action recommended:** Review any anonymized reports shared with earlier versions (`<= 1.0.1`) for unmasked tenant display names.

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
- **Sprint 7 Report UX, Accessibility, SVG Charts, Trend Tab & A4 Print (`S7.1–S7.5`):**
  - Accessibility hardening in `assets/report-template.html`: skip-to-content link, ARIA `tablist`/`tab`/`tabpanel` with `aria-selected`, keyboard arrow/Home/End tab navigation, and `:focus-visible` outlines.
  - Dependency-free inline SVG visuals on Overview: 6-pillar stacked distribution bar chart (`#pillarSvgChart`) and Risk × Effort open-findings heatmap (`#riskEffortHeatmap`).
  - Optional `-PreviousReportJson` parameter on `Invoke-TenantBriefAssessment` computing `Report.Trend` (`ScoreDelta`, `Improved`, `Regressed`, `NewFailed`, `Resolved`) and rendering the `"Önceki Rapora Göre" / "Trend vs Previous"` tab in HTML.
  - Compact HTML-embedded payload projection stripping redundant/empty fields and capping oversized inline markdown tables in HTML while preserving full JSON fidelity on disk.
  - A4 portrait `@page` and `@media print` pagination rules (`break-inside: avoid`) in `Export-TenantBriefExecutiveSummary`.

### Deprecated
- **`Finding.Impact`:** Retained in `v1.2.0` for backward compatibility; scheduled for removal in **`v2.0.0`** (alongside JSON Schema v2). Migrate consumers to `Finding.UserImpact` (end-user/business disruption impact) and `Finding.Risk` (security risk severity).

### Known Limitations
- **Cross-Engine Correlation (`Q01 = 42`):** Only the 42 canonical controls verified directly against upstream ZeroTrustAssessment, CISA ScubaGear 2.0, Maester, and Microsoft ORCA catalogs (`data/control-crosswalk.json`) are merged across engines; unmapped controls remain separate engine-scoped entries.
- **ScubaGear Product Coverage (`Q12 <= 7`):** Multi-product execution covers the 7 ScubaGear 2.0 M365 baselines (`aad, securitysuite, exo, powerplatform, sharepoint, teams, powerbi`); in offline runs or when a service session is disconnected, unavailable products are skipped and reported in `run-manifest.json` (`ScubaProducts`). *(Note: `Q12 = 8` reported during `v1.2.0` was a metric bug fixed in `v2.0.1`; the actual offline 1035 dataset covers `Q12 = 1` [`AAD`].)*
- **Turkish Machine Translations (`619` total = `360` legacy cache + `259` Sprint 3 additions, `0` Azure Translator API, `Reviewed = 0`):** All 619 entries in `data/tr-translation-cache.json` have `Source = "machine"` and have not yet completed human editorial review (`Reviewed = false`, tracked via `Summary.UnreviewedTranslations` and `docs/improvement/translation-review.md`).

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
