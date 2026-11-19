function Get-TenantBriefLicenseWaste {
    <#
    .SYNOPSIS
    Audits disabled, inactive, guest and overlapping licensed users (R1-R7).

    .DESCRIPTION
    Follows Graph @odata.nextLink pagination when enumerating users, so tenants larger than
    one page are analysed completely. Detects disabled licensed accounts (R1), 90+ day
    inactive licensed users (R2, requires AuditLog.Read.All), unassigned seats (R3),
    overlapping SKUs (R4) and licensed guests (R7).

    .EXAMPLE
    Get-TenantBriefLicenseWaste -InactiveDays 90 | Format-List
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory = $false)]
        [object[]]$SubscribedSkus,

        [Parameter(Mandatory = $false)]
        [object[]]$Users,

        [Parameter(Mandatory = $false)]
        [ValidateSet('tr', 'en')]
        [string]$Language = 'tr',

        [Parameter(Mandatory = $false)]
        [int]$InactiveDays = 90
    )

    $catalogPath = Join-Path $script:ModuleRoot 'data/sku-catalog.json'
    $catalogJson = Get-Content -Path $catalogPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $skuPriceMap = @{}
    $skuNameMap = @{}
    $skuGuidToPart = @{}
    # SKUs explicitly marked as non-billable (free tiers, developer sandboxes) must not be reported
    # as recoverable waste; 10,000 free seats would otherwise dominate the R3 counter.
    $skuBillableMap = @{}
    foreach ($c in @($catalogJson.skus)) {
        $skuPartKey = [string]$c.skuPartNumber
        $skuPriceMap[$skuPartKey] = [double]$c.usdPerUserMonth
        $skuNameMap[$skuPartKey]  = [string]$c.name
        $wasteProp = $c.PSObject.Properties['countsAsWaste']
        $skuBillableMap[$skuPartKey] = if ($wasteProp) { [bool]$wasteProp.Value } else { $true }
    }

    if (-not $SubscribedSkus -and (Get-MgContext -ErrorAction SilentlyContinue)) {
        $subResp = Invoke-MgGraphRequest -Method GET -Uri 'https://graph.microsoft.com/v1.0/subscribedSkus' -ErrorAction SilentlyContinue
        if ($subResp -and $subResp.value) { $SubscribedSkus = @($subResp.value) }
    }
    foreach ($s in @($SubscribedSkus | Where-Object { $null -ne $_ })) {
        if ($s.PSObject.Properties['skuId'] -and $s.skuId) {
            $skuGuidToPart[[string]$s.skuId] = [string]$s.skuPartNumber
        } elseif ($s -is [hashtable] -and $s['skuId']) {
            $skuGuidToPart[[string]$s['skuId']] = [string]$s['skuPartNumber']
        }
    }

    $signInChecked = $false
    if (-not $Users -and (Get-MgContext -ErrorAction SilentlyContinue)) {
        try {
            $Users = @(Get-TenantBriefGraphCollection -Uri 'https://graph.microsoft.com/v1.0/users?$select=id,displayName,userPrincipalName,accountEnabled,userType,assignedLicenses,signInActivity&$top=999' -ErrorAction Stop)
            $signInChecked = $true
        } catch {
            Write-Verbose "signInActivity alani okunamadi, pasif kullanici analizi atlanacak: $($_.Exception.Message)"
            $signInChecked = $false
            try {
                $Users = @(Get-TenantBriefGraphCollection -Uri 'https://graph.microsoft.com/v1.0/users?$select=id,displayName,userPrincipalName,accountEnabled,userType,assignedLicenses&$top=999' -ErrorAction SilentlyContinue)
            } catch {
                Write-Verbose "Kullanici listesi okunamadi: $($_.Exception.Message)"
                $Users = $null
            }
        }
        if ($Users -and $Users.Count -eq 0) { $Users = $null }
    } else {
        $signInChecked = $true
    }

    $disabledCount = 0; $disabledUsdMo = 0.0
    $inactiveCount = 0; $inactiveUsdMo = 0.0
    $guestCount = 0;    $guestUsdMo = 0.0
    $overlapCount = 0;  $overlapUsdMo = 0.0
    $overlapDetails = @()
    $cutoff = (Get-Date).ToUniversalTime().AddDays(-$InactiveDays)
    $overlaps = @($catalogJson.overlaps)

    foreach ($u in @($Users)) {
        $assigned = @($u.assignedLicenses)
        if ($assigned.Count -eq 0) { continue }

        $parts = @()
        $userMonthlyCost = 0.0
        foreach ($lic in $assigned) {
            $part = $null
            if ($lic.PSObject.Properties['skuPartNumber'] -and $lic.skuPartNumber) { $part = [string]$lic.skuPartNumber }
            elseif ($lic.PSObject.Properties['skuId'] -and $skuGuidToPart.ContainsKey([string]$lic.skuId)) { $part = $skuGuidToPart[[string]$lic.skuId] }
            elseif ($lic -is [hashtable] -and $lic['skuPartNumber']) { $part = [string]$lic['skuPartNumber'] }
            elseif ($lic -is [hashtable] -and $lic['skuId'] -and $skuGuidToPart.ContainsKey([string]$lic['skuId'])) { $part = $skuGuidToPart[[string]$lic['skuId']] }
            if ($part) {
                $parts += $part
                if ($skuPriceMap.ContainsKey($part)) { $userMonthlyCost += $skuPriceMap[$part] }
            }
        }

        $isEnabled = if ($u.PSObject.Properties['accountEnabled']) { [bool]$u.accountEnabled } else { $true }
        $uType = if ($u.PSObject.Properties['userType']) { [string]$u.userType } else { 'Member' }

        if (-not $isEnabled) {
            $disabledCount++
            $disabledUsdMo += $userMonthlyCost
        } elseif ($uType -eq 'Guest') {
            $guestCount++
            $guestUsdMo += $userMonthlyCost
        } elseif ($signInChecked -and $u.PSObject.Properties['signInActivity'] -and $u.signInActivity -and $u.signInActivity.PSObject.Properties['lastSignInDateTime'] -and $u.signInActivity.lastSignInDateTime) {
            try {
                $lastDt = [DateTime]::Parse([string]$u.signInActivity.lastSignInDateTime).ToUniversalTime()
                if ($lastDt -lt $cutoff) {
                    $inactiveCount++
                    $inactiveUsdMo += $userMonthlyCost
                }
            } catch {}
        }

        if ($parts.Count -gt 1) {
            foreach ($ov in $overlaps) {
                if (($parts -contains [string]$ov.skuA) -and ($parts -contains [string]$ov.skuB)) {
                    $overlapCount++
                    $redCost = if ($skuPriceMap.ContainsKey([string]$ov.redundant)) { $skuPriceMap[[string]$ov.redundant] } else { 0.0 }
                    $overlapUsdMo += $redCost
                    if ($overlapDetails.Count -lt 25) {
                        $overlapDetails += [PSCustomObject]@{
                            Pair      = "$($ov.skuA) + $($ov.skuB)"
                            Redundant = [string]$ov.redundant
                            SavedMo   = $redCost
                            Reason    = if ($Language -eq 'tr') { [string]$ov.reasonTr } else { [string]$ov.reasonEn }
                        }
                    }
                }
            }
        }
    }

    $unassignedUsdMo = 0.0
    $unassignedSeats = 0
    foreach ($s in @($SubscribedSkus | Where-Object { $null -ne $_ -and $_.PSObject.Properties['skuPartNumber'] })) {
        $part = [string]$s.skuPartNumber
        $en = [int]$s.prepaidUnits.enabled
        $con = [int]$s.consumedUnits
        $isBillable = if ($skuBillableMap.ContainsKey($part)) { [bool]$skuBillableMap[$part] } else { $true }
        if ($isBillable -and $en -gt $con) {
            $diff = $en - $con
            $unassignedSeats += $diff
            if ($skuPriceMap.ContainsKey($part)) { $unassignedUsdMo += ($diff * $skuPriceMap[$part]) }
        }
    }

    $totalRecMo = [Math]::Round($unassignedUsdMo + $disabledUsdMo + $overlapUsdMo, 2)
    return [PSCustomObject]@{
        SignInActivityAvailable = $signInChecked
        UnassignedSeats         = $unassignedSeats
        UnassignedUsdMo         = [Math]::Round($unassignedUsdMo, 2)
        DisabledLicensedUsers   = $disabledCount
        DisabledUsdMo           = [Math]::Round($disabledUsdMo, 2)
        Inactive90dUsers        = $inactiveCount
        InactiveUsdMo           = [Math]::Round($inactiveUsdMo, 2)
        LicensedGuests          = $guestCount
        GuestUsdMo              = [Math]::Round($guestUsdMo, 2)
        DuplicateOverlapCount   = $overlapCount
        DuplicateOverlapUsdMo   = [Math]::Round($overlapUsdMo, 2)
        OverlapSamples          = @($overlapDetails)
        TotalRecoverableUsdMo   = $totalRecMo
        TotalRecoverableUsdYr   = [Math]::Round($totalRecMo * 12, 2)
    }
}
