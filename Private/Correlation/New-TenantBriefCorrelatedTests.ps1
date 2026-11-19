function New-TenantBriefCorrelatedTests {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [object[]]$Tests
    )

    $statusRank = @{ 'Passed' = 0; 'Planned' = 1; 'Skipped' = 1; 'Investigate' = 2; 'Error' = 3; 'Failed' = 4 }
    $riskRank = @{ 'Low' = 0; 'Medium' = 1; 'High' = 2; 'Critical' = 3 }
    $enrichable = @('TestCategory', 'TestSfiPillar', 'TestImplementationCost', 'TestMinimumLicense', 'SkippedReason', 'TestResult', 'TestImpact', 'TestDescription')
    $crosswalkMap = Get-TenantBriefCrosswalkMap

    # Ordered dictionary keeps report output deterministic between runs.
    $correlated = [ordered]@{}
    $seq = 0
    foreach ($t in @($Tests)) {
        if ($null -eq $t) { continue }
        $seq++

        $rawId = ([string](Get-TenantBriefPropertyValue -Object $t -Name 'TestId')).Trim()
        $rawIdKey = $rawId.ToUpperInvariant()
        $pillarList = @(ConvertTo-TenantBriefPillarList -PillarValue (Get-TenantBriefPropertyValue -Object $t -Name 'TestPillar'))
        $sourceList = @(Resolve-TenantBriefSourceTag -Test $t)
        $newStatus = [string](Get-TenantBriefPropertyValue -Object $t -Name 'TestStatus')
        $newRisk = [string](Get-TenantBriefPropertyValue -Object $t -Name 'TestRisk')

        $cwEntry = if ($rawIdKey -and $crosswalkMap.ContainsKey($rawIdKey)) { $crosswalkMap[$rawIdKey] } else { $null }
        $canonicalId = if ($cwEntry) { [string]$cwEntry.canonicalId } else { '' }
        $corrKey = if ($canonicalId) {
            "CW:$canonicalId"
        } elseif ($rawIdKey) {
            "RAW:$(($sourceList -join '+').ToUpperInvariant())|$rawIdKey"
        } else {
            "SEQ:$seq"
        }

        if ($correlated.Contains($corrKey)) {
            $existing = $correlated[$corrKey]
            foreach ($p in $pillarList) {
                if ($p -and ($existing.TestPillar -notcontains $p)) {
                    $existing.TestPillar = @($existing.TestPillar) + $p
                }
            }
            foreach ($s in $sourceList) {
                if ($s -and ($existing.TestSources -notcontains $s)) {
                    $existing.TestSources = @($existing.TestSources) + $s
                }
                if ($s) {
                    if ($existing.SourceStatuses.Contains($s)) {
                        $prevSrcStatus = [string]$existing.SourceStatuses[$s]
                        if (($statusRank[$newStatus] ?? 0) -gt ($statusRank[$prevSrcStatus] ?? 0)) {
                            $existing.SourceStatuses[$s] = $newStatus
                        }
                    } else {
                        $existing.SourceStatuses[$s] = $newStatus
                    }
                }
            }
            if ($rawId -and ($existing.CorrelatedIds -notcontains $rawId)) {
                $existing.CorrelatedIds = @($existing.CorrelatedIds) + $rawId
            }

            $oldStatus = [string]$existing.TestStatus
            if (($statusRank[$newStatus] ?? 0) -gt ($statusRank[$oldStatus] ?? 0)) {
                $existing.TestStatus = $newStatus
            }
            # Avoid letting an unexecuted Skipped duplicate override or inflate an evaluated control's risk.
            if ($newStatus -notin @('Skipped', 'Planned') -or ($oldStatus -in @('Skipped', 'Planned'))) {
                if (($riskRank[$newRisk] ?? 0) -gt ($riskRank[[string]$existing.TestRisk] ?? 0)) {
                    $existing.TestRisk = $newRisk
                }
            }
            # Keep the richest metadata available from any engine reporting the same control.
            foreach ($field in $enrichable) {
                $incoming = Get-TenantBriefPropertyValue -Object $t -Name $field
                if ($incoming -and -not (Get-TenantBriefPropertyValue -Object $existing -Name $field)) {
                    $existing.$field = $incoming
                }
            }
            $distinctStatuses = @($existing.SourceStatuses.Values | Where-Object { $_ } | Select-Object -Unique)
            $existing.StatusConflict = ($distinctStatuses.Count -gt 1)
        } else {
            $srcStatuses = [ordered]@{}
            foreach ($s in $sourceList) {
                if ($s) { $srcStatuses[$s] = $newStatus }
            }
            $correlated[$corrKey] = [PSCustomObject]@{
                CanonicalId            = $canonicalId
                TestId                 = $rawId
                CorrelatedIds          = if ($rawId) { @($rawId) } else { @() }
                TestTitle              = Get-TenantBriefPropertyValue -Object $t -Name 'TestTitle'
                TestStatus             = $newStatus
                TestRisk               = $newRisk
                TestPillar             = @($pillarList)
                TestSources            = @($sourceList)
                SourceStatuses         = $srcStatuses
                StatusConflict         = $false
                TestCategory           = Get-TenantBriefPropertyValue -Object $t -Name 'TestCategory'
                TestSfiPillar          = Get-TenantBriefPropertyValue -Object $t -Name 'TestSfiPillar'
                TestImplementationCost = Get-TenantBriefPropertyValue -Object $t -Name 'TestImplementationCost'
                TestMinimumLicense     = Get-TenantBriefPropertyValue -Object $t -Name 'TestMinimumLicense'
                SkippedReason          = Get-TenantBriefPropertyValue -Object $t -Name 'SkippedReason'
                TestResult             = Get-TenantBriefPropertyValue -Object $t -Name 'TestResult'
                TestImpact             = Get-TenantBriefPropertyValue -Object $t -Name 'TestImpact'
                TestDescription        = Get-TenantBriefPropertyValue -Object $t -Name 'TestDescription'
            }
        }
    }

    return @($correlated.Values)
}
