BeforeAll {
    $script:RepoRoot = Split-Path -Path $PSScriptRoot -Parent
    Import-Module (Join-Path $script:RepoRoot 'TenantBrief.psd1') -Force
}

Describe 'S1.5 - Portal & Least-Privilege Role Routing by Canonical Pillar, Source & ID Prefix' {
    It 'routes SCuBA EXO, SECURITYSUITE (DLP vs Defender), TEAMS, and AAD to their exact admin portals instead of generic CISA SCuBA' {
        InModuleScope TenantBrief {
            $tests = @(
                [PSCustomObject]@{ TestId = 'SCUBA-MS.EXO.3.1v1'; TestTitle = 'DKIM'; TestStatus = 'Failed'; TestRisk = 'High'; TestPillar = 'CISA SCuBA'; TestSource = 'CISA SCuBA'; TestCategory = 'EXO' },
                [PSCustomObject]@{ TestId = 'SCUBA-MS.SECURITYSUITE.3.1v1'; TestTitle = 'DLP'; TestStatus = 'Failed'; TestRisk = 'High'; TestPillar = 'CISA SCuBA'; TestSource = 'CISA SCuBA'; TestCategory = 'SECURITYSUITE' },
                [PSCustomObject]@{ TestId = 'SCUBA-MS.AAD.1.1v1'; TestTitle = 'Legacy Auth'; TestStatus = 'Failed'; TestRisk = 'High'; TestPillar = 'CISA SCuBA'; TestSource = 'CISA SCuBA'; TestCategory = 'AAD' },
                [PSCustomObject]@{ TestId = 'SCUBA-MS.TEAMS.1.2v2'; TestTitle = 'Teams Lobby'; TestStatus = 'Failed'; TestRisk = 'Medium'; TestPillar = 'CISA SCuBA'; TestSource = 'CISA SCuBA'; TestCategory = 'TEAMS' }
            )
            $f = @(New-TenantBriefFindings -Tests $tests -Language tr)

            # EXO -> Defender & Exchange
            $f[0].AdminPortal | Should -Match 'Defender & Exchange'
            $f[0].RequiredRole | Should -Match 'Exchange Administrator'

            # SECURITYSUITE 3.x (DLP) -> Purview
            $f[1].AdminPortal | Should -Match 'Purview'
            $f[1].RequiredRole | Should -Match 'Compliance Administrator'

            # AAD -> Entra (never generic CISA SCuBA)
            $f[2].AdminPortal | Should -Match 'Entra'
            $f[2].AdminPortal | Should -Not -Match 'CISA SCuBA'

            # TEAMS -> Teams Admin Center
            $f[3].AdminPortal | Should -Match 'Teams'
            $f[3].RequiredRole | Should -Be 'Teams Administrator'
        }
    }
}
