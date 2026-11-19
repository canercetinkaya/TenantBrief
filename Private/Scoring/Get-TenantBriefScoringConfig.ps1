function Get-TenantBriefScoringConfig {
    [CmdletBinding()]
    param()
    if ($null -ne $script:ScoringConfigCache) { return $script:ScoringConfigCache }
    if (Test-Path -LiteralPath $script:ScoringConfigPath) {
        $script:ScoringConfigCache = Get-Content -LiteralPath $script:ScoringConfigPath -Raw -Encoding UTF8 | ConvertFrom-Json
    }
    return $script:ScoringConfigCache
}
