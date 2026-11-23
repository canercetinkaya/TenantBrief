BeforeAll {
    $script:RepoRoot = Split-Path -Path $PSScriptRoot -Parent
    Import-Module (Join-Path $script:RepoRoot 'TenantBrief.psd1') -Force
}

Describe 'S1.4 - Canonical 6 Pillars (Q02=0, Q03=0), EngineLabel & ScubaGear 2.0 SECURITYSUITE' {
    It 'sets Pillar, PrimaryPillar and DomainPillar to canonical single value and moves tool label to EngineLabel' {
        InModuleScope TenantBrief {
            $incoming = @(
                [PSCustomObject]@{ TestId = 'SCUBA-MS.AAD.1.1v1'; TestTitle = 'Legacy auth'; TestStatus = 'Failed'; TestRisk = 'High'; TestPillar = 'CISA SCuBA'; TestSource = 'CISA SCuBA'; TestCategory = 'AAD' },
                [PSCustomObject]@{ TestId = '35012'; TestTitle = 'Container labels'; TestStatus = 'Failed'; TestRisk = 'Medium'; TestPillar = @('Data', 'AI'); TestCategory = 'Information Protection' }
            )
            $f = @(New-TenantBriefFindings -Tests $incoming -Language tr)

            # SCuBA control: Pillar must be canonical 'Identity' (no tool name), EngineLabel keeps 'CISA SCuBA'
            $f[0].Pillar | Should -Be 'Identity'
            $f[0].PrimaryPillar | Should -Be 'Identity'
            $f[0].DomainPillar | Should -Be 'Identity'
            $f[0].EngineLabel | Should -Be 'CISA SCuBA'

            # Multi-pillar control: DomainPillar is singular (no comma), DomainPillars keeps full array
            $f[1].Pillar | Should -Be 'Data'
            $f[1].DomainPillar | Should -Be 'Data'
            $f[1].DomainPillar | Should -Not -Match ','
            $f[1].DomainPillars | Should -Contain 'Data'
            $f[1].DomainPillars | Should -Contain 'AI'
        }
    }

    It 'routes ScubaGear 2.0 MS.SECURITYSUITE.* controls to Data (3.x DLP) and SecOps (1.x/2.x/4.x Defender)' {
        InModuleScope TenantBrief {
            $dlp = [PSCustomObject]@{ TestId = 'SCUBA-MS.SECURITYSUITE.3.1v1'; TestPillar = 'CISA SCuBA'; TestCategory = 'SECURITYSUITE' }
            $def = [PSCustomObject]@{ TestId = 'SCUBA-MS.SECURITYSUITE.1.1v1'; TestPillar = 'CISA SCuBA'; TestCategory = 'SECURITYSUITE' }

            @(Resolve-TenantBriefDomainPillars -Test $dlp) | Should -Contain 'Data'
            @(Resolve-TenantBriefDomainPillars -Test $def) | Should -Contain 'SecOps'
        }
    }
}
