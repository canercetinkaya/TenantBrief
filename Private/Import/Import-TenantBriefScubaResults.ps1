function Import-TenantBriefScubaResults {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$Path)

    if (-not (Test-Path $Path)) { return @() }
    $scubaJson = if (Test-Path $Path -PathType Leaf) {
        Get-Item $Path
    } else {
        $f = Get-ChildItem -Path $Path -Filter 'ScubaResults*.json' -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
        if (-not $f) { $f = Get-ChildItem -Path $Path -Filter '*Report.json' -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1 }
        $f
    }
    if (-not $scubaJson) { return @() }

    $scubaData = Get-Content -Path $scubaJson.FullName -Raw -Encoding UTF8 | ConvertFrom-Json
    $scCount = 0
    $scubaControlList = [System.Collections.Generic.List[object]]::new()
    if ($scubaData -and $scubaData.PSObject.Properties['Results'] -and $null -ne $scubaData.Results) {
        if ($scubaData.Results -is [System.Array]) {
            foreach ($grp in @($scubaData.Results)) {
                if ($null -eq $grp) { continue }
                if ($grp.PSObject.Properties['Controls']) {
                    foreach ($c in @($grp.Controls)) {
                        if ($null -ne $c) { $scubaControlList.Add($c) }
                    }
                } else {
                    $scubaControlList.Add($grp)
                }
            }
        } else {
            foreach ($prop in $scubaData.Results.PSObject.Properties) {
                if ($null -eq $prop.Value) { continue }
                foreach ($entry in @($prop.Value)) {
                    if ($null -eq $entry) { continue }
                    if ($entry.PSObject.Properties['Controls']) {
                        foreach ($c in @($entry.Controls)) {
                            if ($null -ne $c) { $scubaControlList.Add([PSCustomObject]@{ Cat = [string]$prop.Name; Item = $c }) }
                        }
                    } else {
                        $scubaControlList.Add([PSCustomObject]@{ Cat = [string]$prop.Name; Item = $entry })
                    }
                }
            }
        }
    }

    $out = [System.Collections.Generic.List[object]]::new()
    foreach ($wrap in $scubaControlList) {
        if ($null -eq $wrap) { continue }
        $cat  = if ($wrap.PSObject.Properties['Cat']) { [string]$wrap.Cat } else { 'AAD' }
        $item = if ($wrap.PSObject.Properties['Item']) { $wrap.Item } else { $wrap }
        if ($null -eq $item) { continue }
        $ctrl = if ($item.PSObject.Properties['Control ID']) { [string]$item.'Control ID' } elseif ($item.PSObject.Properties['Control']) { [string]$item.Control } else { "$($scCount + 1)" }
        $reqRaw = if ($item.PSObject.Properties['Requirement']) { [string]$item.Requirement } else { "SCuBA Control $ctrl" }
        $reqClean = ($reqRaw -replace "<div class=['""]policy-indicators['""]>[\s\S]*$", '') -replace '<[^>]+>', ' '
        $req  = ([System.Net.WebUtility]::HtmlDecode($reqClean) -replace '\s+', ' ').Trim()
        $res  = if ($item.PSObject.Properties['Result']) { [string]$item.Result } else { '' }
        $crit = if ($item.PSObject.Properties['Criticality']) { [string]$item.Criticality } else { 'Should' }
        $detRaw = if ($item.PSObject.Properties['Details']) { [string]$item.Details } else { '' }
        $det  = ([System.Net.WebUtility]::HtmlDecode(($detRaw -replace '<[^>]+>', ' ')) -replace '\s+', ' ').Trim()
        if (-not $req) { continue }
        $scCount++
        $mappedStatus = switch -Regex ($res) {
            '^(Pass|Met)$'     { 'Passed' }
            '^(Fail|Not Met)$' { 'Failed' }
            default            { 'Investigate' }
        }
        $out.Add([PSCustomObject]@{
            TestId                 = if ($ctrl -like 'SCUBA-*') { $ctrl } else { "SCUBA-$ctrl" }
            TestTitle              = $req
            TestStatus             = $mappedStatus
            TestRisk               = if ($crit -match 'Shall') { 'High' } else { 'Medium' }
            TestPillar             = 'CISA SCuBA'
            TestSource             = 'CISA SCuBA'
            TestCategory           = $cat
            TestSfiPillar          = 'CISA SCuBA'
            TestImplementationCost = ''
            TestMinimumLicense     = ''
            SkippedReason          = ''
            TestResult             = $det
            TestImpact             = if ($crit -match 'Shall') { 'High' } else { 'Medium' }
            TestDescription        = $req
        })
    }
    return @($out.ToArray())
}
