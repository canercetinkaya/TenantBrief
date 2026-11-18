BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '..\ZeroTrustLens.psd1') -Force

    $script:FixturePath = Join-Path $PSScriptRoot 'fixtures\ZeroTrustAssessmentReport.sample.json'
    $script:OutDir = Join-Path ([System.IO.Path]::GetTempPath()) ("ztl-pipeline-" + [guid]::NewGuid().ToString('N').Substring(0, 8))

    $script:Run = Invoke-ZtLensAssessment `
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

Describe 'Invoke-ZtLensAssessment (offline pipeline)' {
    It 'writes the three report artifacts' {
        $script:Run.HtmlPath | Should -Exist
        $script:Run.JsonPath | Should -Exist
        $script:Run.ExecutiveSummaryPath | Should -Exist
        $script:Run.HtmlPath | Should -Match 'ZeroTrustLensReport-TR\.html$'
        $script:Run.JsonPath | Should -Match 'ZeroTrustLensReport-TR\.json$'
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
        # Risk/Status stay English so Compare-ZtLensReports and the HTML filters keep working.
        ($script:Report.Findings | Where-Object { $_.Risk -notin @('High', 'Medium', 'Low') }).Count | Should -Be 0
        ($script:Report.Findings | Where-Object { $_.Status -notin @('Passed', 'Failed', 'Skipped', 'Investigate', 'Planned', 'Error') }).Count | Should -Be 0
    }

    It 'embeds the report payload inside the standalone HTML file' {
        $html = Get-Content -Path $script:Run.HtmlPath -Raw -Encoding UTF8
        $html.Length | Should -BeGreaterThan 50000
        $html | Should -Match 'ZeroTrustLens Raporu'
        $html | Should -Not -Match '\{\{LANG\}\}'
        $html | Should -Not -Match '\{\{REPORT_JSON\}\}'
    }

    It 'keeps the executive summary offline and printable' {
        $exec = Get-Content -Path $script:Run.ExecutiveSummaryPath -Raw -Encoding UTF8
        $exec | Should -Match 'Yönetici Özeti'
        $exec | Should -Match '@media print'
        $exec | Should -Match 'ZeroTrust'
    }
}

Describe 'Invoke-ZtLensAssessment framework selection' {
    BeforeAll {
        $script:FwOutDir = Join-Path ([System.IO.Path]::GetTempPath()) ("ztl-fw-" + [guid]::NewGuid().ToString('N').Substring(0, 8))
        $script:FwRun = Invoke-ZtLensAssessment -InputReportJson $script:FixturePath -OutputPath $script:FwOutDir -Language en -Framework ISO27001 -NoBrowser
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
        $script:FwRun.HtmlPath | Should -Match 'ZeroTrustLensReport-EN\.html$'
    }
}

Describe 'Compare-ZtLensReports' {
    BeforeAll {
        $script:CompareDir = Join-Path ([System.IO.Path]::GetTempPath()) ("ztl-compare-" + [guid]::NewGuid().ToString('N').Substring(0, 8))
        $null = New-Item -ItemType Directory -Path $script:CompareDir -Force

        $baseline = Get-Content -Path $script:Run.JsonPath -Raw -Encoding UTF8 | ConvertFrom-Json
        $current = Get-Content -Path $script:Run.JsonPath -Raw -Encoding UTF8 | ConvertFrom-Json

        ($current.Findings | Where-Object { $_.Id -eq 'MT.1002' }).Status = 'Passed'
        ($current.Findings | Where-Object { $_.Id -eq 'MT.3001' }).Status = 'Failed'

        $script:BaselineJson = Join-Path $script:CompareDir 'baseline.json'
        $script:CurrentJson = Join-Path $script:CompareDir 'current.json'
        $baseline | ConvertTo-Json -Depth 8 | Set-Content -Path $script:BaselineJson -Encoding UTF8
        $current | ConvertTo-Json -Depth 8 | Set-Content -Path $script:CurrentJson -Encoding UTF8

        $script:Diff = Compare-ZtLensReports -BaselineJsonPath $script:BaselineJson -CurrentJsonPath $script:CurrentJson
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
        { Compare-ZtLensReports -BaselineJsonPath 'Z:\does\not\exist.json' -CurrentJsonPath $script:CurrentJson } | Should -Throw '*not found*'
    }
}

Describe 'Export-ZtLensExecutiveSummary' {
    It 'generates a standalone brief from any report JSON' {
        $target = Join-Path ([System.IO.Path]::GetTempPath()) ("ztl-exec-" + [guid]::NewGuid().ToString('N').Substring(0, 8) + '.html')
        try {
            $path = Export-ZtLensExecutiveSummary -InputLensJsonPath $script:Run.JsonPath -OutputHtmlPath $target -Language tr
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
    It 'records a diagnostic instead of swallowing the error' {        $out = Join-Path ([System.IO.Path]::GetTempPath()) ("ztl-diag-" + [guid]::NewGuid().ToString('N').Substring(0, 8))
        try {
            $result = InModuleScope ZeroTrustLens -Parameters @{ Fixture = $script:FixturePath; Out = $out } {
                param($Fixture, $Out)
                Mock Get-ZtLensCopilotReadiness { throw 'simulated copilot outage' }
                Invoke-ZtLensAssessment -InputReportJson $Fixture -OutputPath $Out -Language tr -NoBrowser
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
        $script:ResumeRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("ztl-resume-" + [guid]::NewGuid().ToString('N').Substring(0, 8))
        $script:ResumeRunDir = Join-Path $script:ResumeRoot 'tenant_20260101_0000'
        $exportDir = Join-Path $script:ResumeRunDir 'raw-zt\zt-export'
        $null = New-Item -ItemType Directory -Path $exportDir -Force
        Copy-Item -Path $script:FixturePath -Destination (Join-Path $exportDir 'ZeroTrustAssessmentReport.json')

        $script:ResumeRun = Invoke-ZtLensAssessment -Resume -OutputPath $script:ResumeRoot -Language en -NoBrowser
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
        $empty = Join-Path ([System.IO.Path]::GetTempPath()) ("ztl-empty-" + [guid]::NewGuid().ToString('N').Substring(0, 8))
        $null = New-Item -ItemType Directory -Path $empty -Force
        try {
            { Invoke-ZtLensAssessment -Resume -OutputPath $empty -NoBrowser } | Should -Throw '*ZeroTrustAssessmentReport.json*'
        } finally {
            Remove-Item -Path $empty -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}
