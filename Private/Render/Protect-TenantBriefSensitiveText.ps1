function Protect-TenantBriefSensitiveText {
    [CmdletBinding()]
    param(
        [AllowEmptyString()]
        [string]$Text,
        [string]$TenantDomain = '',
        [string]$TenantName = ''
    )
    if ([string]::IsNullOrEmpty($Text)) { return $Text }
    $out = $Text
    # Mask email addresses / UPNs
    $out = $out -replace '\b[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}\b', 'redacted-user@contoso.onmicrosoft.com'
    # Mask GUIDs (including underscore-delimited Azure resource/RG GUIDs)
    $out = $out -replace '(?<![0-9a-fA-F])[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}(?![0-9a-fA-F])', '00000000-0000-0000-0000-000000000000'
    # Mask any tenant-specific *.onmicrosoft.com and *.sharepoint.com hostnames
    $out = $out -replace '(?i)\b(?!contoso\b)[A-Za-z0-9-]+(?:\.mail)?\.onmicrosoft\.com\b', 'contoso.onmicrosoft.com'
    $out = $out -replace '(?i)\b(?!contoso(?:-my|-admin)?\b)[A-Za-z0-9-]+(-my|-admin)?\.sharepoint\.com\b', 'contoso$1.sharepoint.com'
    # Mask explicit tenant domain and tenant prefix derivatives (including underscore/hyphen-delimited Azure resource & policy names)
    if ($TenantDomain -and $TenantDomain.Length -ge 4 -and $TenantDomain -notmatch '^contoso\.onmicrosoft\.com') {
        $out = $out -replace [regex]::Escape($TenantDomain), 'contoso.onmicrosoft.com'
        $tenantPrefix = ($TenantDomain -split '\.')[0]
        if ($tenantPrefix -and $tenantPrefix.Length -ge 4 -and $tenantPrefix -notmatch '^(contoso|fabrikam|example|tenant|microsoft|azure|office|sharepoint|admin|mail|cloud|security)$') {
            $escPrefix = [regex]::Escape($tenantPrefix)
            $out = $out -replace "(?i)(?<![A-Za-z0-9])$escPrefix(-my|-admin)?\.sharepoint\.com(?![A-Za-z0-9])", 'contoso$1.sharepoint.com'
            $out = $out -replace "(?i)(?<![A-Za-z0-9])$escPrefix\.mail\.onmicrosoft\.com(?![A-Za-z0-9])", 'contoso.mail.onmicrosoft.com'
            $out = $out -replace "(?i)(?<![A-Za-z0-9])$escPrefix(?![A-Za-z0-9])", 'contoso'
        }
    }
    if ($TenantName -and $TenantName.Length -ge 4 -and $TenantName -notmatch '^(contoso|fabrikam|example|tenant|microsoft|azure|office|sharepoint|admin|mail|cloud|security)$') {
        $out = $out -replace "(?i)(?<![A-Za-z0-9])$([regex]::Escape($TenantName))(?![A-Za-z0-9])", 'Contoso'
    }
    return $out
}
