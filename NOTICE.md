# Third-Party & Open-Source Attributions (`NOTICE`)

**TenantBrief** is licensed under the MIT License (see [LICENSE](LICENSE)). It orchestrates, normalizes, and correlates outputs from established Microsoft and community security assessment projects—all executed strictly in read-only mode or consumed offline without modifying upstream logic.

We gratefully acknowledge the maintainers and contributors of the following upstream projects and ecosystem references:

## Assessment Engines (Runtime Dependencies & JSON Consumers)

| Project | Maintainer / Source | Role in TenantBrief |
| --- | --- | --- |
| **Microsoft ZeroTrustAssessment** | [github.com/microsoft/zerotrustassessment](https://github.com/microsoft/zerotrustassessment) | Stage 1 core Microsoft 365 & Azure Zero Trust posture evaluation (`Invoke-ZtAssessment`) and tenant overview telemetry |
| **CISA ScubaGear** | [github.com/cisagov/ScubaGear](https://github.com/cisagov/ScubaGear) | Stage 2 CISA Secure Cloud Business Applications (SCuBA) baseline checks via Rego/OPA (`Invoke-SCuBA`) |
| **Microsoft ORCA** | [github.com/martin9700/ORCA](https://github.com/martin9700/ORCA) | Stage 3a Defender for Office 365 & Exchange Online hygiene checks (`Invoke-ORCA`) |
| **Maester (incl. EIDSCA & CIS M365)** | [github.com/maester365/maester](https://github.com/maester365/maester) | Stage 3b live (`Invoke-Maester`) and offline (`-InputMaesterJsonPath`) Entra ID (EIDSCA), CIS M365 Foundations Benchmark v7.0.0, Intune, Defender, Purview, and Copilot Studio checks |
| **EntraFalcon** | [github.com/CompassSecurity/EntraFalcon](https://github.com/CompassSecurity/EntraFalcon) | Optional offline attack-path, tiered administration, and privileged Entra role JSON ingestion (`-InputEntraFalconJsonPath` / `tenant_findings_all_*.json`) |

## Methodology, Copilot Readiness & License ROI References

| Reference | Source | Inspiration / Adaptation in TenantBrief |
| --- | --- | --- |
| **Microsoft FastTrack Copilot Readiness** | [microsoft.github.io/FastTrack](https://microsoft.github.io/FastTrack/#get-m365copilotreadiness) | Copilot eligibility, SharePoint RAC/RCD posture alignment, and optional `-InputFastTrackJsonPath` ingestion |
| **M365 Copilot Automated Readiness** | [github.com/microsoft/m365-copilot-automated-readiness-assessment](https://github.com/microsoft/m365-copilot-automated-readiness-assessment) | Graph-based readiness checks adapted to preserve active MSAL context without calling `Disconnect-MgGraph` |
| **M365 License Review** | [github.com/samuelgtetteh/m365-license-review](https://github.com/samuelgtetteh/m365-license-review) | R1–R7 enterprise license waste categories (disabled accounts, 90+ day inactive seats, unassigned licenses, redundant overlaps, and licensed guests) |
| **Copilot ROI Calculator** | [github.com/amitlals/copilot-roi-calculator](https://github.com/amitlals/copilot-roi-calculator) | Offline, browser-local Microsoft 365 Copilot & Agent Studio ROI & breakeven model |

---

*Disclaimer: TenantBrief is an independent read-only reporting and orchestration layer. Mention of upstream projects or standards (Microsoft, CISA, CIS) denotes technical interoperability and attribution only and does not imply endorsement by those organizations.*
