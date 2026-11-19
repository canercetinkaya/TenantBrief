function ConvertTo-TenantBriefTurkish {
    [CmdletBinding()]
    param([string]$Text)
    if ([string]::IsNullOrWhiteSpace($Text)) { return $Text }
    if ($null -eq $script:GlossaryTrCache) {
        $gPath = Join-Path $script:ModuleRoot 'data/i18n\glossary-tr.json'
        $map = [ordered]@{}
        if (Test-Path -LiteralPath $gPath) {
            $gObj = Get-Content -LiteralPath $gPath -Raw -Encoding UTF8 | ConvertFrom-Json
            foreach ($p in $gObj.replacements.PSObject.Properties) {
                $map[$p.Name] = [string]$p.Value
            }
        }
        $script:GlossaryTrCache = $map
    }
    $out = $Text
    foreach ($k in $script:GlossaryTrCache.Keys) {
        $out = $out -replace [regex]::Escape($k), $script:GlossaryTrCache[$k]
    }
    return $out
}
