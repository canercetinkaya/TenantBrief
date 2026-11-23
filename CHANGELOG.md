# Changelog

All notable changes to **TenantBrief** are documented in this file.

## [2.1.1] - 2026-11-23

### Visual, UX & Editorial Polish
- **Offline Light / Dark Theme Toggle (`assets/report-template.html`):** Added zero-dependency `#btnTheme` header toggle (`Ink Dark` ↔ `Ink Light`) wired via `addEventListener` with safe `localStorage` persistence and strict offline CSP preserved.
- **SVG Token Harmonization & A4 Print Contrast:** Replaced hardcoded bright chart colors in `#donutChart`, `#pillarSvgChart`, and `#riskEffortHeatmap` with CSS variables (`var(--ok)`, `var(--fail)`, `var(--warn)`, `var(--skip)`, `var(--raised)`, `var(--text)`, `var(--muted)`, `var(--border)`) and enforced `#111827` print ink.
- **Live Progress Dashboard (`assets/progress-template.html`):** Applied `Ink Dark` surface ramp, flat monochrome `TB` mark, `tabular-nums` timers, 4px grid, and `prefers-reduced-motion` support.
- **Keyboard Shortcuts:** Pressing `/` opens Findings and focuses `#searchInput`; pressing `Esc` clears and blurs `#searchInput` (with `<kbd>/</kbd>` hint).
- **Editorial Turkish Translations (`data/tr-translation-cache.json`):** Human-reviewed and corrected the 30 highest-priority `ZeroTrust` findings (`PriorityScore 80–95`, `Reviewed: true`, `Source: "human"`), fixing inverted security meanings, truncated descriptions, and corrupted Microsoft Learn URLs.
- **Refreshed `demo/` Reports:** Regenerated all 4 static demo HTML reports (`TenantBriefReport-TR/EN.html` and `TenantBrief-ExecutiveSummary-TR/EN.html`) on the `v2.1.1` template.

## [2.1.0] - 2026-11-23

### Highlights
- **Read-Only Multi-Engine Orchestration:** Runs `ZeroTrustAssessment`, `CISA ScubaGear 2.0`, `Microsoft ORCA`, `Maester` (`EIDSCA` / `CIS M365 v7.0.0` / `XSPM`), and optional `EntraFalcon` / Microsoft FastTrack JSON exports without writing to tenant configuration.
- **6 Canonical Security Pillars & 42-Control Crosswalk:** Normalizes findings into `Identity`, `Devices`, `Network`, `Data`, `AI`, and `SecOps`, calculates pre-correlation verified benchmark scores, separates upstream `Planned` controls, and assigns deterministic `PriorityScore` (`0–100`).
- **ScubaGear 2.0 Full Coverage (`-ScubaInteractiveLogin`):** Runs ScubaGear in an isolated Windows PowerShell 5.1 subprocess under `InvariantCulture` on Windows (bypassing `tr-TR` locale and PowerShell 7 MSAL issues without modifying user modules), and supports non-interactive certificate authentication via `-InputScubaJsonPath`.
- **Preflight & Local Safety Gate:** `Test-TenantBriefPrerequisites` provides a read-only environment check; local module installs/cleanup run only when `-AutoFixDependencies` is explicitly passed.
- **License ROI (`R1–R7`), Copilot Readiness & Usage/Adoption:** Live Graph `/subscribedSkus` and `/users` telemetry across 32 SKUs and 10 overlap rules, plus L1–L4 Copilot readiness and browser-local Print-to-PDF executive briefs.
- **Security, Privacy & Quality Gates:** Strict offline CSP, HTML-escaped JSON payloads, `-Anonymize` redaction, JSON Schema v2.0.0, 130 automated Pester tests, PSScriptAnalyzer CI gate, and monthly read-only upstream version check (`tools/Register-TenantBriefUpstreamCheck.ps1`).
