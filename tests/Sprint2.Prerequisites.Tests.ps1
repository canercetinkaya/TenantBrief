BeforeAll {
    $script:RepoRoot = Split-Path -Path $PSScriptRoot -Parent
    Import-Module (Join-Path $script:RepoRoot 'TenantBrief.psd1') -Force
}

Describe 'S2.2 - Test-TenantBriefPrerequisites (Read-Only Preflight) & Report Coverage Card' {
    It 'exports Test-TenantBriefPrerequisites with comment-based help and runs cleanly offline' {
        $cmds = (Get-Module TenantBrief).ExportedFunctions.Keys
        $cmds | Should -Contain 'Test-TenantBriefPrerequisites'

        $help = Get-Help Test-TenantBriefPrerequisites -ErrorAction SilentlyContinue
        $help.Synopsis | Should -Not -BeNullOrEmpty

        $res = @(Test-TenantBriefPrerequisites)
        $res.Count | Should -BeGreaterOrEqual 8
        ($res | Where-Object { $_.Category -eq 'Module' }).Count | Should -BeGreaterOrEqual 4
        ($res | Where-Object { $_.Category -eq 'Session' }).Count | Should -BeGreaterOrEqual 3
        foreach ($row in $res) {
            $row.Status | Should -BeIn @('Ready', 'Missing', 'NotConnected', 'Warning')
            $row.Name | Should -Not -BeNullOrEmpty
        }
    }

    It 'embeds Prerequisites summary into the assessment report JSON' {
        $tmpDir = Join-Path ([System.IO.Path]::GetTempPath()) ("tb-s22-" + [guid]::NewGuid().ToString('N').Substring(0, 8))
        New-Item -ItemType Directory -Path $tmpDir -Force | Out-Null
        $rawZt = Join-Path $tmpDir 'zt.json'
        try {
            [PSCustomObject]@{
                TenantId   = '00000000-0000-0000-0000-000000000022'
                Domain     = 'contoso.onmicrosoft.com'
                TenantInfo = [PSCustomObject]@{
                    TenantOverview = [PSCustomObject]@{ UserCount = 5; GuestCount = 0; GroupCount = 1; ApplicationCount = 1; DeviceCount = 1; ManagedDeviceCount = 1 }
                    OverviewCaMfaAllUsers = $null; DeviceOverview = $null; AgentOverview = $null; OverviewAuthMethodsPrivilegedUsers = $null
                }
                Tests = @(
                    [PSCustomObject]@{ TestId = '21796'; TestTitle = 'Legacy auth'; TestStatus = 'Passed'; TestRisk = 'High'; TestPillar = 'Identity'; TestCategory = 'CA'; TestSfiPillar = 'Identity'; TestImplementationCost = 'Low'; TestMinimumLicense = 'P1'; TestImpact = 'Low'; TestResult = 'OK'; TestDescription = 'Desc'; SkippedReason = '' }
                )
            } | ConvertTo-Json -Depth 10 | Set-Content -Path $rawZt -Encoding UTF8

            $run = Invoke-TenantBriefAssessment -InputReportJson $rawZt -OutputPath $tmpDir -Language tr -Framework All -NoBrowser
            $rep = Get-Content -LiteralPath $run.JsonPath -Raw -Encoding UTF8 | ConvertFrom-Json
            $rep.PSObject.Properties['Prerequisites'] | Should -Not -BeNullOrEmpty
            @($rep.Prerequisites).Count | Should -BeGreaterOrEqual 8
        } finally {
            Remove-Item -Path $tmpDir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}
