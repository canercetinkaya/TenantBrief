function Get-TenantBriefFrameworks {
    <#
    .SYNOPSIS
    Lists the verified security benchmarks and engines scored by TenantBrief.

    .DESCRIPTION
    Returns the shipped verified sources (ZeroTrust, CIS_M365, CISA_SCuBA, MDO_ORCA,
    EIDSCA, Maester, EntraFalcon) with their Turkish/English display names, source tag,
    and upstream repository reference.

    The list is read from data/framework-mappings.json, so adding a verified source to
    that file is enough to surface it here.

    .EXAMPLE
    Get-TenantBriefFrameworks | Format-Table Id, NameTr, SourceTag
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param()

    if (-not (Test-Path $script:FrameworkMapPath)) {
        throw "Framework mapping file not found: $script:FrameworkMapPath"
    }

    $json = Get-Content -Path $script:FrameworkMapPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $json.frameworks.PSObject.Properties | ForEach-Object {
        $v = $_.Value
        $srcProp = $v.PSObject.Properties['sourceTag']
        $urlProp = $v.PSObject.Properties['upstreamUrl']
        [PSCustomObject]@{
            Id            = $_.Name
            NameEn        = $v.nameEn
            NameTr        = $v.nameTr
            SourceTag     = if ($srcProp) { [string]$srcProp.Value } else { $_.Name }
            UpstreamUrl   = if ($urlProp) { [string]$urlProp.Value } else { '' }
            DescriptionEn = $v.descriptionEn
            DescriptionTr = $v.descriptionTr
        }
    }
}
