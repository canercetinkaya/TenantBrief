BeforeAll {
    $script:RepoRoot = Split-Path -Path $PSScriptRoot -Parent
    Import-Module (Join-Path $script:RepoRoot 'TenantBrief.psd1') -Force
}

Describe 'S4.1 - Copilot Readiness Gate Rules (COP-LIC-01 Fail => Max L1, Warning = 0.5, Q13=0)' {
    It 'caps MaturityLevel at L1 when COP-LIC-01 fails and loads copilotReadiness weights from data/scoring.json' {
        $cfg = Get-Content -LiteralPath (Join-Path $script:RepoRoot 'data\scoring.json') -Raw -Encoding UTF8 | ConvertFrom-Json
        $cfg.PSObject.Properties['copilotReadiness'] | Should -Not -BeNullOrEmpty
        $cfg.copilotReadiness.warningWeight | Should -Be 0.5

        $nonEligibleSkus = @([PSCustomObject]@{ skuPartNumber = 'EXCHANGESTANDARD'; prepaidUnits = @{ enabled = 10 }; consumedUnits = 5 })
        $ti = [PSCustomObject]@{ UserCount = 10; GuestCount = 0; TotalAgents = 0 }
        $cr = Get-TenantBriefCopilotReadiness -SubscribedSkus $nonEligibleSkus -TenantInsights $ti -Language tr
        ($cr.Checks | Where-Object { $_.Id -eq 'COP-LIC-01' }).Status | Should -Be 'Fail'
        $cr.MaturityLevel | Should -Match '^L1'
    }
}
