function Get-TenantBriefI18n {
    [CmdletBinding()]
    param([ValidateSet('tr', 'en')][string]$Language = 'tr')
    if ($script:I18nCache.ContainsKey($Language)) { return $script:I18nCache[$Language] }
    $p = Join-Path $script:ModuleRoot "data/i18n\$Language.json"
    if (Test-Path -LiteralPath $p) {
        $script:I18nCache[$Language] = Get-Content -LiteralPath $p -Raw -Encoding UTF8 | ConvertFrom-Json
        return $script:I18nCache[$Language]
    }
    return $null
}
