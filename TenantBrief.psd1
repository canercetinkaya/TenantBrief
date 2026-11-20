@{
    RootModule        = 'TenantBrief.psm1'
    ModuleVersion     = '2.0.0'
    GUID              = 'b7e4c1a2-9d3f-4e8a-9b1c-5f2a8d4e6c10'
    Author            = 'Caner Çetinkaya'
    CompanyName       = 'canercetinkaya.com'
    Copyright         = '(c) 2026 Caner Çetinkaya. MIT License.'
    Description       = 'Bilingual (TR/EN) Read-Only Microsoft 365 & Azure Security Posture, 6-Pillar Assessment Brief, License ROI/Waste Audit (R1-R7), Copilot Readiness, and Verified Benchmark Scoring (ZeroTrustAssessment, CISA ScubaGear, Microsoft ORCA, Maester EIDSCA/CIS M365, optional EntraFalcon JSON).'
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
        'Export-TenantBriefExecutiveSummary',
        'Test-TenantBriefPrerequisites'
    )
    CmdletsToExport   = @()
    VariablesToExport = @()
    AliasesToExport   = @()
    PrivateData       = @{
        PSData = @{
            Tags         = @('TenantBrief', 'ZeroTrust', 'Security', 'Microsoft365', 'Azure', 'EntraID', 'ScubaGear', 'Maester', 'EIDSCA', 'ORCA', 'CIS-M365', 'EntraFalcon', 'LicenseROI', 'Copilot')
            LicenseUri   = 'https://github.com/canercetinkaya/TenantBrief/blob/main/LICENSE'
            ProjectUri   = 'https://github.com/canercetinkaya/TenantBrief'
            ReleaseNotes = 'v2.0.0 (Breaking Change): Removes deprecated Finding.Impact alias (use Finding.UserImpact), adds mandatory SchemaVersion "2.0.0" to TenantBriefReport-*.json and schemas/tenantbrief-report.schema.json, ships docs/migration-v1-to-v2.md, and preserves cross-version v1->v2 Compare-TenantBriefReports compatibility.'
        }
    }
}
