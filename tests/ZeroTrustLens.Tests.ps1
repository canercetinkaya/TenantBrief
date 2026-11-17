BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '..\ZeroTrustLens.psd1') -Force
}

Describe 'ZeroTrustLens Module' {
    It 'Exports expected functions' {
        $cmds = (Get-Module ZeroTrustLens).ExportedFunctions.Keys
        $cmds | Should -Contain 'Connect-ZtLens'
        $cmds | Should -Contain 'Invoke-ZtLensAssessment'
        $cmds | Should -Contain 'Get-ZtLensFrameworks'
        $cmds | Should -Contain 'Get-ZtLensLicenseRoi'
        $cmds | Should -Contain 'Get-ZtLensLicenseWaste'
        $cmds | Should -Contain 'Get-ZtLensCopilotReadiness'
        $cmds | Should -Contain 'Compare-ZtLensReports'
        $cmds | Should -Contain 'Export-ZtLensExecutiveSummary'
    }

    It 'Lists 5 compliance frameworks' {
        $fws = Get-ZtLensFrameworks
        $fws.Count | Should -Be 5
    }

    It 'Calculates License ROI from SKU payload' {
        $mockSkus = @(
            [PSCustomObject]@{ skuPartNumber = 'SPE_E5'; prepaidUnits = @{ enabled = 100 }; consumedUnits = 75 },
            [PSCustomObject]@{ skuPartNumber = 'AAD_PREMIUM_P2'; prepaidUnits = @{ enabled = 50 }; consumedUnits = 50 }
        )
        $roi = Get-ZtLensLicenseRoi -SubscribedSkus $mockSkus
        $roi.Count | Should -Be 2
        $roi[0].Unassigned | Should -Be 25
        $roi[0].EstimatedIdleUsdMo | Should -Be 1425
    }

    It 'Audits disabled, inactive, guest and overlapping SKUs via Get-ZtLensLicenseWaste' {
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
        $w = Get-ZtLensLicenseWaste -SubscribedSkus $skus -Users $users -Language en
        $w.UnassignedSeats | Should -Be 3
        $w.DisabledLicensedUsers | Should -Be 1
        $w.DisabledUsdMo | Should -Be 57
        $w.LicensedGuests | Should -Be 1
        $w.DuplicateOverlapCount | Should -Be 1
        $w.DuplicateOverlapUsdMo | Should -Be 36
        $w.Inactive90dUsers | Should -Be 1
    }

    It 'Follows @odata.nextLink pagination when enumerating users' {
        InModuleScope ZeroTrustLens {
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
                $res = @(Get-ZtLensGraphCollection -Uri 'https://graph.microsoft.com/v1.0/users?$top=999')
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
        $cr = Get-ZtLensCopilotReadiness -SubscribedSkus $mockSkus -TenantInsights $ti -OfflineOnly -Language tr
        $cr.EligibleBaseSeats | Should -Be 25
        $cr.CopilotSeats | Should -Be 5
        $cr.Checks.Count | Should -BeGreaterThan 1
        $cr.Warnings.Count | Should -BeGreaterThan 0
    }
}
