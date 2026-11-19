function Get-TenantBriefCrosswalkMap {
    [CmdletBinding()]
    param()

    if ($null -ne $script:CrosswalkMapCache) { return $script:CrosswalkMapCache }
    $map = @{}
    if (Test-Path -LiteralPath $script:CrosswalkPath) {
        $cw = Get-Content -LiteralPath $script:CrosswalkPath -Raw -Encoding UTF8 | ConvertFrom-Json
        foreach ($c in @($cw.controls)) {
            foreach ($uId in @($c.ids)) {
                $k = ([string]$uId).Trim().ToUpperInvariant()
                if ($k) { $map[$k] = $c }
            }
        }
    }
    $script:CrosswalkMapCache = $map
    return $map
}
