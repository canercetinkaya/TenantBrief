function Resolve-TenantBriefDomainPillars {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][object]$Test)

    $id = [string](Get-TenantBriefPropertyValue -Object $Test -Name 'TestId')
    $cat = [string](Get-TenantBriefPropertyValue -Object $Test -Name 'TestCategory')
    $pillars = @(ConvertTo-TenantBriefPillarList -PillarValue (Get-TenantBriefPropertyValue -Object $Test -Name 'TestPillar'))

    $domain = New-Object System.Collections.Generic.List[string]
    $seen = New-Object System.Collections.Generic.HashSet[string] ([System.StringComparer]::OrdinalIgnoreCase)
    $addDom = {
        param([string]$D)
        if ($D -and $seen.Add($D)) { $domain.Add($D) }
    }

    foreach ($p in $pillars) {
        switch ($p) {
            'Identity'                       { & $addDom 'Identity' }
            'Devices'                        { & $addDom 'Devices' }
            'Network'                        { & $addDom 'Network' }
            'Infrastructure'                 { & $addDom 'Network' }
            'Data'                           { & $addDom 'Data' }
            'AI'                             { & $addDom 'AI' }
            'SecOps'                         { & $addDom 'SecOps' }
            'Defender for Office 365 (ORCA)' { & $addDom 'SecOps' }
            'EntraFalcon'                    { & $addDom 'Identity' }
            'CISA SCuBA' {
                if ($id -match '\.SECURITYSUITE\.3\.') { & $addDom 'Data' }
                elseif ($id -match '\.(EXO|DEFENDER|SECURITYSUITE)\.') { & $addDom 'SecOps' }
                elseif ($id -match '\.(SHAREPOINT|ONE|POWERBI)\.') { & $addDom 'Data' }
                else { & $addDom 'Identity' }
            }
            'Maester (EIDSCA / CIS)' {
                if ($id -match '^CIS\.M365\.(4\.|5\.1\.4\.6$)' -or $cat -match 'Intune') {
                    & $addDom 'Devices'
                } elseif ($id -match '^CIS\.M365\.(1\.3\.6|1\.3\.7|7\.|8\.1\.1)' -or $cat -match 'Purview|SharePoint') {
                    & $addDom 'Data'
                } elseif ($id -match '^CIS\.M365\.(1\.3\.3|1\.3\.5|2\.|3\.|6\.|8\.6\.1)' -or $cat -match 'Exchange|Defender|Exposure|Audit') {
                    & $addDom 'SecOps'
                } elseif ($cat -match 'Copilot|Agent') {
                    & $addDom 'AI'
                } elseif ($cat -match 'AzureConfig|Network|Infra') {
                    & $addDom 'Network'
                } else {
                    & $addDom 'Identity'
                }
            }
        }
    }

    if ($domain.Count -eq 0) { & $addDom 'Identity' }
    return @($domain.ToArray())
}
