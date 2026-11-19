BeforeAll {
    $script:RepoRoot = Split-Path -Path $PSScriptRoot -Parent
    Import-Module (Join-Path $script:RepoRoot 'TenantBrief.psd1') -Force
}

Describe 'Sprint 7 - Accessibility (S7.1), SVG Charts (S7.2), Trend Tab (S7.3), Size Optimization (S7.4), A4 Print (S7.5)' {
    It 'includes accessibility landmarks, ARIA tablist/tabs, focus-visible styles, and SVG pillar + risk/effort heatmap containers' {
        $tpl = Get-Content -LiteralPath (Join-Path $script:RepoRoot 'assets/report-template.html') -Raw -Encoding UTF8
        $tpl | Should -Match 'role="tablist"'
        $tpl | Should -Match 'role="tab"'
        $tpl | Should -Match 'aria-selected='
        $tpl | Should -Match ':focus-visible'
        $tpl | Should -Match 'id="mainContent"'
        $tpl | Should -Match 'id="pillarSvgChart"'
        $tpl | Should -Match 'id="riskEffortHeatmap"'
        $tpl | Should -Match 'id="navTrend"'
        $tpl | Should -Match 'id="tab-trend"'
    }

    It 'computes Trend diff when -PreviousReportJson is provided and keeps Executive Summary A4 print-ready' {
        $tmpDir = Join-Path ([System.IO.Path]::GetTempPath()) ("tb-s7-trend-" + [guid]::NewGuid().ToString('N').Substring(0, 8))
        New-Item -ItemType Directory -Path $tmpDir -Force | Out-Null
        try {
            $prevJson = Join-Path $tmpDir 'prev.json'
            [PSCustomObject]@{
                GeneratedAt = '2026-10-01T10:00:00Z'
                Summary     = [PSCustomObject]@{ Total = 2; Passed = 0; Failed = 2 }
                Findings    = @(
                    [PSCustomObject]@{ Id = '21882'; CanonicalId = 'TB-ID-MFA-ALL-USERS'; Title = 'Require MFA'; Status = 'Failed'; Risk = 'High'; DomainPillar = 'Identity' },
                    [PSCustomObject]@{ Id = '21860'; CanonicalId = ''; Title = 'Block legacy auth'; Status = 'Passed'; Risk = 'High'; DomainPillar = 'Identity' }
                )
            } | ConvertTo-Json -Depth 6 | Set-Content -Path $prevJson -Encoding UTF8

            $currRaw = Join-Path $tmpDir 'curr-raw.json'
            [PSCustomObject]@{
                TenantId   = '00000000-0000-0000-0000-000000000073'
                Domain     = 'contoso.onmicrosoft.com'
                TenantInfo = [PSCustomObject]@{
                    TenantOverview = [PSCustomObject]@{ UserCount = 50; GuestCount = 2; GroupCount = 5; ApplicationCount = 5; DeviceCount = 10; ManagedDeviceCount = 8 }
                    OverviewCaMfaAllUsers = $null; DeviceOverview = $null; AgentOverview = $null; OverviewAuthMethodsPrivilegedUsers = $null
                }
                Tests = @(
                    [PSCustomObject]@{
                        TestId = '21882'; TestTitle = 'Require MFA for all users'; TestStatus = 'Passed'; TestRisk = 'High'
                        TestPillar = 'Identity'; TestCategory = 'CA'; TestSfiPillar = 'Identity'
                        TestImplementationCost = 'Low'; TestMinimumLicense = 'P1'; TestImpact = 'Low'
                        TestResult = 'MFA enforced'; TestDescription = 'MFA policy active'; SkippedReason = ''
                    },
                    [PSCustomObject]@{
                        TestId = '21860'; TestTitle = 'Block legacy auth'; TestStatus = 'Failed'; TestRisk = 'High'
                        TestPillar = 'Identity'; TestCategory = 'CA'; TestSfiPillar = 'Identity'
                        TestImplementationCost = 'Low'; TestMinimumLicense = 'P1'; TestImpact = 'Low'
                        TestResult = 'Legacy auth allowed'; TestDescription = 'Legacy auth open'; SkippedReason = ''
                    }
                )
            } | ConvertTo-Json -Depth 10 | Set-Content -Path $currRaw -Encoding UTF8

            $res = Invoke-TenantBriefAssessment -InputReportJson $currRaw -PreviousReportJson $prevJson -OutputPath $tmpDir -Language tr -Framework All -NoBrowser
            $rep = Get-Content -LiteralPath $res.JsonPath -Raw -Encoding UTF8 | ConvertFrom-Json
            $rep.Trend | Should -Not -BeNullOrEmpty
            @($rep.Trend.Improved).Count | Should -BeGreaterOrEqual 1
            @($rep.Trend.Regressed).Count | Should -BeGreaterOrEqual 1

            $execHtml = Get-Content -LiteralPath $res.ExecutiveSummaryPath -Raw -Encoding UTF8
            $execHtml | Should -Match '@page\s*\{\s*size:\s*A4'
            $execHtml | Should -Match 'break-inside:\s*avoid'
        } finally {
            Remove-Item -Path $tmpDir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}
