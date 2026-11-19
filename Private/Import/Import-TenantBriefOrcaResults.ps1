function Import-TenantBriefOrcaResults {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$Path)

    if (-not (Test-Path $Path)) { return @() }
    $orcaFile = if (Test-Path $Path -PathType Leaf) {
        Get-Item $Path
    } else {
        Get-ChildItem -Path $Path -Filter '*.json' -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
    }
    if (-not $orcaFile) { return @() }

    $orcaData = Get-Content -Path $orcaFile.FullName -Raw -Encoding UTF8 | ConvertFrom-Json
    $orcaItems = if ($orcaData.PSObject.Properties['Results']) { @($orcaData.Results) } elseif ($orcaData.PSObject.Properties['Checks']) { @($orcaData.Checks) } else { @($orcaData) }
    $ocCount = 0
    $out = @()
    foreach ($item in $orcaItems) {
        $cName = if ($item.PSObject.Properties['Name'] -and $item.Name) { [string]$item.Name } elseif ($item.PSObject.Properties['CheckName'] -and $item.CheckName) { [string]$item.CheckName } else { '' }
        if (-not $cName) { continue }
        $ocCount++
        $ctrl = if ($item.PSObject.Properties['Control']) { [string]$item.Control } else { "ORCA-$ocCount" }
        $st   = if ($item.PSObject.Properties['Result']) { [string]$item.Result } else { '' }
        $area = if ($item.PSObject.Properties['Area'] -and $item.Area) { [string]$item.Area } else { 'Defender for Office 365' }
        $rec  = if ($item.PSObject.Properties['FailRecommendation']) { [string]$item.FailRecommendation } else { '' }
        $passTxt = if ($item.PSObject.Properties['PassText']) { [string]$item.PassText } else { '' }
        $imp  = if ($item.PSObject.Properties['Importance']) { [string]$item.Importance } else { '' }
        $chiRaw = if ($item.PSObject.Properties['ChiValue']) { $item.ChiValue } else { $null }
        $mappedRisk = if ($null -ne $chiRaw -and "$chiRaw" -ne '') {
            switch ([string]$chiRaw) {
                { $_ -in @('100', 'Critical') }       { 'Critical' }
                { $_ -in @('20', 'VeryHigh', '15', 'High') } { 'High' }
                { $_ -in @('10', 'Medium') }          { 'Medium' }
                { $_ -in @('5', 'Low', '0', 'NotRated') } { 'Low' }
                default                               { 'Medium' }
            }
        } else { 'Medium' }
        $mappedOrStatus = if ($st -in @('1', 'Pass', 'OK')) { 'Passed' } elseif ($st -in @('2', '0', 'Informational', 'Info', 'None')) { 'Investigate' } else { 'Failed' }
        $out += [PSCustomObject]@{
            TestId                 = if ($ctrl -like 'ORCA-*') { $ctrl } else { "ORCA-$ctrl" }
            TestTitle              = $cName
            TestStatus             = $mappedOrStatus
            TestRisk               = $mappedRisk
            TestPillar             = 'Defender for Office 365 (ORCA)'
            TestSource             = 'MDO / ORCA'
            TestCategory           = $area
            TestSfiPillar          = 'Defender for Office 365'
            TestImplementationCost = ''
            TestMinimumLicense     = ''
            SkippedReason          = ''
            TestResult             = if ($mappedOrStatus -eq 'Passed' -and $passTxt) { $passTxt } else { $rec }
            TestImpact             = 'Medium'
            TestDescription        = if ($imp) { $imp } else { $cName }
        }
    }
    return @($out)
}
