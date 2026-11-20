BeforeAll {
    $script:RepoRoot = Split-Path -Path $PSScriptRoot -Parent
    Import-Module (Join-Path $script:RepoRoot 'TenantBrief.psd1') -Force
    $script:SchemaPath = Join-Path $script:RepoRoot 'schemas/tenantbrief-report.schema.json'
}

Describe 'v2.0.0 Breaking Change Package (V2.1-V2.4) - Schema v2, Impact Removal & Migration' {
    It 'defines SchemaVersion 2.0.0 and removes deprecated Finding.Impact from schema and template' {
        $schema = Get-Content -LiteralPath $script:SchemaPath -Raw -Encoding UTF8 | ConvertFrom-Json
        $schema.required | Should -Contain 'SchemaVersion'
        $schema.properties.SchemaVersion.const | Should -Be '2.0.0'

        $findingProps = $schema.properties.Findings.items.properties
        $findingProps.PSObject.Properties['UserImpact'] | Should -Not -BeNullOrEmpty
        $findingProps.PSObject.Properties['Impact'] | Should -BeNullOrEmpty

        $tpl = Get-Content -LiteralPath (Join-Path $script:RepoRoot 'assets/report-template.html') -Raw -Encoding UTF8
        $tpl | Should -Not -Match '\bf\.Impact\b'
        $tpl | Should -Match '\bf\.UserImpact\b'

        $migPath = Join-Path $script:RepoRoot 'docs/migration-v1-to-v2.md'
        Test-Path -LiteralPath $migPath | Should -BeTrue
        $mig = Get-Content -LiteralPath $migPath -Raw -Encoding UTF8
        $mig | Should -Match 'UserImpact'
        $mig | Should -Match 'SchemaVersion'
    }

    It 'emits SchemaVersion 2.0.0 without Finding.Impact and compares cleanly against a v1.x report' {
        $tmpDir = Join-Path ([System.IO.Path]::GetTempPath()) ("tb-v2-" + [guid]::NewGuid().ToString('N').Substring(0, 8))
        New-Item -ItemType Directory -Path $tmpDir -Force | Out-Null
        try {
            $run = Invoke-TenantBriefAssessment `
                -InputReportJson (Join-Path $script:RepoRoot 'tests/fixtures/ZeroTrustAssessmentReport.sample.json') `
                -OutputPath $tmpDir -Language tr -Framework All -NoBrowser

            $rawJson = Get-Content -LiteralPath $run.JsonPath -Raw -Encoding UTF8
            Test-Json -Json $rawJson -SchemaFile $script:SchemaPath | Should -BeTrue

            $rep = $rawJson | ConvertFrom-Json
            $rep.SchemaVersion | Should -Be '2.0.0'
            @($rep.Findings).Count | Should -BeGreaterThan 0
            $rep.Findings[0].PSObject.Properties['UserImpact'] | Should -Not -BeNullOrEmpty
            $rep.Findings[0].PSObject.Properties['Impact'] | Should -BeNullOrEmpty

            # Cross-version v1.x -> v2.0.0 Compare-TenantBriefReports check
            $v1Path = Join-Path $tmpDir 'v1-baseline.json'
            $firstId = [string]$rep.Findings[0].Id
            $prevStatus = if ($rep.Findings[0].Status -eq 'Passed') { 'Failed' } else { 'Passed' }
            [PSCustomObject]@{
                Tenant   = 'contoso.onmicrosoft.com'
                Summary  = [PSCustomObject]@{ Total = 1; Passed = 0; Failed = 1 }
                Findings = @(
                    [PSCustomObject]@{ Id = $firstId; Status = $prevStatus; Risk = 'High'; Title = 'Legacy v1 control'; Impact = 'Yüksek' }
                )
            } | ConvertTo-Json -Depth 5 | Set-Content -Path $v1Path -Encoding UTF8

            $diff = Compare-TenantBriefReports -BaselineJsonPath $v1Path -CurrentJsonPath $run.JsonPath
            ($diff.ImprovedCount + $diff.RegressedCount) | Should -Be 1
        } finally {
            Remove-Item -Path $tmpDir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}
