BeforeAll {
    $script:RepoRoot = Split-Path -Path $PSScriptRoot -Parent
    Import-Module (Join-Path $script:RepoRoot 'TenantBrief.psd1') -Force

    function script:Get-NormalizedReportJson {
        param([Parameter(Mandatory = $true)][string]$JsonPath)
        $obj = Get-Content -LiteralPath $JsonPath -Raw -Encoding UTF8 | ConvertFrom-Json
        if ($obj.PSObject.Properties['GeneratedAt']) { $obj.GeneratedAt = '<NORMALIZED_TIMESTAMP>' }
        if ($obj.PSObject.Properties['Prerequisites']) { $obj.Prerequisites = @('<NORMALIZED_PREREQS>') }
        if ($obj.PSObject.Properties['Metadata'] -and $obj.Metadata) {
            foreach ($k in @('GeneratedAt', 'ReportGeneratedAt', 'RunTimestamp', 'OutputPath')) {
                if ($obj.Metadata.PSObject.Properties[$k]) { $obj.Metadata.$k = '<NORMALIZED>' }
            }
        }
        if ($obj.PSObject.Properties['Run'] -and $obj.Run) {
            foreach ($k in @('StartedAt', 'FinishedAt', 'CompletedAt', 'OutputPath', 'ReportDir', 'ManifestPath', 'SourceReport')) {
                if ($obj.Run.PSObject.Properties[$k]) { $obj.Run.$k = '<NORMALIZED>' }
            }
            foreach ($k in @('ElapsedSeconds', 'DurationSeconds')) {
                if ($obj.Run.PSObject.Properties[$k]) { $obj.Run.$k = 0 }
            }
            if ($obj.Run.PSObject.Properties['Stages'] -and $obj.Run.Stages) {
                foreach ($st in @($obj.Run.Stages)) {
                    foreach ($k in @('StartedAt', 'FinishedAt', 'CompletedAt')) {
                        if ($st.PSObject.Properties[$k]) { $st.$k = '<NORMALIZED>' }
                    }
                    foreach ($k in @('DurationSeconds', 'ElapsedSeconds')) {
                        if ($st.PSObject.Properties[$k]) { $st.$k = 0 }
                    }
                }
            }
        }
        $json = $obj | ConvertTo-Json -Depth 12
        $json = $json -replace '\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d+)?(?:[+-]\d{2}:\d{2}|Z)', '<NORMALIZED_ISO>'
        $json = $json -replace '\d{4}-\d{2}-\d{2} \d{2}:\d{2}', '<NORMALIZED_DATE>'
        return $json
    }
}

Describe 'S6.1 - Golden-File Regression Suite (Refactored Module Invariance)' {
    It 'matches normalized TR golden snapshot from tests/fixtures/raw/*' {
        $rawDir = Join-Path $script:RepoRoot 'tests\fixtures\raw'
        $goldenPath = Join-Path $script:RepoRoot 'tests\golden\TenantBriefReport-TR.normalized.json'
        Test-Path -LiteralPath $goldenPath | Should -BeTrue

        $tmpDir = Join-Path ([System.IO.Path]::GetTempPath()) ("tb-golden-tr-" + [guid]::NewGuid().ToString('N').Substring(0, 8))
        New-Item -ItemType Directory -Path $tmpDir -Force | Out-Null
        try {
            $null = Invoke-TenantBriefAssessment `
                -InputReportJson (Join-Path $rawDir 'ZeroTrustAssessmentReport.json') `
                -InputScubaJsonPath (Join-Path $rawDir 'ScubaResults.json') `
                -InputOrcaJsonPath (Join-Path $rawDir 'OrcaReport.json') `
                -InputMaesterJsonPath (Join-Path $rawDir 'MaesterResults.json') `
                -OutputPath $tmpDir -Language tr -Framework All -NoBrowser

            $actual = Get-NormalizedReportJson -JsonPath (Join-Path $tmpDir 'TenantBriefReport-TR.json')
            $expected = Get-Content -LiteralPath $goldenPath -Raw -Encoding UTF8
            ($actual -replace "`r`n", "`n").Trim() | Should -Be (($expected -replace "`r`n", "`n").Trim())
        } finally {
            Remove-Item -Path $tmpDir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'matches normalized EN golden snapshot from tests/fixtures/raw/*' {
        $rawDir = Join-Path $script:RepoRoot 'tests\fixtures\raw'
        $goldenPath = Join-Path $script:RepoRoot 'tests\golden\TenantBriefReport-EN.normalized.json'
        Test-Path -LiteralPath $goldenPath | Should -BeTrue

        $tmpDir = Join-Path ([System.IO.Path]::GetTempPath()) ("tb-golden-en-" + [guid]::NewGuid().ToString('N').Substring(0, 8))
        New-Item -ItemType Directory -Path $tmpDir -Force | Out-Null
        try {
            $null = Invoke-TenantBriefAssessment `
                -InputReportJson (Join-Path $rawDir 'ZeroTrustAssessmentReport.json') `
                -InputScubaJsonPath (Join-Path $rawDir 'ScubaResults.json') `
                -InputOrcaJsonPath (Join-Path $rawDir 'OrcaReport.json') `
                -InputMaesterJsonPath (Join-Path $rawDir 'MaesterResults.json') `
                -OutputPath $tmpDir -Language en -Framework All -NoBrowser

            $actual = Get-NormalizedReportJson -JsonPath (Join-Path $tmpDir 'TenantBriefReport-EN.json')
            $expected = Get-Content -LiteralPath $goldenPath -Raw -Encoding UTF8
            ($actual -replace "`r`n", "`n").Trim() | Should -Be (($expected -replace "`r`n", "`n").Trim())
        } finally {
            Remove-Item -Path $tmpDir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}
