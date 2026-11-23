BeforeAll {
    $script:RepoRoot = Split-Path -Path $PSScriptRoot -Parent
    Import-Module (Join-Path $script:RepoRoot 'TenantBrief.psd1') -Force
    $script:TrPath = Join-Path $script:RepoRoot 'data\i18n\tr.json'
    $script:EnPath = Join-Path $script:RepoRoot 'data\i18n\en.json'
}

Describe 'S3.1 - Externalized i18n Dictionaries (data/i18n/{tr,en}.json) & Zero Turkish in EN Reports' {
    It 'provides matching keys in data/i18n/tr.json and data/i18n/en.json' {
        Test-Path -LiteralPath $script:TrPath | Should -BeTrue
        Test-Path -LiteralPath $script:EnPath | Should -BeTrue
        $tr = Get-Content -LiteralPath $script:TrPath -Raw -Encoding UTF8 | ConvertFrom-Json
        $en = Get-Content -LiteralPath $script:EnPath -Raw -Encoding UTF8 | ConvertFrom-Json

        $trPortalKeys = @($tr.portals.PSObject.Properties.Name | Sort-Object)
        $enPortalKeys = @($en.portals.PSObject.Properties.Name | Sort-Object)
        ($trPortalKeys -join ',') | Should -Be ($enPortalKeys -join ',')
        $trPortalKeys.Count | Should -BeGreaterOrEqual 10
    }

    It 'renders English AdminPortal names with zero Turkish words when Language=en' {
        InModuleScope TenantBrief {
            $tests = @(
                [PSCustomObject]@{ TestId = '21796'; TestTitle = 'Legacy auth'; TestStatus = 'Failed'; TestRisk = 'High'; TestPillar = 'Identity'; TestCategory = 'CA' },
                [PSCustomObject]@{ TestId = 'ORCA-104'; TestTitle = 'Phish'; TestStatus = 'Failed'; TestRisk = 'Critical'; TestPillar = 'Defender for Office 365 (ORCA)'; TestSource = 'MDO / ORCA'; TestCategory = 'MDO' },
                [PSCustomObject]@{ TestId = 'CIS.M365.8.5.3'; TestTitle = 'Teams lobby'; TestStatus = 'Failed'; TestRisk = 'Medium'; TestPillar = 'Maester (EIDSCA / CIS)'; TestSource = 'CIS M365'; TestCategory = 'Teams' },
                [PSCustomObject]@{ TestId = 'CIS.M365.4.1'; TestTitle = 'Intune compliance'; TestStatus = 'Failed'; TestRisk = 'Medium'; TestPillar = 'Devices'; TestCategory = 'Intune' },
                [PSCustomObject]@{ TestId = 'SCUBA-MS.SECURITYSUITE.3.1v1'; TestTitle = 'DLP'; TestStatus = 'Failed'; TestRisk = 'High'; TestPillar = 'CISA SCuBA'; TestSource = 'CISA SCuBA'; TestCategory = 'SECURITYSUITE' }
            )
            $enFindings = @(New-TenantBriefFindings -Tests $tests -Language en)
            foreach ($f in $enFindings) {
                $f.AdminPortal | Should -Not -Match 'Yönetim|yönetim|portalı|Merkezi' -Because "EN finding $($f.Id) must not contain Turkish portal text: $($f.AdminPortal)"
            }
            $trFindings = @(New-TenantBriefFindings -Tests $tests -Language tr)
            ($trFindings | Where-Object { $_.Id -eq '21796' }).AdminPortal | Should -Match 'Microsoft Entra'
        }
    }
}
