#Requires -Version 7.0
<#
.SYNOPSIS
Migrates TenantBrief's Turkish translation cache from bare TestId keys to Source|TestId schema.

.DESCRIPTION
Converts legacy { "<TestId>": { Title, Desc } } entries into
{ "<Source>|<TestId>": { Title, Desc, Remediation, Reviewed, Source } } without losing records.
#>
[CmdletBinding()]
[OutputType([PSCustomObject])]
param(
    [Parameter(Mandatory = $true)]
    [string]$InputPath,

    [Parameter(Mandatory = $false)]
    [string]$OutputPath = $InputPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if (-not (Test-Path -LiteralPath $InputPath)) {
    throw "Translation cache file not found: $InputPath"
}

$raw = Get-Content -LiteralPath $InputPath -Raw -Encoding UTF8 | ConvertFrom-Json
$out = [ordered]@{}
$inCount = 0

foreach ($prop in $raw.PSObject.Properties) {
    $inCount++
    $k = [string]$prop.Name
    $v = $prop.Value

    $newKey = if ($k -match '^[^|]+\|.+$') {
        $k
    } elseif ($k -like 'SCUBA-*') {
        "CISA SCuBA|$k"
    } elseif ($k -like 'CIS.M365.*') {
        "CIS M365|$k"
    } elseif ($k -like 'EIDSCA.*') {
        "EIDSCA|$k"
    } elseif ($k -like 'ORCA-*') {
        "MDO / ORCA|$k"
    } elseif ($k -like 'MT.*') {
        "Maester|$k"
    } elseif ($k -like 'EF-*') {
        "EntraFalcon|$k"
    } else {
        "ZeroTrust|$k"
    }

    $titleVal = if ($v -and $v.PSObject.Properties['Title']) { [string]$v.Title } else { '' }
    $descVal  = if ($v -and $v.PSObject.Properties['Desc']) { [string]$v.Desc } else { '' }
    $remVal   = if ($v -and $v.PSObject.Properties['Remediation']) { [string]$v.Remediation } else { '' }
    $revVal   = if ($v -and $v.PSObject.Properties['Reviewed']) { [bool]$v.Reviewed } else { $false }
    $srcVal   = if ($v -and $v.PSObject.Properties['Source'] -and $v.Source) { [string]$v.Source } else { 'machine' }

    $out[$newKey] = [PSCustomObject]@{
        Title       = $titleVal
        Desc        = $descVal
        Remediation = $remVal
        Reviewed    = $revVal
        Source      = $srcVal
    }
}

$out | ConvertTo-Json -Depth 5 | Set-Content -Path $OutputPath -Encoding UTF8

return [PSCustomObject]@{
    InputCount  = $inCount
    OutputCount = $out.Count
    OutputPath  = (Resolve-Path -LiteralPath $OutputPath).Path
}
