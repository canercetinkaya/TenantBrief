function Resolve-TenantBriefSourceTag {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][object]$Test)

    $existing = @(Get-TenantBriefPropertyValue -Object $Test -Name 'TestSources')
    $list = New-Object System.Collections.Generic.List[string]
    $seen = New-Object System.Collections.Generic.HashSet[string] ([System.StringComparer]::OrdinalIgnoreCase)
    $addTag = {
        param([string]$Tag)
        if ($Tag -and $seen.Add($Tag)) { $list.Add($Tag) }
    }

    foreach ($e in $existing) { & $addTag ([string]$e) }
    $explicit = [string](Get-TenantBriefPropertyValue -Object $Test -Name 'TestSource')
    if ($explicit) { & $addTag $explicit }

    $id = [string](Get-TenantBriefPropertyValue -Object $Test -Name 'TestId')
    $corr = @(Get-TenantBriefPropertyValue -Object $Test -Name 'CorrelatedIds')
    $allIds = @($id) + @($corr | ForEach-Object { [string]$_ })
    $pillars = @(ConvertTo-TenantBriefPillarList -PillarValue (Get-TenantBriefPropertyValue -Object $Test -Name 'TestPillar'))

    if ((@($allIds | Where-Object { $_ -like 'SCUBA-*' }).Count -gt 0) -or ($pillars -contains 'CISA SCuBA')) { & $addTag 'CISA SCuBA' }
    if ((@($allIds | Where-Object { $_ -like 'ORCA-*' }).Count -gt 0) -or ($pillars -contains 'Defender for Office 365 (ORCA)')) { & $addTag 'MDO / ORCA' }
    if ((@($allIds | Where-Object { $_ -like 'EF-*' }).Count -gt 0) -or ($pillars -contains 'EntraFalcon')) { & $addTag 'EntraFalcon' }
    if ((@($allIds | Where-Object { $_ -like 'FT.*' }).Count -gt 0) -or ($pillars -contains 'FastTrack')) { & $addTag 'FastTrack' }
    if (@($allIds | Where-Object { $_ -like 'CIS.M365.*' }).Count -gt 0) { & $addTag 'CIS M365' }
    if (@($allIds | Where-Object { $_ -like 'EIDSCA.*' }).Count -gt 0) { & $addTag 'EIDSCA' }
    if (($pillars -contains 'Maester (EIDSCA / CIS)') -and -not $explicit -and -not ($seen.Contains('CIS M365') -or $seen.Contains('EIDSCA'))) {
        & $addTag 'Maester'
    }

    $ztPillars = @('Identity', 'Devices', 'Network', 'Data', 'Infrastructure', 'SecOps', 'AI')
    if (@($pillars | Where-Object { $ztPillars -contains $_ }).Count -gt 0 -or ($id -match '^\d+$')) {
        & $addTag 'ZeroTrust'
    }

    if ($list.Count -eq 0) { & $addTag 'ZeroTrust' }
    return @($list.ToArray())
}
