BeforeAll {
    $script:RepoRoot = Split-Path -Path $PSScriptRoot -Parent
    Import-Module (Join-Path $script:RepoRoot 'TenantBrief.psd1') -Force
}

Describe 'S1.3 - Status Priority (Failed 4 > Error 3 > Investigate 2 > Skipped/Planned 1 > Passed 0) & Planned Exclusion' {
    It 'ranks Error above Passed and sets StatusConflict=true' {
        InModuleScope TenantBrief {
            $incoming = @(
                [PSCustomObject]@{ TestId = '21808'; TestTitle = 'Device code'; TestStatus = 'Passed'; TestRisk = 'High'; TestPillar = 'Identity' },
                [PSCustomObject]@{ TestId = 'SCUBA-MS.AAD.3.9v1'; TestTitle = 'Device code'; TestStatus = 'Error'; TestRisk = 'High'; TestPillar = 'CISA SCuBA'; TestSource = 'CISA SCuBA' }
            )
            $r = @(New-TenantBriefCorrelatedTests -Tests $incoming)
            $r.Count | Should -Be 1
            $r[0].TestStatus | Should -Be 'Error'
            $r[0].StatusConflict | Should -BeTrue
        }
    }

    It 'ranks Failed above Error and sets StatusConflict=true' {
        InModuleScope TenantBrief {
            $incoming = @(
                [PSCustomObject]@{ TestId = '21808'; TestTitle = 'Device code'; TestStatus = 'Error'; TestRisk = 'High'; TestPillar = 'Identity' },
                [PSCustomObject]@{ TestId = 'SCUBA-MS.AAD.3.9v1'; TestTitle = 'Device code'; TestStatus = 'Failed'; TestRisk = 'High'; TestPillar = 'CISA SCuBA'; TestSource = 'CISA SCuBA' }
            )
            $r = @(New-TenantBriefCorrelatedTests -Tests $incoming)
            $r.Count | Should -Be 1
            $r[0].TestStatus | Should -Be 'Failed'
            $r[0].StatusConflict | Should -BeTrue
        }
    }

    It 'excludes Planned controls from Findings and Summary.Total into PlannedFindings (Q11=0)' {
        $tmpDir = Join-Path ([System.IO.Path]::GetTempPath()) ("tb-s13-" + [guid]::NewGuid().ToString('N').Substring(0, 8))
        New-Item -ItemType Directory -Path $tmpDir -Force | Out-Null
        $rawZt = Join-Path $tmpDir 'zt.json'
        try {
            [PSCustomObject]@{
                TenantId   = '00000000-0000-0000-0000-000000000003'
                Domain     = 'contoso.onmicrosoft.com'
                TenantInfo = [PSCustomObject]@{
                    TenantOverview = [PSCustomObject]@{ UserCount = 10; GuestCount = 0; GroupCount = 2; ApplicationCount = 2; DeviceCount = 2; ManagedDeviceCount = 2 }
                    OverviewCaMfaAllUsers = $null; DeviceOverview = $null; AgentOverview = $null; OverviewAuthMethodsPrivilegedUsers = $null
                }
                Tests = @(
                    [PSCustomObject]@{ TestId = '21796'; TestTitle = 'Active check'; TestStatus = 'Passed'; TestRisk = 'High'; TestPillar = 'Identity'; TestCategory = 'CA'; TestSfiPillar = 'Identity'; TestImplementationCost = 'Low'; TestMinimumLicense = 'P1'; TestImpact = 'Low'; TestResult = 'OK'; TestDescription = 'Desc'; SkippedReason = '' },
                    [PSCustomObject]@{ TestId = '99001'; TestTitle = 'Upcoming planned check'; TestStatus = 'Planned'; TestRisk = 'Medium'; TestPillar = 'Identity'; TestCategory = 'Future'; TestSfiPillar = 'Identity'; TestImplementationCost = 'Low'; TestMinimumLicense = ''; TestImpact = 'Low'; TestResult = ''; TestDescription = 'Planned upstream test'; SkippedReason = '' }
                )
            } | ConvertTo-Json -Depth 10 | Set-Content -Path $rawZt -Encoding UTF8

            $run = Invoke-TenantBriefAssessment -InputReportJson $rawZt -OutputPath $tmpDir -Language tr -Framework All -NoBrowser
            $rep = Get-Content -LiteralPath $run.JsonPath -Raw -Encoding UTF8 | ConvertFrom-Json

            @($rep.Findings | Where-Object { $_.Status -eq 'Planned' }).Count | Should -Be 0
            $rep.Summary.Total | Should -Be 1
            $rep.Summary.Planned | Should -Be 0
            $rep.Summary.PlannedExcluded | Should -Be 1
            @($rep.PlannedFindings).Count | Should -Be 1
            $rep.PlannedFindings[0].Id | Should -Be '99001'
        } finally {
            Remove-Item -Path $tmpDir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}
