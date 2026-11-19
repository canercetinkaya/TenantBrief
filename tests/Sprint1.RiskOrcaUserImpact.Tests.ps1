BeforeAll {
    $script:RepoRoot = Split-Path -Path $PSScriptRoot -Parent
    Import-Module (Join-Path $script:RepoRoot 'TenantBrief.psd1') -Force
    $script:TemplatePath = Join-Path $script:RepoRoot 'assets\report-template.html'
}

Describe 'S1.6 - ORCA ChiValue (Critical/High/Medium/Low), UserImpact & Template Critical Filter' {
    It 'maps ORCA ChiValue (ORCACHI enum 100/20/15/10/5/0) to Critical, High, Medium, Low' {
        $tmpFile = Join-Path ([System.IO.Path]::GetTempPath()) ("tb-orca-" + [guid]::NewGuid().ToString('N').Substring(0, 8) + '.json')
        try {
            [PSCustomObject]@{
                Results = @(
                    [PSCustomObject]@{ Control = '104'; Name = 'High Confidence Phish'; Area = 'MDO'; Result = '0'; ChiValue = 100; FailRecommendation = 'Fix'; Importance = 'Critical' },
                    [PSCustomObject]@{ Control = '105'; Name = 'Safe Links'; Area = 'MDO'; Result = '0'; ChiValue = 20; FailRecommendation = 'Fix'; Importance = 'VeryHigh' },
                    [PSCustomObject]@{ Control = '108'; Name = 'DKIM'; Area = 'DKIM'; Result = '0'; ChiValue = 15; FailRecommendation = 'Fix'; Importance = 'High' },
                    [PSCustomObject]@{ Control = '114'; Name = 'IP Allow List'; Area = 'EOP'; Result = '0'; ChiValue = 10; FailRecommendation = 'Fix'; Importance = 'Medium' },
                    [PSCustomObject]@{ Control = '107'; Name = 'Spam Notify'; Area = 'EOP'; Result = '0'; ChiValue = 5; FailRecommendation = 'Fix'; Importance = 'Low' }
                )
            } | ConvertTo-Json -Depth 6 | Set-Content -Path $tmpFile -Encoding UTF8

            InModuleScope TenantBrief -Parameters @{ Path = $tmpFile } {
                $items = @(Import-TenantBriefOrcaResults -Path $Path)
                $items.Count | Should -Be 5
                ($items | Where-Object { $_.TestId -eq 'ORCA-104' }).TestRisk | Should -Be 'Critical'
                ($items | Where-Object { $_.TestId -eq 'ORCA-105' }).TestRisk | Should -Be 'High'
                ($items | Where-Object { $_.TestId -eq 'ORCA-108' }).TestRisk | Should -Be 'High'
                ($items | Where-Object { $_.TestId -eq 'ORCA-114' }).TestRisk | Should -Be 'Medium'
                ($items | Where-Object { $_.TestId -eq 'ORCA-107' }).TestRisk | Should -Be 'Low'
            }
        } finally {
            Remove-Item -Path $tmpFile -Force -ErrorAction SilentlyContinue
        }
    }

    It 'emits UserImpact while preserving deprecated Impact and adds Critical filter to report-template.html' {
        InModuleScope TenantBrief {
            $f = @(New-TenantBriefFindings -Tests @([PSCustomObject]@{ TestId = '21796'; TestTitle = 'Legacy auth'; TestStatus = 'Failed'; TestRisk = 'High'; TestImpact = 'Low'; TestPillar = 'Identity' }) -Language tr)
            $f[0].UserImpact | Should -Be 'Düşük'
            $f[0].Impact | Should -Be 'Düşük'
        }

        $html = Get-Content -LiteralPath $script:TemplatePath -Raw -Encoding UTF8
        $html | Should -Match "'Critical'"
    }
}
