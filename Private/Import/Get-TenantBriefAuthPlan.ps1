function Get-TenantBriefAuthPlan {
    <#
    .SYNOPSIS
    Computes the authentication plan, target services, and expected interactive prompt range without opening any session.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter()]
        [Alias('Profile')]
        [ValidateSet('Quick', 'Full')]
        [string]$AuthProfile = 'Quick',

        [Parameter()]
        [switch]$IncludeAzure,

        [Parameter()]
        [string[]]$Service,

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

    $resolvedServices = [System.Collections.Generic.List[string]]::new()
    if ($PSBoundParameters.ContainsKey('Service') -and $Service -and $Service.Count -gt 0) {
        foreach ($s in $Service) {
            if ($s -and -not $resolvedServices.Contains($s)) { $resolvedServices.Add($s) }
        }
        if ($IncludeAzure -and -not $resolvedServices.Contains('Azure')) {
            $resolvedServices.Add('Azure')
        }
    } elseif ($AuthProfile -eq 'Full') {
        foreach ($s in @('Graph', 'ExchangeOnline', 'SecurityCompliance')) { $resolvedServices.Add($s) }
        if (-not $SkipSharePoint) { $resolvedServices.Add('SharePointOnline') }
        if ($IncludeAzure) { $resolvedServices.Add('Azure') }
    } else {
        # Quick (default): Graph + ExchangeOnline + SecurityCompliance (no Azure unless -IncludeAzure, no SPO, no Teams)
        foreach ($s in @('Graph', 'ExchangeOnline', 'SecurityCompliance')) { $resolvedServices.Add($s) }
        if ($IncludeAzure) { $resolvedServices.Add('Azure') }
    }

    if ($SkipSharePoint -and $resolvedServices.Contains('SharePointOnline')) {
        $null = $resolvedServices.Remove('SharePointOnline')
    }

    $includeTeams = ($AuthProfile -eq 'Full') -and (-not $SkipTeams)
    $includeSpo = $resolvedServices.Contains('SharePointOnline')

    $requestedScuba = @($ScubaProducts | ForEach-Object { ([string]$_).Trim().ToLowerInvariant() } | Where-Object { $_ } | Select-Object -Unique)
    if ($requestedScuba.Count -eq 0) {
        $requestedScuba = @('aad', 'securitysuite', 'exo', 'sharepoint', 'teams', 'powerplatform', 'powerbi')
    }

    # Empirically verified on ScubaGear 2.0.0: 'aad' passes in main session with -LogIn:$false (0 extra prompts);
    # non-AAD providers require -LogIn:$true inside the isolated Windows PowerShell 5.1 subprocess.
    $scubaMain = @($requestedScuba | Where-Object { $_ -eq 'aad' })
    $scubaSub = if ($ScubaInteractiveLogin) { @($requestedScuba | Where-Object { $_ -ne 'aad' }) } else { @() }

    $steps = [System.Collections.Generic.List[object]]::new()
    $minPrompts = 0
    $maxPrompts = 0

    if ($resolvedServices.Contains('Graph')) {
        $steps.Add([PSCustomObject]@{
            Phase          = 'Connect'
            Service        = 'Microsoft Graph'
            AuthFlow       = 'Interactive / Browser SSO'
            ExpectedPrompt = '1 (or silent SSO)'
            Notes          = 'Primary session (ZeroTrust, License ROI, Copilot, Maester, ScubaGear aad). UPN reused as login hint.'
        })
        $minPrompts += 0; $maxPrompts += 1
    }
    if ($resolvedServices.Contains('Azure')) {
        $steps.Add([PSCustomObject]@{
            Phase          = 'Connect'
            Service        = 'Azure ARM (-IncludeAzure)'
            AuthFlow       = 'Interactive / Cached Context'
            ExpectedPrompt = '0-1'
            Notes          = 'Azure subscription & network checks (only enabled via -IncludeAzure).'
        })
        $minPrompts += 0; $maxPrompts += 1
    }
    if ($resolvedServices.Contains('ExchangeOnline')) {
        $steps.Add([PSCustomObject]@{
            Phase          = 'Connect'
            Service        = 'Exchange Online'
            AuthFlow       = 'Interactive + UPN Login Hint'
            ExpectedPrompt = '1 (or silent SSO)'
            Notes          = 'ORCA, CIS EXO, and Exchange telemetry. Receives Graph UPN via -UserPrincipalName.'
        })
        $minPrompts += 0; $maxPrompts += 1
    }
    if ($resolvedServices.Contains('SecurityCompliance')) {
        $steps.Add([PSCustomObject]@{
            Phase          = 'Connect'
            Service        = 'Security & Compliance (IPPS)'
            AuthFlow       = 'Interactive + UPN Login Hint'
            ExpectedPrompt = '0-1'
            Notes          = 'Defender for Office 365 & Purview DLP checks. Receives Graph UPN via -UserPrincipalName.'
        })
        $minPrompts += 0; $maxPrompts += 1
    }
    if ($includeSpo) {
        $steps.Add([PSCustomObject]@{
            Phase          = 'Connect'
            Service        = 'SharePoint Online'
            AuthFlow       = 'Interactive (SPO Admin URL)'
            ExpectedPrompt = '1'
            Notes          = 'Explicitly enabled in Full profile. Separate Connect-SPOService prompt may open if ZTA does not attach SPO.'
        })
        $minPrompts += 1; $maxPrompts += 1
    }
    if ($includeTeams) {
        $steps.Add([PSCustomObject]@{
            Phase          = 'Connect'
            Service        = 'Microsoft Teams'
            AuthFlow       = 'Interactive (Device Code fallback if WAM blocks)'
            ExpectedPrompt = '1'
            Notes          = 'Maester Teams/CIS checks. -AccountId intentionally omitted (WAM Error 3399548929).'
        })
        $minPrompts += 1; $maxPrompts += 1
    }
    if (@($scubaMain).Count -gt 0) {
        $steps.Add([PSCustomObject]@{
            Phase          = 'Stage 2 (ScubaGear)'
            Service        = 'ScubaGear: aad (Main Session)'
            AuthFlow       = 'Reuses active Graph session (-LogIn:$false)'
            ExpectedPrompt = '0'
            Notes          = 'Runs in main runspace under InvariantCulture with zero additional sign-in prompts.'
        })
    }
    if (@($scubaSub).Count -gt 0) {
        # securitysuite shares EXO/IPPS auth inside ScubaGear; other providers each authenticate separately.
        $subPromptProviders = @($scubaSub | Where-Object { $_ -ne 'securitysuite' })
        $subCount = [math]::Max(1, @($subPromptProviders).Count)
        $steps.Add([PSCustomObject]@{
            Phase          = 'Stage 2 (ScubaGear)'
            Service        = "ScubaGear Subprocess ($($scubaSub -join ', '))"
            AuthFlow       = 'Isolated Windows PowerShell 5.1 (-LogIn:$true)'
            ExpectedPrompt = "$subCount"
            Notes          = 'Runs only non-AAD products in isolated PS 5.1 (InvariantCulture); aad already completed in main session.'
        })
        $minPrompts += $subCount; $maxPrompts += ($subCount + 1)
    }

    return [PSCustomObject]@{
        Profile                  = $AuthProfile
        IncludeAzure             = [bool]$IncludeAzure
        Services                 = $resolvedServices.ToArray()
        IncludeTeams             = $includeTeams
        IncludeSharePoint        = $includeSpo
        ScubaMainSessionProducts = $scubaMain
        ScubaSubprocessProducts  = $scubaSub
        EstimatedMinPrompts      = $minPrompts
        EstimatedMaxPrompts      = $maxPrompts
        Steps                    = $steps.ToArray()
    }
}

function Write-TenantBriefAuthBriefing {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [PSCustomObject]$Plan
    )

    $lines = [System.Collections.Generic.List[string]]::new()
    $lines.Add('')
    $lines.Add("[TenantBrief] Authentication Plan (Profile: $($Plan.Profile) | Expected prompts: $($Plan.EstimatedMinPrompts)-$($Plan.EstimatedMaxPrompts))")
    $lines.Add(("  Services : {0}" -f ($Plan.Services -join ', ')))
    if ($Plan.IncludeTeams) {
        $lines.Add('  Teams    : Enabled (Full profile — separate interactive sign-in; Device Code fallback on WAM lock)')
    } else {
        $lines.Add('  Teams    : Skipped (use -Profile Full to include Teams)')
    }
    if ($Plan.IncludeSharePoint) {
        $lines.Add('  SPO      : Enabled (Full profile — explicit SharePoint Online sign-in included in plan)')
    } else {
        $lines.Add('  SPO      : Skipped (use -Profile Full to include SharePoint Online)')
    }
    foreach ($st in @($Plan.Steps)) {
        $lines.Add(("  - [{0}] {1} | Prompts: {2} | {3}" -f $st.Phase, $st.Service, $st.ExpectedPrompt, $st.Notes))
    }
    $lines.Add('')
    Write-Information -MessageData ($lines -join [Environment]::NewLine) -InformationAction Continue
}
