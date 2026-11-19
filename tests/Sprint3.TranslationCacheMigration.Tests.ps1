BeforeAll {
    $script:RepoRoot = Split-Path -Path $PSScriptRoot -Parent
    Import-Module (Join-Path $script:RepoRoot 'TenantBrief.psd1') -Force
    $script:MigrateScript = Join-Path $script:RepoRoot 'tools\Migrate-TranslationCache.ps1'
    $script:CachePath = Join-Path $script:RepoRoot 'data\tr-translation-cache.json'
}

Describe 'S3.3 - Translation Cache Migration (Source|TestId Schema, Zero Loss)' {
    It 'migrates legacy TestId cache to Source|TestId schema without losing any entries' {
        Test-Path -LiteralPath $script:MigrateScript | Should -BeTrue
        $tmpIn = Join-Path ([System.IO.Path]::GetTempPath()) ("tb-mig-in-" + [guid]::NewGuid().ToString('N').Substring(0, 8) + '.json')
        $tmpOut = Join-Path ([System.IO.Path]::GetTempPath()) ("tb-mig-out-" + [guid]::NewGuid().ToString('N').Substring(0, 8) + '.json')
        try {
            [PSCustomObject]@{
                '21796'              = [PSCustomObject]@{ Title = 'Eski kimlik doğrulama'; Desc = 'Açıklama 1' }
                'SCUBA-MS.AAD.1.1v1' = [PSCustomObject]@{ Title = 'SCuBA eski kimlik'; Desc = 'Açıklama 2' }
                'CIS.M365.1.1.1'     = [PSCustomObject]@{ Title = 'Bulut yöneticileri'; Desc = 'Açıklama 3' }
            } | ConvertTo-Json -Depth 5 | Set-Content -Path $tmpIn -Encoding UTF8

            $res = & $script:MigrateScript -InputPath $tmpIn -OutputPath $tmpOut
            $res.InputCount | Should -Be 3
            $res.OutputCount | Should -Be 3

            $outObj = Get-Content -LiteralPath $tmpOut -Raw -Encoding UTF8 | ConvertFrom-Json
            $outObj.PSObject.Properties['ZeroTrust|21796'] | Should -Not -BeNullOrEmpty
            $outObj.PSObject.Properties['CISA SCuBA|SCUBA-MS.AAD.1.1v1'] | Should -Not -BeNullOrEmpty
            $outObj.PSObject.Properties['CIS M365|CIS.M365.1.1.1'] | Should -Not -BeNullOrEmpty
            $outObj.'ZeroTrust|21796'.Reviewed | Should -BeFalse
            $outObj.'ZeroTrust|21796'.Source | Should -Be 'machine'
        } finally {
            Remove-Item -Path $tmpIn, $tmpOut -Force -ErrorAction SilentlyContinue
        }
    }

    It 'ships data/tr-translation-cache.json in Source|TestId schema with at least 360 entries and resolves it in New-TenantBriefFindings' {
        $cache = Get-Content -LiteralPath $script:CachePath -Raw -Encoding UTF8 | ConvertFrom-Json
        $props = @($cache.PSObject.Properties)
        $props.Count | Should -BeGreaterOrEqual 360
        $badKeys = @($props | Where-Object { $_.Name -notmatch '^[^|]+\|.+$' })
        $badKeys.Count | Should -Be 0

        InModuleScope TenantBrief {
            $cacheHt = @{
                'CISA SCuBA|SCUBA-MS.AAD.1.1v1' = [PSCustomObject]@{ Title = 'Eski kimlik doğrulama engellenmelidir'; Desc = 'Açıklama'; Remediation = ''; Reviewed = $false; Source = 'machine' }
            }
            $t = [PSCustomObject]@{ TestId = 'SCUBA-MS.AAD.1.1v1'; TestTitle = 'Legacy authentication SHALL be blocked.'; TestStatus = 'Failed'; TestRisk = 'High'; TestPillar = 'CISA SCuBA'; TestSource = 'CISA SCuBA' }
            $f = @(New-TenantBriefFindings -Tests @($t) -Language tr -TranslationCache $cacheHt)
            $f[0].Title | Should -Be 'Eski kimlik doğrulama engellenmelidir'
        }
    }
}
