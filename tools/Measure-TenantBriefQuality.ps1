<#
.SYNOPSIS
Measures data quality metrics (Q01-Q15) for a TenantBrief JSON/HTML assessment report.

.DESCRIPTION
Implements the fixed Q01-Q15 metric definitions from .agents/skills/report-quality-audit/SKILL.md.
Returns a human-readable summary table by default or a machine-readable JSON object with -AsJson,
including up to 3 sample finding IDs per metric for evidence-backed auditing.

.EXAMPLE
./tools/Measure-TenantBriefQuality.ps1 -Path ./demo/TenantBriefReport-TR.json

.EXAMPLE
./tools/Measure-TenantBriefQuality.ps1 -Path ./demo/TenantBriefReport-TR.json -HtmlPath ./demo/TenantBriefReport-TR.html -AsJson
#>
[CmdletBinding()]
[OutputType([PSCustomObject], [string])]
param(
    [Parameter(Mandatory = $true)]
    [string]$Path,

    [Parameter(Mandatory = $false)]
    [string]$HtmlPath,

    [Parameter(Mandatory = $false)]
    [string]$ReadmePath,

    [Parameter(Mandatory = $false)]
    [string]$DenylistPath,

    [Parameter(Mandatory = $false)]
    [switch]$AsJson
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if (-not (Test-Path -LiteralPath $Path)) {
    throw "Report JSON file not found: $Path"
}

$repoRoot = Split-Path -Path $PSScriptRoot -Parent
if (-not $ReadmePath) { $ReadmePath = Join-Path $repoRoot 'README.md' }
if (-not $DenylistPath) { $DenylistPath = Join-Path $repoRoot 'tests\i18n-denylist.txt' }

$report = Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json
$findings = @()
if ($report.PSObject.Properties['Findings'] -and $null -ne $report.Findings) {
    $findings = @($report.Findings)
}
$frameworks = @()
if ($report.PSObject.Properties['Frameworks'] -and $null -ne $report.Frameworks) {
    $frameworks = @($report.Frameworks)
}
$lang = if ($report.PSObject.Properties['Language'] -and $report.Language) { [string]$report.Language } else { 'tr' }

$getProp = {
    param([object]$Obj, [string]$Name)
    if ($null -eq $Obj) { return $null }
    if ($Obj -is [hashtable]) {
        if ($Obj.ContainsKey($Name)) { return $Obj[$Name] }
        return $null
    }
    $p = $Obj.PSObject.Properties[$Name]
    if ($p) { return $p.Value }
    return $null
}

$sampleIds = {
    param([object[]]$Items)
    $ids = New-Object System.Collections.Generic.List[string]
    foreach ($it in @($Items)) {
        $idVal = [string](& $getProp $it 'Id')
        if ($idVal -and $ids.Count -lt 3) { [void]$ids.Add($idVal) }
    }
    return $ids.ToArray()
}

$canonicalSix = @('Identity', 'Devices', 'Network', 'Data', 'AI', 'SecOps')

# Q01: MultiSourceFindings
$q01Items = @($findings | Where-Object {
    $srcs = @(& $getProp $_ 'Sources' | Where-Object { $_ })
    $srcs.Count -gt 1
})

# Q02: PillarOutsideSix
$q02Items = @($findings | Where-Object {
    $pil = [string](& $getProp $_ 'Pillar')
    $canonicalSix -notcontains $pil
})

# Q03: CommaJoinedPillar
$q03Items = @($findings | Where-Object {
    $dp = [string](& $getProp $_ 'DomainPillar')
    $dp -like '*,*'
})

# Q04a / Q04b / Q04: RiskImpactConflict (reads v2 UserImpact, falls back to v1 Impact for historical reports)
$getImpactVal = {
    param($item)
    $u = [string](& $getProp $item 'UserImpact')
    if ($u) { return $u }
    return [string](& $getProp $item 'Impact')
}
$q04aItems = @($findings | Where-Object {
    ([string](& $getProp $_ 'Risk')) -eq 'High' -and (& $getImpactVal $_) -in @('Low', 'Düşük')
})
$q04bItems = @($findings | Where-Object {
    ([string](& $getProp $_ 'Risk')) -eq 'Low' -and (& $getImpactVal $_) -in @('High', 'Yüksek')
})
$q04Items = @($q04aItems) + @($q04bItems)

# Q05: StatusConflictUnflagged
$q05List = New-Object System.Collections.Generic.List[object]
foreach ($f in $findings) {
    $ss = & $getProp $f 'SourceStatuses'
    if ($null -ne $ss) {
        $vals = @()
        if ($ss -is [hashtable]) { $vals = @($ss.Values | Select-Object -Unique) }
        else { $vals = @($ss.PSObject.Properties | ForEach-Object { $_.Value } | Select-Object -Unique) }
        $flagged = [bool](& $getProp $f 'StatusConflict')
        if ($vals.Count -gt 1 -and -not $flagged) { [void]$q05List.Add($f) }
    }
}
$q05Items = $q05List.ToArray()

# Q06: CostUnknown
$q06Items = @($findings | Where-Object {
    $c = [string](& $getProp $_ 'ImplementationCost')
    [string]::IsNullOrWhiteSpace($c) -or $c -eq 'Unknown'
})

# Q07: FailedWithoutLicense
$q07Items = @($findings | Where-Object {
    ([string](& $getProp $_ 'Status')) -eq 'Failed' -and [string]::IsNullOrWhiteSpace([string](& $getProp $_ 'MinimumLicense'))
})

# Q08a (case-sensitive narrow) & Q08b (SKILL.md case-insensitive)
$enRxCore = '\b(SHALL|SHOULD|MUST|is|are|the|enabled|configured)\b'
$q08aItems = if ($lang -eq 'tr') {
    @($findings | Where-Object { ([string](& $getProp $_ 'Title')) -cmatch $enRxCore })
} else { @() }
$q08bItems = if ($lang -eq 'tr') {
    @($findings | Where-Object { ([string](& $getProp $_ 'Title')) -match $enRxCore })
} else { @() }

# Q09: DenylistHits
$denyTerms = @('tasdiqi')
if ($DenylistPath -and (Test-Path -LiteralPath $DenylistPath)) {
    $loadedTerms = @(Get-Content -LiteralPath $DenylistPath -Encoding UTF8 | ForEach-Object { $_.Trim() } | Where-Object { $_ -and -not $_.StartsWith('#') })
    if ($loadedTerms.Count -gt 0) { $denyTerms = $loadedTerms }
}
$q09List = New-Object System.Collections.Generic.List[object]
foreach ($f in $findings) {
    $blob = "{0} {1} {2}" -f ([string](& $getProp $f 'Title')), ([string](& $getProp $f 'RemediationTr')), ([string](& $getProp $f 'Remediation'))
    foreach ($term in $denyTerms) {
        if ($blob -match [regex]::Escape($term)) {
            [void]$q09List.Add($f)
            break
        }
    }
}
$q09Items = $q09List.ToArray()

# Q10a ('...'), Q10b ('öğrenin/Learn/Related links'), Q10 (union)
$q10aItems = @($findings | Where-Object {
    $rem = [string](& $getProp $_ 'Remediation')
    if (-not $rem) { $rem = [string](& $getProp $_ 'RemediationTr') }
    $rem -and ($rem -match '\.\.\.')
})
$q10bItems = @($findings | Where-Object {
    $rem = [string](& $getProp $_ 'Remediation')
    if (-not $rem) { $rem = [string](& $getProp $_ 'RemediationTr') }
    $rem -and ($rem -cmatch '(öğrenin|Learn|Related links)')
})
$q10Items = @($findings | Where-Object {
    $rem = [string](& $getProp $_ 'Remediation')
    if (-not $rem) { $rem = [string](& $getProp $_ 'RemediationTr') }
    $rem -and ($rem -match '\.\.\.' -or $rem -match '(?i)(öğrenin|Learn more|Related links)')
})

# Q11: PlannedInScore
$q11Items = @($findings | Where-Object { ([string](& $getProp $_ 'Status')) -eq 'Planned' })

# Q12: ScubaProductsCovered (canonical ScubaGear 2.0 product set: max 7; DEFENDER normalizes to SECURITYSUITE; ignores ZeroTrust categories)
$canonicalScubaProducts = @('AAD', 'SECURITYSUITE', 'EXO', 'POWERPLATFORM', 'SHAREPOINT', 'TEAMS', 'POWERBI')
$scubaProdSet = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
foreach ($f in $findings) {
    $fid = [string](& $getProp $f 'Id')
    $srcs = @(& $getProp $f 'Sources')
    if ($fid -notlike 'SCUBA-*' -and ($srcs -notcontains 'CISA SCuBA')) { continue }

    $candidateIds = @($fid) + @(& $getProp $f 'CorrelatedIds')
    $matchedFromId = $false
    foreach ($cid in $candidateIds) {
        $cStr = [string]$cid
        if ($cStr -match '(?i)^SCUBA-MS\.([A-Z0-9]+)\.') {
            $prod = $Matches[1].ToUpperInvariant()
            if ($prod -eq 'DEFENDER') { $prod = 'SECURITYSUITE' }
            if ($canonicalScubaProducts -contains $prod) {
                [void]$scubaProdSet.Add($prod)
                $matchedFromId = $true
            }
        }
    }
    if (-not $matchedFromId -and $fid -like 'SCUBA-*') {
        $catNorm = ([string](& $getProp $f 'Category')).Trim().ToUpperInvariant()
        if ($catNorm -eq 'DEFENDER') { $catNorm = 'SECURITYSUITE' }
        if ($canonicalScubaProducts -contains $catNorm) {
            [void]$scubaProdSet.Add($catNorm)
        }
    }
}
$scubaCats = @($scubaProdSet | Sort-Object)

# Q13: CopilotGateViolation
$q13Count = 0
$q13Samples = New-Object System.Collections.Generic.List[string]
$cr = & $getProp $report 'CopilotReadiness'
if ($cr) {
    $crChecks = @(& $getProp $cr 'Checks' | Where-Object { $null -ne $_ })
    $mat = [string](& $getProp $cr 'MaturityLevel')
    $failedCr = @($crChecks | Where-Object { ([string](& $getProp $_ 'Status')) -eq 'Fail' })
    if ($failedCr.Count -gt 0 -and $mat -and $mat -notmatch '^L1\b') {
        $q13Count = 1
        foreach ($fc in $failedCr) {
            $fid = [string](& $getProp $fc 'Id')
            if ($fid -and $q13Samples.Count -lt 3) { [void]$q13Samples.Add($fid) }
        }
    }
}

# Q14: UnescapedHtml
$q14Val = $null
$q14Samples = New-Object System.Collections.Generic.List[string]
if ($HtmlPath -and (Test-Path -LiteralPath $HtmlPath)) {
    $htmlText = Get-Content -LiteralPath $HtmlPath -Raw -Encoding UTF8
    $xssHits = [regex]::Matches($htmlText, '(?i)(<img[^>]+onerror\s*=|<svg[^>]+onload\s*=|<script>\s*alert\s*\()')
    $q14Val = $xssHits.Count
    foreach ($m in ($xssHits | Select-Object -First 3)) {
        [void]$q14Samples.Add($m.Value.Substring(0, [Math]::Min(40, $m.Value.Length)))
    }
}

# Q15: ClaimMismatch (engines mentioned in README vs Frameworks in report)
$q15Missing = New-Object System.Collections.Generic.List[string]
if ($ReadmePath -and (Test-Path -LiteralPath $ReadmePath)) {
    $readmeText = Get-Content -LiteralPath $ReadmePath -Raw -Encoding UTF8
    $fwIds = @($frameworks | ForEach-Object { [string](& $getProp $_ 'Id') })
    $fwTags = @($frameworks | ForEach-Object { [string](& $getProp $_ 'SourceTag') })
    $claimedEngines = @(
        @{ Name = 'ZeroTrustAssessment'; Pattern = 'ZeroTrustAssessment'; Ids = @('ZeroTrust'); Tags = @('ZeroTrust') },
        @{ Name = 'ScubaGear';           Pattern = 'ScubaGear';           Ids = @('CISA_SCuBA'); Tags = @('CISA SCuBA') },
        @{ Name = 'ORCA';                Pattern = '\bORCA\b';            Ids = @('MDO_ORCA'); Tags = @('MDO / ORCA') },
        @{ Name = 'Maester';             Pattern = '\bMaester\b';         Ids = @('Maester', 'CIS_M365', 'EIDSCA'); Tags = @('Maester', 'CIS M365', 'EIDSCA'); OptionalPattern = '' },
        @{ Name = 'EntraFalcon';         Pattern = 'EntraFalcon';         Ids = @('EntraFalcon'); Tags = @('EntraFalcon'); OptionalPattern = '(?i)(optional\s+`?EntraFalcon|EntraFalcon[^\r\n]{0,80}optional)' }
    )
    foreach ($ce in $claimedEngines) {
        if ($readmeText -match $ce.Pattern) {
            if ($ce.ContainsKey('OptionalPattern') -and $ce['OptionalPattern'] -and ($readmeText -match $ce['OptionalPattern'])) { continue }
            $present = $false
            foreach ($cid in $ce.Ids) { if ($fwIds -contains $cid) { $present = $true } }
            foreach ($ctg in $ce.Tags) { if ($fwTags -contains $ctg) { $present = $true } }
            if (-not $present) { [void]$q15Missing.Add($ce.Name) }
        }
    }
}

$totalFindings = @($findings).Count
$metrics = @(
    [PSCustomObject]@{ Code = 'Q01';  Metric = 'MultiSourceFindings';      Value = @($q01Items).Count;  Target = '> 0';   SampleIds = (& $sampleIds $q01Items) },
    [PSCustomObject]@{ Code = 'Q02';  Metric = 'PillarOutsideSix';         Value = @($q02Items).Count;  Target = '0';     SampleIds = (& $sampleIds $q02Items) },
    [PSCustomObject]@{ Code = 'Q03';  Metric = 'CommaJoinedPillar';        Value = @($q03Items).Count;  Target = '0';     SampleIds = (& $sampleIds $q03Items) },
    [PSCustomObject]@{ Code = 'Q04a'; Metric = 'RiskHighImpactLow';        Value = @($q04aItems).Count; Target = '0';     SampleIds = (& $sampleIds $q04aItems) },
    [PSCustomObject]@{ Code = 'Q04b'; Metric = 'RiskLowImpactHigh';        Value = @($q04bItems).Count; Target = '0';     SampleIds = (& $sampleIds $q04bItems) },
    [PSCustomObject]@{ Code = 'Q04';  Metric = 'RiskImpactConflict';       Value = @($q04Items).Count;  Target = '0';     SampleIds = (& $sampleIds $q04Items) },
    [PSCustomObject]@{ Code = 'Q05';  Metric = 'StatusConflictUnflagged';  Value = @($q05Items).Count;  Target = '0';     SampleIds = (& $sampleIds $q05Items) },
    [PSCustomObject]@{ Code = 'Q06';  Metric = 'CostUnknown';              Value = @($q06Items).Count;  Target = '< 5%';  SampleIds = (& $sampleIds $q06Items) },
    [PSCustomObject]@{ Code = 'Q07';  Metric = 'FailedWithoutLicense';     Value = @($q07Items).Count;  Target = '< 10%'; SampleIds = (& $sampleIds $q07Items) },
    [PSCustomObject]@{ Code = 'Q08a'; Metric = 'EnglishTitlesInTR_Narrow'; Value = @($q08aItems).Count; Target = '< 5';   SampleIds = (& $sampleIds $q08aItems) },
    [PSCustomObject]@{ Code = 'Q08b'; Metric = 'EnglishTitlesInTR';        Value = @($q08bItems).Count; Target = '< 5';   SampleIds = (& $sampleIds $q08bItems) },
    [PSCustomObject]@{ Code = 'Q09';  Metric = 'DenylistHits';             Value = @($q09Items).Count;  Target = '0';     SampleIds = (& $sampleIds $q09Items) },
    [PSCustomObject]@{ Code = 'Q10a'; Metric = 'TruncatedWithEllipsis';    Value = @($q10aItems).Count; Target = '0';     SampleIds = (& $sampleIds $q10aItems) },
    [PSCustomObject]@{ Code = 'Q10b'; Metric = 'RemediationLearnArtifact'; Value = @($q10bItems).Count; Target = '0';     SampleIds = (& $sampleIds $q10bItems) },
    [PSCustomObject]@{ Code = 'Q10';  Metric = 'TruncatedRemediation';     Value = @($q10Items).Count;  Target = '0';     SampleIds = (& $sampleIds $q10Items) },
    [PSCustomObject]@{ Code = 'Q11';  Metric = 'PlannedInScore';           Value = @($q11Items).Count;  Target = '0';     SampleIds = (& $sampleIds $q11Items) },
    [PSCustomObject]@{ Code = 'Q12';  Metric = 'ScubaProductsCovered';     Value = @($scubaCats).Count; Target = '>= 5';  SampleIds = @($scubaCats | Select-Object -First 3) },
    [PSCustomObject]@{ Code = 'Q13';  Metric = 'CopilotGateViolation';     Value = $q13Count;           Target = '0';     SampleIds = $q13Samples.ToArray() },
    [PSCustomObject]@{ Code = 'Q14';  Metric = 'UnescapedHtml';            Value = if ($null -eq $q14Val) { 'NotEvaluated' } else { $q14Val }; Target = '0'; SampleIds = $q14Samples.ToArray() },
    [PSCustomObject]@{ Code = 'Q15';  Metric = 'ClaimMismatch';            Value = $q15Missing.Count;   Target = '0';     SampleIds = @($q15Missing.ToArray() | Select-Object -First 3) }
)

$resultObj = [PSCustomObject]@{
    ReportPath    = (Resolve-Path -LiteralPath $Path).Path
    Tenant        = [string](& $getProp $report 'Tenant')
    Language      = $lang
    TotalFindings = $totalFindings
    GeneratedAt   = (Get-Date).ToString('o')
    Metrics       = $metrics
}

if ($AsJson) {
    return ($resultObj | ConvertTo-Json -Depth 6)
}

return $resultObj
