function ConvertTo-TenantBriefTurkish {
    [CmdletBinding()]
    param([string]$Text)
    if ([string]::IsNullOrWhiteSpace($Text)) { return $Text }
    if ($null -eq $script:GlossaryTrCache) {
        $gPath = Join-Path $script:ModuleRoot 'data/i18n/glossary-tr.json'
        $map = [System.Collections.Generic.Dictionary[string, string]]::new([System.StringComparer]::OrdinalIgnoreCase)
        $orderedKeys = [System.Collections.Generic.List[string]]::new()
        if (Test-Path -LiteralPath $gPath) {
            $gObj = Get-Content -LiteralPath $gPath -Raw -Encoding UTF8 | ConvertFrom-Json
            foreach ($p in $gObj.replacements.PSObject.Properties) {
                $map[$p.Name] = [string]$p.Value
                $orderedKeys.Add($p.Name)
            }
        }
        $pattern = if ($orderedKeys.Count -gt 0) {
            ($orderedKeys | ForEach-Object { [regex]::Escape($_) }) -join '|'
        } else { '' }
        $script:GlossaryTrCache = [PSCustomObject]@{
            Map   = $map
            Regex = if ($pattern) { [regex]::new($pattern, [System.Text.RegularExpressions.RegexOptions]::IgnoreCase -bor [System.Text.RegularExpressions.RegexOptions]::Compiled) } else { $null }
        }
    }
    if ($null -eq $script:GlossaryTrCache.Regex) { return $Text }
    $mapRef = $script:GlossaryTrCache.Map
    return $script:GlossaryTrCache.Regex.Replace($Text, [System.Text.RegularExpressions.MatchEvaluator]{
        param($m)
        $val = $null
        if ($mapRef.TryGetValue($m.Value, [ref]$val)) { return $val }
        return $m.Value
    })
}
