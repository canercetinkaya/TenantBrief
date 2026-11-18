BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '..\TenantBrief.psd1') -Force

    $script:FixturePath = Join-Path $PSScriptRoot 'fixtures\ZeroTrustAssessmentReport.sample.json'
    $script:OutDir = Join-Path ([System.IO.Path]::GetTempPath()) ("tb-pipeline-" + [guid]::NewGuid().ToString('N').Substring(0, 8))

    $script:Run = Invoke-TenantBriefAssessment `
        -InputReportJson $script:FixturePath `
        -OutputPath $script:OutDir `
        -Language tr `
        -Framework All `
        -Anonymize `
        -NoBrowser

    $script:Report = Get-Content -Path $script:Run.JsonPath -Raw -Encoding UTF8 | ConvertFrom-Json
}

AfterAll {
    if ($script:OutDir -and (Test-Path $script:OutDir)) {
        Remove-Item -Path $script:OutDir -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Describe 'Invoke-TenantBriefAssessment (offline pipeline)' {
    It 'writes the three report artifacts' {
        $script:Run.HtmlPath | Should -Exist
        $script:Run.JsonPath | Should -Exist
        $script:Run.ExecutiveSummaryPath | Should -Exist
        $script:Run.HtmlPath | Should -Match 'TenantBriefReport-TR\.html$'
        $script:Run.JsonPath | Should -Match 'TenantBriefReport-TR\.json$'
    }

    It 'correlates duplicate control titles reported by two engines' {
        # 'Ensure MFA is enforced for all users' exists in Identity (Passed) and CISA SCuBA (Failed)
        @($script:Report.Findings | Where-Object { $_.Title -eq 'Ensure MFA is enforced for all users' }).Count | Should -Be 1
    }

    It 'keeps the worst status when correlating a control' {
        $merged = $script:Report.Findings | Where-Object { $_.Title -eq 'Ensure MFA is enforced for all users' }
        $merged.Status | Should -Be 'Failed'
    }

    It 'summarizes the fixture without dropping findings' {
        $script:Report.Summary.Total | Should -Be 15
        $script:Report.Summary.Passed | Should -Be 3
        $script:Report.Summary.Failed | Should -Be 6
        $script:Report.Summary.Investigate | Should -Be 2
        $script:Report.Summary.Skipped | Should -Be 3
        $script:Report.Summary.Error | Should -Be 1
        $script:Report.Summary.HighRiskFailed | Should -Be 2
    }

    It 'keeps the summary consistent with the finding statuses' {
        $s = $script:Report.Summary
        ($s.Passed + $s.Failed + $s.Investigate + $s.Skipped + $s.Planned + $s.Error) | Should -Be $s.Total
    }

    It 'keeps engine errors visible instead of dropping them' {
        $errors = @($script:Report.Findings | Where-Object { $_.Status -eq 'Error' })
        $errors.Count | Should -Be 1
        $errors[0].Id | Should -Be 'MT.9001'
        $zt = $script:Report.Frameworks | Where-Object { $_.Id -eq 'ZeroTrust' }
        $zt.Errors | Should -Be 1
        # An unmeasured control must not be counted as a pass.
        $zt.Score | Should -Be 25
    }

    It 'scores every selected compliance framework once' {
        @($script:Report.Frameworks).Count | Should -Be 5
        foreach ($fw in $script:Report.Frameworks) {
            $fw.Evaluated | Should -BeGreaterThan 0
            $fw.Score | Should -BeGreaterOrEqual 0
            $fw.Score | Should -BeLessOrEqual 100
        }
    }

    It 'scores correlated controls inside every framework they belong to' {
        # Coverage is read from data/framework-mappings.json (scoredPillars), not hardcoded.
        $byId = @{}
        foreach ($fw in $script:Report.Frameworks) { $byId[$fw.Id] = $fw }
        $byId['ZeroTrust'].Evaluated | Should -Be 12
        $byId['ZeroTrust'].Score | Should -Be 25
        $byId['ISO27001'].Evaluated | Should -Be 12
        $byId['NIST_CSF_2'].Evaluated | Should -Be 10
        $byId['NIST_CSF_2'].Score | Should -Be 20
        $byId['CIS_M365'].Evaluated | Should -Be 9
        $byId['CIS_M365'].Score | Should -Be 11.1
        $byId['KVKK_TR'].Evaluated | Should -Be 10
        $byId['KVKK_TR'].Score | Should -Be 10
    }

    It 'writes a run manifest with every stage accounted for' {
        $manifestPath = Join-Path $script:OutDir 'run-manifest.json'
        $manifestPath | Should -Exist
        $m = Get-Content -Path $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
        $m.Status | Should -Be 'completed'
        @($m.Stages).Count | Should -Be 5
        ($m.Stages | Where-Object { $_.Stage -eq 1 }).Status | Should -Be 'skipped'
        ($m.Stages | Where-Object { $_.Stage -eq 2 }).Status | Should -Be 'skipped'
        ($m.Stages | Where-Object { $_.Stage -eq 5 }).Status | Should -Be 'completed'
    }

    It 'renders no diagnostics banner on a clean run' {
        @($script:Report.Diagnostics).Count | Should -Be 0
        (Get-Content -Path $script:Run.HtmlPath -Raw -Encoding UTF8) | Should -Not -Match 'kismi veriyle' 
    }

    It 'anonymizes the tenant identifier' {
        $script:Report.Tenant | Should -Match 'Anonymized'
        $script:Report.Tenant | Should -Not -Match 'fabrikam'
        (Get-Content -Path $script:Run.HtmlPath -Raw -Encoding UTF8) | Should -Not -Match 'fabrikam\.onmicrosoft\.com'
    }

    It 'maps skipped controls to license blind spots' {
        @($script:Report.LicenseROI.Gaps).Count | Should -BeGreaterThan 0
        ($script:Report.LicenseROI.Gaps | ForEach-Object { $_.License }) -join '|' | Should -Match 'Defender for Endpoint'
        $script:Report.LicenseROI.Summary | Should -Match 'atlandı'
    }

    It 'builds a three-phase 30-60-90 day roadmap' {
        @($script:Report.Roadmap).Count | Should -Be 3
        $script:Report.Roadmap[0].Count | Should -Be $script:Report.Summary.HighRiskFailed
    }

    It 'produces Turkish remediation guidance and localized impact labels' {
        $failed = $script:Report.Findings | Where-Object { $_.Status -eq 'Failed' } | Select-Object -First 1
        $failed.RemediationTr | Should -Match 'Denetim \(Report-only\) kipinde pilot gruba'
        ($script:Report.Findings | Where-Object { $_.Impact -eq 'Yüksek' }).Count | Should -BeGreaterThan 0
    }

    It 'keeps the machine-readable contract in English' {
        # Risk/Status stay English so Compare-TenantBriefReports and the HTML filters keep working.
        ($script:Report.Findings | Where-Object { $_.Risk -notin @('High', 'Medium', 'Low') }).Count | Should -Be 0
        ($script:Report.Findings | Where-Object { $_.Status -notin @('Passed', 'Failed', 'Skipped', 'Investigate', 'Planned', 'Error') }).Count | Should -Be 0
    }

    It 'embeds the report payload inside the standalone HTML file' {
        $html = Get-Content -Path $script:Run.HtmlPath -Raw -Encoding UTF8
        $html.Length | Should -BeGreaterThan 50000
        $html | Should -Match 'TenantBrief Raporu'
        $html | Should -Not -Match '\{\{LANG\}\}'
        $html | Should -Not -Match '\{\{REPORT_JSON\}\}'
    }

    It 'keeps the executive summary offline and printable' {
        $exec = Get-Content -Path $script:Run.ExecutiveSummaryPath -Raw -Encoding UTF8
        $exec | Should -Match 'Yönetici Özeti'
        $exec | Should -Match '@media print'
        $exec | Should -Match 'TenantBrief'
    }
}

Describe 'Invoke-TenantBriefAssessment framework selection' {
    BeforeAll {
        $script:FwOutDir = Join-Path ([System.IO.Path]::GetTempPath()) ("tb-fw-" + [guid]::NewGuid().ToString('N').Substring(0, 8))
        $script:FwRun = Invoke-TenantBriefAssessment -InputReportJson $script:FixturePath -OutputPath $script:FwOutDir -Language en -Framework ISO27001 -NoBrowser
        $script:FwReport = Get-Content -Path $script:FwRun.JsonPath -Raw -Encoding UTF8 | ConvertFrom-Json
    }

    AfterAll {
        if ($script:FwOutDir -and (Test-Path $script:FwOutDir)) {
            Remove-Item -Path $script:FwOutDir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'scores only the requested framework' {
        @($script:FwReport.Frameworks).Count | Should -Be 1
        $script:FwReport.Frameworks[0].Id | Should -Be 'ISO27001'
        $script:FwReport.Framework | Should -Be 'ISO27001'
    }

    It 'reports the un-anonymized tenant name when -Anonymize is omitted' {
        $script:FwReport.Tenant | Should -Be 'fabrikam.onmicrosoft.com'
    }

    It 'keeps English labels' {
        $script:FwReport.Labels.TotalChecks | Should -Be 'Total Checks'
        $script:FwRun.HtmlPath | Should -Match 'TenantBriefReport-EN\.html$'
    }
}

Describe 'Compare-TenantBriefReports' {
    BeforeAll {
        $script:CompareDir = Join-Path ([System.IO.Path]::GetTempPath()) ("tb-compare-" + [guid]::NewGuid().ToString('N').Substring(0, 8))
        $null = New-Item -ItemType Directory -Path $script:CompareDir -Force

        $baseline = Get-Content -Path $script:Run.JsonPath -Raw -Encoding UTF8 | ConvertFrom-Json
        $current = Get-Content -Path $script:Run.JsonPath -Raw -Encoding UTF8 | ConvertFrom-Json

        ($current.Findings | Where-Object { $_.Id -eq 'MT.1002' }).Status = 'Passed'
        ($current.Findings | Where-Object { $_.Id -eq 'MT.3001' }).Status = 'Failed'

        $script:BaselineJson = Join-Path $script:CompareDir 'baseline.json'
        $script:CurrentJson = Join-Path $script:CompareDir 'current.json'
        $baseline | ConvertTo-Json -Depth 8 | Set-Content -Path $script:BaselineJson -Encoding UTF8
        $current | ConvertTo-Json -Depth 8 | Set-Content -Path $script:CurrentJson -Encoding UTF8

        $script:Diff = Compare-TenantBriefReports -BaselineJsonPath $script:BaselineJson -CurrentJsonPath $script:CurrentJson
    }

    AfterAll {
        if ($script:CompareDir -and (Test-Path $script:CompareDir)) {
            Remove-Item -Path $script:CompareDir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'detects improvements and regressions' {
        $script:Diff.ImprovedCount | Should -Be 1
        $script:Diff.RegressedCount | Should -Be 1
        $script:Diff.Improved[0].Id | Should -Be 'MT.1002'
        $script:Diff.Regressed[0].Id | Should -Be 'MT.3001'
    }

    It 'counts untouched controls' {
        $script:Diff.UnchangedCount | Should -Be ($script:Diff.CurrentTotal - 2)
    }

    It 'fails fast on a missing baseline file' {
        { Compare-TenantBriefReports -BaselineJsonPath 'Z:\does\not\exist.json' -CurrentJsonPath $script:CurrentJson } | Should -Throw '*not found*'
    }
}

Describe 'Export-TenantBriefExecutiveSummary' {
    It 'generates a standalone brief from any report JSON' {
        $target = Join-Path ([System.IO.Path]::GetTempPath()) ("tb-exec-" + [guid]::NewGuid().ToString('N').Substring(0, 8) + '.html')
        try {
            $path = Export-TenantBriefExecutiveSummary -InputJsonPath $script:Run.JsonPath -OutputHtmlPath $target -Language tr
            $path | Should -Exist
            $content = Get-Content -Path $target -Raw -Encoding UTF8
            $content | Should -Match 'Framework'
            $content | Should -Match '<table'
        } finally {
            Remove-Item -Path $target -Force -ErrorAction SilentlyContinue
        }
    }
}

Describe 'Stage failure handling' {
    It 'records a diagnostic instead of swallowing the error' {        $out = Join-Path ([System.IO.Path]::GetTempPath()) ("tb-diag-" + [guid]::NewGuid().ToString('N').Substring(0, 8))
        try {
            $result = InModuleScope TenantBrief -Parameters @{ Fixture = $script:FixturePath; Out = $out } {
                param($Fixture, $Out)
                Mock Get-TenantBriefCopilotReadiness { throw 'simulated copilot outage' }
                Invoke-TenantBriefAssessment -InputReportJson $Fixture -OutputPath $Out -Language tr -NoBrowser
            }

            $rep = Get-Content -Path $result.JsonPath -Raw -Encoding UTF8 | ConvertFrom-Json
            @($rep.Diagnostics).Count | Should -BeGreaterThan 0
            ($rep.Diagnostics | ForEach-Object { $_.Message }) -join '|' | Should -Match 'simulated copilot outage'
            $rep.Run.Status | Should -Be 'partial'

            $html = Get-Content -Path $result.HtmlPath -Raw -Encoding UTF8
            $html | Should -Match 'kismi veriyle'
            $html | Should -Match 'simulated copilot outage'

            $m = Get-Content -Path (Join-Path $out 'run-manifest.json') -Raw -Encoding UTF8 | ConvertFrom-Json
            $m.Status | Should -Be 'partial'
            @($m.Diagnostics).Count | Should -BeGreaterThan 0

            # The report is still produced from the data that did work.
            $rep.Summary.Total | Should -Be 15
        } finally {
            Remove-Item -Path $out -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

Describe '-Resume' {
    BeforeAll {
        $script:ResumeRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("tb-resume-" + [guid]::NewGuid().ToString('N').Substring(0, 8))
        $script:ResumeRunDir = Join-Path $script:ResumeRoot 'tenant_20260101_0000'
        $exportDir = Join-Path $script:ResumeRunDir 'raw-zt\zt-export'
        $null = New-Item -ItemType Directory -Path $exportDir -Force
        Copy-Item -Path $script:FixturePath -Destination (Join-Path $exportDir 'ZeroTrustAssessmentReport.json')

        $script:ResumeRun = Invoke-TenantBriefAssessment -Resume -OutputPath $script:ResumeRoot -Language en -NoBrowser
        $script:ResumeReport = Get-Content -Path $script:ResumeRun.JsonPath -Raw -Encoding UTF8 | ConvertFrom-Json
    }

    AfterAll {
        if ($script:ResumeRoot) { Remove-Item -Path $script:ResumeRoot -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'reuses stage 1 output from the interrupted run folder' {
        $script:ResumeRun.JsonPath | Should -Match 'tenant_20260101_0000'
        $script:ResumeReport.Run.Resumed | Should -BeTrue
        ($script:ResumeReport.Run.Stages | Where-Object { $_.Stage -eq 1 }).Status | Should -Be 'skipped'
        @($script:ResumeReport.Diagnostics | Where-Object { $_.Component -eq 'Resume' }).Count | Should -Be 1
    }

    It 'still produces the complete report set' {
        $script:ResumeRun.HtmlPath | Should -Exist
        $script:ResumeRun.ExecutiveSummaryPath | Should -Exist
        $script:ResumeReport.Summary.Total | Should -Be 15
    }

    It 'does not treat a resumed stage as a degraded run' {
        $script:ResumeReport.Run.Status | Should -Be 'completed'
        (Get-Content -Path $script:ResumeRun.HtmlPath -Raw -Encoding UTF8) | Should -Not -Match 'kismi veriyle'
        (Get-Content -Path $script:ResumeRun.HtmlPath -Raw -Encoding UTF8) | Should -Match 'was not rescanned'
    }

    It 'fails fast when there is nothing to resume' {
        $empty = Join-Path ([System.IO.Path]::GetTempPath()) ("tb-empty-" + [guid]::NewGuid().ToString('N').Substring(0, 8))
        $null = New-Item -ItemType Directory -Path $empty -Force
        try {
            { Invoke-TenantBriefAssessment -Resume -OutputPath $empty -NoBrowser } | Should -Throw '*ZeroTrustAssessmentReport.json*'
        } finally {
            Remove-Item -Path $empty -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

Describe 'Remediation payload' {
    It 'writes remediation text only for actionable findings' {
        $actionable = @($script:Report.Findings | Where-Object { $_.Status -in @('Failed', 'Investigate') })
        $others = @($script:Report.Findings | Where-Object { $_.Status -notin @('Failed', 'Investigate') })

        $actionable.Count | Should -BeGreaterThan 0
        foreach ($f in $actionable) { $f.RemediationTr | Should -Not -BeNullOrEmpty }
        foreach ($f in $others) { $f.RemediationTr | Should -Be '' }
    }

    It 'keeps the report payload free of repeated guidance' {
        $remTotal = ($script:Report.Findings | ForEach-Object { ($_.RemediationTr + '').Length } | Measure-Object -Sum).Sum
        # The dead weight was ~75k characters for 360 findings; per finding it must stay well below 1k.
        ($remTotal / $script:Report.Findings.Count) | Should -BeLessThan 700
    }
}

Describe 'Executive summary prioritisation' {
    BeforeAll {
        $script:ExecDir = Join-Path ([System.IO.Path]::GetTempPath()) ("tb-exec2-" + [guid]::NewGuid().ToString('N').Substring(0, 8))
        $null = New-Item -ItemType Directory -Path $script:ExecDir -Force

        $findings = @(
            [PSCustomObject]@{ Id = 'ZZZ-EXPENSIVE'; Status = 'Failed'; Risk = 'High'; ImplementationCost = 'High'; Title = 'Expensive high-risk fix'; Pillar = 'Identity'; Category = 'Auth'; Description = 'x'; RemediationTr = 'r' }
            [PSCustomObject]@{ Id = 'AAA-CHEAP'; Status = 'Failed'; Risk = 'High'; ImplementationCost = 'Low'; Title = 'Cheap high-risk fix'; Pillar = 'Identity'; Category = 'Auth'; Description = 'x'; RemediationTr = 'r' }
            [PSCustomObject]@{ Id = 'MMM-MEDIUM'; Status = 'Failed'; Risk = 'High'; ImplementationCost = 'Medium'; Title = 'Medium high-risk fix'; Pillar = 'Identity'; Category = 'Auth'; Description = 'x'; RemediationTr = 'r' }
            [PSCustomObject]@{ Id = 'NNN-UNKNOWN'; Status = 'Failed'; Risk = 'High'; ImplementationCost = 'Unknown'; Title = 'Unknown cost fix'; Pillar = 'Identity'; Category = 'Auth'; Description = 'x'; RemediationTr = 'r' }
        )
        $lens = [PSCustomObject]@{
            Tenant    = 'contoso.onmicrosoft.com'
            Summary   = [PSCustomObject]@{ Total = 4; Passed = 0; Failed = 4; Investigate = 0; Skipped = 0; Planned = 0; Error = 0; HighRiskFailed = 4 }
            Frameworks = @([PSCustomObject]@{ Name = 'ZeroTrust'; Passed = 0; Evaluated = 4; Score = 0 })
            LicenseROI = [PSCustomObject]@{ TotalIdleUsdYr = 0 }
            Findings  = $findings
        }
        $script:LensJson = Join-Path $script:ExecDir 'lens.json'
        $lens | ConvertTo-Json -Depth 6 | Set-Content -Path $script:LensJson -Encoding UTF8

        $script:ExecHtml = Join-Path $script:ExecDir 'exec.html'
        $null = Export-TenantBriefExecutiveSummary -InputJsonPath $script:LensJson -OutputHtmlPath $script:ExecHtml -Language en
        $script:ExecContent = Get-Content -Path $script:ExecHtml -Raw -Encoding UTF8
    }

    AfterAll {
        if ($script:ExecDir) { Remove-Item -Path $script:ExecDir -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'orders high-risk remediations by effort, cheapest first' {
        $cheap = $script:ExecContent.IndexOf('Cheap high-risk fix')
        $medium = $script:ExecContent.IndexOf('Medium high-risk fix')
        $unknown = $script:ExecContent.IndexOf('Unknown cost fix')
        $expensive = $script:ExecContent.IndexOf('Expensive high-risk fix')

        $cheap | Should -BeGreaterThan 0
        $cheap | Should -BeLessThan $medium
        $medium | Should -BeLessThan $expensive
        # Unknown effort is listed last: an unknown cost is not a "quick win" promise.
        $expensive | Should -BeLessThan $unknown
    }

    It 'says so in the heading' {
        $script:ExecContent | Should -Match 'lowest effort first'
    }
}

Describe 'Multi-engine Maester & EntraFalcon JSON ingestion' {
    BeforeAll {
        $script:MultiDir = Join-Path ([System.IO.Path]::GetTempPath()) ("tb-multi-" + [guid]::NewGuid().ToString('N').Substring(0, 8))
        $null = New-Item -ItemType Directory -Path $script:MultiDir -Force

        $script:MaesterSample = Join-Path $script:MultiDir 'maester.json'
        [PSCustomObject]@{
            Tests = @(
                [PSCustomObject]@{
                    Id           = 'EIDSCA.AP01'
                    Title        = 'EIDSCA.AP01: Disable default user consent'
                    Result       = 'Failed'
                    Severity     = 'High'
                    Block        = 'Consent'
                    ResultDetail = [PSCustomObject]@{ TestDescription = 'Restrict app consent'; TestResult = 'User consent enabled' }
                }
            )
        } | ConvertTo-Json -Depth 5 | Set-Content -Path $script:MaesterSample -Encoding UTF8

        $script:FalconSample = Join-Path $script:MultiDir 'tenant_findings_all_sample.json'
        @(
            [PSCustomObject]@{
                FindingId       = 'ROLE-001'
                Title           = 'Permanent Global Admin assignment detected'
                Category        = 'Entra Roles'
                Severity        = 3
                Status          = 'Vulnerable'
                Description     = 'Convert permanent GA to PIM eligible.'
                Threat          = 'Permanent privilege exposure'
                Remediation     = 'Enable PIM eligible assignment'
                AffectedObjects = @(@{ id = 'ga1' })
            }
        ) | ConvertTo-Json -Depth 5 | Set-Content -Path $script:FalconSample -Encoding UTF8

        $script:MultiRun = Invoke-TenantBriefAssessment `
            -InputReportJson $script:FixturePath `
            -InputMaesterJsonPath $script:MaesterSample `
            -InputEntraFalconJsonPath $script:FalconSample `
            -OutputPath $script:MultiDir `
            -Language tr `
            -Framework All `
            -Anonymize `
            -NoBrowser

        $script:MultiReport = Get-Content -Path $script:MultiRun.JsonPath -Raw -Encoding UTF8 | ConvertFrom-Json
    }

    AfterAll {
        if ($script:MultiDir) { Remove-Item -Path $script:MultiDir -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'merges Maester and EntraFalcon controls into findings and summary' {
        $script:MultiReport.Summary.Total | Should -Be 17
        ($script:MultiReport.Findings | Where-Object { $_.Pillar -match 'Maester' }).Count | Should -Be 1
        ($script:MultiReport.Findings | Where-Object { $_.Pillar -eq 'EntraFalcon' }).Count | Should -Be 1
        $ef = $script:MultiReport.Findings | Where-Object { $_.Id -eq 'EF-ROLE-001' }
        $ef.RequiredRole | Should -Be 'Conditional Access Administrator / Security Administrator'
        $ef.DomainPillar | Should -Be 'Identity'
        $ef.Sources | Should -Contain 'EntraFalcon'
        $ei = $script:MultiReport.Findings | Where-Object { $_.Id -eq 'EIDSCA.AP01' }
        $ei.Sources | Should -Contain 'EIDSCA'
        $ei.DomainPillar | Should -Be 'Identity'
    }

    It 'attaches canonical DomainPillar, Sources and CorrelatedIds on correlated controls' {
        $merged = $script:Report.Findings | Where-Object { $_.Title -eq 'Ensure MFA is enforced for all users' }
        $merged.DomainPillar | Should -Be 'Identity'
        $merged.Sources | Should -Contain 'ZeroTrust'
        $merged.Sources | Should -Contain 'CISA SCuBA'
        $merged.CorrelatedIds | Should -Contain 'MT.1001'
        $merged.CorrelatedIds | Should -Contain 'SCUBA-AAD-1'

        $html = Get-Content -Path $script:Run.HtmlPath -Raw -Encoding UTF8
        $html | Should -Match 'id="sourceCoverageCard"'
        $html | Should -Match 'id="sourceChips"'
    }
}
