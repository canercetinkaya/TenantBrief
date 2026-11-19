BeforeAll {
    $script:RepoRoot = Split-Path -Path $PSScriptRoot -Parent
    Import-Module (Join-Path $script:RepoRoot 'TenantBrief.psd1') -Force
    $script:TemplatePath = Join-Path $script:RepoRoot 'assets\report-template.html'
}

Describe 'S5.2 & S5.3 - Content-Security-Policy Meta & Deep -Anonymize Masking' {
    It 'embeds strict offline Content-Security-Policy meta tag in report-template.html and Executive Summary' {
        $tpl = Get-Content -LiteralPath $script:TemplatePath -Raw -Encoding UTF8
        $tpl | Should -Match 'http-equiv="Content-Security-Policy"'
        $tpl | Should -Match "default-src 'none'"
        $tpl | Should -Match "connect-src 'none'"
    }

    It 'masks UPNs, emails, GUIDs, and tenant domains across Result, Description, SkippedReason, and HTML when -Anonymize is set' {
        $tmpDir = Join-Path ([System.IO.Path]::GetTempPath()) ("tb-s53-" + [guid]::NewGuid().ToString('N').Substring(0, 8))
        New-Item -ItemType Directory -Path $tmpDir -Force | Out-Null
        $rawZt = Join-Path $tmpDir 'zt.json'
        $secrets = @(
            'ceo.secret@fabrikam.corp',
            '11111111-2222-3333-4444-555555555555',
            'fabrikam.corp',
            'admin.breakglass@fabrikam.onmicrosoft.com',
            '99999999-aaaa-bbbb-cccc-dddddddddddd'
        )
        try {
            [PSCustomObject]@{
                TenantId   = '11111111-2222-3333-4444-555555555555'
                Domain     = 'fabrikam.corp'
                TenantInfo = [PSCustomObject]@{
                    TenantOverview = [PSCustomObject]@{ UserCount = 50; GuestCount = 2; GroupCount = 5; ApplicationCount = 5; DeviceCount = 10; ManagedDeviceCount = 10 }
                    OverviewCaMfaAllUsers = [PSCustomObject]@{ description = 'Policy 99999999-aaaa-bbbb-cccc-dddddddddddd covers fabrikam.corp' }
                    DeviceOverview = $null; AgentOverview = $null; OverviewAuthMethodsPrivilegedUsers = $null
                }
                Tests = @(
                    [PSCustomObject]@{
                        TestId = '21796'; TestTitle = 'Legacy auth'; TestStatus = 'Failed'; TestRisk = 'High'
                        TestPillar = 'Identity'; TestCategory = 'CA'; TestSfiPillar = 'Identity'
                        TestImplementationCost = 'Low'; TestMinimumLicense = 'P1'; TestImpact = 'Low'
                        TestResult = 'User ceo.secret@fabrikam.corp signed in via app 11111111-2222-3333-4444-555555555555 on fabrikam.corp'
                        TestDescription = 'Exclude admin.breakglass@fabrikam.onmicrosoft.com from policy 99999999-aaaa-bbbb-cccc-dddddddddddd'
                        SkippedReason = 'Scope missing for ceo.secret@fabrikam.corp'
                    }
                )
            } | ConvertTo-Json -Depth 10 | Set-Content -Path $rawZt -Encoding UTF8

            $run = Invoke-TenantBriefAssessment -InputReportJson $rawZt -OutputPath $tmpDir -Language tr -Framework All -Anonymize -NoBrowser
            $jsonTxt = Get-Content -LiteralPath $run.JsonPath -Raw -Encoding UTF8
            $htmlTxt = Get-Content -LiteralPath $run.HtmlPath -Raw -Encoding UTF8
            $execTxt = Get-Content -LiteralPath $run.ExecutiveSummaryPath -Raw -Encoding UTF8

            $execTxt | Should -Match 'http-equiv="Content-Security-Policy"'
            $execTxt | Should -Match "script-src 'none'"

            foreach ($sec in $secrets) {
                $jsonTxt | Should -Not -Match ([regex]::Escape($sec)) -Because "JSON must mask sensitive value '$sec'"
                $htmlTxt | Should -Not -Match ([regex]::Escape($sec)) -Because "HTML must mask sensitive value '$sec'"
                $execTxt | Should -Not -Match ([regex]::Escape($sec)) -Because "Executive Summary must mask sensitive value '$sec'"
            }
        } finally {
            Remove-Item -Path $tmpDir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}
