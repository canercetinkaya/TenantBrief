function Get-TenantBriefLicenseRoi {
    <#
    .SYNOPSIS
    Computes purchased/assigned/idle seat ratios and idle USD estimate per SKU.

    .DESCRIPTION
    Reads Graph /v1.0/subscribedSkus (or accepts -SubscribedSkus) and prices each SKU from
    data/sku-catalog.json to estimate unused spend per month.

    .EXAMPLE
    Get-TenantBriefLicenseRoi | Format-Table ProductName, Purchased, Assigned, Unassigned, EstimatedIdleUsdMo
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory = $false)]
        [object[]]$SubscribedSkus
    )

    $catalogPath = Join-Path $script:ModuleRoot 'data/sku-catalog.json'
    $catalog = (Get-Content -Path $catalogPath -Raw -Encoding UTF8 | ConvertFrom-Json).skus
    $skuIndex = @{}
    foreach ($c in $catalog) { $skuIndex[$c.skuPartNumber] = $c }

    if (-not $SubscribedSkus) {
        $resp = Invoke-MgGraphRequest -Method GET -Uri 'https://graph.microsoft.com/v1.0/subscribedSkus'
        $SubscribedSkus = @($resp.value)
    }

    $results = foreach ($s in $SubscribedSkus) {
        $part = [string]$s.skuPartNumber
        $enabled = [int]$s.prepaidUnits.enabled
        $consumed = [int]$s.consumedUnits
        if ($enabled -le 0) { continue }

        $unassigned = [Math]::Max(0, $enabled - $consumed)
        $utilPct = [Math]::Round(($consumed / $enabled) * 100, 1)
        $meta = $skuIndex[$part]
        $unitUsd = if ($meta) { [double]$meta.usdPerUserMonth } else { 0.0 }
        $idleUsdMonth = [Math]::Round($unassigned * $unitUsd, 2)
        $billableProp = if ($meta) { $meta.PSObject.Properties['countsAsWaste'] } else { $null }
        $billable = if ($billableProp) { [bool]$billableProp.Value } else { $unitUsd -gt 0 }

        [PSCustomObject]@{
            SkuPartNumber       = $part
            ProductName         = if ($meta) { $meta.name } else { $part }
            Category            = if ($meta) { $meta.category } else { 'Other' }
            Purchased           = $enabled
            Assigned            = $consumed
            Unassigned          = $unassigned
            UtilizationPercent  = $utilPct
            Billable            = $billable
            EstimatedIdleUsdMo  = $idleUsdMonth
        }
    }
    return @($results)
}
