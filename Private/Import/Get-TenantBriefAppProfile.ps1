function Get-TenantBriefAppProfilePath {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter()]
        [string]$ProfilePath
    )
    if (-not [string]::IsNullOrWhiteSpace($ProfilePath)) {
        return $ProfilePath
    }
    $baseDir = if ($env:LOCALAPPDATA) {
        Join-Path $env:LOCALAPPDATA 'TenantBrief'
    } else {
        Join-Path $HOME '.tenantbrief'
    }
    return (Join-Path $baseDir 'app-profile.json')
}

function Get-TenantBriefAppProfile {
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter()]
        [string]$ProfilePath
    )
    $path = Get-TenantBriefAppProfilePath -ProfilePath $ProfilePath
    if (-not (Test-Path -LiteralPath $path)) {
        return $null
    }
    return (Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json)
}
