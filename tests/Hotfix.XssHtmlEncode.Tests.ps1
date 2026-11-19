BeforeAll {
    $script:RepoRoot = Split-Path -Path $PSScriptRoot -Parent
    Import-Module (Join-Path $script:RepoRoot 'TenantBrief.psd1') -Force
    $script:TemplatePath = Join-Path $script:RepoRoot 'assets\report-template.html'
}

Describe 'Hotfix v1.0.1 - XSS, HtmlEncode, U+2028/2029, Depth and innerHTML audit (S1.0)' {
    It 'escapes closing script tags, onerror payloads, and U+2028/U+2029 in main HTML report and Executive Summary' {
        $tmpDir = Join-Path ([System.IO.Path]::GetTempPath()) ("tb-xss-" + [guid]::NewGuid().ToString('N').Substring(0, 8))
        New-Item -ItemType Directory -Path $tmpDir -Force | Out-Null
        $rawZt = Join-Path $tmpDir 'ZeroTrustAssessmentReport.json'
        $lsChar = [string][char]0x2028
        $psChar = [string][char]0x2029
        $xssTitle = "</script><script>alert(1)</script><img src=x onerror=alert(1)> LineSep${lsChar}ParaSep${psChar}"
        $xssCat   = '<svg onload=alert(2)>EvilCategory'
        $xssDom   = '<img src=x onerror=alert(3)>contoso.onmicrosoft.com'
        try {
            [PSCustomObject]@{
                TenantId   = '00000000-0000-0000-0000-000000000001'
                TenantName = $xssDom
                Domain     = $xssDom
                TenantInfo = [PSCustomObject]@{
                    TenantOverview = [PSCustomObject]@{ UserCount = 5; GuestCount = 0; GroupCount = 1; ApplicationCount = 1; DeviceCount = 1; ManagedDeviceCount = 1 }
                    OverviewCaMfaAllUsers = [PSCustomObject]@{ description = '<img src=x onerror=alert(7)>MFA' }
                    DeviceOverview = [PSCustomObject]@{ DeviceCompliance = $null }
                    AgentOverview = $null
                    OverviewAuthMethodsPrivilegedUsers = $null
                }
                Tests = @(
                    [PSCustomObject]@{
                        TestId                 = '99901'
                        TestTitle              = $xssTitle
                        TestStatus             = 'Failed'
                        TestRisk               = 'High'
                        TestPillar             = 'Identity'
                        TestCategory           = $xssCat
                        TestSfiPillar          = 'Protect identities and secrets'
                        TestImplementationCost = 'Low'
                        TestMinimumLicense     = 'P1" onmouseover="alert(6)'
                        TestImpact             = 'Low'
                        TestResult             = '<img src=x onerror=alert(4)>'
                        TestDescription        = '**Remediation action** Fix <script>alert(5)</script> now.'
                        SkippedReason          = ''
                    }
                )
            } | ConvertTo-Json -Depth 10 | Set-Content -Path $rawZt -Encoding UTF8

            $res = Invoke-TenantBriefAssessment -InputReportJson $rawZt -OutputPath $tmpDir -Language tr -Framework All -NoBrowser
            $mainHtml = Get-Content -LiteralPath $res.HtmlPath -Raw -Encoding UTF8
            $execHtml = Get-Content -LiteralPath $res.ExecutiveSummaryPath -Raw -Encoding UTF8

            # Main HTML: embedded JSON must use EscapeHtml (\u003c), escape U+2028/U+2029, and HtmlEncode {{TITLE}}/{{SUBTITLE}}
            $mainHtml | Should -Not -Match '</script><script>alert\(1\)'
            $mainHtml | Should -Not -Match '<img src=x onerror=alert\('
            $mainHtml.Contains([char]0x2028) | Should -BeFalse
            $mainHtml.Contains([char]0x2029) | Should -BeFalse

            # Executive Summary HTML: must HtmlEncode all dynamic tenant fields
            $execHtml | Should -Not -Match '<script>alert\(1\)'
            $execHtml | Should -Not -Match '<img src=x onerror='
            $execHtml | Should -Not -Match '<svg onload='
            $execHtml | Should -Match '&lt;script&gt;alert\(1\)&lt;/script&gt;'
        } finally {
            Remove-Item -Path $tmpDir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'does not truncate deeply nested objects beyond Depth 6 in serialized JSON' {
        $deepObj = [PSCustomObject]@{
            L1 = [PSCustomObject]@{
                L2 = [PSCustomObject]@{
                    L3 = [PSCustomObject]@{
                        L4 = [PSCustomObject]@{
                            L5 = [PSCustomObject]@{
                                L6 = [PSCustomObject]@{
                                    L7 = [PSCustomObject]@{
                                        Leaf = 'DEEP-VALUE-OK'
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
        $psmText = Get-Content -LiteralPath (Join-Path $script:RepoRoot 'TenantBrief.psm1') -Raw -Encoding UTF8
        # Verify report JSON serialization does not use Depth 6
        $depth6Count = ([regex]::Matches($psmText, '\$reportObj \| ConvertTo-Json -Depth 6')).Count
        $depth6Count | Should -Be 0
        $json = $deepObj | ConvertTo-Json -Depth 12 -Compress -EscapeHandling EscapeHtml
        $json | Should -Match 'DEEP-VALUE-OK'
        $json | Should -Not -Match 'System\.Management\.Automation\.PSCustomObject'
    }

    It 'ensures report-template.html escapes single quotes in esc() and has no raw string interpolations in onclick attributes or innerHTML sinks' {
        $html = Get-Content -LiteralPath $script:TemplatePath -Raw -Encoding UTF8

        # 1. esc() must escape single quotes too
        $html | Should -Match "replace\(/&/g,'&amp;'\)[\s\S]*replace\(/'/g,'&#39;'\)"

        # 2. No onclick="..." should interpolate raw JS string variables like '${q}', '${filterTok}', '${esc(src)}'
        $unsafeOnclick = [regex]::Matches($html, 'onclick="[^"]*\$\{(?:q|filterTok|esc\([^)]+\))\}[^"]*"')
        $unsafeOnclick.Count | Should -Be 0

        # 3. Inside HTML-building template lines (excluding search haystack `const hay =`), no untrusted finding/tenant string field should be interpolated without esc() or renderMd()
        $lines = $html -split '\r?\n'
        $violations = New-Object System.Collections.Generic.List[string]
        for ($i = 0; $i -lt $lines.Count; $i++) {
            $ln = $lines[$i]
            if ($ln -match 'const hay\s*=') { continue }
            if ($ln -match '\.textContent\s*=') { continue }
            $m = [regex]::Match($ln, '\$\{(?:f|x|k|c|g|a|site|o)\.(?:Title|Id|Category|Result|Description|RemediationTr|SiteName|SiteUrl|AgentName|Owner|ProductName|Pair|Redundant|Reason|License|Note|Name|Detail|Explanation|Warning)\}')
            if ($m.Success) {
                $violations.Add(("L{0}: {1}" -f ($i + 1), $m.Value))
            }
        }
        $violations.Count | Should -Be 0
    }
}
