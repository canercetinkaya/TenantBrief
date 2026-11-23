function Import-TenantBriefMaesterResults {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)][object]$MaesterResult,
        [Parameter(Mandatory = $false)][string]$JsonPath
    )

    $testsArray = @()
    if ($MaesterResult -and $MaesterResult.PSObject.Properties['Tests']) {
        $testsArray = @($MaesterResult.Tests)
    } elseif ($JsonPath -and (Test-Path $JsonPath)) {
        $parsed = Get-Content -Path $JsonPath -Raw -Encoding UTF8 | ConvertFrom-Json
        if ($parsed -and $parsed.PSObject.Properties['Tests']) {
            $testsArray = @($parsed.Tests)
        } elseif ($parsed) {
            $testsArray = @($parsed)
        }
    }

    $out = [System.Collections.Generic.List[object]]::new()
    foreach ($item in $testsArray) {
        if ($null -eq $item) { continue }
        $rawId = Get-TenantBriefPropertyValue -Object $item -Name 'Id'
        if (-not $rawId) { $rawId = Get-TenantBriefPropertyValue -Object $item -Name 'ID' }
        if (-not $rawId) { $rawId = Get-TenantBriefPropertyValue -Object $item -Name 'Name' }
        $rawId = [string]$rawId

        $res = [string](Get-TenantBriefPropertyValue -Object $item -Name 'Result')
        # Excluded tags (-ExcludeTag) are recorded by Pester as NotRun; never inflate report totals with them.
        if ($res -eq 'NotRun') { continue }

        $block = [string](Get-TenantBriefPropertyValue -Object $item -Name 'Block')
        if (-not $block) { $block = 'Entra / M365 Baseline' }
        # Skip non-M365-tenant suites (on-prem AD, Azure DevOps, GitHub) and CISA/ORCA duplicates handled natively.
        if ($rawId -match '^(AD|CISA|ORCA|AZDO)\.' -or $rawId -match '^CIS\.GH\.' -or $block -match '^(CISA|ORCA|Azure DevOps|Active Directory)') {
            continue
        }

        $rawTitle = [string](Get-TenantBriefPropertyValue -Object $item -Name 'Title')
        if (-not $rawTitle) { $rawTitle = [string](Get-TenantBriefPropertyValue -Object $item -Name 'Name') }
        $cleanTitle = ($rawTitle -replace '^[A-Za-z0-9\.\-_]+:\s*', '').Trim()
        if (-not $cleanTitle) { $cleanTitle = $rawId }
        if (-not $cleanTitle) { continue }

        $rd = Get-TenantBriefPropertyValue -Object $item -Name 'ResultDetail'
        $errRecords = @(Get-TenantBriefPropertyValue -Object $item -Name 'ErrorRecord')
        $isPesterSkip = ($res -eq 'Error') -and (
            ([string](Get-TenantBriefPropertyValue -Object $rd -Name 'TestSkipped') -eq 'Error') -or
            (@($errRecords | Where-Object { $_ -and ([string](Get-TenantBriefPropertyValue -Object $_ -Name 'FullyQualifiedErrorId')) -match 'PesterTestSkipped' }).Count -gt 0)
        )

        $mappedStatus = if ($isPesterSkip) {
            'Skipped'
        } else {
            switch -Regex ($res) {
                '^Passed$'  { 'Passed' }
                '^Failed$'  { 'Failed' }
                '^Skipped$' { 'Skipped' }
                '^Error$'   { 'Error' }
                default     { 'Investigate' }
            }
        }

        $sev = [string](Get-TenantBriefPropertyValue -Object $item -Name 'Severity')
        $mappedRisk = switch -Regex ($sev) {
            '^(Critical|High)$' { 'High' }
            '^(Low|Info)$'      { 'Low' }
            default             { 'Medium' }
        }

        $catLabel = $block
        if ($rawId -like 'CIS.M365.*' -and $block -eq 'CIS') {
            $catLabel = switch -Regex ($rawId) {
                '^CIS\.M365\.1\.(3\.[67])' { 'CIS M365 · Data & Storage' }
                '^CIS\.M365\.1\.3\.3'      { 'CIS M365 · Exchange & Calendar' }
                '^CIS\.M365\.2\.'          { 'CIS M365 · Defender for Office 365 & EXO' }
                '^CIS\.M365\.3\.'          { 'CIS M365 · Purview Audit' }
                '^CIS\.M365\.4\.'          { 'CIS M365 · Intune' }
                '^CIS\.M365\.5\.1\.4\.6$'  { 'CIS M365 · Intune / BitLocker' }
                '^CIS\.M365\.5\.'          { 'CIS M365 · Entra ID' }
                '^CIS\.M365\.6\.'          { 'CIS M365 · Exchange Online' }
                '^CIS\.M365\.7\.'          { 'CIS M365 · SharePoint & OneDrive' }
                '^CIS\.M365\.8\.'          { 'CIS M365 · Microsoft Teams' }
                default                    { 'CIS M365 · Microsoft 365 Admin' }
            }
        }

        $sourceTag = if ($rawId -like 'CIS.M365.*') { 'CIS M365' } elseif ($rawId -like 'EIDSCA.*') { 'EIDSCA' } else { 'Maester' }

        $desc = [string](Get-TenantBriefPropertyValue -Object $rd -Name 'TestDescription')
        if (-not $desc) { $desc = $cleanTitle }
        $helpUrl = [string](Get-TenantBriefPropertyValue -Object $item -Name 'HelpUrl')
        if ($helpUrl) { $desc = "$desc`n`n[Reference]($helpUrl)" }

        $tRes = [string](Get-TenantBriefPropertyValue -Object $rd -Name 'TestResult')
        $skipR = [string](Get-TenantBriefPropertyValue -Object $rd -Name 'SkippedReason')
        if ($isPesterSkip -and $skipR) {
            if ($skipR -match 'missing permission scope\s+([^\s"''\r\n]+)') {
                $scopeClean = $Matches[1].Trim().TrimEnd('.', ',')
                $skipR = "Graph API izni eksik / Missing permission scope: $scopeClean"
            } elseif ($skipR -match 'S2SUnauthorized|Invalid permission') {
                $skipR = 'Graph / Exchange API izni veya servis yetkisi bu kiracıda etkin değil (S2SUnauthorized).'
            } else {
                $skipR = (($skipR -replace '```[\s\S]*$', '') -replace '\s+', ' ').Trim()
                if ($skipR.Length -gt 240) { $skipR = $skipR.Substring(0, 240) + '...' }
            }
        }

        $out.Add([PSCustomObject]@{
            TestId                 = $rawId
            TestTitle              = $cleanTitle
            TestStatus             = $mappedStatus
            TestRisk               = $mappedRisk
            TestPillar             = 'Maester (EIDSCA / CIS)'
            TestSource             = $sourceTag
            TestCategory           = $catLabel
            TestSfiPillar          = 'Protect identities and secrets'
            TestImplementationCost = 'Low'
            TestMinimumLicense     = ''
            SkippedReason          = $skipR
            TestResult             = $tRes
            TestImpact             = $mappedRisk
            TestDescription        = $desc
        })
    }
    return @($out.ToArray())
}
