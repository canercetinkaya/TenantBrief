@{
    RootModule        = 'ZeroTrustLens.psm1'
    ModuleVersion     = '1.0.0'
    GUID              = 'b7e4c1a2-9d3f-4e8a-9b1c-5f2a8d4e6c10'
    Author            = 'Caner Çetinkaya'
    CompanyName       = 'canercetinkaya.com'
    Copyright         = '(c) 2026 Caner Çetinkaya. MIT License.'
    Description       = 'Bilingual (TR/EN) Read-Only Microsoft 365 & Azure Zero Trust, License ROI, and Multi-Framework (ISO 27001, NIST CSF 2.0, CIS M365, KVKK) Posture Assessment Tool.'
    PowerShellVersion = '7.0'
    FunctionsToExport = @(
        'Connect-ZtLens',
        'Invoke-ZtLensAssessment',
        'Get-ZtLensFrameworks',
        'Get-ZtLensLicenseRoi',
        'Compare-ZtLensReports',
        'Export-ZtLensExecutiveSummary'
    )
    PrivateData = @{
        PSData = @{
            Tags       = @('ZeroTrust', 'Microsoft365', 'Security', 'Compliance', 'ISO27001', 'KVKK', 'ReadOnly')
            LicenseUri = 'https://github.com/canercetinkaya/ZeroTrustLens/blob/master/LICENSE'
            ProjectUri = 'https://github.com/canercetinkaya/ZeroTrustLens'
        }
    }
    CmdletsToExport   = @()
    VariablesToExport = @()
    AliasesToExport   = @()
    PrivateData       = @{
        PSData = @{
            Tags         = @('ZeroTrust', 'Security', 'Microsoft365', 'Azure', 'EntraID', 'ISO27001', 'NIST', 'KVKK', 'LicenseROI')
            LicenseUri   = 'https://github.com/canercetinkaya/ZeroTrustLens/blob/main/LICENSE'
            ProjectUri   = 'https://github.com/canercetinkaya/ZeroTrustLens'
            ReleaseNotes = 'Initial v1.0.0 release: Bilingual (TR/EN) CISO & Architect reporting, M365 License ROI analysis, and selectable compliance framework scoring.'
        }
    }
}
