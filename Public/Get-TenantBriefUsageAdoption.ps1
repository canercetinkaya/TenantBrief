function Get-TenantBriefUsageAdoption {
    <#
    .SYNOPSIS
    Read-only executive Usage & Adoption snapshot using existing Microsoft Graph Reader scopes
    (Reports.Read.All, DeviceManagementManagedDevices.Read.All, SecurityIncident.Read.All, IdentityRiskyUser.Read.All).
    No per-user surveillance; returns tenant-level aggregate counts and percentages only.
    #>
    [CmdletBinding()]
    param(
        [Parameter()]
        [ValidateSet('D7', 'D30', 'D90', 'D180')]
        [string]$Period = 'D30',

        [Parameter()]
        [ValidateSet('tr', 'en')]
        [string]$Language = 'tr'
    )

    if (-not (Get-MgContext -ErrorAction SilentlyContinue)) { return $null }

    $parseReportRows = {
        param([string]$Uri)
        try {
            $resp = Invoke-MgGraphRequest -Method GET -Uri $Uri -ErrorAction Stop
            if ($null -eq $resp) { return @() }
            if ($resp -is [string]) {
                $clean = $resp.TrimStart([char]0xFEFF).Trim()
                if (-not $clean) { return @() }
                if ($clean.StartsWith('{') -or $clean.StartsWith('[')) {
                    $j = $clean | ConvertFrom-Json
                    if ($j.PSObject.Properties['value']) { return @($j.value) }
                    return @($j)
                }
                return @($clean | ConvertFrom-Csv)
            }
            if ($resp -is [hashtable] -and $resp.ContainsKey('value')) { return @($resp['value']) }
            if ($resp.PSObject.Properties['value']) { return @($resp.value) }
            return @($resp)
        } catch {
            return @()
        }
    }
    $toIntSafe = {
        param($Val)
        $n = 0
        if ($null -ne $Val -and [int]::TryParse(([string]$Val -replace '[^\d-]', ''), [ref]$n)) { return $n }
        return 0
    }
    $toDoubleSafe = {
        param($Val)
        $d = 0.0
        if ($null -ne $Val -and [double]::TryParse(([string]$Val), [System.Globalization.CultureInfo]::InvariantCulture, [ref]$d)) { return $d }
        return 0.0
    }

    # 1. M365 Services Adoption (Assigned vs Active over Period)
    $services = @()
    $svcRows = @(& $parseReportRows "https://graph.microsoft.com/v1.0/reports/getOffice365ServicesUserCounts(period='$Period')")
    if ($svcRows.Count -gt 0) {
        $latest = $svcRows | Select-Object -Last 1
        $svcDefs = @(
            @{ Name = 'Exchange Online';   Active = 'Exchange Active';    Inactive = 'Exchange Inactive' },
            @{ Name = 'Microsoft Teams';   Active = 'Teams Active';       Inactive = 'Teams Inactive' },
            @{ Name = 'SharePoint Online'; Active = 'SharePoint Active';  Inactive = 'SharePoint Inactive' },
            @{ Name = 'OneDrive';          Active = 'OneDrive Active';    Inactive = 'OneDrive Inactive' },
            @{ Name = 'Viva Engage';       Active = 'Yammer Active';      Inactive = 'Yammer Inactive' }
        )
        foreach ($sd in $svcDefs) {
            $act = & $toIntSafe (Get-TenantBriefPropertyValue -Object $latest -Name $sd.Active)
            $ina = & $toIntSafe (Get-TenantBriefPropertyValue -Object $latest -Name $sd.Inactive)
            $tot = $act + $ina
            if ($tot -gt 0 -or $act -gt 0) {
                $pct = if ($tot -gt 0) { [Math]::Round(($act / $tot) * 100, 1) } else { 0 }
                $services += [PSCustomObject]@{
                    Service       = $sd.Name
                    ActiveUsers   = $act
                    InactiveUsers = $ina
                    TotalEnabled  = $tot
                    AdoptionPct   = $pct
                }
            }
        }
    }

    # 2. Microsoft 365 Copilot Real Usage (beta Reports.Read.All)
    $copilotUsage = $null
    $copRows = @(& $parseReportRows "https://graph.microsoft.com/beta/reports/getMicrosoft365CopilotUserCountSummary(period='$Period')")
    if ($copRows.Count -gt 0) {
        $c = $copRows | Select-Object -Last 1
        $en = & $toIntSafe (Get-TenantBriefPropertyValue -Object $c -Name 'Any App Enabled Users')
        if ($en -eq 0) { $en = & $toIntSafe (Get-TenantBriefPropertyValue -Object $c -Name 'enabledUsers') }
        $ac = & $toIntSafe (Get-TenantBriefPropertyValue -Object $c -Name 'Any App Active Users')
        if ($ac -eq 0) { $ac = & $toIntSafe (Get-TenantBriefPropertyValue -Object $c -Name 'activeUsers') }
        $idleCop = [Math]::Max(0, $en - $ac)
        $copUsagePct = if ($en -gt 0) { [Math]::Round(($ac / $en) * 100, 1) } else { 0 }
        $copilotUsage = [PSCustomObject]@{
            EnabledUsers     = $en
            ActiveUsers      = $ac
            IdleUsers        = $idleCop
            AdoptionPct      = $copUsagePct
            EstIdleUsdMo     = ($idleCop * 30)
            TeamsActive      = & $toIntSafe (Get-TenantBriefPropertyValue -Object $c -Name 'Teams Active Users')
            OutlookActive    = & $toIntSafe (Get-TenantBriefPropertyValue -Object $c -Name 'Outlook Active Users')
            WordActive       = & $toIntSafe (Get-TenantBriefPropertyValue -Object $c -Name 'Word Active Users')
            ExcelActive      = & $toIntSafe (Get-TenantBriefPropertyValue -Object $c -Name 'Excel Active Users')
            PowerPointActive = & $toIntSafe (Get-TenantBriefPropertyValue -Object $c -Name 'PowerPoint Active Users')
            CopilotChatActive = & $toIntSafe (Get-TenantBriefPropertyValue -Object $c -Name 'Copilot Chat (work) Active Users')
        }
    }

    # 3. M365 App Platforms (Windows, Mac, Web, iOS, Android)
    $platforms = @()
    $platRows = @(& $parseReportRows "https://graph.microsoft.com/v1.0/reports/getM365AppPlatformUserCounts(period='$Period')")
    if ($platRows.Count -gt 0) {
        $pl = $platRows | Select-Object -Last 1
        foreach ($pName in @('Windows', 'Mac', 'Web', 'Mobile', 'iOS', 'Android')) {
            $cnt = & $toIntSafe (Get-TenantBriefPropertyValue -Object $pl -Name $pName)
            if ($cnt -gt 0) {
                $platforms += [PSCustomObject]@{ Platform = $pName; Users = $cnt }
            }
        }
    }

    # 4. SharePoint Site Counts & Storage (GB)
    $spSites = $null
    $spSiteRows = @(& $parseReportRows "https://graph.microsoft.com/v1.0/reports/getSharePointSiteUsageSiteCounts(period='$Period')")
    $spStorRows = @(& $parseReportRows "https://graph.microsoft.com/v1.0/reports/getSharePointSiteUsageStorage(period='$Period')")
    if ($spSiteRows.Count -gt 0 -or $spStorRows.Count -gt 0) {
        $sr = if ($spSiteRows.Count -gt 0) { $spSiteRows | Select-Object -Last 1 } else { $null }
        $st = if ($spStorRows.Count -gt 0) { $spStorRows | Select-Object -Last 1 } else { $null }
        $bytesUsed = & $toDoubleSafe (Get-TenantBriefPropertyValue -Object $st -Name 'Storage Used (Byte)')
        $spSites = [PSCustomObject]@{
            TotalSites    = & $toIntSafe (Get-TenantBriefPropertyValue -Object $sr -Name 'Total')
            ActiveSites   = & $toIntSafe (Get-TenantBriefPropertyValue -Object $sr -Name 'Active')
            StorageUsedGB = [Math]::Round($bytesUsed / 1GB, 2)
        }
    }

    # 5. Tenant-Wide Auth Methods / Passwordless Adoption
    $authSummary = $null
    try {
        $regRows = @(Get-TenantBriefGraphCollection -Uri 'https://graph.microsoft.com/v1.0/reports/authenticationMethods/userRegistrationDetails?$top=999' -PageLimit 20)
        if ($regRows.Count -gt 0) {
            $totReg = $regRows.Count
            $mfaReg = @($regRows | Where-Object { [bool](Get-TenantBriefPropertyValue -Object $_ -Name 'isMfaRegistered') }).Count
            $pwlReg = @($regRows | Where-Object { [bool](Get-TenantBriefPropertyValue -Object $_ -Name 'isPasswordlessCapable') }).Count
            $ssprReg = @($regRows | Where-Object { [bool](Get-TenantBriefPropertyValue -Object $_ -Name 'isSsprRegistered') }).Count
            $authSummary = [PSCustomObject]@{
                TotalUsers      = $totReg
                MfaRegistered   = $mfaReg
                MfaPct          = [Math]::Round(($mfaReg / $totReg) * 100, 1)
                Passwordless    = $pwlReg
                PasswordlessPct = [Math]::Round(($pwlReg / $totReg) * 100, 1)
                SsprRegistered  = $ssprReg
                SsprPct         = [Math]::Round(($ssprReg / $totReg) * 100, 1)
            }
        }
    } catch {}

    # 6. Managed Devices OS & Compliance Breakdown
    $deviceBreakdown = @()
    try {
        $devRows = @(Get-TenantBriefGraphCollection -Uri 'https://graph.microsoft.com/v1.0/deviceManagement/managedDevices?$select=operatingSystem,complianceState&$top=500' -PageLimit 10)
        if ($devRows.Count -gt 0) {
            $byOs = $devRows | Group-Object {
                $os = [string](Get-TenantBriefPropertyValue -Object $_ -Name 'operatingSystem')
                if ($os) { $os } else { 'Other' }
            }
            foreach ($g in ($byOs | Sort-Object Count -Descending)) {
                $comp = @($g.Group | Where-Object { ([string](Get-TenantBriefPropertyValue -Object $_ -Name 'complianceState')) -eq 'compliant' }).Count
                $deviceBreakdown += [PSCustomObject]@{
                    OS           = $g.Name
                    Total        = $g.Count
                    Compliant    = $comp
                    NonCompliant = ($g.Count - $comp)
                    CompliantPct = if ($g.Count -gt 0) { [Math]::Round(($comp / $g.Count) * 100, 1) } else { 0 }
                }
            }
        }
    } catch {}

    # 7. SecOps Snapshot: Open Defender XDR Incidents & Active Risky Users
    $secOps = [PSCustomObject]@{
        ActiveIncidents     = 0
        HighIncidents       = 0
        MediumIncidents     = 0
        LowIncidents        = 0
        ActiveRiskyUsers    = 0
        IncidentsAvailable  = $false
        RiskyUsersAvailable = $false
    }
    try {
        $incResp = Invoke-MgGraphRequest -Method GET -Uri "https://graph.microsoft.com/v1.0/security/incidents?`$top=50&`$filter=status ne 'resolved'" -ErrorAction Stop
        if ($incResp -and $incResp.PSObject.Properties['value'] -or ($incResp -is [hashtable] -and $incResp.ContainsKey('value'))) {
            $incList = @(Get-TenantBriefPropertyValue -Object $incResp -Name 'value')
            $secOps.IncidentsAvailable = $true
            $secOps.ActiveIncidents = $incList.Count
            $secOps.HighIncidents   = @($incList | Where-Object { ([string](Get-TenantBriefPropertyValue -Object $_ -Name 'severity')) -eq 'high' }).Count
            $secOps.MediumIncidents = @($incList | Where-Object { ([string](Get-TenantBriefPropertyValue -Object $_ -Name 'severity')) -eq 'medium' }).Count
            $secOps.LowIncidents    = @($incList | Where-Object { ([string](Get-TenantBriefPropertyValue -Object $_ -Name 'severity')) -in @('low', 'informational') }).Count
        }
    } catch {}
    try {
        $ruResp = Invoke-MgGraphRequest -Method GET -Uri "https://graph.microsoft.com/v1.0/identityProtection/riskyUsers?`$filter=riskState eq 'atRisk'&`$top=50" -ErrorAction Stop
        if ($ruResp -and ($ruResp.PSObject.Properties['value'] -or ($ruResp -is [hashtable] -and $ruResp.ContainsKey('value')))) {
            $ruList = @(Get-TenantBriefPropertyValue -Object $ruResp -Name 'value')
            $secOps.RiskyUsersAvailable = $true
            $secOps.ActiveRiskyUsers = $ruList.Count
        }
    } catch {}

    return [PSCustomObject]@{
        Period          = $Period
        CapturedAtUtc   = (Get-Date).ToUniversalTime().ToString('o')
        Services        = @($services)
        CopilotUsage    = $copilotUsage
        Platforms       = @($platforms)
        SharePointUsage = $spSites
        AuthAdoption    = $authSummary
        ManagedDevices  = @($deviceBreakdown)
        SecOps          = $secOps
    }
}
