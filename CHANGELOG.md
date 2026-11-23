# Changelog

All notable changes to **TenantBrief** are documented in this file.

## [Unreleased]

### Highlights
- **Read-Only Multi-Engine Orchestration:** Runs `ZeroTrustAssessment`, `CISA ScubaGear 2.0`, `Microsoft ORCA`, `Maester` (`EIDSCA` / `CIS M365 v7.0.0` / `XSPM`), and optional `EntraFalcon` / Microsoft FastTrack JSON exports without writing to tenant configuration.
- **6 Canonical Security Pillars & 42-Control Crosswalk:** Normalizes findings into `Identity`, `Devices`, `Network`, `Data`, `AI`, and `SecOps`, calculates pre-correlation verified benchmark scores, separates upstream `Planned` controls, and assigns deterministic `PriorityScore` (`0–100`).
- **ScubaGear 2.0 Full Coverage (`-ScubaInteractiveLogin`):** Runs ScubaGear in an isolated Windows PowerShell 5.1 subprocess under `InvariantCulture` on Windows (bypassing `tr-TR` locale and PowerShell 7 MSAL issues without modifying user modules), and supports non-interactive certificate authentication via `-InputScubaJsonPath`.
- **Preflight & Local Safety Gate:** `Test-TenantBriefPrerequisites` provides a read-only environment check; local module installs/cleanup run only when `-AutoFixDependencies` is explicitly passed.
- **License ROI (`R1–R7`), Copilot Readiness & Usage/Adoption:** Live Graph `/subscribedSkus` and `/users` telemetry across 32 SKUs and 10 overlap rules, plus L1–L4 Copilot readiness and browser-local Print-to-PDF executive briefs.
- **Security, Privacy & Quality Gates:** Strict offline CSP, HTML-escaped JSON payloads, `-Anonymize` redaction, JSON Schema v2.0.0, 130 automated Pester tests, PSScriptAnalyzer CI gate, and monthly read-only upstream version check (`tools/Register-TenantBriefUpstreamCheck.ps1`).
