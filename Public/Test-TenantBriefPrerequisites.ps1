function Test-TenantBriefPrerequisites {
    <#
    .SYNOPSIS
    Runs a strictly read-only preflight check of TenantBrief modules, OPA binary, and M365 sessions.

    .DESCRIPTION
    Inspects locally installed PowerShell modules (ZeroTrustAssessment, ScubaGear, ORCA, Maester,
    MicrosoftTeams, Microsoft.Online.SharePoint.PowerShell, powershell-yaml), the ScubaGear OPA
    executable, and active Microsoft Graph / Exchange Online / SharePoint Online / Teams sessions.
    Makes zero changes to the local machine or tenant.

    .EXAMPLE
    Test-TenantBriefPrerequisites | Format-Table Category, Name, Status, InstalledVersion, Details
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter()]
        [switch]$AuthPlan,

        [Parameter()]
        [Alias('Profile')]
        [ValidateSet('Quick', 'Full')]
        [string]$AuthProfile = 'Quick',

        [Parameter()]
        [switch]$IncludeAzure,

        [Parameter()]
        [switch]$SkipTeams,

        [Parameter()]
        [switch]$SkipSharePoint,

        [Parameter()]
        [switch]$ScubaInteractiveLogin,

        [Parameter()]
        [ValidateSet('aad', 'securitysuite', 'exo', 'sharepoint', 'teams', 'powerplatform', 'powerbi')]
        [string[]]$ScubaProducts = @('aad', 'securitysuite', 'exo', 'sharepoint', 'teams', 'powerplatform', 'powerbi')
    )

    if ($AuthPlan) {
        $plan = Get-TenantBriefAuthPlan `
            -AuthProfile $AuthProfile `
            -IncludeAzure:$IncludeAzure `
            -SkipTeams:$SkipTeams `
            -SkipSharePoint:$SkipSharePoint `
            -ScubaInteractiveLogin:$ScubaInteractiveLogin `
            -ScubaProducts $ScubaProducts
        Write-TenantBriefAuthBriefing -Plan $plan
        return $plan
    }

    $results = New-Object System.Collections.Generic.List[object]

    $moduleSpecs = @(
        @{ Name = 'ZeroTrustAssessment'; Required = $true;  InstallCmd = 'Install-Module ZeroTrustAssessment -Scope CurrentUser' },
        @{ Name = 'ScubaGear';           Required = $false; InstallCmd = 'Install-Module ScubaGear -Scope CurrentUser' },
        @{ Name = 'ORCA';                Required = $false; InstallCmd = 'Install-Module ORCA -Scope CurrentUser' },
        @{ Name = 'Maester';             Required = $false; InstallCmd = 'Install-Module Maester -Scope CurrentUser' },
        @{ Name = 'powershell-yaml';     Required = $false; InstallCmd = 'Install-Module powershell-yaml -Scope CurrentUser' },
        @{ Name = 'MicrosoftTeams';      Required = $false; InstallCmd = 'Install-Module MicrosoftTeams -Scope CurrentUser' },
        @{ Name = 'Microsoft.Online.SharePoint.PowerShell'; Required = $false; InstallCmd = 'Save-Module Microsoft.Online.SharePoint.PowerShell -Path "$HOME\Documents\WindowsPowerShell\Modules"' }
    )

    $allModNames = @($moduleSpecs | ForEach-Object { $_.Name })
    $installedByName = @{}
    foreach ($m in @(Get-Module -ListAvailable -Name $allModNames -ErrorAction SilentlyContinue)) {
        $key = $m.Name.ToLowerInvariant()
        if (-not $installedByName.ContainsKey($key) -or $m.Version -gt $installedByName[$key].Version) {
            $installedByName[$key] = $m
        }
    }

    foreach ($spec in $moduleSpecs) {
        $key = $spec.Name.ToLowerInvariant()
        $found = if ($installedByName.ContainsKey($key)) { $installedByName[$key] } else { $null }
        $status = if ($found) { 'Ready' } elseif ($spec.Required) { 'Missing' } else { 'Warning' }
        $results.Add([PSCustomObject]@{
            Category         = 'Module'
            Name             = $spec.Name
            Status           = $status
            InstalledVersion = if ($found) { [string]$found.Version } else { '' }
            Details          = if ($found) { 'Installed' } elseif ($spec.Required) { 'Required module not found' } else { 'Optional engine/module not installed' }
            Remedy           = if ($found) { '' } else { $spec.InstallCmd }
        })
    }

    $opaExe = if ($env:USERPROFILE) { Join-Path $env:USERPROFILE '.scubagear\Tools\opa_windows_amd64.exe' } else { '' }
    $opaReady = ($opaExe -and (Test-Path -LiteralPath $opaExe))
    $results.Add([PSCustomObject]@{
        Category         = 'Binary'
        Name             = 'ScubaGear OPA'
        Status           = if ($opaReady) { 'Ready' } else { 'Warning' }
        InstalledVersion = ''
        Details          = if ($opaReady) { 'OPA executable present' } else { 'OPA executable not found under ~/.scubagear/Tools' }
        Remedy           = if ($opaReady) { '' } else { 'Install-OPAforSCuBA' }
    })

    $mgCtx = $null
    if (Get-Command Get-MgContext -ErrorAction SilentlyContinue) {
        try { $mgCtx = Get-MgContext -ErrorAction SilentlyContinue } catch { $mgCtx = $null }
    }
    $mgScopes = if ($mgCtx -and $mgCtx.PSObject.Properties['Scopes'] -and $mgCtx.Scopes) { @($mgCtx.Scopes) } else { @() }
    $results.Add([PSCustomObject]@{
        Category         = 'Session'
        Name             = 'Microsoft Graph'
        Status           = if ($mgCtx) { 'Ready' } else { 'NotConnected' }
        InstalledVersion = ''
        Details          = if ($mgCtx) { "Connected ($($mgScopes.Count) scopes)" } else { 'No active Microsoft Graph session' }
        Remedy           = if ($mgCtx) { '' } else { 'Connect-TenantBrief' }
    })

    $exoReady = $false
    if (Get-Command Get-ConnectionInformation -ErrorAction SilentlyContinue) {
        try { $exoReady = (@(Get-ConnectionInformation -ErrorAction SilentlyContinue | Where-Object { $_.State -eq 'Connected' }).Count -gt 0) } catch { $exoReady = $false }
    }
    $results.Add([PSCustomObject]@{
        Category         = 'Session'
        Name             = 'Exchange Online'
        Status           = if ($exoReady) { 'Ready' } else { 'NotConnected' }
        InstalledVersion = ''
        Details          = if ($exoReady) { 'Connected' } else { 'Not connected (required for ORCA and ScubaGear EXO/SecuritySuite)' }
        Remedy           = if ($exoReady) { '' } else { 'Connect-TenantBrief -Service ExchangeOnline' }
    })

    $spoReady = $false
    if (Get-Command Get-SPOTenant -ErrorAction SilentlyContinue) {
        try { $null = Get-SPOTenant -ErrorAction Stop; $spoReady = $true } catch { $spoReady = $false }
    }
    $results.Add([PSCustomObject]@{
        Category         = 'Session'
        Name             = 'SharePoint Online'
        Status           = if ($spoReady) { 'Ready' } else { 'NotConnected' }
        InstalledVersion = ''
        Details          = if ($spoReady) { 'Connected' } else { 'Not connected (SPO sharing checks will be skipped)' }
        Remedy           = if ($spoReady) { '' } else { 'Connect-TenantBrief -Service SharePointOnline' }
    })

    $teamsReady = $false
    if (Get-Command Get-CsTenant -ErrorAction SilentlyContinue) {
        try { $null = Get-CsTenant -ErrorAction Stop; $teamsReady = $true } catch { $teamsReady = $false }
    }
    $results.Add([PSCustomObject]@{
        Category         = 'Session'
        Name             = 'Microsoft Teams'
        Status           = if ($teamsReady) { 'Ready' } else { 'NotConnected' }
        InstalledVersion = ''
        Details          = if ($teamsReady) { 'Connected' } else { 'Not connected (Teams checks will be skipped)' }
        Remedy           = if ($teamsReady) { '' } else { 'Connect-MicrosoftTeams' }
    })

    return $results.ToArray()
}
