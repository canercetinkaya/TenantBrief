BeforeAll {
    $script:RepoRoot = Split-Path -Path $PSScriptRoot -Parent
    Import-Module (Join-Path $script:RepoRoot 'TenantBrief.psd1') -Force
}

Describe 'feat/auth-ux - Profiles (Quick/Full), AuthPlan Dry-Run, UPN Hint & ScubaGear Hybrid Split' {
    It 'defaults Test-TenantBriefPrerequisites -AuthPlan to Quick (Graph + EXO + IPPS, no Azure, no Teams, no SPO)' {
        $plan = Test-TenantBriefPrerequisites -AuthPlan
        $plan.Profile | Should -Be 'Quick'
        $plan.Services | Should -Contain 'Graph'
        $plan.Services | Should -Contain 'ExchangeOnline'
        $plan.Services | Should -Contain 'SecurityCompliance'
        $plan.Services | Should -Not -Contain 'Azure'
        $plan.Services | Should -Not -Contain 'SharePointOnline'
        $plan.IncludeTeams | Should -BeFalse
        $plan.IncludeSharePoint | Should -BeFalse
        $plan.ScubaMainSessionProducts | Should -Contain 'aad'
        @($plan.ScubaSubprocessProducts).Count | Should -Be 0
    }

    It 'enables Azure only when -IncludeAzure is explicitly supplied, and discloses SPO & Teams in Full profile' {
        $quickAz = Test-TenantBriefPrerequisites -AuthPlan -Profile Quick -IncludeAzure
        $quickAz.Services | Should -Contain 'Azure'
        $quickAz.IncludeTeams | Should -BeFalse

        $fullPlan = Test-TenantBriefPrerequisites -AuthPlan -Profile Full -ScubaInteractiveLogin -ScubaProducts @('aad', 'securitysuite', 'exo')
        $fullPlan.Services | Should -Contain 'SharePointOnline'
        $fullPlan.IncludeSharePoint | Should -BeTrue
        $fullPlan.IncludeTeams | Should -BeTrue
        ($fullPlan.Steps | Where-Object { $_.Service -eq 'SharePoint Online' }) | Should -Not -BeNullOrEmpty
        $fullPlan.ScubaMainSessionProducts | Should -Be @('aad')
        $fullPlan.ScubaSubprocessProducts | Should -Be @('securitysuite', 'exo')
    }

    It 'validates Invoke-TenantBriefAssessment -ScubaProducts against ScubaGear 2.0 names (securitysuite, not defender)' {
        $cmd = Get-Command Invoke-TenantBriefAssessment
        $vAttr = $cmd.Parameters['ScubaProducts'].Attributes | Where-Object { $_ -is [System.Management.Automation.ValidateSetAttribute] } | Select-Object -First 1
        $vAttr.ValidValues | Should -Contain 'securitysuite'
        $vAttr.ValidValues | Should -Not -Contain 'defender'
    }

    It 'runs ScubaGear aad in main session (-LogIn:$false) and routes only remaining non-AAD products to Windows PowerShell 5.1 subprocess' {
        $tmpDir = Join-Path ([System.IO.Path]::GetTempPath()) ("tb-authux-split-" + [guid]::NewGuid().ToString('N').Substring(0, 8))
        New-Item -ItemType Directory -Path $tmpDir -Force | Out-Null
        try {
            $res = InModuleScope TenantBrief -Parameters @{ OutDir = $tmpDir } {
                $script:__mainCall = $null
                $script:__subCall  = $null
                function script:Invoke-SCuBA {
                    param($ProductNames, [bool]$LogIn, [switch]$DisconnectOnExit, $OPAPath, $OutPath, [switch]$Quiet)
                    $null = $DisconnectOnExit; $null = $OPAPath; $null = $Quiet
                    $script:__mainCall = [PSCustomObject]@{ ProductNames = @($ProductNames); LogIn = $LogIn }
                    $dir = Join-Path $OutPath 'M365BaselineConformance_main'
                    New-Item -ItemType Directory -Path $dir -Force | Out-Null
                    [PSCustomObject]@{
                        Results = [PSCustomObject]@{
                            AAD = @([PSCustomObject]@{ Controls = @([PSCustomObject]@{ 'Control ID' = 'MS.AAD.1.1v1'; Requirement = 'Block legacy auth'; Result = 'Pass'; Criticality = 'Shall'; Details = 'OK' }) })
                        }
                    } | ConvertTo-Json -Depth 10 | Set-Content -Path (Join-Path $dir 'ScubaResults.json') -Encoding UTF8
                }
                Mock Get-Module { [PSCustomObject]@{ Name = 'ScubaGear'; Version = [version]'2.0.0'; ModuleBase = 'C:\Mock\ScubaGear\2.0.0' } }
                Mock Import-Module { }
                Mock Get-Command {
                    param($Name)
                    if ($Name -eq 'powershell.exe') { return [PSCustomObject]@{ Name = 'powershell.exe'; Source = 'C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe' } }
                    if ($Name -eq 'Invoke-SCuBA') { return [PSCustomObject]@{ Name = 'Invoke-SCuBA' } }
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
                    $null = $WinPowerShellPath; $null = $OpaPath; $null = $ExtraModulePaths
                    $script:__subCall = [PSCustomObject]@{ ProductNames = @($ProductNames) }
                    $dir = Join-Path $OutPath 'M365BaselineConformance_sub'
                    New-Item -ItemType Directory -Path $dir -Force | Out-Null
                    [PSCustomObject]@{
                        Results = [PSCustomObject]@{
                            EXO = @([PSCustomObject]@{ Controls = @([PSCustomObject]@{ 'Control ID' = 'MS.EXO.1.1v2'; Requirement = 'Auto-forwarding'; Result = 'Fail'; Criticality = 'Shall'; Details = 'Fail' }) })
                        }
                    } | ConvertTo-Json -Depth 10 | Set-Content -Path (Join-Path $dir 'ScubaResults.json') -Encoding UTF8
                    return 0
                }

                $diag = [System.Collections.Generic.List[object]]::new()
                $mf = [PSCustomObject]@{ Stages = @() }
                $items = @(Invoke-TenantBriefBaselineCollections -OutputPath $OutDir -Account '' -Log { param($m) $null = $m } -State @{} -Diagnostics $diag -Manifest $mf -ManifestPath '' -SkipMaester -ScubaInteractiveLogin -ScubaProducts @('aad', 'exo', 'securitysuite'))
                return [PSCustomObject]@{
                    MainCall = $script:__mainCall
                    SubCall  = $script:__subCall
                    Count    = $items.Count
                    Cats     = @($items | ForEach-Object { $_.TestCategory })
                }
            }

            $res.MainCall.ProductNames | Should -Be @('aad')
            $res.MainCall.LogIn | Should -BeFalse
            $res.SubCall.ProductNames | Should -Be @('exo', 'securitysuite')
            $res.SubCall.ProductNames | Should -Not -Contain 'aad'
            $res.Count | Should -Be 2
            $res.Cats | Should -Contain 'AAD'
            $res.Cats | Should -Contain 'EXO'
        } finally {
            Remove-Item -Path $tmpDir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}
