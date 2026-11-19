BeforeAll {
    $script:RepoRoot = Split-Path -Path $PSScriptRoot -Parent
    Import-Module (Join-Path $script:RepoRoot 'TenantBrief.psd1') -Force
}

Describe 'S4.2 - Dynamic Roadmap Phases (PriorityScore-Ordered FindingIds & Category-Driven Focus)' {
    It 'generates dynamic Focus from actual phase categories and includes PriorityScore-ordered FindingIds' {
        $tmpDir = Join-Path ([System.IO.Path]::GetTempPath()) ("tb-s42-" + [guid]::NewGuid().ToString('N').Substring(0, 8))
        New-Item -ItemType Directory -Path $tmpDir -Force | Out-Null
        $rawZt = Join-Path $tmpDir 'zt.json'
        try {
            [PSCustomObject]@{
                TenantId   = '00000000-0000-0000-0000-000000000042'
                Domain     = 'contoso.onmicrosoft.com'
                TenantInfo = [PSCustomObject]@{
                    TenantOverview = [PSCustomObject]@{ UserCount = 50; GuestCount = 0; GroupCount = 2; ApplicationCount = 2; DeviceCount = 2; ManagedDeviceCount = 2 }
                    OverviewCaMfaAllUsers = $null; DeviceOverview = $null; AgentOverview = $null; OverviewAuthMethodsPrivilegedUsers = $null
                }
                Tests = @(
                    [PSCustomObject]@{ TestId = '90001'; TestTitle = 'High Unknown Cost'; TestStatus = 'Failed'; TestRisk = 'High'; TestPillar = 'Identity'; TestCategory = 'CustomCatAlpha'; TestImplementationCost = 'Unknown'; TestMinimumLicense = 'P1'; TestImpact = 'Low'; TestResult = 'R'; TestDescription = 'D'; SkippedReason = '' },
                    [PSCustomObject]@{ TestId = '90002'; TestTitle = 'High Low Cost'; TestStatus = 'Failed'; TestRisk = 'High'; TestPillar = 'Identity'; TestCategory = 'CustomCatAlpha'; TestImplementationCost = 'Low'; TestMinimumLicense = 'P1'; TestImpact = 'Low'; TestResult = 'R'; TestDescription = 'D'; SkippedReason = '' },
                    [PSCustomObject]@{ TestId = '90003'; TestTitle = 'Med Item'; TestStatus = 'Failed'; TestRisk = 'Medium'; TestPillar = 'Data'; TestCategory = 'CustomCatBeta'; TestImplementationCost = 'Medium'; TestMinimumLicense = 'P1'; TestImpact = 'Low'; TestResult = 'R'; TestDescription = 'D'; SkippedReason = '' }
                )
            } | ConvertTo-Json -Depth 10 | Set-Content -Path $rawZt -Encoding UTF8

            $run = Invoke-TenantBriefAssessment -InputReportJson $rawZt -OutputPath $tmpDir -Language tr -Framework All -NoBrowser
            $rep = Get-Content -LiteralPath $run.JsonPath -Raw -Encoding UTF8 | ConvertFrom-Json

            $rep.Roadmap[0].Focus | Should -Match 'CustomCatAlpha'
            $rep.Roadmap[0].Focus | Should -Not -Match 'Passkey'
            $rep.Roadmap[0].PSObject.Properties['FindingIds'] | Should -Not -BeNullOrEmpty
            $rep.Roadmap[0].FindingIds[0] | Should -Be '90002'
            $rep.Roadmap[0].FindingIds[1] | Should -Be '90001'
            $rep.Roadmap[1].Focus | Should -Match 'CustomCatBeta'
        } finally {
            Remove-Item -Path $tmpDir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}
