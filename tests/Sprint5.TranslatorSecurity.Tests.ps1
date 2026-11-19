BeforeAll {
    $script:RepoRoot = Split-Path -Path $PSScriptRoot -Parent
    Import-Module (Join-Path $script:RepoRoot 'TenantBrief.psd1') -Force
}

Describe 'S5.4 & S5.5 - TranslatorKey SecureString / Data-Flow Guard & SECURITY.md' {
    It 'accepts SecureString for -TranslatorKey, never leaks key to report/manifest, and strips tenant UPN/GUID before translation' {
        $tmpDir = Join-Path ([System.IO.Path]::GetTempPath()) ("tb-s54-" + [guid]::NewGuid().ToString('N').Substring(0, 8))
        New-Item -ItemType Directory -Path $tmpDir -Force | Out-Null
        $rawZt = Join-Path $tmpDir 'zt.json'
        $cachePath = Join-Path $script:RepoRoot 'data\tr-translation-cache.json'
        $origCache = if (Test-Path -LiteralPath $cachePath) { Get-Content -LiteralPath $cachePath -Raw -Encoding UTF8 } else { $null }
        $plainKey = 'FAKE-TRANSLATOR-SECRET-998877'
        $secKey = [System.Security.SecureString]::new()
        foreach ($ch in $plainKey.ToCharArray()) { $secKey.AppendChar($ch) }
        $secKey.MakeReadOnly()
        try {
            [PSCustomObject]@{
                TenantId   = '00000000-0000-0000-0000-000000000054'
                Domain     = 'fabrikam.corp'
                TenantInfo = [PSCustomObject]@{
                    TenantOverview = [PSCustomObject]@{ UserCount = 30; GuestCount = 0; GroupCount = 2; ApplicationCount = 2; DeviceCount = 2; ManagedDeviceCount = 2 }
                    OverviewCaMfaAllUsers = $null; DeviceOverview = $null; AgentOverview = $null; OverviewAuthMethodsPrivilegedUsers = $null
                }
                Tests = @(
                    [PSCustomObject]@{
                        TestId = '99540'; TestTitle = 'Custom check for alice@fabrikam.corp'; TestStatus = 'Failed'; TestRisk = 'High'
                        TestPillar = 'Identity'; TestCategory = 'CA'; TestSfiPillar = 'Identity'
                        TestImplementationCost = 'Low'; TestMinimumLicense = 'P1'; TestImpact = 'Low'
                        TestResult = 'Tenant secret finding'; TestDescription = 'Check policy 11111111-2222-3333-4444-555555555555 for alice@fabrikam.corp'
                        SkippedReason = ''
                    }
                )
            } | ConvertTo-Json -Depth 10 | Set-Content -Path $rawZt -Encoding UTF8

            $capturedBody = ''
            InModuleScope TenantBrief -Parameters @{ ZtPath = $rawZt; OutDir = $tmpDir; Key = $secKey } {
                $script:__s54Body = ''
                Mock Invoke-RestMethod {
                    param($Method, $Uri, $Headers, $Body, $ErrorAction)
                    $null = $Method; $null = $Uri; $null = $Headers; $null = $ErrorAction
                    $script:__s54Body = [System.Text.Encoding]::UTF8.GetString($Body)
                    return @(
                        [PSCustomObject]@{ translations = @([PSCustomObject]@{ text = 'Özel kontrol' }) },
                        [PSCustomObject]@{ translations = @([PSCustomObject]@{ text = 'Politika kontrolü' }) }
                    )
                }
                $null = Invoke-TenantBriefAssessment -InputReportJson $ZtPath -OutputPath $OutDir -Language tr -Framework All -TranslatorKey $Key -NoBrowser
            }
            $capturedBody = InModuleScope TenantBrief { $script:__s54Body }
            $capturedBody | Should -Not -BeNullOrEmpty
            $capturedBody | Should -Not -Match 'alice@fabrikam\.corp'
            $capturedBody | Should -Not -Match '11111111-2222-3333-4444-555555555555'

            foreach ($f in (Get-ChildItem -Path $tmpDir -File)) {
                $txt = Get-Content -LiteralPath $f.FullName -Raw -Encoding UTF8
                $txt | Should -Not -Match ([regex]::Escape($plainKey))
            }
        } finally {
            if ($null -ne $origCache) {
                [System.IO.File]::WriteAllText($cachePath, $origCache, [System.Text.UTF8Encoding]::new($false))
            }
            Remove-Item -Path $tmpDir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'ships SECURITY.md and documents Translator data flow in README.md' {
        Test-Path -LiteralPath (Join-Path $script:RepoRoot 'SECURITY.md') | Should -BeTrue
        $readme = Get-Content -LiteralPath (Join-Path $script:RepoRoot 'README.md') -Raw -Encoding UTF8
        $readme | Should -Match 'TranslatorKey|AZURE_TRANSLATOR_KEY'
    }
}
