BeforeAll {
    $script:RepoRoot = Split-Path -Path $PSScriptRoot -Parent
    Import-Module (Join-Path $script:RepoRoot 'TenantBrief.psd1') -Force
}

Describe 'S2.6 - Structured Diagnostics (Stage, Component, Severity, Remedy) & Executive Summary Warning' {
    It 'records Severity and Remedy on Add-TenantBriefDiagnostic and triggers Executive Summary partial-data warning' {
        $tmpDir = Join-Path ([System.IO.Path]::GetTempPath()) ("tb-s26-" + [guid]::NewGuid().ToString('N').Substring(0, 8))
        New-Item -ItemType Directory -Path $tmpDir -Force | Out-Null
        try {
            $diag = $null
            InModuleScope TenantBrief {
                $list = New-Object System.Collections.Generic.List[object]
                Add-TenantBriefDiagnostic -Diagnostics $list -Stage 2 -Component 'ScubaGear' -Severity 'Error' -Message 'OPA binary missing' -Remedy 'Run Install-OPAforSCuBA'
                $list.Count | Should -Be 1
                $list[0].Severity | Should -Be 'Error'
                $list[0].Remedy | Should -Be 'Run Install-OPAforSCuBA'
                $script:__s26Diag = $list.ToArray()
            }
            $diag = InModuleScope TenantBrief { $script:__s26Diag }

            $jsonPath = Join-Path $tmpDir 'rep.json'
            $htmlPath = Join-Path $tmpDir 'exec.html'
            [PSCustomObject]@{
                Tenant      = 'contoso.onmicrosoft.com'
                Summary     = [PSCustomObject]@{ Total = 1; Passed = 1; Failed = 0; Investigate = 0; Skipped = 0; Planned = 0; Error = 0; HighRiskFailed = 0 }
                Frameworks  = @([PSCustomObject]@{ Name = 'ZeroTrust'; Passed = 1; Evaluated = 1; Score = 100 })
                LicenseROI  = [PSCustomObject]@{ TotalIdleUsdYr = 0 }
                Diagnostics = @($diag)
                Findings    = @()
            } | ConvertTo-Json -Depth 8 | Set-Content -Path $jsonPath -Encoding UTF8

            $out = Export-TenantBriefExecutiveSummary -InputJsonPath $jsonPath -OutputHtmlPath $htmlPath -Language tr
            $html = Get-Content -LiteralPath $out -Raw -Encoding UTF8
            $html | Should -Match 'kısmi veriyle'
        } finally {
            Remove-Item -Path $tmpDir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}
