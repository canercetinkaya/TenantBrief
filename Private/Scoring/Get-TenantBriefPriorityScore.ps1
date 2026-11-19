function Get-TenantBriefPriorityScore {
    [CmdletBinding()]
    param(
        [string]$Status,
        [string]$Risk,
        [string]$ImplementationCost,
        [int]$SourceCount = 1,
        [bool]$StatusConflict = $false
    )
    if ($Status -eq 'Passed' -or $Status -eq 'Planned') { return 0 }
    $cfg = Get-TenantBriefScoringConfig
    $rW = if ($cfg -and $cfg.riskWeights.PSObject.Properties[$Risk]) { [int]$cfg.riskWeights.$Risk } else { 8 }
    $sW = if ($cfg -and $cfg.statusWeights.PSObject.Properties[$Status]) { [int]$cfg.statusWeights.$Status } else { 0 }
    $costKey = if ([string]::IsNullOrWhiteSpace($ImplementationCost)) { 'Unknown' } else { $ImplementationCost }
    $cB = if ($cfg -and $cfg.costBonus.PSObject.Properties[$costKey]) { [int]$cfg.costBonus.$costKey } else { 0 }
    $extraSrc = [Math]::Max(0, $SourceCount - 1)
    $perExtra = if ($cfg) { [int]$cfg.multiSourceBonusPerExtra } else { 4 }
    $cap = if ($cfg) { [int]$cfg.multiSourceBonusCap } else { 10 }
    $mB = [Math]::Min($cap, ($extraSrc * $perExtra))
    $confB = if ($StatusConflict -and $cfg) { [int]$cfg.conflictBonus } else { 0 }
    return [Math]::Min(100, [Math]::Max(0, ($rW + $sW + $cB + $mB + $confB)))
}
