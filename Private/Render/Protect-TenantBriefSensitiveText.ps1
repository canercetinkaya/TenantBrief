function Protect-TenantBriefSensitiveText {
    [CmdletBinding()]
    param(
        [AllowEmptyString()]
        [string]$Text,
        [string]$TenantDomain = ''
    )
    if ([string]::IsNullOrEmpty($Text)) { return $Text }
    $out = $Text
    # Mask email addresses / UPNs
    $out = $out -replace '\b[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}\b', 'redacted-user@contoso.onmicrosoft.com'
    # Mask GUIDs
    $out = $out -replace '\b[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}\b', '00000000-0000-0000-0000-000000000000'
    # Mask any tenant-specific *.onmicrosoft.com and *.sharepoint.com hostnames
    $out = $out -replace '(?i)\b(?!contoso\b)[A-Za-z0-9-]+(?:\.mail)?\.onmicrosoft\.com\b', 'contoso.onmicrosoft.com'
    $out = $out -replace '(?i)\b(?!contoso(?:-my|-admin)?\b)[A-Za-z0-9-]+(-my|-admin)?\.sharepoint\.com\b', 'contoso$1.sharepoint.com'
    # Mask explicit tenant domain and tenant prefix derivatives (e.g. SharePoint/mail subdomains & rule names)
    if ($TenantDomain -and $TenantDomain.Length -ge 4 -and $TenantDomain -notmatch '^contoso\.onmicrosoft\.com') {
        $out = $out -replace [regex]::Escape($TenantDomain), 'contoso.onmicrosoft.com'
        $tenantPrefix = ($TenantDomain -split '\.')[0]
        if ($tenantPrefix -and $tenantPrefix.Length -ge 4 -and $tenantPrefix -notmatch '^(contoso|fabrikam|example|tenant|microsoft|azure|office|sharepoint|admin|mail|cloud|security)$') {
            $escPrefix = [regex]::Escape($tenantPrefix)
            $out = $out -replace "(?i)\b$escPrefix(-my|-admin)?\.sharepoint\.com\b", 'contoso$1.sharepoint.com'
            $out = $out -replace "(?i)\b$escPrefix\.mail\.onmicrosoft\.com\b", 'contoso.mail.onmicrosoft.com'
            $out = $out -replace "(?i)\b$escPrefix\b", 'contoso'
        }
    }
    return $out
}
