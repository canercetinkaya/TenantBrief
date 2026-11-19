function Get-TenantBriefFrameworkScorecard {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][object[]]$Tests,
        [Parameter(Mandatory = $true)][object]$FrameworkConfig,
        [Parameter(Mandatory = $true)][string[]]$FrameworkIds,
        [Parameter(Mandatory = $false)][ValidateSet('tr', 'en')][string]$Language = 'tr'
    )

    # Map each verified benchmark/engine directly to its actual SourceTag so every percentage
    # reflects controls actually measured by that benchmark/engine—never synthetic pillar averages.
    $fallbackSourceMap = @{
        'ZeroTrust'   = 'ZeroTrust'
        'CIS_M365'    = 'CIS M365'
        'CISA_SCuBA'  = 'CISA SCuBA'
        'MDO_ORCA'    = 'MDO / ORCA'
        'EIDSCA'      = 'EIDSCA'
        'Maester'     = 'Maester'
        'EntraFalcon' = 'EntraFalcon'
    }

    foreach ($fwId in $FrameworkIds) {
        $fwMeta = if ($FrameworkConfig -and $FrameworkConfig.PSObject.Properties[$fwId]) { $FrameworkConfig.$fwId } else { $null }
        $fwName = if ($fwMeta) { if ($Language -eq 'tr') { [string]$fwMeta.nameTr } else { [string]$fwMeta.nameEn } } else { $fwId }

        $srcProp = if ($fwMeta) { $fwMeta.PSObject.Properties['sourceTag'] } else { $null }
        $sourceTag = if ($srcProp -and $srcProp.Value) { [string]$srcProp.Value } elseif ($fallbackSourceMap.ContainsKey($fwId)) { $fallbackSourceMap[$fwId] } else { $fwId }
        $urlProp = if ($fwMeta) { $fwMeta.PSObject.Properties['upstreamUrl'] } else { $null }
        $upstreamUrl = if ($urlProp -and $urlProp.Value) { [string]$urlProp.Value } else { '' }

        $fwTests = @($Tests | Where-Object {
            $tSources = @(Resolve-TenantBriefSourceTag -Test $_)
            $tSources -contains $sourceTag
        })

        $fwPass  = @($fwTests | Where-Object { $_.TestStatus -eq 'Passed' }).Count
        $fwFail  = @($fwTests | Where-Object { $_.TestStatus -eq 'Failed' }).Count
        $fwInv   = @($fwTests | Where-Object { $_.TestStatus -eq 'Investigate' }).Count
        $fwSkip  = @($fwTests | Where-Object { $_.TestStatus -in @('Skipped', 'Planned') }).Count
        # 'Error' means the control should have been evaluated but the engine failed: it is a
        # non-pass that must stay visible in the denominator (unmeasured is not compliant).
        $fwErr   = @($fwTests | Where-Object { $_.TestStatus -eq 'Error' }).Count
        $fwEval  = $fwPass + $fwFail + $fwInv + $fwErr
        $fwScore = if ($fwEval -gt 0) { [Math]::Round(($fwPass / $fwEval) * 100, 1) } else { 0 }

        [PSCustomObject]@{
            Id          = $fwId
            Name        = $fwName
            SourceTag   = $sourceTag
            UpstreamUrl = $upstreamUrl
            Score       = $fwScore
            Passed      = $fwPass
            Failed      = $fwFail
            Investigate = $fwInv
            Skipped     = $fwSkip
            Errors      = $fwErr
            Evaluated   = $fwEval
            Total       = $fwTests.Count
        }
    }
}
