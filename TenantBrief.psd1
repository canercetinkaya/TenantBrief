@{
    RootModule        = 'TenantBrief.psm1'
    ModuleVersion     = '1.0.0'
    GUID              = 'b7e4c1a2-9d3f-4e8a-9b1c-5f2a8d4e6c10'
    Author            = 'Caner Çetinkaya'
    CompanyName       = 'canercetinkaya.com'
    Copyright         = '(c) 2026 Caner Çetinkaya. MIT License.'
    Description       = 'Bilingual (TR/EN) Read-Only Microsoft 365 & Azure Security Posture, License ROI, Copilot Readiness, and Multi-Framework (Zero Trust, ISO 27001, NIST CSF 2.0, CIS M365, KVKK) Assessment Brief.'
    PowerShellVersion = '7.0'
    FunctionsToExport = @(
        'Connect-TenantBrief',
        'Invoke-TenantBriefAssessment',
        'Get-TenantBriefFrameworks',
        'Get-TenantBriefLicenseRoi',
        'Get-TenantBriefLicenseWaste',
        'Get-TenantBriefCopilotReadiness',
        'Compare-TenantBriefReports',
        'Export-TenantBriefExecutiveSummary'
    )
    CmdletsToExport   = @()
    VariablesToExport = @()
    AliasesToExport   = @(
        'Connect-ZtLens',
        'Invoke-ZtLensAssessment',
        'Get-ZtLensFrameworks',
        'Get-ZtLensLicenseRoi',
        'Get-ZtLensLicenseWaste',
        'Get-ZtLensCopilotReadiness',
        'Compare-ZtLensReports',
        'Export-ZtLensExecutiveSummary'
    )
    PrivateData       = @{
        PSData = @{
            Tags         = @('TenantBrief', 'ZeroTrust', 'Security', 'Microsoft365', 'Azure', 'EntraID', 'ISO27001', 'NIST', 'KVKK', 'LicenseROI', 'Copilot')
            LicenseUri   = 'https://github.com/canercetinkaya/TenantBrief/blob/main/LICENSE'
            ProjectUri   = 'https://github.com/canercetinkaya/TenantBrief'
            ReleaseNotes = 'Rebranded from ZeroTrustLens to TenantBrief with full backward-compatible *-ZtLens* aliases: Bilingual (TR/EN) CISO & Architect reporting, M365 License ROI & Waste analysis, Copilot Readiness, and selectable compliance framework scoring.'
        }
    }
}
