BeforeAll {
    $script:RepoRoot = Split-Path -Path $PSScriptRoot -Parent
    Import-Module (Join-Path $script:RepoRoot 'TenantBrief.psd1') -Force
}

Describe 'S2.1 - ScubaGear 2.0.0 Multi-Product Coverage & Run Manifest Recording' {
    It 'invokes Invoke-SCuBA with all 7 verified ScubaGear 2.0 products and records Requested/Executed/Skipped in run-manifest.json' {
        $tmpDir = Join-Path ([System.IO.Path]::GetTempPath()) ("tb-s21-" + [guid]::NewGuid().ToString('N').Substring(0, 8))
        New-Item -ItemType Directory -Path $tmpDir -Force | Out-Null
        $manifestPath = Join-Path $tmpDir 'run-manifest.json'
        try {
            InModuleScope TenantBrief -Parameters @{ OutDir = $tmpDir; ManifestPath = $manifestPath } {
                $script:__capturedProducts = @()
                function Invoke-SCuBA {
                    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', '')]
                    param($ProductNames, [switch]$LogIn, [switch]$DisconnectOnExit, $OPAPath, $OutPath, [switch]$Quiet)
                    $script:__capturedProducts = @($ProductNames)
                }
                Mock Get-Module {
                    param($Name, [switch]$ListAvailable)
                    $null = $ListAvailable
                    if ($Name -in @('ScubaGear', 'powershell-yaml')) { return [PSCustomObject]@{ Name = $Name; Version = [version]'2.0.0' } }
                    return $null
                }
                Mock Import-Module { }
                Mock Test-Path { return $true }
                Mock Import-TenantBriefScubaResults {
                    return @(
                        [PSCustomObject]@{ TestId = 'SCUBA-MS.AAD.1.1v1'; TestTitle = 'AAD'; TestStatus = 'Passed'; TestRisk = 'High'; TestPillar = 'CISA SCuBA'; TestSource = 'CISA SCuBA'; TestCategory = 'AAD' },
                        [PSCustomObject]@{ TestId = 'SCUBA-MS.SECURITYSUITE.1.1v1'; TestTitle = 'SecSuite'; TestStatus = 'Passed'; TestRisk = 'High'; TestPillar = 'CISA SCuBA'; TestSource = 'CISA SCuBA'; TestCategory = 'SECURITYSUITE' },
                        [PSCustomObject]@{ TestId = 'SCUBA-MS.EXO.3.1v1'; TestTitle = 'EXO'; TestStatus = 'Passed'; TestRisk = 'High'; TestPillar = 'CISA SCuBA'; TestSource = 'CISA SCuBA'; TestCategory = 'EXO' }
                    )
                }

                $diag = New-Object System.Collections.Generic.List[object]
                $manifest = [PSCustomObject]@{
                    Status      = 'running'
                    StartedAt   = (Get-Date).ToString('o')
                    UpdatedAt   = (Get-Date).ToString('o')
                    Stages      = @()
                    Diagnostics = @()
                }
                $state = @{ Stage = 2 }
                $null = Invoke-TenantBriefBaselineCollections -OutputPath $OutDir -Log { param($m) $null = $m } -State $state -Diagnostics $diag -Manifest $manifest -ManifestPath $ManifestPath -SkipMaester

                $script:__capturedProducts | Should -Contain 'aad'
                $script:__capturedProducts.Count | Should -Be 1

                $saved = Get-Content -LiteralPath $ManifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
                $saved.PSObject.Properties['ScubaProducts'] | Should -Not -BeNullOrEmpty
                $expected = @('aad', 'securitysuite', 'exo', 'powerplatform', 'sharepoint', 'teams', 'powerbi')
                foreach ($p in $expected) {
                    @($saved.ScubaProducts.Requested) | Should -Contain $p
                }
                @($saved.ScubaProducts.Requested).Count | Should -Be 7
                @($saved.ScubaProducts.Executed) | Should -Contain 'aad'
                @($saved.ScubaProducts.Executed) | Should -Contain 'securitysuite'
                @($saved.ScubaProducts.Executed) | Should -Contain 'exo'
                @($saved.ScubaProducts.Skipped) | Should -Contain 'powerbi'

                Remove-Item function:Invoke-SCuBA -ErrorAction SilentlyContinue
            }
        } finally {
            Remove-Item -Path $tmpDir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}
