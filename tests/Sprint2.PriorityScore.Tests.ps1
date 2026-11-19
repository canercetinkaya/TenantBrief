BeforeAll {
    $script:RepoRoot = Split-Path -Path $PSScriptRoot -Parent
    Import-Module (Join-Path $script:RepoRoot 'TenantBrief.psd1') -Force
    $script:ScoringPath = Join-Path $script:RepoRoot 'data\scoring.json'
}

Describe 'S2.7 - PriorityScore Weighted Formula & data/scoring.json' {
    It 'loads data/scoring.json and computes deterministic PriorityScore ordering on findings' {
        Test-Path -LiteralPath $script:ScoringPath | Should -BeTrue
        $cfg = Get-Content -LiteralPath $script:ScoringPath -Raw -Encoding UTF8 | ConvertFrom-Json
        $cfg.riskWeights.Critical | Should -BeGreaterThan $cfg.riskWeights.High
        $cfg.costBonus.Low | Should -BeGreaterThan $cfg.costBonus.Medium
        $cfg.costBonus.Medium | Should -BeGreaterThan $cfg.costBonus.High
        $cfg.costBonus.High | Should -BeGreaterThan $cfg.costBonus.Unknown

        InModuleScope TenantBrief {
            $tests = @(
                [PSCustomObject]@{ TestId = 'C1'; TestTitle = 'Crit Low'; TestStatus = 'Failed'; TestRisk = 'Critical'; TestImplementationCost = 'Low'; TestPillar = 'Identity' },
                [PSCustomObject]@{ TestId = 'H1'; TestTitle = 'High Low'; TestStatus = 'Failed'; TestRisk = 'High'; TestImplementationCost = 'Low'; TestPillar = 'Identity' },
                [PSCustomObject]@{ TestId = 'H2'; TestTitle = 'High Med'; TestStatus = 'Failed'; TestRisk = 'High'; TestImplementationCost = 'Medium'; TestPillar = 'Identity' },
                [PSCustomObject]@{ TestId = 'H3'; TestTitle = 'High Unk'; TestStatus = 'Failed'; TestRisk = 'High'; TestImplementationCost = 'Unknown'; TestPillar = 'Identity' },
                [PSCustomObject]@{ TestId = 'P1'; TestTitle = 'Passed'; TestStatus = 'Passed'; TestRisk = 'High'; TestImplementationCost = 'Low'; TestPillar = 'Identity' }
            )
            $f = @(New-TenantBriefFindings -Tests $tests -Language en)
            $byId = @{}; foreach ($item in $f) { $byId[$item.Id] = $item }

            $byId['C1'].PriorityScore | Should -BeGreaterThan $byId['H1'].PriorityScore
            $byId['H1'].PriorityScore | Should -BeGreaterThan $byId['H2'].PriorityScore
            $byId['H2'].PriorityScore | Should -BeGreaterThan $byId['H3'].PriorityScore
            $byId['H3'].PriorityScore | Should -BeGreaterThan $byId['P1'].PriorityScore
            $byId['C1'].PriorityScore | Should -BeLessOrEqual 100
            $byId['P1'].PriorityScore | Should -BeGreaterOrEqual 0
        }

        $readme = Get-Content -LiteralPath (Join-Path $script:RepoRoot 'README.md') -Raw -Encoding UTF8
        $readme | Should -Match 'PriorityScore'
        $readme | Should -Match 'scoring\.json'
    }
}
