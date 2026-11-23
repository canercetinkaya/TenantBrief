BeforeAll {
    $script:RepoRoot = Split-Path -Path $PSScriptRoot -Parent
    Import-Module (Join-Path $script:RepoRoot 'TenantBrief.psd1') -Force
}

Describe 'v2.0.2 - ScubaGear InvariantCulture Guard & Isolated Windows PowerShell 5.1 Subprocess' {
    It 'runs in-process Invoke-SCuBA under InvariantCulture and restores original CurrentCulture' {
        $tmpDir = Join-Path ([System.IO.Path]::GetTempPath()) ("tb-v202-cult-" + [guid]::NewGuid().ToString('N').Substring(0, 8))
        New-Item -ItemType Directory -Path $tmpDir -Force | Out-Null
        $origCulture = [System.Threading.Thread]::CurrentThread.CurrentCulture
        try {
            $trCulture = [System.Globalization.CultureInfo]::GetCultureInfo('tr-TR')
            [System.Threading.Thread]::CurrentThread.CurrentCulture = $trCulture

            $res = InModuleScope TenantBrief -Parameters @{ OutDir = $tmpDir } {
                $script:__v202ObservedCulture = $null
                $script:__v202ObservedUpperI = $null
                function script:Invoke-SCuBA {
                    param($ProductNames, [bool]$LogIn, [switch]$DisconnectOnExit, $OPAPath, $OutPath, [switch]$Quiet)
                    $null = $ProductNames; $null = $LogIn; $null = $DisconnectOnExit; $null = $OPAPath; $null = $OutPath; $null = $Quiet
                    $script:__v202ObservedCulture = [System.Threading.Thread]::CurrentThread.CurrentCulture.Name
                    $script:__v202ObservedUpperI = 'isInitial'.Substring(0, 1).ToUpper() + 'isInitial'.Substring(1)
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

                $diag = [System.Collections.Generic.List[object]]::new()
                $mf = [PSCustomObject]@{ Stages = @() }
                $null = Invoke-TenantBriefBaselineCollections -OutputPath $OutDir -Account '' -Log { param($m) $null = $m } -State @{} -Diagnostics $diag -Manifest $mf -ManifestPath '' -SkipMaester

                return [PSCustomObject]@{
                    ObservedCulture = $script:__v202ObservedCulture
                    ObservedUpperI  = $script:__v202ObservedUpperI
                    RestoredCulture = [System.Threading.Thread]::CurrentThread.CurrentCulture.Name
                }
            }

            $res.ObservedCulture | Should -Be ''
            $res.ObservedUpperI | Should -Be 'IsInitial'
            $res.RestoredCulture | Should -Be 'tr-TR'
        } finally {
            [System.Threading.Thread]::CurrentThread.CurrentCulture = $origCulture
            Remove-Item -Path $tmpDir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'routes -ScubaInteractiveLogin through isolated Windows PowerShell 5.1 subprocess and merges multi-product ScubaResults.json' {
        $tmpDir = Join-Path ([System.IO.Path]::GetTempPath()) ("tb-v202-sub-" + [guid]::NewGuid().ToString('N').Substring(0, 8))
        New-Item -ItemType Directory -Path $tmpDir -Force | Out-Null
        try {
            $res = InModuleScope TenantBrief -Parameters @{ OutDir = $tmpDir } {
                $script:__v202SubCall = $null
                Mock Get-Module {
                    [PSCustomObject]@{
                        Name       = 'ScubaGear'
                        Version    = [version]'2.0.0'
                        ModuleBase = 'C:\MockModules\ScubaGear\2.0.0'
                    }
                }
                Mock Get-Command {
                    param($Name)
                    if ($Name -eq 'powershell.exe') {
                        return [PSCustomObject]@{ Name = 'powershell.exe'; Source = 'C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe' }
                    }
                    return $null
                }
                Mock Test-Path {
                    param($Path, $LiteralPath, $PathType)
                    $target = if ($LiteralPath) { $LiteralPath } else { $Path }
                    if ($target -like '*opa_windows_amd64.exe*') { return $true }
                    if ($PathType -eq 'Leaf') { return [System.IO.File]::Exists($target) }
                    if ($PathType -eq 'Container') { return [System.IO.Directory]::Exists($target) }
                    return ([System.IO.File]::Exists($target) -or [System.IO.Directory]::Exists($target))
                }
                Mock Invoke-TenantBriefScubaSubprocess {
                    param($WinPowerShellPath, $ProductNames, $OpaPath, $OutPath, $ExtraModulePaths)
                    $script:__v202SubCall = [PSCustomObject]@{
                        WinPowerShellPath = $WinPowerShellPath
                        ProductNames      = @($ProductNames)
                        OpaPath           = $OpaPath
                        OutPath           = $OutPath
                        ExtraModulePaths  = @($ExtraModulePaths)
                    }
                    $sub = Join-Path $OutPath 'M365BaselineConformance_v202'
                    New-Item -ItemType Directory -Path $sub -Force | Out-Null
                    [PSCustomObject]@{
                        Results = [PSCustomObject]@{
                            AAD           = @([PSCustomObject]@{ Controls = @([PSCustomObject]@{ 'Control ID' = 'MS.AAD.1.1v1'; Requirement = 'Block legacy auth'; Result = 'Pass'; Criticality = 'Shall'; Details = 'OK' }) })
                            EXO           = @([PSCustomObject]@{ Controls = @([PSCustomObject]@{ 'Control ID' = 'MS.EXO.1.1v2'; Requirement = 'Auto-forwarding'; Result = 'Fail'; Criticality = 'Shall'; Details = 'Fail' }) })
                            SHAREPOINT    = @([PSCustomObject]@{ Controls = @([PSCustomObject]@{ 'Control ID' = 'MS.SHAREPOINT.1.1v1'; Requirement = 'External sharing'; Result = 'Fail'; Criticality = 'Shall'; Details = 'Fail' }) })
                            TEAMS         = @([PSCustomObject]@{ Controls = @([PSCustomObject]@{ 'Control ID' = 'MS.TEAMS.1.1v1'; Requirement = 'External access'; Result = 'Pass'; Criticality = 'Shall'; Details = 'OK' }) })
                            SECURITYSUITE = @([PSCustomObject]@{ Controls = @([PSCustomObject]@{ 'Control ID' = 'MS.SECURITYSUITE.1.1v1'; Requirement = 'Defender policy'; Result = 'Pass'; Criticality = 'Shall'; Details = 'OK' }) })
                            PowerBI       = $null
                        }
                    } | ConvertTo-Json -Depth 8 | Set-Content -Path (Join-Path $sub 'ScubaResults_v202.json') -Encoding UTF8
                    return 0
                }

                $diag = [System.Collections.Generic.List[object]]::new()
                $mf = [PSCustomObject]@{ Stages = @() }
                $items = @(Invoke-TenantBriefBaselineCollections -OutputPath $OutDir -Account '' -Log { param($m) $null = $m } -State @{} -Diagnostics $diag -Manifest $mf -ManifestPath '' -SkipMaester -ScubaInteractiveLogin)

                return [PSCustomObject]@{
                    SubCall   = $script:__v202SubCall
                    ItemCount = $items.Count
                    Executed  = @($mf.ScubaProducts.Executed)
                    Skipped   = @($mf.ScubaProducts.Skipped)
                }
            }

            $res.SubCall | Should -Not -BeNullOrEmpty
            $res.SubCall.ProductNames.Count | Should -Be 7
            $res.SubCall.ExtraModulePaths | Should -Contain 'C:\MockModules'
            $res.ItemCount | Should -Be 5
            $res.Executed.Count | Should -Be 5
            $res.Skipped.Count | Should -Be 2
        } finally {
            Remove-Item -Path $tmpDir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'records Warning + Remedy in Diagnostics when Windows PowerShell 5.1 subprocess exits non-zero' {
        $tmpDir = Join-Path ([System.IO.Path]::GetTempPath()) ("tb-v202-err-" + [guid]::NewGuid().ToString('N').Substring(0, 8))
        New-Item -ItemType Directory -Path $tmpDir -Force | Out-Null
        try {
            $res = InModuleScope TenantBrief -Parameters @{ OutDir = $tmpDir } {
                Mock Get-Module {
                    [PSCustomObject]@{ Name = 'ScubaGear'; Version = [version]'2.0.0'; ModuleBase = 'C:\MockModules\ScubaGear\2.0.0' }
                }
                Mock Get-Command {
                    param($Name)
                    if ($Name -eq 'powershell.exe') {
                        return [PSCustomObject]@{ Name = 'powershell.exe'; Source = 'C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe' }
                    }
                    return $null
                }
                Mock Test-Path {
                    param($Path, $LiteralPath, $PathType)
                    $target = if ($LiteralPath) { $LiteralPath } else { $Path }
                    if ($target -like '*opa_windows_amd64.exe*') { return $true }
                    if ($PathType -eq 'Leaf') { return [System.IO.File]::Exists($target) }
                    if ($PathType -eq 'Container') { return [System.IO.Directory]::Exists($target) }
                    return ([System.IO.File]::Exists($target) -or [System.IO.Directory]::Exists($target))
                }
                Mock Invoke-TenantBriefScubaSubprocess { return 1 }

                $diag = [System.Collections.Generic.List[object]]::new()
                $mf = [PSCustomObject]@{ Stages = @() }
                $null = Invoke-TenantBriefBaselineCollections -OutputPath $OutDir -Account '' -Log { param($m) $null = $m } -State @{} -Diagnostics $diag -Manifest $mf -ManifestPath '' -SkipMaester -ScubaInteractiveLogin
                return $diag.ToArray()
            }

            $warn = @($res | Where-Object { $_.Component -eq 'ScubaGear' -and $_.Severity -eq 'Warning' -and $_.Message -match 'exited with code 1' })
            $warn.Count | Should -BeGreaterOrEqual 1
            $warn[0].Remedy | Should -Match 'DebugLogs'
        } finally {
            Remove-Item -Path $tmpDir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}
