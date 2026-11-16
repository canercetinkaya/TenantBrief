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
}
