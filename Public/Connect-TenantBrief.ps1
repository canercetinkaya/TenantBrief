function Connect-TenantBrief {
    <#
    .SYNOPSIS
    Connects read-only to the Microsoft 365 and Azure services used by the assessment.

    .DESCRIPTION
    Clears stale Graph/Azure/Exchange Online sessions, installs missing dependencies
    (ScubaGear, OPA, powershell-yaml, ORCA) and validates an active Graph context.
    
    The connection is strictly read-only: no tenant policy, Conditional Access rule or
    directory object is modified, and Disconnect-MgGraph is never called mid-session.

    .EXAMPLE
    Connect-TenantBrief -UseDeviceCode
    #>
    [CmdletBinding()]
    [OutputType([void])]
    param(
        [Parameter()]
        [string]$Tenant,

        [Parameter()]
        [Alias('Profile')]
        [ValidateSet('Quick', 'Full')]
        [string]$AuthProfile = 'Quick',

        [Parameter()]
        [switch]$IncludeAzure,

        [Parameter()]
        [ValidateSet('Graph', 'Azure', 'ExchangeOnline', 'SecurityCompliance', 'SharePointOnline')]
        [string[]]$Service,

        [Parameter()]
        [switch]$UseDeviceCode,

        [Parameter()]
        [switch]$SkipTeams,

        [Parameter()]
        [switch]$SkipSharePoint,

        [Parameter()]
        [switch]$AutoFixDependencies,

        [Parameter()]
        [switch]$UseAppAuth,

        [Parameter()]
        [string]$AppId,

        [Parameter()]
        [string]$CertificateThumbprint,

        [Parameter()]
        [string]$Organization,

        [Parameter()]
        [string]$AppProfilePath
    )

    $script:TenantBriefAppAuth = $null

    if ($UseAppAuth -or (-not [string]::IsNullOrWhiteSpace($AppId) -and -not [string]::IsNullOrWhiteSpace($CertificateThumbprint))) {
        $prof = if ($UseAppAuth) { Get-TenantBriefAppProfile -ProfilePath $AppProfilePath } else { $null }
        if ($UseAppAuth -and -not $prof) {
            throw "No local TenantBrief app profile found. Run Initialize-TenantBriefApp once to create your read-only App Registration and local certificate."
        }
        $resolvedAppId  = if (-not [string]::IsNullOrWhiteSpace($AppId)) { $AppId } else { [string]$prof.AppId }
        $resolvedThumb  = if (-not [string]::IsNullOrWhiteSpace($CertificateThumbprint)) { $CertificateThumbprint } else { [string]$prof.CertificateThumbprint }
        $resolvedTenant = if (-not [string]::IsNullOrWhiteSpace($Tenant)) { $Tenant } else { [string]$prof.TenantId }
        $resolvedOrg    = if (-not [string]::IsNullOrWhiteSpace($Organization)) { $Organization } else { [string]$prof.Organization }

        $certObj = Get-Item -Path "Cert:\CurrentUser\My\$resolvedThumb" -ErrorAction SilentlyContinue
        if (-not $certObj) { $certObj = Get-Item -Path "Cert:\LocalMachine\My\$resolvedThumb" -ErrorAction SilentlyContinue }
        if (-not $certObj) {
            throw "Certificate with thumbprint '$resolvedThumb' was not found in CurrentUser\My or LocalMachine\My."
        }

        Write-Information -MessageData "[TenantBrief] Connecting in Zero-Popup App-Only mode ($resolvedOrg | AppId: $resolvedAppId)..." -InformationAction Continue
        $docsDirApp = [Environment]::GetFolderPath('MyDocuments')
        $winPsModApp = if ($docsDirApp) { Join-Path $docsDirApp 'WindowsPowerShell\Modules' } else { Join-Path $HOME 'Documents\WindowsPowerShell\Modules' }
        if (Test-Path -LiteralPath $winPsModApp) {
            $appPathEntries = @($env:PSModulePath -split [System.IO.Path]::PathSeparator | Where-Object { $_ })
            if ($appPathEntries -notcontains $winPsModApp) {
                $env:PSModulePath = (@($winPsModApp) + $appPathEntries) -join [System.IO.Path]::PathSeparator
            }
        }
        Set-StrictMode -Off
        try {
            Connect-MgGraph -ClientId $resolvedAppId -TenantId $resolvedTenant -CertificateThumbprint $resolvedThumb -NoWelcome -ErrorAction Stop | Out-Null
            if (Get-Module -ListAvailable -Name 'ExchangeOnlineManagement') {
                try {
                    Import-Module ExchangeOnlineManagement -Global -ErrorAction Stop -WarningAction SilentlyContinue | Out-Null
                    Connect-ExchangeOnline -AppId $resolvedAppId -CertificateThumbprint $resolvedThumb -Organization $resolvedOrg -ShowBanner:$false -ErrorAction Stop | Out-Null
                } catch {
                    Write-Warning "[TenantBrief] App-Only Exchange Online connection skipped: $($_.Exception.Message)"
                }
            }
            if (Get-Module -ListAvailable -Name 'ZeroTrustAssessment') {
                try {
                    Import-Module ZeroTrustAssessment -Global -ErrorAction Stop -WarningAction SilentlyContinue | Out-Null
                    Connect-ZtAssessment -TenantId $resolvedTenant -ClientId $resolvedAppId -Certificate $certObj -Service @('Graph', 'ExchangeOnline') -ErrorAction Stop | Out-Null
                } catch {
                    Write-Warning "[TenantBrief] App-Only ZeroTrustAssessment connection note: $($_.Exception.Message)"
                }
            }
            if (-not $SkipTeams -and (Get-Module -ListAvailable -Name 'MicrosoftTeams')) {
                try {
                    Import-Module MicrosoftTeams -Global -ErrorAction Stop -WarningAction SilentlyContinue | Out-Null
                    Connect-MicrosoftTeams -ApplicationId $resolvedAppId -TenantId $resolvedTenant -CertificateThumbprint $resolvedThumb -ErrorAction Stop | Out-Null
                } catch {
                    Write-Warning "[TenantBrief] App-Only Teams connection skipped: $($_.Exception.Message)"
                }
            }
        } finally {
            Set-StrictMode -Version Latest
        }

        $script:TenantBriefAppAuth = [PSCustomObject]@{
            AppId                 = $resolvedAppId
            CertificateThumbprint = $resolvedThumb
            TenantId              = $resolvedTenant
            Organization          = $resolvedOrg
        }
        Write-Information -MessageData "[TenantBrief] Zero-Popup App-Only session active (0 prompts). Stage 2 ScubaGear will reuse this certificate automatically." -InformationAction Continue
        return
    }

    $planArgs = @{
        AuthProfile    = $AuthProfile
        IncludeAzure   = [bool]$IncludeAzure
        SkipTeams      = [bool]$SkipTeams
        SkipSharePoint = [bool]$SkipSharePoint
    }
    if ($PSBoundParameters.ContainsKey('Service') -and $Service -and $Service.Count -gt 0) {
        $planArgs['Service'] = $Service
    }
    $authPlan = Get-TenantBriefAuthPlan @planArgs
    $effectiveServices = @($authPlan.Services)
    Write-TenantBriefAuthBriefing -Plan $authPlan

    Write-Host "[TenantBrief] Cleaning any previous tenant sessions..." -ForegroundColor DarkGray
    if (Get-Module -Name 'Microsoft.Graph.Authentication') {
        try { Disconnect-MgGraph -ErrorAction SilentlyContinue | Out-Null } catch {}
    }
    if (Get-Module -Name 'Az.Accounts') {
        try { Clear-AzContext -Force -ErrorAction SilentlyContinue | Out-Null } catch {}
        try { Disconnect-AzAccount -ErrorAction SilentlyContinue | Out-Null } catch {}
    }
    if (Get-Module -Name 'ExchangeOnlineManagement') {
        try { Disconnect-ExchangeOnline -Confirm:$false -ErrorAction SilentlyContinue | Out-Null } catch {}
    }
    if (Get-Module -Name 'MicrosoftTeams') {
        try { Disconnect-MicrosoftTeams -ErrorAction SilentlyContinue | Out-Null } catch {}
    }
    if (Get-Module -Name 'Microsoft.Online.SharePoint.PowerShell') {
        try { Disconnect-SPOService -ErrorAction SilentlyContinue | Out-Null } catch {}
    }

    Write-Host "[TenantBrief] Checking ZeroTrustAssessment, ScubaGear, ORCA, Maester, Teams & PSGallery dependencies..." -ForegroundColor Cyan
    if (-not (Get-Module -ListAvailable -Name 'ZeroTrustAssessment')) {
        throw "Required module 'ZeroTrustAssessment' is not installed. Run: Install-Module ZeroTrustAssessment -Scope CurrentUser"
    }

    foreach ($dep in @('Microsoft.Graph.Beta.Teams', 'MicrosoftTeams', 'powershell-yaml', 'ScubaGear', 'ORCA', 'Maester')) {
        if (-not (Get-Module -ListAvailable -Name $dep)) {
            if ($AutoFixDependencies) {
                Write-Host "[TenantBrief] Installing missing module '$dep' from PSGallery..." -ForegroundColor Yellow
                try {
                    Install-Module -Name $dep -Repository PSGallery -Scope CurrentUser -Force -AllowClobber -ErrorAction Stop
                } catch {
                    Write-Warning "Could not auto-install '$dep': $($_.Exception.Message)"
                }
            } else {
                Write-Warning "[TenantBrief] Optional module '$dep' is not installed. Run: Install-Module $dep -Scope CurrentUser (or pass -AutoFixDependencies)."
            }
        }
    }

    # ZeroTrustAssessment pins exact dependency versions in ZeroTrustAssessment.psd1
    # (Microsoft.Graph.Authentication 2.40.0, Microsoft.Online.SharePoint.PowerShell 16.0.27612.12000).
    $spoReqVersion = '16.0.27612.12000'
    $graphReqVersion = '2.40.0'
    $aipReqVersion = '3.1.0.0'
    $ztAvail = Get-Module -ListAvailable -Name 'ZeroTrustAssessment' | Sort-Object Version -Descending | Select-Object -First 1
    if ($ztAvail) {
        try {
            $ztManifest = Import-PowerShellDataFile -Path $ztAvail.Path -ErrorAction Stop
            $winSpecs = $ztManifest.PrivateData.WindowsPowerShellRequiredModules
            $spoSpec = @($winSpecs) | Where-Object { $_ -and $_.ModuleName -eq 'Microsoft.Online.SharePoint.PowerShell' } | Select-Object -First 1
            if ($spoSpec -and $spoSpec.RequiredVersion) { $spoReqVersion = [string]$spoSpec.RequiredVersion }
            $aipSpec = @($winSpecs) | Where-Object { $_ -and $_.ModuleName -eq 'AipService' } | Select-Object -First 1
            if ($aipSpec -and $aipSpec.RequiredVersion) { $aipReqVersion = [string]$aipSpec.RequiredVersion }
            $xplatSpecs = $ztManifest.PrivateData.XPlatPowerShellRequiredModules
            $gSpec = @($xplatSpecs) | Where-Object { $_ -and $_.ModuleName -eq 'Microsoft.Graph.Authentication' } | Select-Object -First 1
            if ($gSpec -and $gSpec.RequiredVersion) { $graphReqVersion = [string]$gSpec.RequiredVersion }
        } catch {}
    }

    # Prune newer unpinned Microsoft.Graph.Authentication versions only when -AutoFixDependencies is explicitly supplied.
    $allGraphMods = @(Get-Module -ListAvailable -Name 'Microsoft.Graph.Authentication')
    if ($allGraphMods | Where-Object { $_.Version.ToString() -eq $graphReqVersion }) {
        foreach ($gm in $allGraphMods) {
            if ($gm.Version.ToString() -ne $graphReqVersion -and $gm.ModuleBase -like "$($env:USERPROFILE)*") {
                if ($AutoFixDependencies) {
                    try {
                        Remove-Item -Path $gm.ModuleBase -Recurse -Force -ErrorAction Stop
                        Write-Host "[TenantBrief] Removed unpinned Microsoft.Graph.Authentication v$($gm.Version) to keep v$graphReqVersion aligned with ZeroTrustAssessment." -ForegroundColor DarkGray
                    } catch {
                        Write-Warning "[TenantBrief] Could not remove Microsoft.Graph.Authentication v$($gm.Version) at '$($gm.ModuleBase)' (close other PowerShell windows holding the DLL): $($_.Exception.Message)"
                    }
                } else {
                    Write-Warning "[TenantBrief] Unpinned Microsoft.Graph.Authentication v$($gm.Version) detected alongside v$graphReqVersion. Pass -AutoFixDependencies or remove '$($gm.ModuleBase)' manually if assembly conflicts occur."
                }
            }
        }
    }

    # Satisfy ZeroTrustAssessment Initialize-Dependencies check when retired AipService is not in -Service
    if ('AipService' -notin $Service -and $env:APPDATA) {
        $hasAip = Get-Module -FullyQualifiedName @{ ModuleName = 'AipService'; GUID = 'e338ccc0-3333-4479-87fe-66382d33782d'; RequiredVersion = $aipReqVersion } -ListAvailable -ErrorAction SilentlyContinue
        if (-not $hasAip) {
            $aipStubDir = Join-Path $env:APPDATA "ZeroTrustAssessment\Modules\AipService\$aipReqVersion"
            if (-not (Test-Path (Join-Path $aipStubDir 'AipService.psd1'))) {
                try {
                    $null = New-Item -ItemType Directory -Path $aipStubDir -Force -ErrorAction Stop
                    Set-Content -Path (Join-Path $aipStubDir 'AipService.psm1') -Value '# Placeholder stub when AipService is not selected in -Service.' -Encoding UTF8
                    @"
@{
    RootModule    = 'AipService.psm1'
    ModuleVersion = '$aipReqVersion'
    GUID          = 'e338ccc0-3333-4479-87fe-66382d33782d'
}
"@ | Set-Content -Path (Join-Path $aipStubDir 'AipService.psd1') -Encoding UTF8
                } catch {}
            }
        }
    }

    $docsDir = [Environment]::GetFolderPath('MyDocuments')
    $winPsModulesDir = if ($docsDir) { Join-Path $docsDir 'WindowsPowerShell\Modules' } else { Join-Path $HOME 'Documents\WindowsPowerShell\Modules' }
    if (-not (Test-Path $winPsModulesDir)) {
        try { $null = New-Item -ItemType Directory -Path $winPsModulesDir -Force -ErrorAction Stop } catch {}
    }
    $pathEntries = @($env:PSModulePath -split [System.IO.Path]::PathSeparator | Where-Object { $_ })
    if ($pathEntries -notcontains $winPsModulesDir) {
        $env:PSModulePath = (@($winPsModulesDir) + $pathEntries) -join [System.IO.Path]::PathSeparator
    }

    # Remove newer/unpinned copies in the PS7-only Documents\PowerShell\Modules folder that -UseWindowsPowerShell
    # cannot load and that can shadow the pinned version expected by ZeroTrustAssessment.
    if ($docsDir) {
        $ps7SpoDir = Join-Path $docsDir 'PowerShell\Modules\Microsoft.Online.SharePoint.PowerShell'
        if (Test-Path $ps7SpoDir) {
            foreach ($verDir in @(Get-ChildItem -Path $ps7SpoDir -Directory -ErrorAction SilentlyContinue)) {
                if ($verDir.Name -ne $spoReqVersion) {
                    if ($AutoFixDependencies) {
                        try {
                            Remove-Item -Path $verDir.FullName -Recurse -Force -ErrorAction Stop
                        } catch {
                            Write-Warning "[TenantBrief] Could not remove unpinned PS7 SharePoint module '$($verDir.FullName)': $($_.Exception.Message)"
                        }
                    } else {
                        Write-Warning "[TenantBrief] Unpinned PS7 SharePoint module '$($verDir.FullName)' detected. Pass -AutoFixDependencies or remove it manually."
                    }
                }
            }
        }
    }

    $spoTargetDir = Join-Path $winPsModulesDir "Microsoft.Online.SharePoint.PowerShell\$spoReqVersion"
    if (-not (Test-Path $spoTargetDir)) {
        if ($AutoFixDependencies) {
            Write-Host "[TenantBrief] Installing Microsoft.Online.SharePoint.PowerShell v$spoReqVersion into WindowsPowerShell\Modules for PS7/WinPS5 compatibility..." -ForegroundColor Yellow
            try {
                if (Get-Command Save-Module -ErrorAction SilentlyContinue) {
                    Save-Module -Name 'Microsoft.Online.SharePoint.PowerShell' -RequiredVersion $spoReqVersion -Repository PSGallery -Path $winPsModulesDir -Force -ErrorAction Stop
                } elseif (Get-Command Save-PSResource -ErrorAction SilentlyContinue) {
                    Save-PSResource -Name 'Microsoft.Online.SharePoint.PowerShell' -Version $spoReqVersion -Repository PSGallery -Path $winPsModulesDir -TrustRepository -ErrorAction Stop
                } else {
                    Write-Warning "Could not auto-install Microsoft.Online.SharePoint.PowerShell v$spoReqVersion`: neither Save-Module nor Save-PSResource is available."
                }
            } catch {
                Write-Warning "Could not auto-install Microsoft.Online.SharePoint.PowerShell v$spoReqVersion`: $($_.Exception.Message)"
            }
        } else {
            Write-Warning "[TenantBrief] Microsoft.Online.SharePoint.PowerShell v$spoReqVersion is not in '$winPsModulesDir'. Run: Save-Module Microsoft.Online.SharePoint.PowerShell -RequiredVersion $spoReqVersion -Path '$winPsModulesDir' (or pass -AutoFixDependencies)."
        }
    }

    $opaExe = Join-Path $env:USERPROFILE '.scubagear\Tools\opa_windows_amd64.exe'
    if (-not (Test-Path $opaExe) -and (Get-Module -ListAvailable -Name 'ScubaGear')) {
        if ($AutoFixDependencies) {
            Write-Host "[TenantBrief] Installing OPA executable for ScubaGear..." -ForegroundColor Yellow
            try {
                Set-StrictMode -Off
                Import-Module ScubaGear -ErrorAction SilentlyContinue -WarningAction SilentlyContinue 6>$null 3>$null 2>$null | Out-Null
                Install-OPAforSCuBA | Out-Null
            } catch {
                Write-Warning "Could not auto-install OPA: $($_.Exception.Message)"
            } finally {
                Set-StrictMode -Version Latest
            }
        } else {
            Write-Warning "[TenantBrief] ScubaGear OPA executable not found at '$opaExe'. Run: Install-OPAforSCuBA (or pass -AutoFixDependencies)."
        }
    }

    $phaseAServices = @($effectiveServices | Where-Object { $_ -in @('Graph', 'Azure') })
    $phaseBServices = @($effectiveServices | Where-Object { $_ -in @('ExchangeOnline', 'SecurityCompliance', 'SharePointOnline') })
    if ($phaseAServices.Count -eq 0 -and $phaseBServices.Count -gt 0) {
        $phaseAServices = $phaseBServices
        $phaseBServices = @()
    }

    $paramsA = @{ Service = $phaseAServices }
    if ($Tenant) { $paramsA['TenantId'] = $Tenant }
    if ($UseDeviceCode) { $paramsA['UseDeviceCode'] = $true }

    Write-Host "[TenantBrief] Connecting in Read-Only mode (Profile: $AuthProfile)..." -ForegroundColor Green
    Set-StrictMode -Off
    try {
        Import-Module -Name 'Microsoft.Graph.Authentication' -RequiredVersion $graphReqVersion -Global -ErrorAction SilentlyContinue 2>$null 3>$null | Out-Null
        Import-Module ZeroTrustAssessment -Global -ErrorAction SilentlyContinue 2>$null 3>$null | Out-Null
        Connect-ZtAssessment @paramsA
    } finally {
        Set-StrictMode -Version Latest
    }

    $mgCtx = Get-MgContext -ErrorAction SilentlyContinue
    if (-not $mgCtx) {
        throw "Authentication canceled or failed: Microsoft Graph session could not be established."
    }
    $loginHintUpn = [string]$mgCtx.Account
    Write-Host "[TenantBrief] Verified active Graph session for: $loginHintUpn" -ForegroundColor Green

    if ($phaseBServices.Count -gt 0) {
        $paramsB = @{ Service = $phaseBServices }
        if ($mgCtx.TenantId) { $paramsB['TenantId'] = $mgCtx.TenantId }
        elseif ($Tenant) { $paramsB['TenantId'] = $Tenant }
        if ($UseDeviceCode) { $paramsB['UseDeviceCode'] = $true }
        if (-not [string]::IsNullOrWhiteSpace($loginHintUpn)) {
            $paramsB['UserPrincipalName'] = $loginHintUpn
        }
        Write-Information -MessageData "[TenantBrief] Connecting secondary services ($($phaseBServices -join ', ')) with UPN login hint ($loginHintUpn)..." -InformationAction Continue
        Set-StrictMode -Off
        try {
            Connect-ZtAssessment @paramsB
        } finally {
            Set-StrictMode -Version Latest
        }
    }

    # Auto-connect Microsoft Teams only in Full profile (not Quick) and without -AccountId (d41e7ff WAM Error 3399548929)
    if ($authPlan.IncludeTeams -and (Get-Module -ListAvailable -Name 'MicrosoftTeams')) {
        Write-Host "[TenantBrief] Connecting to Microsoft Teams (Read-Only for Teams/CIS checks)..." -ForegroundColor Cyan
        Set-StrictMode -Off
        try {
            Import-Module MicrosoftTeams -Global -ErrorAction Stop -WarningAction SilentlyContinue | Out-Null
            $teamsParams = @{ ErrorAction = 'Stop' }
            if ($mgCtx.TenantId) { $teamsParams['TenantId'] = $mgCtx.TenantId }
            elseif ($Tenant) { $teamsParams['TenantId'] = $Tenant }
            if ($UseDeviceCode) { $teamsParams['UseDeviceCode'] = $true }
            try {
                Connect-MicrosoftTeams @teamsParams | Out-Null
            } catch {
                $tErr = $_.Exception.Message
                if (-not $UseDeviceCode -and ($tErr -match 'WAM Error|3399548929|Need user interaction|broker')) {
                    Write-Host "[TenantBrief] WAM blocked interactive sign-in for Teams; retrying with Device Code (microsoft.com/devicelogin)..." -ForegroundColor Yellow
                    $teamsParams['UseDeviceCode'] = $true
                    Connect-MicrosoftTeams @teamsParams | Out-Null
                } else {
                    throw
                }
            }
            Write-Host "[TenantBrief] Connected to Microsoft Teams." -ForegroundColor Green
        } catch {
            Write-Warning "[TenantBrief] Microsoft Teams connection skipped: $($_.Exception.Message)"
        } finally {
            Set-StrictMode -Version Latest
        }
    }

    # Verify SharePoint Online session only when explicitly part of the AuthPlan (disclosed in pre-auth briefing)
    if ($authPlan.IncludeSharePoint) {
        $spoConnected = $false
        try {
            if (Get-Command Get-SPOTenant -ErrorAction SilentlyContinue) {
                $null = Get-SPOTenant -ErrorAction Stop
                $spoConnected = $true
            }
        } catch {}

        if (-not $spoConnected) {
            try {
                $orgResp = Invoke-MgGraphRequest -Method GET -Uri 'https://graph.microsoft.com/v1.0/organization?$select=verifiedDomains' -ErrorAction Stop
                $onMs = @($orgResp.value[0].verifiedDomains | Where-Object { $_.name -like '*.onmicrosoft.com' -and $_.name -notlike '*.mail.onmicrosoft.com' } | Select-Object -First 1)
                $prefix = if ($onMs -and $onMs.name) { ($onMs.name -split '\.')[0] } else { '' }
                if ($prefix) {
                    $spoAdminUrl = "https://$prefix-admin.sharepoint.com"
                    Write-Host "[TenantBrief] Connecting to SharePoint Online ($spoAdminUrl)..." -ForegroundColor Cyan
                    Set-StrictMode -Off
                    try {
                        if ($PSVersionTable.PSVersion.Major -ge 7) {
                            Import-Module Microsoft.Online.SharePoint.PowerShell -UseWindowsPowerShell -Global -ErrorAction Stop -WarningAction SilentlyContinue 3>$null | Out-Null
                        } else {
                            Import-Module Microsoft.Online.SharePoint.PowerShell -Global -ErrorAction Stop -WarningAction SilentlyContinue | Out-Null
                        }
                        Connect-SPOService -Url $spoAdminUrl -ErrorAction Stop | Out-Null
                        Write-Host "[TenantBrief] Connected to SharePoint Online ($spoAdminUrl)." -ForegroundColor Green
                    } finally {
                        Set-StrictMode -Version Latest
                    }
                }
            } catch {
                Write-Warning "[TenantBrief] SharePoint Online auto-connect skipped: $($_.Exception.Message)"
            }
        }
    }
}
