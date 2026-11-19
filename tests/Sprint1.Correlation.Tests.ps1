BeforeAll {
    $script:RepoRoot = Split-Path -Path $PSScriptRoot -Parent
    Import-Module (Join-Path $script:RepoRoot 'TenantBrief.psd1') -Force
}

Describe 'S1.2 - Crosswalk-Only Correlation, SourceStatuses, StatusConflict & Framework Score Invariance' {
    It 'correlates 4 legacy auth controls across 3 engines via control-crosswalk.json despite completely different titles' {
        InModuleScope TenantBrief {
            $incoming = @(
                [PSCustomObject]@{ TestId = '21796'; TestTitle = 'Block legacy authentication policies are configured'; TestStatus = 'Passed'; TestRisk = 'High'; TestPillar = 'Identity'; TestCategory = 'Authentication' },
                [PSCustomObject]@{ TestId = 'SCUBA-MS.AAD.1.1v1'; TestTitle = 'Legacy authentication SHALL be blocked.'; TestStatus = 'Failed'; TestRisk = 'High'; TestPillar = 'CISA SCuBA'; TestSource = 'CISA SCuBA'; TestCategory = 'AAD' },
                [PSCustomObject]@{ TestId = 'MT.1009'; TestTitle = 'At least one Conditional Access policy is configured to block other legacy authentication.'; TestStatus = 'Failed'; TestRisk = 'High'; TestPillar = 'Maester (EIDSCA / CIS)'; TestSource = 'Maester'; TestCategory = 'Conditional Access' },
                [PSCustomObject]@{ TestId = 'MT.1010'; TestTitle = 'At least one Conditional Access policy is configured to block legacy authentication for Exchange ActiveSync.'; TestStatus = 'Passed'; TestRisk = 'High'; TestPillar = 'Maester (EIDSCA / CIS)'; TestSource = 'Maester'; TestCategory = 'Conditional Access' }
            )
            $r = @(New-TenantBriefCorrelatedTests -Tests $incoming)
            $r.Count | Should -Be 1
            $r[0].CanonicalId | Should -Be 'TB-ID-LEGACY-AUTH'
            @($r[0].CorrelatedIds).Count | Should -Be 4
            @($r[0].TestSources).Count | Should -Be 3
            $r[0].TestStatus | Should -Be 'Failed'
            $r[0].StatusConflict | Should -BeTrue
            $r[0].SourceStatuses['ZeroTrust'] | Should -Be 'Passed'
            $r[0].SourceStatuses['CISA SCuBA'] | Should -Be 'Failed'
        }
    }

    It 'does NOT merge unmapped controls merely because they share the same English title' {
        InModuleScope TenantBrief {
            $incoming = @(
                [PSCustomObject]@{ TestId = 'UNMAPPED-1'; TestTitle = 'Identical generic control title'; TestStatus = 'Passed'; TestRisk = 'Medium'; TestPillar = 'Identity' },
                [PSCustomObject]@{ TestId = 'UNMAPPED-2'; TestTitle = 'Identical generic control title'; TestStatus = 'Failed'; TestRisk = 'High'; TestPillar = 'CISA SCuBA'; TestSource = 'CISA SCuBA' }
            )
            $r = @(New-TenantBriefCorrelatedTests -Tests $incoming)
            $r.Count | Should -Be 2
        }
    }

    It 'detects StatusConflict on Device Code flow and preserves pre-correlation Framework scores with UniqueControls vs SourceControls' {
        $tmpDir = Join-Path ([System.IO.Path]::GetTempPath()) ("tb-s12-" + [guid]::NewGuid().ToString('N').Substring(0, 8))
        New-Item -ItemType Directory -Path $tmpDir -Force | Out-Null
        $rawZt = Join-Path $tmpDir 'zt.json'
        $rawScuba = Join-Path $tmpDir 'ScubaResults.json'
        try {
            [PSCustomObject]@{
                TenantId   = '00000000-0000-0000-0000-000000000002'
                Domain     = 'contoso.onmicrosoft.com'
                TenantInfo = [PSCustomObject]@{
                    TenantOverview = [PSCustomObject]@{ UserCount = 10; GuestCount = 0; GroupCount = 2; ApplicationCount = 2; DeviceCount = 2; ManagedDeviceCount = 2 }
                    OverviewCaMfaAllUsers = $null
                    DeviceOverview = $null
                    AgentOverview = $null
                    OverviewAuthMethodsPrivilegedUsers = $null
                }
                Tests = @(
                    [PSCustomObject]@{ TestId = '21808'; TestTitle = 'Restrict device code flow'; TestStatus = 'Passed'; TestRisk = 'High'; TestPillar = 'Identity'; TestCategory = 'CA'; TestSfiPillar = 'Identity'; TestImplementationCost = 'Low'; TestMinimumLicense = 'P1'; TestImpact = 'Low'; TestResult = 'OK'; TestDescription = 'Desc'; SkippedReason = '' }
                )
            } | ConvertTo-Json -Depth 10 | Set-Content -Path $rawZt -Encoding UTF8

            [PSCustomObject]@{
                Results = [PSCustomObject]@{
                    AAD = @(
                        [PSCustomObject]@{
                            Controls = @(
                                [PSCustomObject]@{ 'Control ID' = 'MS.AAD.3.9v1'; Requirement = 'Device code authentication SHOULD be blocked.'; Result = 'Fail'; Criticality = 'Should'; Details = 'Not blocked' }
                            )
                        }
                    )
                }
            } | ConvertTo-Json -Depth 10 | Set-Content -Path $rawScuba -Encoding UTF8

            $run = Invoke-TenantBriefAssessment -InputReportJson $rawZt -InputScubaJsonPath $rawScuba -OutputPath $tmpDir -Language tr -Framework All -NoBrowser
            $rep = Get-Content -LiteralPath $run.JsonPath -Raw -Encoding UTF8 | ConvertFrom-Json

            $rep.Summary.SourceControls | Should -Be 2
            $rep.Summary.UniqueControls | Should -Be 1
            $rep.Findings.Count | Should -Be 1
            $rep.Findings[0].CanonicalId | Should -Be 'TB-ID-DEVICE-CODE-FLOW'
            $rep.Findings[0].StatusConflict | Should -BeTrue
            $rep.Findings[0].Status | Should -Be 'Failed'

            # Framework scores must stay pre-correlation: ZeroTrust = 1/1 (100%), CISA SCuBA = 0/1 (0%)
            $ztFw = $rep.Frameworks | Where-Object { $_.Id -eq 'ZeroTrust' }
            $scFw = $rep.Frameworks | Where-Object { $_.Id -eq 'CISA_SCuBA' }
            $ztFw.Score | Should -Be 100
            $scFw.Score | Should -Be 0
        } finally {
            Remove-Item -Path $tmpDir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}
