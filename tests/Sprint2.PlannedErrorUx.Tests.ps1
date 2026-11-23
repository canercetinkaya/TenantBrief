BeforeAll {
    $script:RepoRoot = Split-Path -Path $PSScriptRoot -Parent
    Import-Module (Join-Path $script:RepoRoot 'TenantBrief.psd1') -Force
    $script:TemplatePath = Join-Path $script:RepoRoot 'assets\report-template.html'
}

Describe 'S2.5 - Planned Upstream List & Error Permission Action Card' {
    It 'populates ErrorRemedy for 403/Forbidden Error findings and renders plannedUpstreamCard + errorActionCard in template' {
        InModuleScope TenantBrief {
            $tests = @(
                [PSCustomObject]@{
                    TestId = 'MT.9001'; TestTitle = 'Conditional Access check'; TestStatus = 'Error'
                    TestRisk = 'Medium'; TestPillar = 'Identity'; TestCategory = 'CA'
                    TestResult = 'HTTP 403 Forbidden: Authorization_RequestDenied (Policy.Read.All)'
                }
            )
            $f = @(New-TenantBriefFindings -Tests $tests -Language tr)
            $f[0].PSObject.Properties['ErrorRemedy'] | Should -Not -BeNullOrEmpty
            $f[0].ErrorRemedy | Should -Match '403|Graph|yetki|izin|Policy\.Read\.All'
        }

        $html = Get-Content -LiteralPath $script:TemplatePath -Raw -Encoding UTF8
        $html | Should -Match 'plannedUpstreamCard'
        $html | Should -Match 'errorActionCard'
    }
}
