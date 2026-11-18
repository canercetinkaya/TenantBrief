BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '..\TenantBrief.psd1') -Force
}

Describe 'TenantBrief Module' {
    It 'Exports expected functions' {
        $cmds = (Get-Module TenantBrief).ExportedFunctions.Keys
        $cmds | Should -Contain 'Connect-TenantBrief'
        $cmds | Should -Contain 'Invoke-TenantBriefAssessment'
        $cmds | Should -Contain 'Get-TenantBriefFrameworks'
        $cmds | Should -Contain 'Get-TenantBriefLicenseRoi'
        $cmds | Should -Contain 'Get-TenantBriefLicenseWaste'
        $cmds | Should -Contain 'Get-TenantBriefCopilotReadiness'
        $cmds | Should -Contain 'Compare-TenantBriefReports'
        $cmds | Should -Contain 'Export-TenantBriefExecutiveSummary'
    }

    It 'Preserves backward-compatible *-ZtLens* aliases' {
        $aliases = (Get-Module TenantBrief).ExportedAliases
        $aliases['Connect-ZtLens'].Definition | Should -Be 'Connect-TenantBrief'
        $aliases['Invoke-ZtLensAssessment'].Definition | Should -Be 'Invoke-TenantBriefAssessment'
        $aliases['Get-ZtLensFrameworks'].Definition | Should -Be 'Get-TenantBriefFrameworks'
        $aliases['Get-ZtLensLicenseRoi'].Definition | Should -Be 'Get-TenantBriefLicenseRoi'
        $aliases['Get-ZtLensLicenseWaste'].Definition | Should -Be 'Get-TenantBriefLicenseWaste'
        $aliases['Get-ZtLensCopilotReadiness'].Definition | Should -Be 'Get-TenantBriefCopilotReadiness'
        $aliases['Compare-ZtLensReports'].Definition | Should -Be 'Compare-TenantBriefReports'
        $aliases['Export-ZtLensExecutiveSummary'].Definition | Should -Be 'Export-TenantBriefExecutiveSummary'
    }

    It 'Lists 7 verified benchmark and engine definitions' {
        $fws = Get-TenantBriefFrameworks
        $fws.Count | Should -Be 7
        ($fws | ForEach-Object { $_.Id }) | Should -Contain 'CISA_SCuBA'
        ($fws | ForEach-Object { $_.Id }) | Should -Contain 'EIDSCA'
    }

    It 'Calculates License ROI from SKU payload' {
        $mockSkus = @(
            [PSCustomObject]@{ skuPartNumber = 'SPE_E5'; prepaidUnits = @{ enabled = 100 }; consumedUnits = 75 },
            [PSCustomObject]@{ skuPartNumber = 'AAD_PREMIUM_P2'; prepaidUnits = @{ enabled = 50 }; consumedUnits = 50 }
        )
        $roi = Get-TenantBriefLicenseRoi -SubscribedSkus $mockSkus
        $roi.Count | Should -Be 2
        $roi[0].Unassigned | Should -Be 25
        $roi[0].EstimatedIdleUsdMo | Should -Be 1425
    }

    It 'Audits disabled, inactive, guest and overlapping SKUs via Get-TenantBriefLicenseWaste' {
        $skus = @(
            [PSCustomObject]@{ skuId = '111'; skuPartNumber = 'SPE_E5'; prepaidUnits = @{ enabled = 10 }; consumedUnits = 8 },
            [PSCustomObject]@{ skuId = '222'; skuPartNumber = 'SPE_E3'; prepaidUnits = @{ enabled = 10 }; consumedUnits = 9 }
        )
        $oldDate = (Get-Date).ToUniversalTime().AddDays(-120).ToString('o')
        $users = @(
            [PSCustomObject]@{ id = 'u1'; accountEnabled = $false; userType = 'Member'; assignedLicenses = @(@{ skuId = '111' }) },
            [PSCustomObject]@{ id = 'u2'; accountEnabled = $true; userType = 'Guest'; assignedLicenses = @(@{ skuId = '222' }) },
            [PSCustomObject]@{ id = 'u3'; accountEnabled = $true; userType = 'Member'; assignedLicenses = @(@{ skuId = '111' }, @{ skuId = '222' }); signInActivity = [PSCustomObject]@{ lastSignInDateTime = $oldDate } }
        )
        $w = Get-TenantBriefLicenseWaste -SubscribedSkus $skus -Users $users -Language en
        $w.UnassignedSeats | Should -Be 3
        $w.DisabledLicensedUsers | Should -Be 1
        $w.DisabledUsdMo | Should -Be 57
        $w.LicensedGuests | Should -Be 1
        $w.DuplicateOverlapCount | Should -Be 1
        $w.DuplicateOverlapUsdMo | Should -Be 36
        $w.Inactive90dUsers | Should -Be 1
    }

    It 'Documents every exported cmdlet with comment-based help' {        foreach ($cmd in (Get-Module TenantBrief).ExportedFunctions.Keys) {
            $help = Get-Help $cmd -ErrorAction SilentlyContinue
            $help.Synopsis | Should -Not -BeNullOrEmpty -Because "$cmd needs a synopsis"
        }
    }

    It 'Follows @odata.nextLink pagination when enumerating users' {
        InModuleScope TenantBrief {
            $script:__pagingCalls = 0
            function Invoke-MgGraphRequest {
                param($Method, $Uri, $ErrorAction)
                $script:__pagingCalls++
                if ($script:__pagingCalls -eq 1) {
                    return [PSCustomObject]@{ value = @([PSCustomObject]@{ id = 'p1' }); '@odata.nextLink' = 'https://graph.microsoft.com/v1.0/users?$skiptoken=p2' }
                }
                return [PSCustomObject]@{ value = @([PSCustomObject]@{ id = 'p2' }) }
            }
            try {
                $res = @(Get-TenantBriefGraphCollection -Uri 'https://graph.microsoft.com/v1.0/users?$top=999')
                $res.Count | Should -Be 2
                $script:__pagingCalls | Should -Be 2
            } finally {
                Remove-Item function:Invoke-MgGraphRequest -ErrorAction SilentlyContinue
            }
        }
    }

    It 'Evaluates Copilot Readiness score, warnings and checks' {
        $mockSkus = @(
            [PSCustomObject]@{ skuPartNumber = 'SPE_E5'; prepaidUnits = @{ enabled = 25 }; consumedUnits = 20 },
            [PSCustomObject]@{ skuPartNumber = 'Microsoft_365_Copilot'; prepaidUnits = @{ enabled = 5 }; consumedUnits = 5 }
        )
        $ti = [PSCustomObject]@{ UserCount = 25; GuestCount = 6; TotalAgents = 2 }
        $cr = Get-TenantBriefCopilotReadiness -SubscribedSkus $mockSkus -TenantInsights $ti -OfflineOnly -Language tr
        $cr.EligibleBaseSeats | Should -Be 25
        $cr.CopilotSeats | Should -Be 5
        $cr.Checks.Count | Should -BeGreaterThan 1
        $cr.Warnings.Count | Should -BeGreaterThan 0
    }

    It 'correlates the same control reported by two engines and keeps both pillars' {
        InModuleScope TenantBrief {
            $incoming = @(
                [PSCustomObject]@{
                    TestId = 'ZT.1'; TestTitle = 'Ensure MFA is enforced for all users'; TestStatus = 'Passed'
                    TestRisk = 'Medium'; TestPillar = 'Identity'; TestCategory = 'Authentication'; TestSfiPillar = 'Identity'
                    TestImplementationCost = 'Low'; TestMinimumLicense = 'ENTRA_PREMIUM_P1'; SkippedReason = ''
                    TestResult = 'Conditional Access policy requires MFA.'; TestImpact = 'Medium'; TestDescription = 'ZeroTrustAssessment text'
                },
                [PSCustomObject]@{
                    TestId = 'SCUBA-AAD-1'; TestTitle = 'Ensure  MFA is enforced for all users!'; TestStatus = 'Failed'
                    TestRisk = 'High'; TestPillar = 'CISA SCuBA'; TestCategory = 'AAD'; TestSfiPillar = 'CISA SCuBA'
                    TestImplementationCost = ''; TestMinimumLicense = ''; SkippedReason = ''
                    TestResult = 'Guests excluded from policy.'; TestImpact = 'High'; TestDescription = 'ScubaGear requirement text'
                }
            )
            $r = @(New-TenantBriefCorrelatedTests -Tests $incoming)
            $r.Count | Should -Be 1
            $r[0].TestStatus | Should -Be 'Failed'
            $r[0].TestRisk | Should -Be 'High'
            (@($r[0].TestPillar) -join ',') | Should -Be 'Identity,CISA SCuBA'
            # The first engine with a value wins; empty fields are enriched from the other engine.
            $r[0].TestImplementationCost | Should -Be 'Low'
            $r[0].TestDescription | Should -Be 'ZeroTrustAssessment text'
        }
    }

    It 'tolerates engine objects that lack optional properties' {
        InModuleScope TenantBrief {
            $legacy = [PSCustomObject]@{ TestId = 'X'; TestTitle = 'Only the basics'; TestStatus = 'Failed' }
            { New-TenantBriefCorrelatedTests -Tests @($legacy) } | Should -Not -Throw
            $r = @(New-TenantBriefCorrelatedTests -Tests @($legacy))
            $r.Count | Should -Be 1
            $r[0].TestImplementationCost | Should -BeNullOrEmpty
        }
    }

    It 'marks a missing implementation cost as Unknown instead of guessing Medium' {
        InModuleScope TenantBrief {
            $f = @(New-TenantBriefFindings -Tests @([PSCustomObject]@{ TestId = 'X'; TestTitle = 't'; TestStatus = 'Failed'; TestPillar = @('Identity') }) -Language en)
            $f[0].ImplementationCost | Should -Be 'Unknown'
            $f[0].Pillar | Should -Be 'Identity'
        }
    }

    It 'normalizes a grouped pillar into Pillar/PrimaryPillar' {
        InModuleScope TenantBrief {
            $f = @(New-TenantBriefFindings -Tests @([PSCustomObject]@{ TestId = 'X'; TestTitle = 't'; TestStatus = 'Failed'; TestPillar = @('Identity', 'CISA SCuBA') }) -Language en)
            $f[0].Pillar | Should -Be 'Identity, CISA SCuBA'
            $f[0].PrimaryPillar | Should -Be 'Identity'
        }
    }

    It 'keeps the SKU catalog internally consistent' {
        $cat = Get-Content -Path (Join-Path $PSScriptRoot '..\data\sku-catalog.json') -Raw -Encoding UTF8 | ConvertFrom-Json
        $parts = @($cat.skus | ForEach-Object { $_.skuPartNumber })
        ($parts | Sort-Object -Unique).Count | Should -Be $parts.Count
        foreach ($s in $cat.skus) {
            $s.name | Should -Not -BeNullOrEmpty
            $s.category | Should -Not -BeNullOrEmpty
            [double]$s.usdPerUserMonth | Should -BeGreaterOrEqual 0
        }
        foreach ($o in $cat.overlaps) {
            $parts | Should -Contain $o.skuA
            $parts | Should -Contain $o.skuB
            $parts | Should -Contain $o.redundant
        }
    }

    It 'labels free and developer tiers instead of falling back to Other' {
        $mock = @(
            [PSCustomObject]@{ skuPartNumber = 'FLOW_FREE'; prepaidUnits = @{ enabled = 10000 }; consumedUnits = 1 },
            [PSCustomObject]@{ skuPartNumber = 'DEVELOPERPACK_E5'; prepaidUnits = @{ enabled = 25 }; consumedUnits = 1 }
        )
        $roi = Get-TenantBriefLicenseRoi -SubscribedSkus $mock
        $flow = $roi | Where-Object { $_.SkuPartNumber -eq 'FLOW_FREE' }
        $dev = $roi | Where-Object { $_.SkuPartNumber -eq 'DEVELOPERPACK_E5' }
        $flow.Category | Should -Be 'Included/Free'
        $flow.EstimatedIdleUsdMo | Should -Be 0
        $flow.Billable | Should -BeFalse
        $dev.Category | Should -Be 'Developer'
        $dev.EstimatedIdleUsdMo | Should -Be 0
        $dev.Billable | Should -BeFalse
    }

    It 'excludes non-billable seats from the R3 unassigned counter' {
        $skus = @(
            [PSCustomObject]@{ skuPartNumber = 'SPE_E5'; prepaidUnits = @{ enabled = 10 }; consumedUnits = 8 },
            [PSCustomObject]@{ skuPartNumber = 'FLOW_FREE'; prepaidUnits = @{ enabled = 10000 }; consumedUnits = 1 }
        )
        $users = @([PSCustomObject]@{ id = 'u1'; accountEnabled = $true; userType = 'Member'; assignedLicenses = @() })
        $w = Get-TenantBriefLicenseWaste -SubscribedSkus $skus -Users $users -Language en
        # Only the paid suite contributes: 10 - 8 = 2, not 2 + 9,999 free seats.
        $w.UnassignedSeats | Should -Be 2
        $w.UnassignedUsdMo | Should -Be 114
    }

    It 'evaluates COP-SPO-01 via Graph /admin/sharepoint/settings when Get-SPOTenant is unavailable' {
        InModuleScope TenantBrief {
            function Get-MgContext { param($ErrorAction) return [PSCustomObject]@{ Account = 'admin@contoso.onmicrosoft.com' } }
            function Get-SPOTenant { param($ErrorAction) throw 'SPO session not connected' }
            function Invoke-MgGraphRequest {
                param($Method, $Uri, $ErrorAction)
                switch -Wildcard ($Uri) {
                    '*/admin/sharepoint/settings' {
                        return @{
                            sharingCapability                 = 'externalUserAndGuestSharing'
                            isResharingByExternalUsersEnabled = $true
                            sharingDomainRestrictionMode      = 'none'
                        }
                    }
                    '*/policies/authorizationPolicy' {
                        return [PSCustomObject]@{
                            allowInvitesFrom = 'adminsAndGuestInviters'
                            guestUserRoleId  = '2af84b1e-32c8-42b7-82bc-daa82404023b'
                            defaultUserRolePermissions = [PSCustomObject]@{ permissionGrantPoliciesAssigned = @() }
                        }
                    }
                    '*sensitivityLabels*' { return [PSCustomObject]@{ value = @([PSCustomObject]@{ id = 'lbl1' }) } }
                    default { return [PSCustomObject]@{ value = @() } }
                }
            }
            try {
                $mockSkus = @([PSCustomObject]@{ skuPartNumber = 'SPE_E5'; prepaidUnits = @{ enabled = 10 }; consumedUnits = 10 })
                $ti = [PSCustomObject]@{ UserCount = 10; GuestCount = 0; TotalAgents = 0 }
                $cr = Get-TenantBriefCopilotReadiness -SubscribedSkus $mockSkus -TenantInsights $ti -Language tr
                $spo = $cr.Checks | Where-Object { $_.Id -eq 'COP-SPO-01' }
                $spo | Should -Not -BeNullOrEmpty
                $spo.Status | Should -Be 'Warning'
                $spo.Detail | Should -Match 'Graph API'
                $spo.Detail | Should -Match 'externalUserAndGuestSharing'
            } finally {
                Remove-Item function:Get-MgContext, function:Get-SPOTenant, function:Invoke-MgGraphRequest -ErrorAction SilentlyContinue
            }
        }
    }

    It 'imports Maester EIDSCA/CIS test results into the Maester pillar' {
        InModuleScope TenantBrief {
            $mockMaester = [PSCustomObject]@{
                Tests = @(
                    [PSCustomObject]@{
                        Id           = 'EIDSCA.AF01'
                        Title        = 'EIDSCA.AF01: Block legacy authentication methods'
                        Result       = 'Failed'
                        Severity     = 'High'
                        Block        = 'Entra ID Authentication Methods'
                        HelpUrl      = 'https://maester.dev/docs/tests/EIDSCA.AF01'
                        ResultDetail = [PSCustomObject]@{
                            TestDescription = 'Verify authentication method migration posture.'
                            TestResult      = 'Legacy SMS policy enabled'
                            SkippedReason   = ''
                        }
                    },
                    [PSCustomObject]@{
                        Id           = 'CIS.M365.5.1'
                        Title        = 'Ensure Security Defaults or CA is configured'
                        Result       = 'Passed'
                        Severity     = 'Medium'
                        Block        = 'CIS M365'
                        ResultDetail = [PSCustomObject]@{ TestDescription = 'CA enabled'; TestResult = 'OK' }
                    }
                )
            }
            $res = @(Import-TenantBriefMaesterResults -MaesterResult $mockMaester)
            $res.Count | Should -Be 2
            $res[0].TestId | Should -Be 'EIDSCA.AF01'
            $res[0].TestTitle | Should -Be 'Block legacy authentication methods'
            $res[0].TestStatus | Should -Be 'Failed'
            $res[0].TestRisk | Should -Be 'High'
            $res[0].TestPillar | Should -Be 'Maester (EIDSCA / CIS)'
            $res[0].TestDescription | Should -Match 'https://maester.dev'
            $res[1].TestStatus | Should -Be 'Passed'
        }
    }

    It 'imports EntraFalcon tenant_findings_all JSON findings into the EntraFalcon pillar' {
        $tmpEf = Join-Path ([System.IO.Path]::GetTempPath()) ("tb-ef-" + [guid]::NewGuid().ToString('N').Substring(0, 8) + '.json')
        try {
            @(
                [PSCustomObject]@{
                    FindingId       = 'USR-001'
                    Title           = 'Privileged users without phishing-resistant MFA'
                    Category        = 'Users'
                    Severity        = 4
                    Status          = 'Vulnerable'
                    Description     = 'High privilege accounts rely on phishable factors.'
                    Threat          = 'AiTM phishing token theft'
                    Remediation     = 'Enforce FIDO2 Authentication Strength'
                    AffectedObjects = @(@{ id = 'u1' }, @{ id = 'u2' })
                },
                [PSCustomObject]@{
                    FindingId       = 'EF-APP-02'
                    Title           = 'No toxic Graph AppRole assignments'
                    Category        = 'Enterprise Apps'
                    Severity        = 2
                    Status          = 'NotVulnerable'
                    Description     = 'Checked all SPs.'
                    Threat          = ''
                    Remediation     = ''
                    AffectedObjects = @()
                }
            ) | ConvertTo-Json -Depth 5 | Set-Content -Path $tmpEf -Encoding UTF8

            InModuleScope TenantBrief -Parameters @{ Json = $tmpEf } {
                param($Json)
                $res = @(Import-TenantBriefEntraFalconFindings -JsonPath $Json)
                $res.Count | Should -Be 2
                $res[0].TestId | Should -Be 'EF-USR-001'
                $res[0].TestStatus | Should -Be 'Failed'
                $res[0].TestRisk | Should -Be 'High'
                $res[0].TestPillar | Should -Be 'EntraFalcon'
                $res[0].TestResult | Should -Match 'Affected objects: 2'
                $res[0].TestDescription | Should -Match 'Enforce FIDO2'
                $res[1].TestId | Should -Be 'EF-APP-02'
                $res[1].TestStatus | Should -Be 'Passed'
            }
        } finally {
            Remove-Item -Path $tmpEf -Force -ErrorAction SilentlyContinue
        }
    }

    It 'attaches least-privilege RequiredRole and AdminPortal to findings' {
        InModuleScope TenantBrief {
            $tests = @(
                [PSCustomObject]@{ TestId = 'X1'; TestTitle = 'CA check'; TestStatus = 'Failed'; TestPillar = @('Maester (EIDSCA / CIS)') },
                [PSCustomObject]@{ TestId = 'X2'; TestTitle = 'Device check'; TestStatus = 'Passed'; TestPillar = @('Devices') }
            )
            $f = @(New-TenantBriefFindings -Tests $tests -Language tr)
            $f[0].RequiredRole | Should -Be 'Conditional Access Administrator / Security Administrator'
            $f[0].AdminPortal | Should -Match 'entra\.microsoft\.com'
            $f[0].RemediationTr | Should -Match 'Conditional Access Administrator'
            $f[1].RequiredRole | Should -Be 'Intune Administrator'
            $f[1].RemediationTr | Should -Be ''
        }
    }

    It 'filters Maester NotRun/AD/AZDO/GitHub/CISA/ORCA entries and normalizes PesterTestSkipped errors to Skipped' {
        InModuleScope TenantBrief {
            $mockMaester = [PSCustomObject]@{
                Tests = @(
                    [PSCustomObject]@{ Id = 'AD.001'; Title = 'On-prem AD check'; Result = 'NotRun'; Block = 'Active Directory'; ResultDetail = [PSCustomObject]@{} },
                    [PSCustomObject]@{ Id = 'AZDO.001'; Title = 'Azure DevOps repo'; Result = 'Skipped'; Block = 'Azure DevOps'; ResultDetail = [PSCustomObject]@{} },
                    [PSCustomObject]@{ Id = 'CIS.GH.1.2.2'; Title = 'GitHub branch'; Result = 'Skipped'; Block = 'CIS'; ResultDetail = [PSCustomObject]@{} },
                    [PSCustomObject]@{ Id = 'CISA.MS.AAD.1.1v1'; Title = 'Duplicate SCuBA'; Result = 'NotRun'; Block = 'CISA'; ResultDetail = [PSCustomObject]@{} },
                    [PSCustomObject]@{
                        Id = 'MT.1029'; Title = 'MT.1029: Stale accounts are not assigned to privileged roles.'; Result = 'Error'; Severity = 'High'; Block = 'Maester/Entra'
                        ErrorRecord = @([PSCustomObject]@{ FullyQualifiedErrorId = 'PesterTestSkipped' })
                        ResultDetail = [PSCustomObject]@{
                            TestSkipped = 'Error'
                            SkippedReason = 'Authorization failed due to missing permission scope RoleManagementAlert.Read.Directory.'
                        }
                    },
                    [PSCustomObject]@{
                        Id = 'CIS.M365.2.1.7'; Title = 'Ensure anti-phishing policy created'; Result = 'Failed'; Severity = 'High'; Block = 'CIS'
                        ResultDetail = [PSCustomObject]@{ TestDescription = 'Anti-phish policy'; TestResult = 'Default only' }
                    }
                )
            }
            $res = @(Import-TenantBriefMaesterResults -MaesterResult $mockMaester)
            $res.Count | Should -Be 2
            ($res | Where-Object { $_.TestId -eq 'MT.1029' }).TestStatus | Should -Be 'Skipped'
            ($res | Where-Object { $_.TestId -eq 'MT.1029' }).SkippedReason | Should -Match 'RoleManagementAlert\.Read\.Directory'
            $cis = $res | Where-Object { $_.TestId -eq 'CIS.M365.2.1.7' }
            $cis.TestSource | Should -Be 'CIS M365'
            $cis.TestCategory | Should -Match 'Defender for Office 365'
        }
    }

    It 'splits space-joined multi-pillars and attaches canonical DomainPillar, Sources and CorrelatedIds' {
        InModuleScope TenantBrief {
            $rawTests = @(
                [PSCustomObject]@{ TestId = '21781'; TestTitle = 'Sensitivity labels cover AI data'; TestStatus = 'Failed'; TestRisk = 'High'; TestPillar = 'Data AI'; TestCategory = 'Information Protection' },
                [PSCustomObject]@{ TestId = 'EIDSCA.AF01'; TestTitle = 'Sensitivity labels cover AI data'; TestStatus = 'Passed'; TestRisk = 'Low'; TestPillar = 'Maester (EIDSCA / CIS)'; TestSource = 'EIDSCA' }
            )
            $corr = @(New-TenantBriefCorrelatedTests -Tests $rawTests)
            $corr.Count | Should -Be 1
            $corr[0].TestPillar | Should -Contain 'Data'
            $corr[0].TestPillar | Should -Contain 'AI'
            $f = @(New-TenantBriefFindings -Tests $corr -Language tr)
            $f[0].FrameworkRef | Should -Not -Be 'General Control'
            $f[0].FrameworkRef | Should -Match 'Microsoft Zero Trust'
            $f[0].FrameworkRef | Should -Match 'EIDSCA\.AF01'
            $f[0].Sources | Should -Contain 'ZeroTrust'
            $f[0].Sources | Should -Contain 'EIDSCA'
            $f[0].CorrelatedIds | Should -Contain '21781'
            $f[0].CorrelatedIds | Should -Contain 'EIDSCA.AF01'
            $f[0].DomainPillars | Should -Contain 'Data'
            $f[0].DomainPillars | Should -Contain 'AI'
        }
    }

    It 'counts DEVELOPERPACK_E5 as eligible base seat and emits COP-APP-01 under StrictMode' {
        InModuleScope TenantBrief {
            function Get-MgContext { param($ErrorAction) return [PSCustomObject]@{ Account = 'admin@contoso.onmicrosoft.com' } }
            function Get-SPOTenant { param($ErrorAction) throw 'SPO unavailable' }
            function Invoke-MgGraphRequest {
                param($Method, $Uri, $ErrorAction)
                switch -Wildcard ($Uri) {
                    '*/policies/authorizationPolicy' {
                        return [PSCustomObject]@{
                            allowInvitesFrom = 'adminsAndGuestInviters'
                            guestUserRoleId  = '2af84b1e-32c8-42b7-82bc-daa82404023b'
                            defaultUserRolePermissions = [PSCustomObject]@{ permissionGrantPoliciesAssigned = @() }
                        }
                    }
                    '*sensitivityLabels*' { return [PSCustomObject]@{ value = @([PSCustomObject]@{ id = 'lbl1' }) } }
                    '*/admin/sharepoint/settings' { return @{ sharingCapability = 'disabled'; isResharingByExternalUsersEnabled = $false; sharingDomainRestrictionMode = 'none' } }
                    default { return [PSCustomObject]@{ value = @() } }
                }
            }
            try {
                $mockSkus = @([PSCustomObject]@{ skuPartNumber = 'DEVELOPERPACK_E5'; prepaidUnits = @{ enabled = 25 }; consumedUnits = 1 })
                $ti = [PSCustomObject]@{ UserCount = 1; GuestCount = 0; TotalAgents = 0 }
                $cr = Get-TenantBriefCopilotReadiness -SubscribedSkus $mockSkus -TenantInsights $ti -Language tr
                $cr.EligibleBaseSeats | Should -Be 25
                $cr.MaturityLevel | Should -Match 'Yönetilen'
                ($cr.Checks | Where-Object { $_.Id -eq 'COP-LIC-01' }).Status | Should -Be 'Pass'
                $app = $cr.Checks | Where-Object { $_.Id -eq 'COP-APP-01' }
                $app | Should -Not -BeNullOrEmpty
                $app.Status | Should -Be 'Pass'
            } finally {
                Remove-Item function:Get-MgContext, function:Get-SPOTenant, function:Invoke-MgGraphRequest -ErrorAction SilentlyContinue
            }
        }
    }
}
