@{
    RootModule        = 'TenantBrief.psm1'
    ModuleVersion     = '1.0.0'
    GUID              = 'b7e4c1a2-9d3f-4e8a-9b1c-5f2a8d4e6c10'
    Author            = 'Caner Çetinkaya'
    CompanyName       = 'canercetinkaya.com'
    Copyright         = '(c) 2026 Caner Çetinkaya. MIT License.'
    Description       = 'Bilingual (TR/EN) Read-Only Microsoft 365 & Azure Security Posture, 6-Pillar Assessment Brief, License ROI/Waste Audit (R1-R7), Copilot Readiness, and Verified Benchmark Scoring (ZeroTrustAssessment, CISA ScubaGear, Microsoft ORCA, Maester EIDSCA/CIS M365, EntraFalcon).'
    PowerShellVersion = '7.0'
    FunctionsToExport = @(
        'Connect-TenantBrief',
        'Invoke-TenantBriefAssessment',
        'Get-TenantBriefFrameworks',
        'Get-TenantBriefLicenseRoi',
        'Get-TenantBriefLicenseWaste',
        'Get-TenantBriefCopilotReadiness',
        'Get-TenantBriefUsageAdoption',
        'Import-TenantBriefSharePointRisk',
        'Import-TenantBriefPowerPlatformAgents',
        'Compare-TenantBriefReports',
        'Export-TenantBriefExecutiveSummary'
    )
    CmdletsToExport   = @()
    VariablesToExport = @()
    AliasesToExport   = @()
    PrivateData       = @{
        PSData = @{
            Tags         = @('TenantBrief', 'ZeroTrust', 'Security', 'Microsoft365', 'Azure', 'EntraID', 'ScubaGear', 'Maester', 'EIDSCA', 'ORCA', 'CIS-M365', 'EntraFalcon', 'LicenseROI', 'Copilot')
            LicenseUri   = 'https://github.com/canercetinkaya/TenantBrief/blob/main/LICENSE'
            ProjectUri   = 'https://github.com/canercetinkaya/TenantBrief'
            ReleaseNotes = 'Unified 6 canonical security pillars with multi-source provenance tags, removed synthetic ISO/NIST/KVKK guesses in favor of verified per-benchmark scoring (ZeroTrustAssessment, CIS M365 v7.0.0, CISA SCuBA, ORCA, EIDSCA, Maester, EntraFalcon), filtered Maester NotRun/out-of-scope suites, and fixed PesterTestSkipped & Copilot DEVELOPERPACK_E5 readiness.'
        }
    }
}
