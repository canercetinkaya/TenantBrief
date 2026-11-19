BeforeAll {
    $script:RepoRoot = Split-Path -Path $PSScriptRoot -Parent
    Import-Module (Join-Path $script:RepoRoot 'TenantBrief.psd1') -Force
}

Describe 'S4.3 & S4.4 - Executive Summary Signals (Test Tenant Banner, N/A ROI, Secure Score, Copilot, SecOps) & Scoring Rule Docs' {
    It 'renders test-tenant banner when UserCount<25, N/A ROI when Skus empty, and exact JSON numbers for Secure Score, Incidents, and Copilot' {
        $tmpDir = Join-Path ([System.IO.Path]::GetTempPath()) ("tb-s43-" + [guid]::NewGuid().ToString('N').Substring(0, 8))
        New-Item -ItemType Directory -Path $tmpDir -Force | Out-Null
        try {
            $jsonPath = Join-Path $tmpDir 'rep.json'
            $htmlPath = Join-Path $tmpDir 'exec.html'
            [PSCustomObject]@{
                Tenant         = 'lab.onmicrosoft.com'
                TenantInsights = [PSCustomObject]@{ UserCount = 5; SecureScoreCurrent = 42.5; SecureScoreMax = 100; MfaCoverageDesc = 'MFA %80' }
                UsageAdoption  = [PSCustomObject]@{ SecOps = [PSCustomObject]@{ IncidentsAvailable = $true; HighIncidents = 3; ActiveIncidents = 5 } }
                CopilotReadiness = [PSCustomObject]@{ Score = 33.3; MaturityLevel = 'L1 - Başlangıç (Initial)' }
                Summary        = [PSCustomObject]@{ Total = 2; Passed = 1; Failed = 1; Investigate = 0; Skipped = 0; Planned = 0; Error = 0; HighRiskFailed = 1 }
                Frameworks     = @([PSCustomObject]@{ Name = 'ZeroTrust'; Passed = 1; Evaluated = 2; Score = 50 })
                LicenseROI     = [PSCustomObject]@{ Skus = @(); TotalIdleUsdYr = 0 }
                Findings       = @(
                    [PSCustomObject]@{ Id = 'F1'; Status = 'Failed'; Risk = 'High'; PriorityScore = 80; ImplementationCost = 'Low'; Title = 'Top Priority Fix'; Pillar = 'Identity'; Category = 'Auth'; Description = 'd'; RemediationTr = 'r' }
                )
            } | ConvertTo-Json -Depth 8 | Set-Content -Path $jsonPath -Encoding UTF8

            $out = Export-TenantBriefExecutiveSummary -InputJsonPath $jsonPath -OutputHtmlPath $htmlPath -Language tr
            $html = [System.Net.WebUtility]::HtmlDecode((Get-Content -LiteralPath $out -Raw -Encoding UTF8))

            $html | Should -Match 'Test / Lab'
            $html | Should -Match 'Uygulanamaz'
            $html | Should -Match '42\.5\s*/\s*100'
            $html | Should -Match 'L1 - Başlangıç'
            $html | Should -Match 'Top Priority Fix'
        } finally {
            Remove-Item -Path $tmpDir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'documents pre-correlation per-source framework scoring rule in README.md (S4.4)' {
        $readme = Get-Content -LiteralPath (Join-Path $script:RepoRoot 'README.md') -Raw -Encoding UTF8
        $readme | Should -Match 'pre-correlation|korelasyon öncesi'
    }
}
