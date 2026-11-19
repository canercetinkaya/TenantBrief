function ConvertTo-TenantBriefPillarList {
    [CmdletBinding()]
    param([Parameter(Mandatory = $false)][object]$PillarValue)

    $knownMulti = @(
        'CISA SCuBA',
        'Defender for Office 365 (ORCA)',
        'Maester (EIDSCA / CIS)'
    )
    $rawTokens = New-Object System.Collections.Generic.List[string]
    foreach ($entry in @($PillarValue)) {
        if ($null -eq $entry) { continue }
        $s = ([string]$entry).Trim()
        if (-not $s) { continue }
        # Split comma-separated entries first, preserving known multi-word engine pillar labels.
        foreach ($part in ($s -split '\s*,\s*')) {
            $p = $part.Trim()
            if (-not $p) { continue }
            if ($knownMulti -contains $p) {
                $rawTokens.Add($p)
            } elseif ($p -match '\s+' -and ($p -notin @('CISA SCuBA', 'EntraFalcon', 'General'))) {
                foreach ($sub in ($p -split '\s+')) {
                    if ($sub.Trim()) { $rawTokens.Add($sub.Trim()) }
                }
            } else {
                $rawTokens.Add($p)
            }
        }
    }

    $seen = New-Object System.Collections.Generic.HashSet[string] ([System.StringComparer]::OrdinalIgnoreCase)
    $out = New-Object System.Collections.Generic.List[string]
    foreach ($tok in $rawTokens) {
        if ($seen.Add($tok)) { $out.Add($tok) }
    }
    return @($out.ToArray())
}
