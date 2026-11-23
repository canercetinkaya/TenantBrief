BeforeAll {
    $script:RepoRoot = Split-Path -Path $PSScriptRoot -Parent
    Import-Module (Join-Path $script:RepoRoot 'TenantBrief.psd1') -Force
}

Describe 'feat/cert-auto-auth - Initialize-TenantBriefApp, -UseAppAuth & Zero-Popup Stage 2 ScubaGear' {
    It 'exports Initialize-TenantBriefApp with -WhatIf and -Remove support' {
        $cmd = Get-Command Initialize-TenantBriefApp -ErrorAction Stop
        $cmd.Parameters.ContainsKey('WhatIf') | Should -BeTrue
        $cmd.Parameters.ContainsKey('Remove') | Should -BeTrue
        $res = Initialize-TenantBriefApp -WhatIf
        $res.Action | Should -Be 'WhatIf'
    }

    It 'routes Stage 2 ScubaGear directly in PowerShell 7 with AppID + CertificateThumbprint + Organization when AppAuth is active (0 subprocesses)' {
        $tmpDir = Join-Path ([System.IO.Path]::GetTempPath()) ("tb-appauth-" + [guid]::NewGuid().ToString('N').Substring(0, 8))
        New-Item -ItemType Directory -Path $tmpDir -Force | Out-Null
        try {
            $res = InModuleScope TenantBrief -Parameters @{ OutDir = $tmpDir } {
                $script:__appScubaCall = $null
                function script:Invoke-SCuBA {
                    param($ProductNames, [bool]$LogIn, $AppID, $CertificateThumbprint, $Organization, [switch]$DisconnectOnExit, $OPAPath, $OutPath, [switch]$Quiet)
                    $null = $DisconnectOnExit; $null = $OPAPath; $null = $Quiet
                    $script:__appScubaCall = [PSCustomObject]@{
                        ProductNames          = @($ProductNames)
                        LogIn                 = $LogIn
                        AppID                 = $AppID
                        CertificateThumbprint = $CertificateThumbprint
                        Organization          = $Organization
                    }
                    $dir = Join-Path $OutPath 'M365BaselineConformance_app'
                    New-Item -ItemType Directory -Path $dir -Force | Out-Null
                    [PSCustomObject]@{
                        Results = [PSCustomObject]@{
                            AAD = @([PSCustomObject]@{ Controls = @([PSCustomObject]@{ 'Control ID' = 'MS.AAD.1.1v1'; Requirement = 'Block legacy auth'; Result = 'Pass'; Criticality = 'Shall'; Details = 'OK' }) })
                            EXO = @([PSCustomObject]@{ Controls = @([PSCustomObject]@{ 'Control ID' = 'MS.EXO.1.1v2'; Requirement = 'Auto-forwarding'; Result = 'Fail'; Criticality = 'Shall'; Details = 'Fail' }) })
                        }
                    } | ConvertTo-Json -Depth 10 | Set-Content -Path (Join-Path $dir 'ScubaResults.json') -Encoding UTF8
                }
                Mock Get-Module { [PSCustomObject]@{ Name = 'ScubaGear'; Version = [version]'2.0.0'; ModuleBase = 'C:\Mock\ScubaGear\2.0.0' } }
                Mock Import-Module { }
                Mock Test-Path {
                    param($Path, $LiteralPath, $PathType)
                    $target = if ($LiteralPath) { $LiteralPath } else { $Path }
                    if ($target -like '*opa_windows_amd64.exe*') { return $true }
                    if ($PathType -eq 'Leaf') { return [System.IO.File]::Exists($target) }
                    if ($PathType -eq 'Container') { return [System.IO.Directory]::Exists($target) }
                    return ([System.IO.File]::Exists($target) -or [System.IO.Directory]::Exists($target))
                }
                Mock Invoke-TenantBriefScubaSubprocess { throw 'Subprocess must not be called in App-Only cert mode' }

                $appAuth = [PSCustomObject]@{
                    AppId                 = '11111111-2222-3333-4444-555555555555'
                    CertificateThumbprint = 'AABBCCDDEEFF00112233445566778899AABBCCDD'
                    TenantId              = '99999999-8888-7777-6666-555555555555'
                    Organization          = 'contoso.onmicrosoft.com'
                }
                $diag = [System.Collections.Generic.List[object]]::new()
                $mf = [PSCustomObject]@{ Stages = @() }
                $items = @(Invoke-TenantBriefBaselineCollections -OutputPath $OutDir -Account '' -Log { param($m) $null = $m } -State @{} -Diagnostics $diag -Manifest $mf -ManifestPath '' -SkipMaester -ScubaProducts @('aad', 'exo', 'securitysuite') -AppAuth $appAuth)
                return [PSCustomObject]@{
                    Call  = $script:__appScubaCall
                    Count = $items.Count
                }
            }

            $res.Call.LogIn | Should -BeTrue
            $res.Call.AppID | Should -Be '11111111-2222-3333-4444-555555555555'
            $res.Call.CertificateThumbprint | Should -Be 'AABBCCDDEEFF00112233445566778899AABBCCDD'
            $res.Call.Organization | Should -Be 'contoso.onmicrosoft.com'
            $res.Call.ProductNames | Should -Be @('aad', 'exo', 'securitysuite')
            $res.Count | Should -Be 2
        } finally {
            Remove-Item -Path $tmpDir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}
