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

        $isDict = $t -is [System.Collections.IDictionary]
        $readProp = {
            param([string]$n)
            if ($isDict) { if ($t.Contains($n)) { return $t[$n] } return $null }
            $p = $t.PSObject.Properties[$n]
            if ($null -ne $p) { return $p.Value }
            return $null
        }

        $rawId = ([string](& $readProp 'TestId')).Trim()
        $rawIdKey = $rawId.ToUpperInvariant()
        $pillarList = @(ConvertTo-TenantBriefPillarList -PillarValue (& $readProp 'TestPillar'))
        $sourceList = @(Resolve-TenantBriefSourceTag -Test $t)
        $newStatus = [string](& $readProp 'TestStatus')
        $newRisk = [string](& $readProp 'TestRisk')

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
                TestTitle              = & $readProp 'TestTitle'
                TestStatus             = $newStatus
                TestRisk               = $newRisk
                TestPillar             = @($pillarList)
                TestSources            = @($sourceList)
                SourceStatuses         = $srcStatuses
                StatusConflict         = $false
                TestCategory           = & $readProp 'TestCategory'
                TestSfiPillar          = & $readProp 'TestSfiPillar'
                TestImplementationCost = & $readProp 'TestImplementationCost'
                TestMinimumLicense     = & $readProp 'TestMinimumLicense'
                SkippedReason          = & $readProp 'SkippedReason'
                TestResult             = & $readProp 'TestResult'
                TestImpact             = & $readProp 'TestImpact'
                TestDescription        = & $readProp 'TestDescription'
            }
        }
    }

    return @($correlated.Values)
}
