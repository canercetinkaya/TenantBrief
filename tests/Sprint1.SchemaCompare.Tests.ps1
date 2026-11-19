BeforeAll {
    $script:RepoRoot = Split-Path -Path $PSScriptRoot -Parent
    Import-Module (Join-Path $script:RepoRoot 'TenantBrief.psd1') -Force
    $script:SchemaPath = Join-Path $script:RepoRoot 'schemas\tenantbrief-report.schema.json'
}

Describe 'S1.7 - Tightened Report Schema (with Critical & deprecated Impact) & Compare-TenantBriefReports Backward Compatibility' {
    It 'defines Risk enum including Critical, Status enum, and deprecated Impact in tenantbrief-report.schema.json' {
        $schema = Get-Content -LiteralPath $script:SchemaPath -Raw -Encoding UTF8 | ConvertFrom-Json
        $findingProps = $schema.properties.Findings.items.properties

        $findingProps.Risk.enum | Should -Contain 'Critical'
        $findingProps.Risk.enum | Should -Contain 'High'
        $findingProps.Risk.enum | Should -Contain 'Medium'
        $findingProps.Risk.enum | Should -Contain 'Low'
        $findingProps.Status.enum | Should -Contain 'Error'
        $findingProps.Impact.deprecated | Should -BeTrue
        $findingProps.PSObject.Properties['UserImpact'] | Should -Not -BeNullOrEmpty
        $findingProps.PSObject.Properties['CanonicalId'] | Should -Not -BeNullOrEmpty
        $findingProps.PSObject.Properties['EngineLabel'] | Should -Not -BeNullOrEmpty
        $schema.properties.PSObject.Properties['PlannedFindings'] | Should -Not -BeNullOrEmpty
    }

    It 'validates a Sprint 1 report with Critical ORCA risk and PlannedFindings against the tightened schema and compares cleanly against a legacy v1.0.x report' {
        $tmpDir = Join-Path ([System.IO.Path]::GetTempPath()) ("tb-s17-" + [guid]::NewGuid().ToString('N').Substring(0, 8))
        New-Item -ItemType Directory -Path $tmpDir -Force | Out-Null
        $rawZt = Join-Path $tmpDir 'zt.json'
        $rawOrca = Join-Path $tmpDir 'orca.json'
        $legacyPath = Join-Path $tmpDir 'legacy-1035.json'
        try {
            [PSCustomObject]@{
                TenantId   = '00000000-0000-0000-0000-000000000007'
                Domain     = 'contoso.onmicrosoft.com'
                TenantInfo = [PSCustomObject]@{
                    TenantOverview = [PSCustomObject]@{ UserCount = 10; GuestCount = 0; GroupCount = 2; ApplicationCount = 2; DeviceCount = 2; ManagedDeviceCount = 2 }
                    OverviewCaMfaAllUsers = $null; DeviceOverview = $null; AgentOverview = $null; OverviewAuthMethodsPrivilegedUsers = $null
                }
                Tests = @(
                    [PSCustomObject]@{ TestId = '21796'; TestTitle = 'Block legacy auth'; TestStatus = 'Passed'; TestRisk = 'High'; TestPillar = 'Identity'; TestCategory = 'CA'; TestSfiPillar = 'Identity'; TestImplementationCost = 'Low'; TestMinimumLicense = 'P1'; TestImpact = 'Low'; TestResult = 'OK'; TestDescription = 'Desc'; SkippedReason = '' },
                    [PSCustomObject]@{ TestId = '99002'; TestTitle = 'Planned item'; TestStatus = 'Planned'; TestRisk = 'Low'; TestPillar = 'Identity'; TestCategory = 'Future'; TestSfiPillar = 'Identity'; TestImplementationCost = 'Low'; TestMinimumLicense = ''; TestImpact = 'Low'; TestResult = ''; TestDescription = 'Planned'; SkippedReason = '' }
                )
            } | ConvertTo-Json -Depth 10 | Set-Content -Path $rawZt -Encoding UTF8

            [PSCustomObject]@{
                Results = @(
                    [PSCustomObject]@{ Control = '104'; Name = 'High Confidence Phish'; Area = 'MDO'; Result = '0'; ChiValue = 100; FailRecommendation = 'Fix'; Importance = 'Critical' }
                )
            } | ConvertTo-Json -Depth 6 | Set-Content -Path $rawOrca -Encoding UTF8

            $run = Invoke-TenantBriefAssessment -InputReportJson $rawZt -InputOrcaJsonPath $rawOrca -OutputPath $tmpDir -Language tr -Framework All -NoBrowser
            $newRawJson = Get-Content -LiteralPath $run.JsonPath -Raw -Encoding UTF8
            Test-Json -Json $newRawJson -SchemaFile $script:SchemaPath | Should -BeTrue

            # Legacy v1.0.x schema report (no CanonicalId, no UserImpact, no PlannedFindings, old Pillar)
            [PSCustomObject]@{
                Tenant  = 'contoso.onmicrosoft.com'
                Summary = [PSCustomObject]@{ Total = 2; Passed = 1; Failed = 1; Investigate = 0; Skipped = 0; Planned = 0; Error = 0; HighRiskFailed = 1 }
                Findings = @(
                    [PSCustomObject]@{ Id = '21796'; Status = 'Failed'; Risk = 'High'; Title = 'Block legacy auth'; Pillar = 'Identity'; Impact = 'Düşük' },
                    [PSCustomObject]@{ Id = 'ORCA-104'; Status = 'Passed'; Risk = 'Medium'; Title = 'High Confidence Phish'; Pillar = 'Defender for Office 365 (ORCA)'; Impact = 'Orta' }
                )
            } | ConvertTo-Json -Depth 6 | Set-Content -Path $legacyPath -Encoding UTF8

            $diff = Compare-TenantBriefReports -BaselineJsonPath $legacyPath -CurrentJsonPath $run.JsonPath
            $diff.ImprovedCount | Should -Be 1
            $diff.Improved[0].Id | Should -Be '21796'
            $diff.RegressedCount | Should -Be 1
            $diff.Regressed[0].Id | Should -Be 'ORCA-104'
            $diff.Regressed[0].Risk | Should -Be 'Critical'
        } finally {
            Remove-Item -Path $tmpDir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}
