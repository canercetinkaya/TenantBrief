function Import-TenantBriefEntraFalconFindings {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$JsonPath
    )

    if (-not (Test-Path $JsonPath)) { return @() }
    $rawList = @(Get-Content -Path $JsonPath -Raw -Encoding UTF8 | ConvertFrom-Json)
    $out = @()

    foreach ($f in $rawList) {
        if ($null -eq $f) { continue }
        $fid = [string](Get-TenantBriefPropertyValue -Object $f -Name 'FindingId')
        if (-not $fid) { continue }
        $tid = if ($fid -like 'EF-*') { $fid } else { "EF-$fid" }

        $title = [string](Get-TenantBriefPropertyValue -Object $f -Name 'Title')
        if (-not $title) { continue }

        $cat = [string](Get-TenantBriefPropertyValue -Object $f -Name 'Category')
        if (-not $cat) { $cat = 'Entra ID' }

        $sevNum = 0
        [void][int]::TryParse([string](Get-TenantBriefPropertyValue -Object $f -Name 'Severity'), [ref]$sevNum)
        $risk = if ($sevNum -ge 3) { 'High' } elseif ($sevNum -eq 2) { 'Medium' } else { 'Low' }

        $stRaw = [string](Get-TenantBriefPropertyValue -Object $f -Name 'Status')
        $status = switch -Regex ($stRaw) {
            '^Vulnerable$'    { 'Failed' }
            '^NotVulnerable$' { 'Passed' }
            '^Skipped$'       { 'Skipped' }
            default           { 'Investigate' }
        }

        $desc = [string](Get-TenantBriefPropertyValue -Object $f -Name 'Description')
        $rem = [string](Get-TenantBriefPropertyValue -Object $f -Name 'Remediation')
        $threat = [string](Get-TenantBriefPropertyValue -Object $f -Name 'Threat')
        $affRaw = Get-TenantBriefPropertyValue -Object $f -Name 'AffectedObjects'
        $affCount = if ($null -eq $affRaw) { 0 } else { @($affRaw).Count }

        $resTxt = if ($affCount -gt 0) { "Affected objects: $affCount`n`n$threat".Trim() } else { $threat }
        $fullDesc = if ($rem) { "$desc`n`n**Remediation action**`n$rem".Trim() } else { $desc }

        $out += [PSCustomObject]@{
            TestId                 = $tid
            TestTitle              = $title
            TestStatus             = $status
            TestRisk               = $risk
            TestPillar             = 'EntraFalcon'
            TestCategory           = $cat
            TestSfiPillar          = 'Protect identities and secrets'
            TestImplementationCost = 'Medium'
            TestMinimumLicense     = 'Entra ID P1/P2'
            SkippedReason          = if ($status -eq 'Skipped') { 'Skipped by EntraFalcon' } else { '' }
            TestResult             = $resTxt
            TestImpact             = $risk
            TestDescription        = $fullDesc
        }
    }
    return @($out)
}
