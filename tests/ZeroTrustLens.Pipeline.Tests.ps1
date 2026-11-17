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
        $script:Report.Summary.Total | Should -Be 14
        $script:Report.Summary.Passed | Should -Be 3
        $script:Report.Summary.Failed | Should -Be 6
        $script:Report.Summary.Investigate | Should -Be 2
        $script:Report.Summary.Skipped | Should -Be 3
        $script:Report.Summary.HighRiskFailed | Should -Be 2
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
        # MT.1001 is reported by both Identity (ZeroTrustAssessment) and CISA SCuBA
        $zt = $script:Report.Frameworks | Where-Object { $_.Id -eq 'ZeroTrust' }
        $cis = $script:Report.Frameworks | Where-Object { $_.Id -eq 'CIS_M365' }
        $zt.Evaluated | Should -Be 11
        $zt.Score | Should -Be 27.3
        $cis.Evaluated | Should -Be 8
        $cis.Score | Should -Be 12.5
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
        ($script:Report.Findings | Where-Object { $_.Status -notin @('Passed', 'Failed', 'Skipped', 'Investigate', 'Planned') }).Count | Should -Be 0
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
