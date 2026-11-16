# ZeroTrustLens

**ZeroTrustLens** is a strictly **read-only**, bilingual (**Turkish / English**) Microsoft 365 & Azure security posture, **License ROI**, and **multi-framework compliance** assessment toolkit built on top of Microsoft's `ZeroTrustAssessment` engine.

> **Why ZeroTrustLens?**
> Standard Zero Trust assessments show *what failed*, but CISOs, security architects, and IT directors also need to answer:
> 1. **License ROI & Blind Spots:** How much of our paid Microsoft 365 E3/E5 security investment is actually configured vs. sitting idle (`Skipped` / unconfigured)?
> 2. **Multi-Framework Alignment:** How do our Microsoft 365 controls map to **ISO/IEC 27001:2022**, **NIST CSF 2.0**, **CIS Microsoft 365 Foundations**, and **KVKK (Turkey)**?
> 3. **Executive Action Plan:** Which high-risk findings should be fixed in **30 / 60 / 90 days** without breaking production?

---

## Key Capabilities

- **Strictly Read-Only Architecture:** Never modifies tenant policies, Conditional Access rules, or Entra ID objects. Uses least-privilege read-only Microsoft Graph scopes.
- **M365 License ROI & Blind-Spot Analysis:** Identifies `Skipped` and unconfigured checks so organizations can see paid security features that are not yet delivering value.
- **5 Selectable Compliance Frameworks:**
  - `ZeroTrust` (Microsoft 7-pillar model)
  - `ISO27001` (ISO/IEC 27001:2022 Annex A)
  - `NIST_CSF_2` (NIST Cybersecurity Framework 2.0)
  - `CIS_M365` (CIS Microsoft 365 Foundations)
  - `KVKK_TR` (KVKK Technical Measures)
- **30-60-90 Day CISO Roadmap:** Prioritizes `Failed` findings by risk severity (`High`, `Medium`, `Low`) into actionable phases.
- **Cross-Engine Correlation (`ZeroTrustAssessment` + `ScubaGear` + `ORCA`):** Automatically detects and runs installed `ScubaGear` and `ORCA` modules in read-only mode and deduplicates overlapping findings.
- **Interactive What-If Simulator & Print-to-PDF Executive Summary:** Simulates framework score improvements in real time and automatically generates `ZeroTrustLens-ExecutiveSummary-<LANG>.html` for CISO/audit briefings.
- **Historical Drift Comparison (`Compare-ZtLensReports`) & Real SKU ROI (`Get-ZtLensLicenseRoi`):** Tracks posture improvements over time and calculates idle license cost across 25+ Microsoft 365 SKUs.
- **Bilingual Offline HTML & JSON Reports:** Generates self-contained dark-mode HTML dashboards (`-Language tr` or `-Language en`) with search, status/risk filters, and optional `-Anonymize` mode for safe sharing.

---

## Prerequisites

- **PowerShell 7.0+** (`pwsh`)
- **Microsoft `ZeroTrustAssessment` module** (`Install-Module ZeroTrustAssessment -Scope CurrentUser`)
- Read-only Microsoft Graph permissions (e.g., `Global Reader` or `Security Reader` + `Reports Reader`)

---

## Quick Start

### 1. Clone & Import

```powershell
git clone https://github.com/canercetinkaya/ZeroTrustLens.git
cd ZeroTrustLens
Import-Module .\ZeroTrustLens.psd1 -Force
```

### 2. List Supported Frameworks

```powershell
Get-ZtLensFrameworks
```

### 3. Run Live Tenant Assessment (Read-Only)

```powershell
# Connect with read-only scopes
Connect-ZtLens

# Run assessment and generate Turkish HTML + JSON report
Invoke-ZtLensAssessment -OutputPath .\ZeroTrustLensReport -Language tr -Framework All
```

### 4. Analyze an Existing `ZeroTrustAssessmentReport.json` Offline

```powershell
# Generate an anonymized English report from an existing export
Invoke-ZtLensAssessment `
  -InputReportJson .\ZeroTrustAssessmentReport.json `
  -OutputPath .\demo `
  -Language en `
  -Anonymize `
  -NoBrowser
```

---

## Demo Reports

Anonymized sample reports generated from a real 361-check Microsoft 365 tenant evaluation are included in `demo/`:

- [demo/ZeroTrustLensReport-TR.html](demo/ZeroTrustLensReport-TR.html) (Turkish)
- [demo/ZeroTrustLensReport-EN.html](demo/ZeroTrustLensReport-EN.html) (English)

---

## Security & Privacy

- **Zero Telemetry:** `ZeroTrustLens` does not send telemetry to any external endpoint.
- **Offline-First:** All HTML and JSON outputs are generated locally.
- **Anonymization (`-Anonymize`):** Strips tenant IDs and domain names before generating shareable reports.

## License

MIT License — see [LICENSE](LICENSE).
