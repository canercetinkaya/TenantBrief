BeforeAll {
    $script:RepoRoot = Split-Path -Path $PSScriptRoot -Parent
    Import-Module (Join-Path $script:RepoRoot 'TenantBrief.psd1') -Force
}

Describe 'v2.0.1 - ScubaGear Partial Coverage Diagnostics, -ScubaInteractiveLogin & Executive Summary Warning' {
    It 'records Warning + Remedy in Diagnostics when ScubaProducts.Skipped > 0 and honors -ScubaInteractiveLogin' {
        $tmpDir = Join-Path ([System.IO.Path]::GetTempPath()) ("tb-v201-scuba-" + [guid]::NewGuid().ToString('N').Substring(0, 8))
        New-Item -ItemType Directory -Path $tmpDir -Force | Out-Null
        try {
            $res = InModuleScope TenantBrief -Parameters @{ OutDir = $tmpDir } {
                $script:__v201LogInValues = [System.Collections.Generic.List[bool]]::new()
                function script:Invoke-SCuBA {
                    param($ProductNames, [bool]$LogIn, [switch]$DisconnectOnExit, $OPAPath, $OutPath, [switch]$Quiet)
                    $null = $ProductNames; $null = $DisconnectOnExit; $null = $OPAPath; $null = $Quiet
                    $script:__v201LogInValues.Add($LogIn)
                    $sub = Join-Path $OutPath 'M365BaselineConformance_test'
                    New-Item -ItemType Directory -Path $sub -Force | Out-Null
                    [PSCustomObject]@{
                        Results = [PSCustomObject]@{
                            AAD = @([PSCustomObject]@{
                                Controls = @([PSCustomObject]@{
                                    'Control ID' = 'MS.AAD.1.1v1'; Requirement = 'Block legacy auth'; Result = 'Pass'; Criticality = 'Shall'; Details = 'OK'
                                })
                            })
                        }
                    } | ConvertTo-Json -Depth 8 | Set-Content -Path (Join-Path $sub 'ScubaResults_test.json') -Encoding UTF8
                }
                Mock Get-Module { [PSCustomObject]@{ Name = 'ScubaGear'; Version = [version]'2.0.0' } }
                Mock Import-Module { }
                Mock Test-Path {
                    param($Path, $LiteralPath, $PathType)
                    $target = if ($LiteralPath) { $LiteralPath } else { $Path }
                    if ($target -like '*opa_windows_amd64.exe*') { return $true }
                    if ($PathType -eq 'Leaf') { return [System.IO.File]::Exists($target) }
                    if ($PathType -eq 'Container') { return [System.IO.Directory]::Exists($target) }
                    return ([System.IO.File]::Exists($target) -or [System.IO.Directory]::Exists($target))
                }

                $diag1 = [System.Collections.Generic.List[object]]::new()
                $mf1 = [PSCustomObject]@{ Stages = @() }
                $null = Invoke-TenantBriefBaselineCollections -OutputPath $OutDir -Account '' -Log { param($m) $null = $m } -State @{} -Diagnostics $diag1 -Manifest $mf1 -ManifestPath '' -SkipMaester

                $diag2 = [System.Collections.Generic.List[object]]::new()
                $mf2 = [PSCustomObject]@{ Stages = @() }
                $null = Invoke-TenantBriefBaselineCollections -OutputPath $OutDir -Account '' -Log { param($m) $null = $m } -State @{} -Diagnostics $diag2 -Manifest $mf2 -ManifestPath '' -SkipMaester -ScubaInteractiveLogin

                return [PSCustomObject]@{
                    LogInValues = $script:__v201LogInValues.ToArray()
                    Diag1       = $diag1.ToArray()
                    Manifest1   = $mf1
                }
            }

            $res.LogInValues[0] | Should -BeFalse
            $res.LogInValues | Should -Contain $true
            @($res.Manifest1.ScubaProducts.Skipped).Count | Should -Be 6
            $scubaDiag = @($res.Diag1 | Where-Object { $_.Component -eq 'ScubaGear' -and $_.Severity -eq 'Warning' })
            $scubaDiag.Count | Should -BeGreaterOrEqual 1
            $scubaDiag[0].Remedy | Should -Match 'ScubaInteractiveLogin'
        } finally {
            Remove-Item -Path $tmpDir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'surfaces X/7 ScubaGear coverage warning in CISA_SCuBA framework card and Executive Summary HTML, and documents non-interactive cert auth in README' {
        $tmpDir = Join-Path ([System.IO.Path]::GetTempPath()) ("tb-v201-exec-" + [guid]::NewGuid().ToString('N').Substring(0, 8))
        New-Item -ItemType Directory -Path $tmpDir -Force | Out-Null
        try {
            $jPath = Join-Path $tmpDir 'rep.json'
            $ePath = Join-Path $tmpDir 'exec.html'
            [PSCustomObject]@{
                SchemaVersion = '2.0.0'
                Tenant        = 'contoso.onmicrosoft.com'
                Language      = 'tr'
                Summary       = [PSCustomObject]@{ Total = 2; Passed = 1; Failed = 1; HighRiskFailed = 1 }
                Run           = [PSCustomObject]@{
                    ScubaProducts = [PSCustomObject]@{
                        Requested = @('aad', 'securitysuite', 'exo', 'powerplatform', 'sharepoint', 'teams', 'powerbi')
                        Executed  = @('aad')
                        Skipped   = @('securitysuite', 'exo', 'powerplatform', 'sharepoint', 'teams', 'powerbi')
                    }
                }
                Frameworks    = @(
                    [PSCustomObject]@{ Id = 'CISA_SCuBA'; Name = 'CISA SCuBA M365 Güvenlik Taban Hattı'; Passed = 1; Total = 2; Score = 50.0; CoverageNote = '1/7 ürün tarandı' }
                )
                Findings      = @(
                    [PSCustomObject]@{ Id = 'SCUBA-MS.AAD.1.1v1'; Status = 'Failed'; Risk = 'High'; ImplementationCost = 'Low'; DomainPillar = 'Identity'; Category = 'AAD'; Title = 'Block legacy auth'; Remediation = 'Fix it'; RemediationTr = 'Düzelt' }
                )
                Diagnostics   = @()
            } | ConvertTo-Json -Depth 8 | Set-Content -Path $jPath -Encoding UTF8

            $null = Export-TenantBriefExecutiveSummary -InputJsonPath $jPath -OutputHtmlPath $ePath -Language tr
            $html = [System.Net.WebUtility]::HtmlDecode((Get-Content -LiteralPath $ePath -Raw -Encoding UTF8))
            $html | Should -Match '1/7 ürün tarandı'

            $readme = Get-Content -LiteralPath (Join-Path $script:RepoRoot 'README.md') -Raw -Encoding UTF8
            $readme | Should -Match 'ScubaInteractiveLogin'
            $readme | Should -Match 'CertificateThumbprint'
            $readme | Should -Match 'AppID'
        } finally {
            Remove-Item -Path $tmpDir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}
