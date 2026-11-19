BeforeAll {
    $script:RepoRoot = Split-Path -Path $PSScriptRoot -Parent
    Import-Module (Join-Path $script:RepoRoot 'TenantBrief.psd1') -Force
    $script:GlossaryPath = Join-Path $script:RepoRoot 'data\i18n\glossary-tr.json'
    $script:DenylistPath = Join-Path $script:RepoRoot 'tests\i18n-denylist.txt'
}

Describe 'S3.2 & S3.6 - Turkish Glossary (glossary-tr.json), Denylist CI Scan & ConvertTo-TenantBriefTurkish Post-Processor' {
    It 'provides data/i18n/glossary-tr.json and tests/i18n-denylist.txt' {
        Test-Path -LiteralPath $script:GlossaryPath | Should -BeTrue
        Test-Path -LiteralPath $script:DenylistPath | Should -BeTrue
        $g = Get-Content -LiteralPath $script:GlossaryPath -Raw -Encoding UTF8 | ConvertFrom-Json
        @($g.replacements.PSObject.Properties).Count | Should -BeGreaterOrEqual 10
        $deny = @(Get-Content -LiteralPath $script:DenylistPath -Encoding UTF8 | Where-Object { $_ -and -not $_.StartsWith('#') })
        $deny | Should -Contain 'tasdiqi'
    }

    It 'applies glossary post-processing via ConvertTo-TenantBriefTurkish inside New-TenantBriefFindings (eliminating denylist hits, Q09=0)' {
        InModuleScope TenantBrief {
            $t = [PSCustomObject]@{
                TestId = '99302'; TestTitle = 'Kullanıcı tasdiqi ve phishing-resistant MFA'; TestStatus = 'Failed'
                TestRisk = 'High'; TestPillar = 'Identity'; TestCategory = 'Auth'; TestDescription = 'Legacy authentication engellenmeli.'
            }
            $f = @(New-TenantBriefFindings -Tests @($t) -Language tr)
            $f[0].Title | Should -Not -Match 'tasdiqi'
            $f[0].Title | Should -Match 'doğrulaması'
            $f[0].Title | Should -Match 'oltalamaya dayanıklı'
        }
    }
}
