BeforeAll {
    $script:RepoRoot = Split-Path -Path $PSScriptRoot -Parent
}

Describe 'S2.4 - EntraFalcon Scope Honesty & Q15 ClaimMismatch = 0' {
    It 'reports Q15 ClaimMismatch = 0 on demo report and clarifies optional EntraFalcon in manifest and CLAIMS.md' {
        $q = & (Join-Path $script:RepoRoot 'tools\Measure-TenantBriefQuality.ps1') -Path (Join-Path $script:RepoRoot 'demo\TenantBriefReport-TR.json') -AsJson | ConvertFrom-Json
        $q15 = $q.Metrics | Where-Object { $_.Code -eq 'Q15' }
        $q15.Value | Should -Be 0

        $psd1 = Get-Content -LiteralPath (Join-Path $script:RepoRoot 'TenantBrief.psd1') -Raw -Encoding UTF8
        $psd1 | Should -Match 'optional EntraFalcon'

        $claims = Get-Content -LiteralPath (Join-Path $script:RepoRoot 'docs\improvement\CLAIMS.md') -Raw -Encoding UTF8
        $claims | Should -Match 'S2\.4'
    }
}
