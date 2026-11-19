BeforeAll {
    $script:RepoRoot = Split-Path -Path $PSScriptRoot -Parent
    Import-Module (Join-Path $script:RepoRoot 'TenantBrief.psd1') -Force
    $script:CachePath = Join-Path $script:RepoRoot 'data\tr-translation-cache.json'
    $script:DenylistPath = Join-Path $script:RepoRoot 'tests\i18n-denylist.txt'
}

Describe 'S3.4 - Turkish Translation Cache Coverage (SCuBA/CIS/EIDSCA/Maester/ORCA), Reviewed=false & Summary.UnreviewedTranslations' {
    It 'covers SCuBA, CIS M365, EIDSCA, Maester, and ORCA in tr-translation-cache.json with zero denylist hits and Reviewed=false on machine entries' {
        $cache = Get-Content -LiteralPath $script:CachePath -Raw -Encoding UTF8 | ConvertFrom-Json
        $props = @($cache.PSObject.Properties)

        (@($props | Where-Object { $_.Name -like 'CISA SCuBA|*' }).Count) | Should -BeGreaterOrEqual 34
        (@($props | Where-Object { $_.Name -like 'CIS M365|*' }).Count) | Should -BeGreaterOrEqual 40
        (@($props | Where-Object { $_.Name -like 'EIDSCA|*' }).Count) | Should -BeGreaterOrEqual 20
        (@($props | Where-Object { $_.Name -like 'Maester|*' }).Count) | Should -BeGreaterOrEqual 100

        # Agent-generated machine translations must never be marked Reviewed = true
        $badReviewed = @($props | Where-Object { $_.Value.Source -eq 'machine' -and $_.Value.Reviewed -eq $true })
        $badReviewed.Count | Should -Be 0

        # Denylist scan on all cached Turkish titles
        $deny = @(Get-Content -LiteralPath $script:DenylistPath -Encoding UTF8 | Where-Object { $_ -and -not $_.StartsWith('#') })
        $hits = New-Object System.Collections.Generic.List[string]
        foreach ($p in $props) {
            $t = [string]$p.Value.Title
            foreach ($w in $deny) {
                if ($t -cmatch "\b$([regex]::Escape($w))\b") { $hits.Add("$($p.Name):$w") }
            }
        }
        ($hits -join '; ') | Should -BeNullOrEmpty
    }

    It 'exposes Summary.UnreviewedTranslations in Turkish assessment reports' {
        $tmpDir = Join-Path ([System.IO.Path]::GetTempPath()) ("tb-s34-" + [guid]::NewGuid().ToString('N').Substring(0, 8))
        New-Item -ItemType Directory -Path $tmpDir -Force | Out-Null
        $rawZt = Join-Path $tmpDir 'zt.json'
        try {
            [PSCustomObject]@{
                TenantId   = '00000000-0000-0000-0000-000000000034'
                Domain     = 'contoso.onmicrosoft.com'
                TenantInfo = [PSCustomObject]@{
                    TenantOverview = [PSCustomObject]@{ UserCount = 5; GuestCount = 0; GroupCount = 1; ApplicationCount = 1; DeviceCount = 1; ManagedDeviceCount = 1 }
                    OverviewCaMfaAllUsers = $null; DeviceOverview = $null; AgentOverview = $null; OverviewAuthMethodsPrivilegedUsers = $null
                }
                Tests = @(
                    [PSCustomObject]@{ TestId = '21796'; TestTitle = 'Block legacy authentication policies are configured'; TestStatus = 'Passed'; TestRisk = 'High'; TestPillar = 'Identity'; TestCategory = 'CA'; TestSfiPillar = 'Identity'; TestImplementationCost = 'Low'; TestMinimumLicense = 'P1'; TestImpact = 'Low'; TestResult = 'OK'; TestDescription = 'Desc'; SkippedReason = '' }
                )
            } | ConvertTo-Json -Depth 10 | Set-Content -Path $rawZt -Encoding UTF8

            $run = Invoke-TenantBriefAssessment -InputReportJson $rawZt -OutputPath $tmpDir -Language tr -Framework All -NoBrowser
            $rep = Get-Content -LiteralPath $run.JsonPath -Raw -Encoding UTF8 | ConvertFrom-Json
            $rep.Summary.PSObject.Properties['UnreviewedTranslations'] | Should -Not -BeNullOrEmpty
            $rep.Summary.UnreviewedTranslations | Should -BeGreaterOrEqual 1
        } finally {
            Remove-Item -Path $tmpDir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}
