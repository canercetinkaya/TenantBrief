Set-StrictMode -Version Latest

$script:ModuleRoot = $PSScriptRoot
$script:FrameworkMapPath = Join-Path $script:ModuleRoot 'data\framework-mappings.json'
$script:ReportTemplatePath = Join-Path $script:ModuleRoot 'assets\report-template.html'

function Get-TenantBriefFrameworks {
    <#
    .SYNOPSIS
    Lists the compliance frameworks supported by TenantBrief.

    .DESCRIPTION
    Returns the five shipped frameworks (ZeroTrust, ISO27001, NIST_CSF_2, CIS_M365, KVKK_TR)
    with their Turkish and English display names.
    
    The list is read from data/framework-mappings.json, so adding a framework to that file
    is enough to surface it here.

    .EXAMPLE
    Get-TenantBriefFrameworks | Format-Table Id, NameTr
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param()

    if (-not (Test-Path $script:FrameworkMapPath)) {
        throw "Framework mapping file not found: $script:FrameworkMapPath"
    }

    $json = Get-Content -Path $script:FrameworkMapPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $json.frameworks.PSObject.Properties | ForEach-Object {
        [PSCustomObject]@{
            Id            = $_.Name
            NameEn        = $_.Value.nameEn
            NameTr        = $_.Value.nameTr
            DescriptionEn = $_.Value.descriptionEn
            DescriptionTr = $_.Value.descriptionTr
        }
    }
}

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
        [ValidateSet('Graph', 'Azure', 'ExchangeOnline', 'SecurityCompliance', 'SharePointOnline')]
        [string[]]$Service = @('Graph', 'Azure', 'ExchangeOnline', 'SecurityCompliance', 'SharePointOnline'),

        [Parameter()]
        [switch]$UseDeviceCode
    )

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

    Write-Host "[TenantBrief] Checking ZeroTrustAssessment, ScubaGear, ORCA & PSGallery dependencies..." -ForegroundColor Cyan
    if (-not (Get-Module -ListAvailable -Name 'ZeroTrustAssessment')) {
        throw "Required module 'ZeroTrustAssessment' is not installed. Run: Install-Module ZeroTrustAssessment -Scope CurrentUser"
    }

    foreach ($dep in @('Microsoft.Graph.Beta.Teams', 'powershell-yaml', 'ScubaGear', 'ORCA', 'Maester')) {
        if (-not (Get-Module -ListAvailable -Name $dep)) {
            Write-Host "[TenantBrief] Installing missing module '$dep' from PSGallery..." -ForegroundColor Yellow
            try {
                Install-Module -Name $dep -Repository PSGallery -Scope CurrentUser -Force -AllowClobber -ErrorAction Stop
            } catch {
                Write-Warning "Could not auto-install '$dep': $($_.Exception.Message)"
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

    # Prune newer unpinned Microsoft.Graph.Authentication versions (e.g. 2.41.2 pulled transitively by Maester)
    # when the pinned version exists, preventing CLR "different copy already loaded" errors.
    $allGraphMods = @(Get-Module -ListAvailable -Name 'Microsoft.Graph.Authentication')
    if ($allGraphMods | Where-Object { $_.Version.ToString() -eq $graphReqVersion }) {
        foreach ($gm in $allGraphMods) {
            if ($gm.Version.ToString() -ne $graphReqVersion -and $gm.ModuleBase -like "$($env:USERPROFILE)*") {
                try {
                    Remove-Item -Path $gm.ModuleBase -Recurse -Force -ErrorAction Stop
                    Write-Host "[TenantBrief] Removed unpinned Microsoft.Graph.Authentication v$($gm.Version) to keep v$graphReqVersion aligned with ZeroTrustAssessment." -ForegroundColor DarkGray
                } catch {
                    Write-Warning "[TenantBrief] Could not remove Microsoft.Graph.Authentication v$($gm.Version) at '$($gm.ModuleBase)' (close other PowerShell windows holding the DLL): $($_.Exception.Message)"
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
                    try {
                        Remove-Item -Path $verDir.FullName -Recurse -Force -ErrorAction Stop
                    } catch {
                        Write-Warning "[TenantBrief] Could not remove unpinned PS7 SharePoint module '$($verDir.FullName)': $($_.Exception.Message)"
                    }
                }
            }
        }
    }

    $spoTargetDir = Join-Path $winPsModulesDir "Microsoft.Online.SharePoint.PowerShell\$spoReqVersion"
    if (-not (Test-Path $spoTargetDir)) {
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
    }

    $opaExe = Join-Path $env:USERPROFILE '.scubagear\Tools\opa_windows_amd64.exe'
    if (-not (Test-Path $opaExe) -and (Get-Module -ListAvailable -Name 'ScubaGear')) {
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
    }

    $params = @{ Service = $Service }
    if ($Tenant) { $params['TenantId'] = $Tenant }
    if ($UseDeviceCode) { $params['UseDeviceCode'] = $true }

    Write-Host "[TenantBrief] Connecting in Read-Only mode..." -ForegroundColor Green
    Set-StrictMode -Off
    try {
        Import-Module -Name 'Microsoft.Graph.Authentication' -RequiredVersion $graphReqVersion -Global -ErrorAction SilentlyContinue 2>$null 3>$null | Out-Null
        Import-Module ZeroTrustAssessment -Global -ErrorAction SilentlyContinue 2>$null 3>$null | Out-Null
        Connect-ZtAssessment @params
    } finally {
        Set-StrictMode -Version Latest
    }

    $mgCtx = Get-MgContext -ErrorAction SilentlyContinue
    if (-not $mgCtx) {
        throw "Authentication canceled or failed: Microsoft Graph session could not be established."
    }
    Write-Host "[TenantBrief] Verified active Graph session for: $($mgCtx.Account)" -ForegroundColor Green
}

function ConvertTo-TenantBriefTurkish {
    param([string]$Text)
    if ([string]::IsNullOrWhiteSpace($Text)) { return $Text }
    $map = [ordered]@{
        'Conditional Access policies' = 'Koşullu Erişim ilkeleri'
        'Conditional Access policy'   = 'Koşullu Erişim ilkesi'
        'Conditional Access'          = 'Koşullu Erişim'
        'Sensitivity labels'          = 'Hassasiyet etiketleri'
        'Break-glass'                 = 'Acil durum (Break-glass)'
        'Legacy authentication'       = 'Eski kimlik doğrulama (Legacy Auth)'
        'Token protection'            = 'Belirteç koruması (Token Protection)'
        'Passkey'                     = 'Geçiş anahtarı (Passkey)'
        'Passwordless'                = 'Parolasız kimlik doğrulama'
        'Admin consent'               = 'Yönetici onayı'
        'are configured'              = 'yapılandırılmış'
        'is configured'               = 'yapılandırılmış'
        'are enabled'                 = 'etkinleştirilmiş'
        'is enabled'                  = 'etkinleştirilmiş'
        'are enforced'                = 'zorunlu kılınmış'
        'is enforced'                 = 'zorunlu kılınmış'
        'are published to users'      = 'kullanıcılara yayımlanmış'
        'are blocked'                 = 'engellenmiş'
        'is blocked'                  = 'engellenmiş'
        'are required'                = 'zorunlu'
        'is required'                 = 'zorunlu'
        'for all users'               = 'tüm kullanıcılar için'
        'for all administrators'      = 'tüm yöneticiler için'
        'for privileged roles'        = 'ayrıcalıklı roller için'
        'with encryption'             = 'şifreleme ile'
        'should be'                   = 'olmalıdır'
        'must be'                     = 'olmalıdır'
        'High'                        = 'Yüksek'
        'Medium'                      = 'Orta'
        'Low'                         = 'Düşük'
    }
    $out = $Text
    foreach ($k in $map.Keys) {
        $out = $out -replace [regex]::Escape($k), $map[$k]
    }
    return $out
}

#region Internal pipeline helpers (analysis / presentation)

function Add-TenantBriefDiagnostic {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [System.Collections.Generic.List[object]]$Diagnostics,

        [Parameter(Mandatory = $true)]
        [int]$Stage,

        [Parameter(Mandatory = $true)]
        [string]$Component,

        [Parameter(Mandatory = $true)]
        [string]$Message
    )

    if ($null -eq $Diagnostics) { return }
    $Diagnostics.Add([PSCustomObject]@{
        Stage     = $Stage
        Component = $Component
        Severity  = 'Warning'
        Message   = $Message
        Timestamp = (Get-Date).ToString('o')
    })
    Write-Verbose "[TenantBrief] Stage $Stage / ${Component}: $Message"
}

function Set-TenantBriefStage {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [object]$Manifest,

        [Parameter(Mandatory = $true)]
        [int]$Stage,

        [Parameter(Mandatory = $true)]
        [string]$Name,

        [Parameter(Mandatory = $true)]
        [ValidateSet('started', 'completed', 'failed', 'skipped')]
        [string]$Status,

        [Parameter(Mandatory = $false)]
        [string]$Message
    )

    $now = (Get-Date).ToString('o')
    $entry = $null
    foreach ($s in @($Manifest.Stages)) {
        if ($s.Stage -eq $Stage) { $entry = $s; break }
    }
    if (-not $entry) {
        $entry = [PSCustomObject]@{
            Stage     = $Stage
            Name      = $Name
            Status    = $Status
            StartedAt = $now
            EndedAt   = $null
            Message   = ''
        }
        $Manifest.Stages = @($Manifest.Stages) + $entry
    }
    if (-not $entry.StartedAt) { $entry.StartedAt = $now }
    $entry.Status = $Status
    if ($Status -eq 'started') { $entry.EndedAt = $null } else { $entry.EndedAt = $now }
    if ($Message) { $entry.Message = $Message }
}

function Save-TenantBriefRunManifest {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [object]$Manifest,

        [Parameter(Mandatory = $true)]
        [string]$Path,

        [Parameter(Mandatory = $false)]
        [string]$Status,

        [Parameter(Mandatory = $false)]
        [AllowEmptyCollection()]
        [System.Collections.Generic.List[object]]$Diagnostics
    )

    if ($Status) { $Manifest.Status = $Status }
    $Manifest.UpdatedAt = (Get-Date).ToString('o')
    if ($null -ne $Diagnostics) { $Manifest.Diagnostics = @($Diagnostics) }
    try {
        # Written after every stage transition so an interrupted run still leaves a trace on disk.
        $Manifest | ConvertTo-Json -Depth 6 | Set-Content -Path $Path -Encoding UTF8 -ErrorAction Stop
    } catch {
        Write-Verbose "[TenantBrief] run manifest could not be written: $($_.Exception.Message)"
    }
}

function New-TenantBriefProgressDashboard {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet('tr', 'en')]
        [string]$Language,

        [Parameter(Mandatory = $true)]
        [hashtable]$State,

        [Parameter(Mandatory = $false)]
        [object]$ZtDict
    )

    $progressJob = $null
    $selectedPort = $null
    foreach ($candidatePort in 8925..8945) {
        try {
            $probe = New-Object System.Net.HttpListener
            $probe.Prefixes.Add("http://localhost:$candidatePort/")
            $probe.Start()
            $probe.Stop()
            $probe.Close()
            $selectedPort = $candidatePort
            break
        } catch {
            continue
        }
    }

    $progressHtmlPath = Join-Path $script:ModuleRoot 'assets\progress-template.html'
    if ($selectedPort -and (Test-Path $progressHtmlPath)) {
        $pHtml = Get-Content -Path $progressHtmlPath -Raw -Encoding UTF8
        $isTrUi = ($Language -eq 'tr')
        $labelsJson = if ($isTrUi) {
            '["1. ZeroTrustAssessment (Kiracı Veri Toplama & Testler)","2. CISA ScubaGear (Güvenlik Taban Hattı)","3. Microsoft ORCA & Maester (MDO, EIDSCA & CIS)","4. Korelasyon, Lisans ROI/İsraf, Copilot & 5 Çerçeve","5. TenantBrief Rapor Üretimi"]'
        } else {
            '["1. ZeroTrustAssessment (Tenant Data & Checks)","2. CISA ScubaGear (Security Baselines)","3. Microsoft ORCA & Maester (MDO, EIDSCA & CIS)","4. Correlation, License ROI/Waste, Copilot & 5 Frameworks","5. Generating TenantBrief Reports"]'
        }
        $noticeTxt = if ($isTrUi) {
            'Bilgi: Kiracı büyüklüğüne bağlı olarak tarama birkaç dakikadan 30+ dakikaya kadar sürebilir. Hata mesajı görmediğiniz sürece PowerShell penceresini kapatmayın.'
        } else {
            'Notice: Depending on tenant size, assessment takes from a few minutes up to 30+ minutes. Keep PowerShell open unless an error appears.'
        }
        $pMap = @{
            '{{LANG}}'          = $Language
            '{{TITLE}}'         = $(if ($isTrUi) { 'Canlı Değerlendirme' } else { 'Live Assessment' })
            '{{RUNNING}}'       = $(if ($isTrUi) { 'Çalışıyor' } else { 'Running' })
            '{{NOTICE}}'        = $noticeTxt
            '{{LABELS_JSON}}'   = $labelsJson
            '{{LBL_COMPLETED}}' = $(if ($isTrUi) { 'Tamamlanan' } else { 'Completed' })
            '{{LBL_FAILED}}'    = $(if ($isTrUi) { 'Hata' } else { 'Failed' })
            '{{LBL_ELAPSED}}'   = $(if ($isTrUi) { 'Geçen Süre' } else { 'Elapsed' })
        }
        foreach ($pk in $pMap.Keys) { $pHtml = $pHtml.Replace($pk, $pMap[$pk]) }
        $doneLbl = if ($isTrUi) { 'Tamamlandı' } else { 'Completed' }
        $rs = [runspacefactory]::CreateRunspace()
        $rs.Open()
        $rs.SessionStateProxy.SetVariable('State', $State)
        $rs.SessionStateProxy.SetVariable('ZtDict', $ZtDict)
        $rs.SessionStateProxy.SetVariable('Html', $pHtml)
        $rs.SessionStateProxy.SetVariable('DoneLbl', $doneLbl)
        $rs.SessionStateProxy.SetVariable('Port', $selectedPort)
        $ps = [powershell]::Create()
        $ps.Runspace = $rs
        [void]$ps.AddScript({
            $listener = New-Object System.Net.HttpListener
            $listener.Prefixes.Add("http://localhost:$Port/")
            try {
                $listener.Start()
                while (-not $State.Stop -and $listener.IsListening) {
                    $ctxTask = $listener.GetContextAsync()
                    while (-not $ctxTask.AsyncWaitHandle.WaitOne(250)) {
                        if ($State.Stop) { break }
                    }
                    if ($State.Stop) { break }
                    $ctx = $ctxTask.GetAwaiter().GetResult()
                    $ctx.Response.Headers.Add('Cache-Control', 'no-cache, no-store, must-revalidate')
                    $reqPath = $ctx.Request.Url.AbsolutePath
                    $body = if ($reqPath -eq '/status.json') {
                        $ctx.Response.ContentType = 'application/json; charset=utf-8'
                        $ztStageName = [string]$State.ActiveTask
                        $ztTotal = 0
                        $ztCompleted = 0
                        $ztFailed = 0
                        $workerItems = @()

                        if ($State.Stage -eq 1 -and $null -ne $ZtDict) {
                            $sName = $null; if ($ZtDict.TryGetValue('_stageName', [ref]$sName) -and $sName) { $ztStageName = [string]$sName }
                            $tItems = 0; if ($ZtDict.TryGetValue('_totalItems', [ref]$tItems)) { $ztTotal = [int]$tItems }
                            $cItems = 0; if ($ZtDict.TryGetValue('_completedItems', [ref]$cItems)) { $ztCompleted = [int]$cItems }
                            $fItems = 0; if ($ZtDict.TryGetValue('_failedItems', [ref]$fItems)) { $ztFailed = [int]$fItems }

                            $rawWorkers = [System.Collections.Generic.List[object]]::new()
                            foreach ($k in @($ZtDict.Keys)) {
                                if ($k -is [string] -and $k.StartsWith('worker_')) {
                                    $w = $null
                                    if ($ZtDict.TryGetValue($k, [ref]$w) -and $null -ne $w) {
                                        $prio = switch ([string]$w.Status) { 'Running' { 0 } 'Failed' { 1 } 'TimedOut' { 1 } default { 2 } }
                                        $rawWorkers.Add([PSCustomObject]@{
                                            Prio      = $prio
                                            name      = [string]$w.Name
                                            status    = [string]$w.Status
                                            detail    = [string]$w.Detail
                                            startedAt = [string]$w.StartedAt
                                            updatedAt = [string]$w.UpdatedAt
                                        })
                                    }
                                }
                            }
                            if ($rawWorkers.Count -gt 0) {
                                $workerItems = @($rawWorkers | Sort-Object Prio, @{ Expression = 'updatedAt'; Descending = $true } | Select-Object -First 60 | ForEach-Object {
                                    @{ name = $_.name; status = $_.status; detail = $_.detail; startedAt = $_.startedAt }
                                })
                            }
                        }

                        if ($workerItems.Count -eq 0) {
                            $logEntries = @($State.Logs)
                            [array]::Reverse($logEntries)
                            $workerItems = @($logEntries | Select-Object -First 25 | ForEach-Object {
                                @{ name = $_; status = $(if ($State.Done) { 'Done' } else { 'Running' }); detail = ''; startedAt = '' }
                            })
                            if ($workerItems.Count -eq 0) {
                                $workerItems = @(@{ name = [string]$State.ActiveTask; status = 'Running'; detail = ''; startedAt = '' })
                            }
                        }

                        (@{
                            stage       = $State.Stage
                            done        = $State.Done
                            error       = $State.Error
                            doneLabel   = $DoneLbl
                            ztStageName = $ztStageName
                            ztTotal     = $ztTotal
                            ztCompleted = $ztCompleted
                            ztFailed    = $ztFailed
                            workers     = $workerItems
                        } | ConvertTo-Json -Depth 4 -Compress)
                    } else {
                        $ctx.Response.ContentType = 'text/html; charset=utf-8'
                        $Html
                    }
                    $bytes = [System.Text.Encoding]::UTF8.GetBytes($body)
                    $ctx.Response.ContentLength64 = $bytes.Length
                    $ctx.Response.OutputStream.Write($bytes, 0, $bytes.Length)
                    $ctx.Response.Close()
                }
            } catch {} finally {
                if ($listener.IsListening) { $listener.Stop() }
                $listener.Close()
            }
        })
        $asyncHandle = $ps.BeginInvoke()
        $progressJob = @{ Ps = $ps; Handle = $asyncHandle; Rs = $rs }
        Write-Host "[TenantBrief] Live progress dashboard: http://localhost:$selectedPort/" -ForegroundColor Green
        Start-Process "http://localhost:$selectedPort/"
    }

    return $progressJob
}

function ConvertTo-TenantBriefPillarList {
    [CmdletBinding()]
    param([Parameter(Mandatory = $false)][object]$PillarValue)

    $knownMulti = @(
        'CISA SCuBA',
        'Defender for Office 365 (ORCA)',
        'Maester (EIDSCA / CIS)'
    )
    $rawTokens = New-Object System.Collections.Generic.List[string]
    foreach ($entry in @($PillarValue)) {
        if ($null -eq $entry) { continue }
        $s = ([string]$entry).Trim()
        if (-not $s) { continue }
        # Split comma-separated entries first, preserving known multi-word engine pillar labels.
        foreach ($part in ($s -split '\s*,\s*')) {
            $p = $part.Trim()
            if (-not $p) { continue }
            if ($knownMulti -contains $p) {
                $rawTokens.Add($p)
            } elseif ($p -match '\s+' -and ($p -notin @('CISA SCuBA', 'EntraFalcon', 'General'))) {
                foreach ($sub in ($p -split '\s+')) {
                    if ($sub.Trim()) { $rawTokens.Add($sub.Trim()) }
                }
            } else {
                $rawTokens.Add($p)
            }
        }
    }

    $seen = New-Object System.Collections.Generic.HashSet[string] ([System.StringComparer]::OrdinalIgnoreCase)
    $out = New-Object System.Collections.Generic.List[string]
    foreach ($tok in $rawTokens) {
        if ($seen.Add($tok)) { $out.Add($tok) }
    }
    return @($out.ToArray())
}

function Resolve-TenantBriefSourceTag {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][object]$Test)

    $existing = @(Get-TenantBriefPropertyValue -Object $Test -Name 'TestSources')
    $list = New-Object System.Collections.Generic.List[string]
    $seen = New-Object System.Collections.Generic.HashSet[string] ([System.StringComparer]::OrdinalIgnoreCase)
    $addTag = {
        param([string]$Tag)
        if ($Tag -and $seen.Add($Tag)) { $list.Add($Tag) }
    }

    foreach ($e in $existing) { & $addTag ([string]$e) }
    $explicit = [string](Get-TenantBriefPropertyValue -Object $Test -Name 'TestSource')
    if ($explicit) { & $addTag $explicit }

    $id = [string](Get-TenantBriefPropertyValue -Object $Test -Name 'TestId')
    $pillars = @(ConvertTo-TenantBriefPillarList -PillarValue (Get-TenantBriefPropertyValue -Object $Test -Name 'TestPillar'))

    if ($id -like 'SCUBA-*' -or ($pillars -contains 'CISA SCuBA')) { & $addTag 'CISA SCuBA' }
    if ($id -like 'ORCA-*' -or ($pillars -contains 'Defender for Office 365 (ORCA)')) { & $addTag 'MDO / ORCA' }
    if ($id -like 'EF-*' -or ($pillars -contains 'EntraFalcon')) { & $addTag 'EntraFalcon' }
    if ($id -like 'CIS.M365.*') { & $addTag 'CIS M365' }
    elseif ($id -like 'EIDSCA.*') { & $addTag 'EIDSCA' }
    elseif (($pillars -contains 'Maester (EIDSCA / CIS)') -and -not $explicit) { & $addTag 'Maester' }

    $ztPillars = @('Identity', 'Devices', 'Network', 'Data', 'Infrastructure', 'SecOps', 'AI')
    if (@($pillars | Where-Object { $ztPillars -contains $_ }).Count -gt 0 -or ($id -match '^\d+$')) {
        & $addTag 'ZeroTrust'
    }

    if ($list.Count -eq 0) { & $addTag 'ZeroTrust' }
    return @($list.ToArray())
}

function Resolve-TenantBriefDomainPillars {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][object]$Test)

    $id = [string](Get-TenantBriefPropertyValue -Object $Test -Name 'TestId')
    $cat = [string](Get-TenantBriefPropertyValue -Object $Test -Name 'TestCategory')
    $pillars = @(ConvertTo-TenantBriefPillarList -PillarValue (Get-TenantBriefPropertyValue -Object $Test -Name 'TestPillar'))

    $domain = New-Object System.Collections.Generic.List[string]
    $seen = New-Object System.Collections.Generic.HashSet[string] ([System.StringComparer]::OrdinalIgnoreCase)
    $addDom = {
        param([string]$D)
        if ($D -and $seen.Add($D)) { $domain.Add($D) }
    }

    foreach ($p in $pillars) {
        switch ($p) {
            'Identity'                       { & $addDom 'Identity' }
            'Devices'                        { & $addDom 'Devices' }
            'Network'                        { & $addDom 'Network' }
            'Infrastructure'                 { & $addDom 'Network' }
            'Data'                           { & $addDom 'Data' }
            'AI'                             { & $addDom 'AI' }
            'SecOps'                         { & $addDom 'SecOps' }
            'Defender for Office 365 (ORCA)' { & $addDom 'SecOps' }
            'EntraFalcon'                    { & $addDom 'Identity' }
            'CISA SCuBA' {
                if ($id -match '\.(EXO|DEFENDER)\.') { & $addDom 'SecOps' }
                elseif ($id -match '\.(SHAREPOINT|ONE)\.') { & $addDom 'Data' }
                else { & $addDom 'Identity' }
            }
            'Maester (EIDSCA / CIS)' {
                if ($id -match '^CIS\.M365\.(4\.|5\.1\.4\.6$)' -or $cat -match 'Intune') {
                    & $addDom 'Devices'
                } elseif ($id -match '^CIS\.M365\.(1\.3\.6|1\.3\.7|7\.|8\.1\.1)' -or $cat -match 'Purview|SharePoint') {
                    & $addDom 'Data'
                } elseif ($id -match '^CIS\.M365\.(1\.3\.3|1\.3\.5|2\.|3\.|6\.|8\.6\.1)' -or $cat -match 'Exchange|Defender|Exposure|Audit') {
                    & $addDom 'SecOps'
                } elseif ($cat -match 'Copilot|Agent') {
                    & $addDom 'AI'
                } elseif ($cat -match 'AzureConfig|Network|Infra') {
                    & $addDom 'Network'
                } else {
                    & $addDom 'Identity'
                }
            }
        }
    }

    if ($domain.Count -eq 0) { & $addDom 'Identity' }
    return @($domain.ToArray())
}

function Import-TenantBriefScubaResults {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$Path)

    if (-not (Test-Path $Path)) { return @() }
    $scubaJson = if (Test-Path $Path -PathType Leaf) {
        Get-Item $Path
    } else {
        $f = Get-ChildItem -Path $Path -Filter 'ScubaResults*.json' -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
        if (-not $f) { $f = Get-ChildItem -Path $Path -Filter '*Report.json' -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1 }
        $f
    }
    if (-not $scubaJson) { return @() }

    $scubaData = Get-Content -Path $scubaJson.FullName -Raw -Encoding UTF8 | ConvertFrom-Json
    $scCount = 0
    $scubaControlList = @()
    if ($scubaData.PSObject.Properties['Results']) {
        if ($scubaData.Results -is [System.Array]) {
            foreach ($grp in @($scubaData.Results)) {
                if ($grp.PSObject.Properties['Controls']) { $scubaControlList += @($grp.Controls) } else { $scubaControlList += $grp }
            }
        } else {
            foreach ($prop in $scubaData.Results.PSObject.Properties) {
                foreach ($entry in @($prop.Value)) {
                    if ($entry.PSObject.Properties['Controls']) {
                        foreach ($c in @($entry.Controls)) { $scubaControlList += [PSCustomObject]@{ Cat = [string]$prop.Name; Item = $c } }
                    } else {
                        $scubaControlList += [PSCustomObject]@{ Cat = [string]$prop.Name; Item = $entry }
                    }
                }
            }
        }
    }

    $out = @()
    foreach ($wrap in $scubaControlList) {
        $cat  = if ($wrap.PSObject.Properties['Cat']) { [string]$wrap.Cat } else { 'AAD' }
        $item = if ($wrap.PSObject.Properties['Item']) { $wrap.Item } else { $wrap }
        $ctrl = if ($item.PSObject.Properties['Control ID']) { [string]$item.'Control ID' } elseif ($item.PSObject.Properties['Control']) { [string]$item.Control } else { "$($scCount + 1)" }
        $reqRaw = if ($item.PSObject.Properties['Requirement']) { [string]$item.Requirement } else { "SCuBA Control $ctrl" }
        $reqClean = ($reqRaw -replace "<div class=['""]policy-indicators['""]>[\s\S]*$", '') -replace '<[^>]+>', ' '
        $req  = ([System.Net.WebUtility]::HtmlDecode($reqClean) -replace '\s+', ' ').Trim()
        $res  = if ($item.PSObject.Properties['Result']) { [string]$item.Result } else { '' }
        $crit = if ($item.PSObject.Properties['Criticality']) { [string]$item.Criticality } else { 'Should' }
        $detRaw = if ($item.PSObject.Properties['Details']) { [string]$item.Details } else { '' }
        $det  = ([System.Net.WebUtility]::HtmlDecode(($detRaw -replace '<[^>]+>', ' ')) -replace '\s+', ' ').Trim()
        if (-not $req) { continue }
        $scCount++
        $mappedStatus = switch -Regex ($res) {
            '^(Pass|Met)$'     { 'Passed' }
            '^(Fail|Not Met)$' { 'Failed' }
            default            { 'Investigate' }
        }
        $out += [PSCustomObject]@{
            TestId                 = if ($ctrl -like 'SCUBA-*') { $ctrl } else { "SCUBA-$ctrl" }
            TestTitle              = $req
            TestStatus             = $mappedStatus
            TestRisk               = if ($crit -match 'Shall') { 'High' } else { 'Medium' }
            TestPillar             = 'CISA SCuBA'
            TestSource             = 'CISA SCuBA'
            TestCategory           = $cat
            TestSfiPillar          = 'CISA SCuBA'
            TestImplementationCost = ''
            TestMinimumLicense     = ''
            SkippedReason          = ''
            TestResult             = $det
            TestImpact             = if ($crit -match 'Shall') { 'High' } else { 'Medium' }
            TestDescription        = $req
        }
    }
    return @($out)
}

function Import-TenantBriefOrcaResults {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$Path)

    if (-not (Test-Path $Path)) { return @() }
    $orcaFile = if (Test-Path $Path -PathType Leaf) {
        Get-Item $Path
    } else {
        Get-ChildItem -Path $Path -Filter '*.json' -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
    }
    if (-not $orcaFile) { return @() }

    $orcaData = Get-Content -Path $orcaFile.FullName -Raw -Encoding UTF8 | ConvertFrom-Json
    $orcaItems = if ($orcaData.PSObject.Properties['Results']) { @($orcaData.Results) } elseif ($orcaData.PSObject.Properties['Checks']) { @($orcaData.Checks) } else { @($orcaData) }
    $ocCount = 0
    $out = @()
    foreach ($item in $orcaItems) {
        $cName = if ($item.PSObject.Properties['Name'] -and $item.Name) { [string]$item.Name } elseif ($item.PSObject.Properties['CheckName'] -and $item.CheckName) { [string]$item.CheckName } else { '' }
        if (-not $cName) { continue }
        $ocCount++
        $ctrl = if ($item.PSObject.Properties['Control']) { [string]$item.Control } else { "ORCA-$ocCount" }
        $st   = if ($item.PSObject.Properties['Result']) { [string]$item.Result } else { '' }
        $area = if ($item.PSObject.Properties['Area'] -and $item.Area) { [string]$item.Area } else { 'Defender for Office 365' }
        $rec  = if ($item.PSObject.Properties['FailRecommendation']) { [string]$item.FailRecommendation } else { '' }
        $passTxt = if ($item.PSObject.Properties['PassText']) { [string]$item.PassText } else { '' }
        $imp  = if ($item.PSObject.Properties['Importance']) { [string]$item.Importance } else { '' }
        $mappedOrStatus = if ($st -in @('1', 'Pass', 'OK')) { 'Passed' } elseif ($st -in @('2', '0', 'Informational', 'Info', 'None')) { 'Investigate' } else { 'Failed' }
        $out += [PSCustomObject]@{
            TestId                 = if ($ctrl -like 'ORCA-*') { $ctrl } else { "ORCA-$ctrl" }
            TestTitle              = $cName
            TestStatus             = $mappedOrStatus
            TestRisk               = 'Medium'
            TestPillar             = 'Defender for Office 365 (ORCA)'
            TestSource             = 'MDO / ORCA'
            TestCategory           = $area
            TestSfiPillar          = 'Defender for Office 365'
            TestImplementationCost = ''
            TestMinimumLicense     = ''
            SkippedReason          = ''
            TestResult             = if ($mappedOrStatus -eq 'Passed' -and $passTxt) { $passTxt } else { $rec }
            TestImpact             = 'Medium'
            TestDescription        = if ($imp) { $imp } else { $cName }
        }
    }
    return @($out)
}

function Import-TenantBriefMaesterResults {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)][object]$MaesterResult,
        [Parameter(Mandatory = $false)][string]$JsonPath
    )

    $testsArray = @()
    if ($MaesterResult -and $MaesterResult.PSObject.Properties['Tests']) {
        $testsArray = @($MaesterResult.Tests)
    } elseif ($JsonPath -and (Test-Path $JsonPath)) {
        $parsed = Get-Content -Path $JsonPath -Raw -Encoding UTF8 | ConvertFrom-Json
        if ($parsed -and $parsed.PSObject.Properties['Tests']) {
            $testsArray = @($parsed.Tests)
        } elseif ($parsed) {
            $testsArray = @($parsed)
        }
    }

    $out = @()
    foreach ($item in $testsArray) {
        if ($null -eq $item) { continue }
        $rawId = Get-TenantBriefPropertyValue -Object $item -Name 'Id'
        if (-not $rawId) { $rawId = Get-TenantBriefPropertyValue -Object $item -Name 'ID' }
        if (-not $rawId) { $rawId = Get-TenantBriefPropertyValue -Object $item -Name 'Name' }
        $rawId = [string]$rawId

        $res = [string](Get-TenantBriefPropertyValue -Object $item -Name 'Result')
        # Excluded tags (-ExcludeTag) are recorded by Pester as NotRun; never inflate report totals with them.
        if ($res -eq 'NotRun') { continue }

        $block = [string](Get-TenantBriefPropertyValue -Object $item -Name 'Block')
        if (-not $block) { $block = 'Entra / M365 Baseline' }
        # Skip non-M365-tenant suites (on-prem AD, Azure DevOps, GitHub) and CISA/ORCA duplicates handled natively.
        if ($rawId -match '^(AD|CISA|ORCA|AZDO)\.' -or $rawId -match '^CIS\.GH\.' -or $block -match '^(CISA|ORCA|Azure DevOps|Active Directory)') {
            continue
        }

        $rawTitle = [string](Get-TenantBriefPropertyValue -Object $item -Name 'Title')
        if (-not $rawTitle) { $rawTitle = [string](Get-TenantBriefPropertyValue -Object $item -Name 'Name') }
        $cleanTitle = ($rawTitle -replace '^[A-Za-z0-9\.\-_]+:\s*', '').Trim()
        if (-not $cleanTitle) { $cleanTitle = $rawId }
        if (-not $cleanTitle) { continue }

        $rd = Get-TenantBriefPropertyValue -Object $item -Name 'ResultDetail'
        $errRecords = @(Get-TenantBriefPropertyValue -Object $item -Name 'ErrorRecord')
        $isPesterSkip = ($res -eq 'Error') -and (
            ([string](Get-TenantBriefPropertyValue -Object $rd -Name 'TestSkipped') -eq 'Error') -or
            (@($errRecords | Where-Object { $_ -and ([string](Get-TenantBriefPropertyValue -Object $_ -Name 'FullyQualifiedErrorId')) -match 'PesterTestSkipped' }).Count -gt 0)
        )

        $mappedStatus = if ($isPesterSkip) {
            'Skipped'
        } else {
            switch -Regex ($res) {
                '^Passed$'  { 'Passed' }
                '^Failed$'  { 'Failed' }
                '^Skipped$' { 'Skipped' }
                '^Error$'   { 'Error' }
                default     { 'Investigate' }
            }
        }

        $sev = [string](Get-TenantBriefPropertyValue -Object $item -Name 'Severity')
        $mappedRisk = switch -Regex ($sev) {
            '^(Critical|High)$' { 'High' }
            '^(Low|Info)$'      { 'Low' }
            default             { 'Medium' }
        }

        $catLabel = $block
        if ($rawId -like 'CIS.M365.*' -and $block -eq 'CIS') {
            $catLabel = switch -Regex ($rawId) {
                '^CIS\.M365\.1\.(3\.[67])' { 'CIS M365 · Data & Storage' }
                '^CIS\.M365\.1\.3\.3'      { 'CIS M365 · Exchange & Calendar' }
                '^CIS\.M365\.2\.'          { 'CIS M365 · Defender for Office 365 & EXO' }
                '^CIS\.M365\.3\.'          { 'CIS M365 · Purview Audit' }
                '^CIS\.M365\.4\.'          { 'CIS M365 · Intune' }
                '^CIS\.M365\.5\.1\.4\.6$'  { 'CIS M365 · Intune / BitLocker' }
                '^CIS\.M365\.5\.'          { 'CIS M365 · Entra ID' }
                '^CIS\.M365\.6\.'          { 'CIS M365 · Exchange Online' }
                '^CIS\.M365\.7\.'          { 'CIS M365 · SharePoint & OneDrive' }
                '^CIS\.M365\.8\.'          { 'CIS M365 · Microsoft Teams' }
                default                    { 'CIS M365 · Microsoft 365 Admin' }
            }
        }

        $sourceTag = if ($rawId -like 'CIS.M365.*') { 'CIS M365' } elseif ($rawId -like 'EIDSCA.*') { 'EIDSCA' } else { 'Maester' }

        $desc = [string](Get-TenantBriefPropertyValue -Object $rd -Name 'TestDescription')
        if (-not $desc) { $desc = $cleanTitle }
        $helpUrl = [string](Get-TenantBriefPropertyValue -Object $item -Name 'HelpUrl')
        if ($helpUrl) { $desc = "$desc`n`n[Reference]($helpUrl)" }

        $tRes = [string](Get-TenantBriefPropertyValue -Object $rd -Name 'TestResult')
        $skipR = [string](Get-TenantBriefPropertyValue -Object $rd -Name 'SkippedReason')
        if ($isPesterSkip -and $skipR) {
            if ($skipR -match 'missing permission scope\s+([^\s"''\r\n]+)') {
                $scopeClean = $Matches[1].Trim().TrimEnd('.', ',')
                $skipR = "Graph API izni eksik / Missing permission scope: $scopeClean"
            } elseif ($skipR -match 'S2SUnauthorized|Invalid permission') {
                $skipR = 'Graph / Exchange API izni veya servis yetkisi bu kiracıda etkin değil (S2SUnauthorized).'
            } else {
                $skipR = (($skipR -replace '```[\s\S]*$', '') -replace '\s+', ' ').Trim()
                if ($skipR.Length -gt 240) { $skipR = $skipR.Substring(0, 240) + '...' }
            }
        }

        $out += [PSCustomObject]@{
            TestId                 = $rawId
            TestTitle              = $cleanTitle
            TestStatus             = $mappedStatus
            TestRisk               = $mappedRisk
            TestPillar             = 'Maester (EIDSCA / CIS)'
            TestSource             = $sourceTag
            TestCategory           = $catLabel
            TestSfiPillar          = 'Protect identities and secrets'
            TestImplementationCost = 'Low'
            TestMinimumLicense     = ''
            SkippedReason          = $skipR
            TestResult             = $tRes
            TestImpact             = $mappedRisk
            TestDescription        = $desc
        }
    }
    return @($out)
}

function Import-TenantBriefEntraFalconFindings {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$JsonPath
    )

    if (-not (Test-Path $JsonPath)) { return @() }
    $rawList = @(Get-Content -Path $JsonPath -Raw -Encoding UTF8 | ConvertFrom-Json)
    $out = @()

    foreach ($f in $rawList) {
        if ($null -eq $f) { continue }
        $fid = [string](Get-TenantBriefPropertyValue -Object $f -Name 'FindingId')
        if (-not $fid) { continue }
        $tid = if ($fid -like 'EF-*') { $fid } else { "EF-$fid" }

        $title = [string](Get-TenantBriefPropertyValue -Object $f -Name 'Title')
        if (-not $title) { continue }

        $cat = [string](Get-TenantBriefPropertyValue -Object $f -Name 'Category')
        if (-not $cat) { $cat = 'Entra ID' }

        $sevNum = 0
        [void][int]::TryParse([string](Get-TenantBriefPropertyValue -Object $f -Name 'Severity'), [ref]$sevNum)
        $risk = if ($sevNum -ge 3) { 'High' } elseif ($sevNum -eq 2) { 'Medium' } else { 'Low' }

        $stRaw = [string](Get-TenantBriefPropertyValue -Object $f -Name 'Status')
        $status = switch -Regex ($stRaw) {
            '^Vulnerable$'    { 'Failed' }
            '^NotVulnerable$' { 'Passed' }
            '^Skipped$'       { 'Skipped' }
            default           { 'Investigate' }
        }

        $desc = [string](Get-TenantBriefPropertyValue -Object $f -Name 'Description')
        $rem = [string](Get-TenantBriefPropertyValue -Object $f -Name 'Remediation')
        $threat = [string](Get-TenantBriefPropertyValue -Object $f -Name 'Threat')
        $affRaw = Get-TenantBriefPropertyValue -Object $f -Name 'AffectedObjects'
        $affCount = if ($null -eq $affRaw) { 0 } else { @($affRaw).Count }

        $resTxt = if ($affCount -gt 0) { "Affected objects: $affCount`n`n$threat".Trim() } else { $threat }
        $fullDesc = if ($rem) { "$desc`n`n**Remediation action**`n$rem".Trim() } else { $desc }

        $out += [PSCustomObject]@{
            TestId                 = $tid
            TestTitle              = $title
            TestStatus             = $status
            TestRisk               = $risk
            TestPillar             = 'EntraFalcon'
            TestCategory           = $cat
            TestSfiPillar          = 'Protect identities and secrets'
            TestImplementationCost = 'Medium'
            TestMinimumLicense     = 'Entra ID P1/P2'
            SkippedReason          = if ($status -eq 'Skipped') { 'Skipped by EntraFalcon' } else { '' }
            TestResult             = $resTxt
            TestImpact             = $risk
            TestDescription        = $fullDesc
        }
    }
    return @($out)
}

function Invoke-TenantBriefBaselineCollections {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$OutputPath,

        [Parameter(Mandatory = $false)]
        [string]$Account,

        [Parameter(Mandatory = $true)]
        [scriptblock]$Log,

        [Parameter(Mandatory = $true)]
        [hashtable]$State,

        [Parameter(Mandatory = $false)]
        [AllowEmptyCollection()]
        [System.Collections.Generic.List[object]]$Diagnostics,

        [Parameter(Mandatory = $false)]
        [object]$Manifest,

        [Parameter(Mandatory = $false)]
        [string]$ManifestPath,

        [Parameter(Mandatory = $false)]
        [switch]$SkipMaester
    )

    $markStage = {
        param([int]$StageNumber, [string]$StageName, [string]$StageStatus, [string]$StageMessage)
        if (-not $Manifest -or -not $ManifestPath) { return }
        Set-TenantBriefStage -Manifest $Manifest -Stage $StageNumber -Name $StageName -Status $StageStatus -Message $StageMessage
        Save-TenantBriefRunManifest -Manifest $Manifest -Path $ManifestPath -Diagnostics $Diagnostics
    }
    $note = {
        param([int]$StageNumber, [string]$Component, [string]$Note)
        if ($null -eq $Diagnostics) { return }
        Add-TenantBriefDiagnostic -Diagnostics $Diagnostics -Stage $StageNumber -Component $Component -Message $Note
    }

    $collected = @()
    $scubaOk = $false
    $orcaOk = $false
    $orcaSkipped = $false
    & $markStage 2 'CISA ScubaGear' 'started' ''

    if (-not (Get-Module -ListAvailable -Name 'ScubaGear')) {
        & $Log "[Stage 2/5] ScubaGear not found — installing from PSGallery..."
        try { Install-Module -Name ScubaGear -Repository PSGallery -Scope CurrentUser -Force -AllowClobber -ErrorAction Stop } catch {
            & $note 2 'ScubaGear' "Module install failed: $($_.Exception.Message)"
        }
    }
    if (Get-Module -ListAvailable -Name 'ScubaGear') {
        $scubaOut = Join-Path $OutputPath 'raw-scuba'
        if (-not (Test-Path $scubaOut)) { New-Item -ItemType Directory -Path $scubaOut -Force | Out-Null }
        try {
            if (-not (Get-Module -ListAvailable -Name 'powershell-yaml')) {
                Install-Module -Name 'powershell-yaml' -Repository PSGallery -Scope CurrentUser -Force -ErrorAction SilentlyContinue
            }
            Set-StrictMode -Off
            try {
                Import-Module ScubaGear -ErrorAction Stop -WarningAction SilentlyContinue 6>$null 3>$null 2>$null | Out-Null
            } finally {
                Set-StrictMode -Version Latest
            }
            $opaDir = Join-Path $env:USERPROFILE '.scubagear\Tools'
            $opaExePath = Join-Path $opaDir 'opa_windows_amd64.exe'
            if (-not (Test-Path $opaExePath)) {
                & $Log "[Stage 2/5] Installing OPA executable for ScubaGear..."
                Install-OPAforSCuBA | Out-Null
            }
            & $Log "[Stage 2/5] Running CISA ScubaGear checks (aad baseline — reusing active Graph session)..."
            $null = Invoke-SCuBA -ProductNames @('aad') -LogIn:$false -DisconnectOnExit:$false -OPAPath $opaDir -OutPath $scubaOut -Quiet 6>$null 3>$null
            $scubaItems = @(Import-TenantBriefScubaResults -Path $scubaOut)
            if ($scubaItems.Count -gt 0) {
                $collected += $scubaItems
                & $Log "[Stage 2/5] ScubaGear completed: $($scubaItems.Count) controls merged."
                $scubaOk = $true
            } else {
                "ScubaGear finished without ScubaResults.json / *Report.json output." | Set-Content -Path (Join-Path $scubaOut 'scuba-error.txt') -Encoding UTF8
                & $Log "[Stage 2/5] ScubaGear finished with no JSON output (check raw-scuba\DebugLogs)."
                & $note 2 'ScubaGear' 'Finished without ScubaResults.json / *Report.json output.'
            }
        } catch {
            $errMsg = $_.Exception.Message
            $errMsg | Set-Content -Path (Join-Path $scubaOut 'scuba-error.txt') -Encoding UTF8
            & $Log "[Stage 2/5] ScubaGear skipped: $errMsg"
            & $note 2 'ScubaGear' "Skipped: $errMsg"
        }
    }

    if ($scubaOk) {
        & $markStage 2 'CISA ScubaGear' 'completed' 'ScubaGear controls merged.'
    } else {
        & $markStage 2 'CISA ScubaGear' 'failed' 'ScubaGear produced no controls; the report continues without the SCuBA baseline.'
    }

    $State.Stage = 3
    & $markStage 3 'Microsoft ORCA & Maester' 'started' ''
    if (-not (Get-Module -ListAvailable -Name 'ORCA')) {
        & $Log "[Stage 3/5] ORCA not found — installing from PSGallery..."
        try { Install-Module -Name ORCA -Repository PSGallery -Scope CurrentUser -Force -AllowClobber -ErrorAction Stop } catch {
            & $note 3 'ORCA' "Module install failed: $($_.Exception.Message)"
        }
    }
    if (Get-Module -ListAvailable -Name 'ORCA') {
        $orcaOut = Join-Path $OutputPath 'raw-orca'
        if (-not (Test-Path $orcaOut)) { New-Item -ItemType Directory -Path $orcaOut -Force | Out-Null }
        try {
            Get-Module tmpEXO_* -ErrorAction SilentlyContinue | Import-Module -Global -DisableNameChecking -WarningAction SilentlyContinue -ErrorAction SilentlyContinue | Out-Null
            $exoDoms = @()
            if (Get-Command Get-AcceptedDomain -ErrorAction SilentlyContinue) {
                try { $exoDoms = @(Get-AcceptedDomain -ErrorAction Stop) } catch { $exoDoms = @() }
            }
            if ($exoDoms.Count -eq 0 -and (Get-Command Connect-ExchangeOnline -ErrorAction SilentlyContinue)) {
                & $Log "[Stage 3/5] Refreshing Exchange Online session for ORCA..."
                try {
                    $exoUpn = $Account
                    if ($exoUpn) {
                        $null = Connect-ExchangeOnline -UserPrincipalName $exoUpn -ShowBanner:$false -ErrorAction Stop
                    } else {
                        $null = Connect-ExchangeOnline -ShowBanner:$false -ErrorAction Stop
                    }
                    Get-Module tmpEXO_* -ErrorAction SilentlyContinue | Import-Module -Global -DisableNameChecking -WarningAction SilentlyContinue -ErrorAction SilentlyContinue | Out-Null
                    $exoDoms = @(Get-AcceptedDomain -ErrorAction SilentlyContinue)
                } catch {}
            }

            if ($exoDoms.Count -eq 0) {
                "Exchange Online session unavailable or Get-AcceptedDomain returned 0 domains." | Set-Content -Path (Join-Path $orcaOut 'orca-error.txt') -Encoding UTF8
                & $Log "[Stage 3/5] ORCA skipped: Exchange Online session not connected or returned no domains."
                & $note 3 'ORCA' 'Skipped: Exchange Online session not connected or Get-AcceptedDomain returned 0 domains.'
                $orcaSkipped = $true
            } else {
                & $Log "[Stage 3/5] Running Microsoft ORCA checks (Defender for Office 365)..."
                Import-Module ORCA -Global -DisableNameChecking -WarningAction SilentlyContinue -ErrorAction Stop 6>$null 3>$null | Out-Null
                $null = Invoke-ORCA -Connect:$false -SCC:$false -PerformVersionCheck:$false -InstallModules:$false -ShowSurvey:$false -Output @('JSON') -OutputOptions @{ JSON = @{ OutputDirectory = $orcaOut } } 6>$null 3>$null
                $orcaItems = @(Import-TenantBriefOrcaResults -Path $orcaOut)
                if ($orcaItems.Count -gt 0) {
                    $collected += $orcaItems
                    & $Log "[Stage 3/5] ORCA completed: $($orcaItems.Count) controls merged."
                    $orcaOk = $true
                } else {
                    "ORCA finished without emitting JSON into '$orcaOut'." | Set-Content -Path (Join-Path $orcaOut 'orca-error.txt') -Encoding UTF8
                    & $Log "[Stage 3/5] ORCA finished without JSON output."
                    & $note 3 'ORCA' 'Finished without JSON output.'
                }
            }
        } catch {
            $errMsg = $_.Exception.Message
            $errMsg | Set-Content -Path (Join-Path $orcaOut 'orca-error.txt') -Encoding UTF8
            & $Log "[Stage 3/5] ORCA skipped: $errMsg"
            & $note 3 'ORCA' "Skipped: $errMsg"
        }
    }

    $maesterOk = $false
    $maesterCount = 0
    if (-not $SkipMaester -and (Get-Module -ListAvailable -Name 'Maester')) {
        $maesterOut = Join-Path $OutputPath 'raw-maester'
        if (-not (Test-Path $maesterOut)) { New-Item -ItemType Directory -Path $maesterOut -Force | Out-Null }
        $maesterJsonPath = Join-Path $maesterOut 'MaesterResults.json'
        try {
            Set-StrictMode -Off
            try {
                Import-Module Maester -Global -DisableNameChecking -WarningAction SilentlyContinue -ErrorAction Stop 6>$null 3>$null 2>$null | Out-Null
                $maesterMod = Get-Module -Name 'Maester' | Select-Object -First 1
                $maesterTestsPath = if ($maesterMod) { Join-Path $maesterMod.ModuleBase 'maester-tests' } else { $null }
                if ($maesterTestsPath -and (Test-Path $maesterTestsPath)) {
                    & $Log "[Stage 3b/5] Running Maester checks (EIDSCA, CIS, Maester & XSPM — reusing active Graph session)..."
                    $mtRes = Invoke-Maester -Path $maesterTestsPath -ExcludeTag @('ORCA', 'CISA', 'AD', 'LongRunning', 'Preview') -SkipGraphConnect -NonInteractive -NoLogo -DisableTelemetry -SkipVersionCheck -Verbosity None -OutputJsonFile $maesterJsonPath -PassThru 6>$null 3>$null 2>$null
                    $mtItems = @(Import-TenantBriefMaesterResults -MaesterResult $mtRes -JsonPath $maesterJsonPath)
                    if ($mtItems.Count -gt 0) {
                        $collected += $mtItems
                        $maesterCount = $mtItems.Count
                        $maesterOk = $true
                        & $Log "[Stage 3b/5] Maester completed: $maesterCount controls merged."
                    }
                }
            } finally {
                Set-StrictMode -Version Latest
            }
        } catch {
            $errMsg = $_.Exception.Message
            $errMsg | Set-Content -Path (Join-Path $maesterOut 'maester-error.txt') -Encoding UTF8
            & $Log "[Stage 3b/5] Maester skipped: $errMsg"
            & $note 3 'Maester' "Skipped: $errMsg"
        }
    }

    if ($orcaOk -and $maesterOk) {
        & $markStage 3 'Microsoft ORCA & Maester' 'completed' "ORCA & Maester ($maesterCount) controls merged."
    } elseif ($orcaOk) {
        & $markStage 3 'Microsoft ORCA & Maester' 'completed' 'ORCA controls merged.'
    } elseif ($maesterOk) {
        & $markStage 3 'Microsoft ORCA & Maester' 'completed' "Maester ($maesterCount) controls merged; ORCA skipped or unavailable."
    } elseif ($orcaSkipped) {
        & $markStage 3 'Microsoft ORCA & Maester' 'skipped' 'Exchange Online session unavailable; ORCA & Maester were not completed.'
    } else {
        & $markStage 3 'Microsoft ORCA & Maester' 'failed' 'ORCA/Maester produced no controls; the report continues without Defender for Office 365 & Maester checks.'
    }

    return $collected
}

function Get-TenantBriefPropertyValue {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [object]$Object,

        [Parameter(Mandatory = $true)]
        [string]$Name
    )

    # StrictMode-safe accessor: engines export slightly different shapes and a missing
    # property must read as $null instead of throwing.
    if ($null -eq $Object) { return $null }
    if ($Object -is [System.Collections.IDictionary]) {
        if ($Object.Contains($Name)) { return $Object[$Name] }
        return $null
    }
    $prop = $Object.PSObject.Properties[$Name]
    if ($prop) { return $prop.Value }
    return $null
}

function New-TenantBriefCorrelatedTests {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [object[]]$Tests
    )

    $statusRank = @{ 'Passed' = 0; 'Planned' = 1; 'Skipped' = 1; 'Investigate' = 2; 'Failed' = 3 }
    $riskRank = @{ 'Low' = 0; 'Medium' = 1; 'High' = 2 }
    $enrichable = @('TestCategory', 'TestSfiPillar', 'TestImplementationCost', 'TestMinimumLicense', 'SkippedReason', 'TestResult', 'TestImpact', 'TestDescription')

    # Ordered dictionary keeps report output deterministic between runs.
    $correlated = [ordered]@{}
    foreach ($t in @($Tests)) {
        if ($null -eq $t) { continue }

        $title = [string](Get-TenantBriefPropertyValue -Object $t -Name 'TestTitle')
        # Trim after collapsing separators: a title ending in punctuation would otherwise keep a
        # trailing space and never match its counterpart from another engine.
        $normTitle = ($title.ToLowerInvariant().Trim() -replace '[^a-z0-9]+', ' ').Trim()
        if (-not $normTitle) { $normTitle = [string](Get-TenantBriefPropertyValue -Object $t -Name 'TestId') }

        $rawId = [string](Get-TenantBriefPropertyValue -Object $t -Name 'TestId')
        $pillarList = @(ConvertTo-TenantBriefPillarList -PillarValue (Get-TenantBriefPropertyValue -Object $t -Name 'TestPillar'))
        $sourceList = @(Resolve-TenantBriefSourceTag -Test $t)
        $newStatus = [string](Get-TenantBriefPropertyValue -Object $t -Name 'TestStatus')
        $newRisk = [string](Get-TenantBriefPropertyValue -Object $t -Name 'TestRisk')

        if ($correlated.Contains($normTitle)) {
            $existing = $correlated[$normTitle]
            foreach ($p in $pillarList) {
                if ($p -and ($existing.TestPillar -notcontains $p)) {
                    $existing.TestPillar = @($existing.TestPillar) + $p
                }
            }
            foreach ($s in $sourceList) {
                if ($s -and ($existing.TestSources -notcontains $s)) {
                    $existing.TestSources = @($existing.TestSources) + $s
                }
            }
            if ($rawId -and ($existing.CorrelatedIds -notcontains $rawId)) {
                $existing.CorrelatedIds = @($existing.CorrelatedIds) + $rawId
            }

            $oldStatus = [string]$existing.TestStatus
            if (($statusRank[$newStatus] ?? 0) -gt ($statusRank[$oldStatus] ?? 0)) {
                $existing.TestStatus = $newStatus
            }
            # Avoid letting an unexecuted Skipped duplicate override or inflate an evaluated control's risk.
            if ($newStatus -notin @('Skipped', 'Planned') -or ($oldStatus -in @('Skipped', 'Planned'))) {
                if (($riskRank[$newRisk] ?? 0) -gt ($riskRank[[string]$existing.TestRisk] ?? 0)) {
                    $existing.TestRisk = $newRisk
                }
            }
            # Keep the richest metadata available from any engine reporting the same control.
            foreach ($field in $enrichable) {
                $incoming = Get-TenantBriefPropertyValue -Object $t -Name $field
                if ($incoming -and -not (Get-TenantBriefPropertyValue -Object $existing -Name $field)) {
                    $existing.$field = $incoming
                }
            }
        } else {
            $correlated[$normTitle] = [PSCustomObject]@{
                TestId                 = $rawId
                CorrelatedIds          = if ($rawId) { @($rawId) } else { @() }
                TestTitle              = Get-TenantBriefPropertyValue -Object $t -Name 'TestTitle'
                TestStatus             = $newStatus
                TestRisk               = $newRisk
                TestPillar             = @($pillarList)
                TestSources            = @($sourceList)
                TestCategory           = Get-TenantBriefPropertyValue -Object $t -Name 'TestCategory'
                TestSfiPillar          = Get-TenantBriefPropertyValue -Object $t -Name 'TestSfiPillar'
                TestImplementationCost = Get-TenantBriefPropertyValue -Object $t -Name 'TestImplementationCost'
                TestMinimumLicense     = Get-TenantBriefPropertyValue -Object $t -Name 'TestMinimumLicense'
                SkippedReason          = Get-TenantBriefPropertyValue -Object $t -Name 'SkippedReason'
                TestResult             = Get-TenantBriefPropertyValue -Object $t -Name 'TestResult'
                TestImpact             = Get-TenantBriefPropertyValue -Object $t -Name 'TestImpact'
                TestDescription        = Get-TenantBriefPropertyValue -Object $t -Name 'TestDescription'
            }
        }
    }

    return @($correlated.Values)
}

function Get-TenantBriefFrameworkScorecard {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][object[]]$Tests,
        [Parameter(Mandatory = $true)][object]$FrameworkConfig,
        [Parameter(Mandatory = $true)][string[]]$FrameworkIds,
        [Parameter(Mandatory = $false)][ValidateSet('tr', 'en')][string]$Language = 'tr'
    )

    # Fallback coverage table, used only when data/framework-mappings.json does not declare
    # an explicit scoredPillars list for a framework. The data file is authoritative.
    $fallbackPillars = @{
        'ZeroTrust'  = @('Identity', 'Devices', 'Network', 'Data', 'Infrastructure', 'SecOps', 'AI', 'CISA SCuBA', 'Defender for Office 365 (ORCA)', 'Maester (EIDSCA / CIS)', 'EntraFalcon')
        'ISO27001'   = @('Identity', 'Devices', 'Network', 'Data', 'Infrastructure', 'SecOps', 'CISA SCuBA', 'Defender for Office 365 (ORCA)', 'Maester (EIDSCA / CIS)', 'EntraFalcon')
        'NIST_CSF_2' = @('Identity', 'Devices', 'Network', 'SecOps', 'AI', 'CISA SCuBA', 'Defender for Office 365 (ORCA)', 'Maester (EIDSCA / CIS)', 'EntraFalcon')
        'CIS_M365'   = @('Identity', 'Devices', 'Data', 'CISA SCuBA', 'Defender for Office 365 (ORCA)', 'Maester (EIDSCA / CIS)', 'EntraFalcon')
        'KVKK_TR'    = @('Identity', 'Data', 'SecOps', 'Devices', 'CISA SCuBA', 'Defender for Office 365 (ORCA)', 'Maester (EIDSCA / CIS)', 'EntraFalcon')
    }

    foreach ($fwId in $FrameworkIds) {
        $fwMeta = $FrameworkConfig.$fwId
        $fwName = if ($Language -eq 'tr') { $fwMeta.nameTr } else { $fwMeta.nameEn }

        $scoredProp = $fwMeta.PSObject.Properties['scoredPillars']
        $allowed = if ($scoredProp -and $scoredProp.Value) { @($scoredProp.Value) } else { $fallbackPillars[$fwId] }

        # A control can legitimately belong to several pillars (e.g. ZeroTrust + CISA SCuBA);
        # count it when ANY of its pillars belongs to the framework, but only once per framework.
        $fwTests = if ($allowed) {
            @($Tests | Where-Object {
                $testPillars = @($_.TestPillar)
                @($allowed | Where-Object { $testPillars -contains $_ }).Count -gt 0
            })
        } else { @($Tests) }

        $fwPass = @($fwTests | Where-Object { $_.TestStatus -eq 'Passed' }).Count
        $fwFail = @($fwTests | Where-Object { $_.TestStatus -eq 'Failed' }).Count
        $fwInv  = @($fwTests | Where-Object { $_.TestStatus -eq 'Investigate' }).Count
        # 'Error' means the control should have been evaluated but the engine failed: it is a
        # non-pass that must stay visible in the denominator (unmeasured is not compliant).
        $fwErr  = @($fwTests | Where-Object { $_.TestStatus -eq 'Error' }).Count
        $fwEval = $fwPass + $fwFail + $fwInv + $fwErr
        $fwScore = if ($fwEval -gt 0) { [Math]::Round(($fwPass / $fwEval) * 100, 1) } else { 0 }

        [PSCustomObject]@{
            Id        = $fwId
            Name      = $fwName
            Score     = $fwScore
            Passed    = $fwPass
            Failed    = $fwFail
            Errors    = $fwErr
            Evaluated = $fwEval
        }
    }
}

function New-TenantBriefFindings {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][object[]]$Tests,
        [Parameter(Mandatory = $false)][object]$PillarMap,
        [Parameter(Mandatory = $false)][ValidateSet('tr', 'en')][string]$Language = 'tr',
        [Parameter(Mandatory = $false)][hashtable]$TranslationCache = @{}
    )

    foreach ($t in @($Tests)) {
        $pillarList = @(ConvertTo-TenantBriefPillarList -PillarValue (Get-TenantBriefPropertyValue -Object $t -Name 'TestPillar'))
        $pillarStr = $pillarList -join ', '
        $primaryPillar = if ($pillarList.Count -gt 0) { [string]$pillarList[0] } else { '' }

        $domainList = @(Resolve-TenantBriefDomainPillars -Test $t)
        $domainStr = $domainList -join ', '
        $sourceList = @(Resolve-TenantBriefSourceTag -Test $t)
        $sourceStr = $sourceList -join ', '
        $corrRaw = @(Get-TenantBriefPropertyValue -Object $t -Name 'CorrelatedIds')
        $tid = [string](Get-TenantBriefPropertyValue -Object $t -Name 'TestId')
        $corrList = if ($corrRaw.Count -gt 0) { @($corrRaw | Where-Object { $_ }) } elseif ($tid) { @($tid) } else { @() }

        $fwRef = 'General Control'
        if ($PillarMap) {
            foreach ($pCand in $pillarList) {
                if ($PillarMap.PSObject.Properties[$pCand]) {
                    $fwRef = [string]$PillarMap.$pCand
                    break
                }
            }
        }

        $fTitle = [string](Get-TenantBriefPropertyValue -Object $t -Name 'TestTitle')
        $fDesc  = [string](Get-TenantBriefPropertyValue -Object $t -Name 'TestDescription')
        $fImp   = [string](Get-TenantBriefPropertyValue -Object $t -Name 'TestImpact')
        if ($Language -eq 'tr' -and $TranslationCache.ContainsKey($tid)) {
            if ($TranslationCache[$tid].Title) { $fTitle = [string]$TranslationCache[$tid].Title }
            if ($TranslationCache[$tid].Desc)  { $fDesc  = [string]$TranslationCache[$tid].Desc }
        }
        if ($Language -eq 'tr' -and $fImp) {
            $fImp = $fImp -replace '^High$', 'Yüksek' -replace '^Medium$', 'Orta' -replace '^Low$', 'Düşük'
        }

        $statusRaw = [string](Get-TenantBriefPropertyValue -Object $t -Name 'TestStatus')
        $catRaw = [string](Get-TenantBriefPropertyValue -Object $t -Name 'TestCategory')
        $domPrimary = if ($domainList.Count -gt 0) { [string]$domainList[0] } else { $primaryPillar }

        # Determine admin portal & least-privilege role from Control ID + Category + Domain/Pillar
        $portalName = ''
        $requiredRole = ''
        if ($primaryPillar -eq 'Defender for Office 365 (ORCA)' -or $tid -like 'ORCA-*' -or $catRaw -match 'Exchange|Anti-Phish|Safe Links|Safe Attachments|DKIM|DMARC|SPF|OWA') {
            $portalName = 'Microsoft Defender & Exchange Yönetim Merkezi (security.microsoft.com)'
            $requiredRole = 'Security Administrator / Exchange Administrator'
        } elseif ($tid -match '^CIS\.M365\.8\.' -or $catRaw -match 'Teams') {
            $portalName = 'Microsoft Teams yönetim merkezi (admin.teams.microsoft.com)'
            $requiredRole = 'Teams Administrator'
        } elseif ($domPrimary -eq 'Devices' -or ($primaryPillar -ne 'Identity' -and $catRaw -match 'Intune|BitLocker|Device|Compliance')) {
            $portalName = 'Microsoft Intune yönetim merkezi (intune.microsoft.com)'
            $requiredRole = 'Intune Administrator'
        } elseif ($catRaw -match 'SharePoint|OneDrive') {
            $portalName = 'Microsoft SharePoint & Purview Yönetim Merkezi (purview.microsoft.com)'
            $requiredRole = 'SharePoint Administrator / Compliance Administrator'
        } elseif ($domPrimary -eq 'AI' -or $catRaw -match 'Copilot|Agent') {
            $portalName = 'Microsoft Purview / Entra Agent ID (entra.microsoft.com)'
            $requiredRole = 'Compliance Administrator / Information Protection Admin'
        } elseif ($domPrimary -eq 'Data' -or $catRaw -match 'Purview|Sensitivity|DLP|Information Protection|Encryption|Lockbox|Storage') {
            $portalName = 'Microsoft Purview portalı (purview.microsoft.com)'
            $requiredRole = 'Compliance Administrator / Information Protection Admin'
        } elseif ($primaryPillar -eq 'Infrastructure' -or $catRaw -match 'Defender for Cloud|AzureConfig|Azure Network') {
            $portalName = 'Azure Portal (portal.azure.com)'
            $requiredRole = 'Security Admin / Subscription Contributor'
        } elseif ($domPrimary -eq 'Network' -or $catRaw -match 'Global Secure Access|Private Access|Application Proxy') {
            $portalName = 'Global Secure Access / Azure Portal (portal.azure.com)'
            $requiredRole = 'Global Secure Access Administrator / Network Contributor'
        } elseif ($domPrimary -eq 'SecOps' -or $catRaw -match 'Defender|Exposure|Audit|Sentinel|Incident|Threat') {
            $portalName = 'Microsoft Defender XDR / Sentinel (security.microsoft.com)'
            $requiredRole = 'Security Administrator / Sentinel Contributor'
        } elseif ($primaryPillar -eq 'CISA SCuBA') {
            $portalName = 'M365 / Entra / Exchange / Defender Yönetim Merkezleri (CISA SCuBA)'
            $requiredRole = 'Security Administrator'
        } elseif ($domPrimary -eq 'Identity' -or $primaryPillar -in @('Identity', 'Maester (EIDSCA / CIS)', 'EntraFalcon')) {
            $portalName = 'Microsoft Entra yönetim merkezi (entra.microsoft.com)'
            $requiredRole = 'Conditional Access Administrator / Security Administrator'
        } else {
            $portalName = 'Microsoft 365 Yönetim Merkezi'
            $requiredRole = 'Security Administrator'
        }

        # Extract concrete remediation bullet/step from Description when available; keep guidance compact.
        $remTr = ''
        if ($statusRaw -in @('Failed', 'Investigate')) {
            $extractedStep = ''
            if ($fDesc -match '(?is)(?:\*\*Düzeltme işlemi\*\*|####\s*Remediation action|\*\*Remediation action\*\*)(.+)$') {
                $remBlock = ($Matches[1] -replace '```[\s\S]*?```', ' ' -replace '\[([^\]]+)\]\([^\)]+\)', '$1' -replace 'https?://\S+', ' ' -replace '[#*_`>|\[\]]', ' ' -replace '\s+', ' ').Trim()
                if ($remBlock -match 'Related links') {
                    $remBlock = ($remBlock -split 'Related links')[0].Trim()
                }
                if ($remBlock.Length -gt 160) { $remBlock = $remBlock.Substring(0, 157).Trim() + '...' }
                $extractedStep = $remBlock
            }
            if ($extractedStep -and $extractedStep.Length -gt 12) {
                $remTr = "$portalName üzerinden uygulayın: $extractedStep Pilot gruba Denetim (Report-only) kipinde uygulayıp doğruladıktan sonra Zorunlu (Enforce) durumuna geçin. [En Az Ayrıcalıklı Rol: $requiredRole]"
            } else {
                $remTr = "1. $portalName üzerinden '$fTitle' kontrolünü açın. 2. Değişikliği önce Denetim (Report-only) kipinde pilot gruba uygulayıp oturum açma/olay günlüklerini doğrulayın. 3. Etki analizi sonrası kademeli olarak Zorunlu (Enforce) durumuna geçin. [En Az Ayrıcalıklı Rol: $requiredRole]"
            }
        }

        $minLicRaw = Get-TenantBriefPropertyValue -Object $t -Name 'TestMinimumLicense'
        $minLicStr = if ($minLicRaw -is [System.Array]) { ($minLicRaw -join ', ') } else { [string]$minLicRaw }
        $implCostRaw = Get-TenantBriefPropertyValue -Object $t -Name 'TestImplementationCost'
        $sfiRaw      = Get-TenantBriefPropertyValue -Object $t -Name 'TestSfiPillar'
        $riskRaw     = Get-TenantBriefPropertyValue -Object $t -Name 'TestRisk'
        $resultRaw   = Get-TenantBriefPropertyValue -Object $t -Name 'TestResult'
        $skippedRaw  = Get-TenantBriefPropertyValue -Object $t -Name 'SkippedReason'

        [PSCustomObject]@{
            Id                 = $tid
            CorrelatedIds      = @($corrList)
            Pillar             = if ($pillarStr) { $pillarStr } else { 'General' }
            PrimaryPillar      = if ($primaryPillar) { $primaryPillar } else { 'General' }
            DomainPillar       = $domainStr
            DomainPillars      = @($domainList)
            Source             = $sourceStr
            Sources            = @($sourceList)
            Category           = if ($catRaw) { $catRaw } else { 'General' }
            SfiPillar          = if ($sfiRaw) { [string]$sfiRaw } else { '' }
            ImplementationCost = if ($implCostRaw) { [string]$implCostRaw } else { 'Unknown' }
            MinimumLicense     = $minLicStr
            RequiredRole       = $requiredRole
            AdminPortal        = $portalName
            Status             = $statusRaw
            Risk               = if ($riskRaw) { [string]$riskRaw } else { 'Low' }
            Title              = $fTitle
            FrameworkRef       = $fwRef
            Result             = [string]$resultRaw
            Impact             = $fImp
            Description        = $fDesc
            SkippedReason      = [string]$skippedRaw
            RemediationTr      = $remTr
        }
    }
}

#endregion

function Invoke-TenantBriefAssessment {
    <#
    .SYNOPSIS
    Runs the read-only assessment pipeline and writes HTML, JSON and executive-summary reports.

    .DESCRIPTION
    Orchestrates the five stages: ZeroTrustAssessment, CISA ScubaGear, Microsoft ORCA,
    correlation/license/framework scoring, and report generation.
    
    Without -InputReportJson the function talks to the live tenant and requires an active
    session from Connect-TenantBrief. With -InputReportJson it analyses an existing
    ZeroTrustAssessmentReport.json completely offline and performs no Graph call at all.
    
    All output is written under -OutputPath; the console prints the artifact paths. No
    telemetry or tenant data leaves the machine unless -TranslatorKey is supplied.

    With -Resume, a run that stopped after Stage 1 is finished from its existing
    ZeroTrustAssessmentReport.json instead of rescanning the tenant. Every run also writes
    run-manifest.json with per-stage status and any degraded sub-analysis.

    .EXAMPLE
    Invoke-TenantBriefAssessment -InputReportJson .\ZeroTrustAssessmentReport.json `
    -OutputPath .\demo -Language en -Anonymize -NoBrowser
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter()]
        [string]$InputReportJson,

        [Parameter()]
        [string]$OutputPath = (Join-Path (Get-Location).Path 'TenantBriefReport'),

        [Parameter()]
        [ValidateSet('tr', 'en')]
        [string]$Language = 'tr',

        [Parameter()]
        [ValidateSet('All', 'ZeroTrust', 'ISO27001', 'NIST_CSF_2', 'CIS_M365', 'KVKK_TR')]
        [string]$Framework = 'All',

        [Parameter()]
        [switch]$Anonymize,

        [Parameter()]
        [switch]$NoBrowser,

        [Parameter()]
        [string]$TranslatorKey = $env:AZURE_TRANSLATOR_KEY,

        [Parameter()]
        [string]$InputFastTrackJsonPath,

        [Parameter()]
        [string]$InputMaesterJsonPath,

        [Parameter()]
        [string]$InputEntraFalconJsonPath,

        [Parameter()]
        [switch]$SkipMaester,

        [Parameter()]
        [switch]$Resume
    )

    $OutputPath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($OutputPath)
    if ($OutputPath -like "$($env:SystemRoot)*") {
        $fallbackBase = Join-Path $HOME 'TenantBriefReport'
        Write-Warning "[TenantBrief] '$OutputPath' is inside a system-protected folder. Redirecting report output to '$fallbackBase'."
        $OutputPath = $fallbackBase
    }

    # -Resume: finish a run that died after Stage 1 by reusing its ZeroTrustAssessmentReport.json.
    $resumeNote = $null
    if ($Resume -and -not $InputReportJson) {
        if (-not (Test-Path $OutputPath)) {
            throw "-Resume: '$OutputPath' bulunamadi. Once bir tarama klasoru verin (or. `$HOME\TenantBriefReport)."
        }
        $resumeSource = Get-ChildItem -Path $OutputPath -Filter 'ZeroTrustAssessmentReport.json' -Recurse -File -ErrorAction SilentlyContinue |
            Sort-Object LastWriteTime -Descending | Select-Object -First 1
        if (-not $resumeSource) {
            throw "-Resume: '$OutputPath' altinda ZeroTrustAssessmentReport.json bulunamadi. Bir tarama calistirip tekrar deneyin."
        }
        $InputReportJson = $resumeSource.FullName
        $runRoot = Split-Path -Path (Split-Path -Path (Split-Path -Path $resumeSource.FullName -Parent) -Parent) -Parent
        if ($runRoot -and (Test-Path (Join-Path $runRoot 'raw-zt'))) { $OutputPath = $runRoot }
        $resumeNote = "Stage 1 yeniden kullanildi: $($resumeSource.FullName)"
        Write-Host "[TenantBrief] -Resume: Stage 1 atlandi, mevcut tarama kullaniliyor -> $($resumeSource.FullName)" -ForegroundColor Yellow
    }

    if (-not $InputReportJson) {
        $mgCheck = Get-MgContext -ErrorAction SilentlyContinue
        if (-not $mgCheck) {
            throw "Authentication required or was canceled. Run Connect-TenantBrief and complete sign-in before Invoke-TenantBriefAssessment."
        }
        if (-not (Get-Module -ListAvailable -Name 'ZeroTrustAssessment')) {
            throw "Required module 'ZeroTrustAssessment' is not installed. Run: Install-Module ZeroTrustAssessment -Scope CurrentUser"
        }
        Set-StrictMode -Off
        try {
            Import-Module ZeroTrustAssessment -Global -ErrorAction Stop 2>$null 3>$null | Out-Null
        } finally {
            Set-StrictMode -Version Latest
        }

        $tenantFolder = 'tenant'
        if ($mgCheck.Account -and $mgCheck.Account -match '@(.+)$') {
            $tenantFolder = ($Matches[1] -replace '[^a-zA-Z0-9\.-]', '_')
        }
        $OutputPath = Join-Path $OutputPath ("{0}_{1}" -f $tenantFolder, (Get-Date -Format 'yyyyMMdd_HHmm'))
    }

    try {
        if (-not (Test-Path $OutputPath)) {
            $null = New-Item -ItemType Directory -Path $OutputPath -Force -ErrorAction Stop
        }
        $writeProbe = Join-Path $OutputPath '.tb_write_probe'
        [System.IO.File]::WriteAllText($writeProbe, 'ok')
        Remove-Item -Path $writeProbe -Force -ErrorAction SilentlyContinue
    } catch {
        throw "OutputPath '$OutputPath' is not writable: $($_.Exception.Message). Specify a writable folder with -OutputPath `"$HOME\TenantBriefReport`"."
    }

    $rawOut = Join-Path $OutputPath 'raw-zt'

    # --- P0: run trace (manifest + diagnostics) -------------------------------------------------
    $diagnostics = [System.Collections.Generic.List[object]]::new()
    $manifestPath = Join-Path $OutputPath 'run-manifest.json'
    $moduleVersion = ''
    try { $moduleVersion = (Get-Module TenantBrief).Version.ToString() } catch {}
    $manifest = [PSCustomObject]@{
        StartedAt         = (Get-Date).ToString('o')
        UpdatedAt         = $null
        Status            = 'running'
        Language          = $Language
        Framework         = $Framework
        PowerShellVersion = $PSVersionTable.PSVersion.ToString()
        ModuleVersion     = $moduleVersion
        SourceReport      = $InputReportJson
        Resumed           = [bool]$resumeNote
        OutputPath        = $OutputPath
        Stages            = @()
        Diagnostics       = @()
    }
    $markStage = {
        param([int]$StageNumber, [string]$StageName, [string]$StageStatus, [string]$StageMessage)
        Set-TenantBriefStage -Manifest $manifest -Stage $StageNumber -Name $StageName -Status $StageStatus -Message $StageMessage
        Save-TenantBriefRunManifest -Manifest $manifest -Path $manifestPath -Diagnostics $diagnostics
    }
    if ($resumeNote) {
        Add-TenantBriefDiagnostic -Diagnostics $diagnostics -Stage 1 -Component 'Resume' -Message $resumeNote
    }
    if ($InputReportJson) {
        & $markStage 1 'ZeroTrustAssessment' 'skipped' 'Offline mode: -InputReportJson supplied, tenant was not contacted.'
    } else {
        & $markStage 1 'ZeroTrustAssessment' 'started' ''
    }
    # -------------------------------------------------------------------------------------------
    $progressJob = $null
    $logQueue = [System.Collections.ArrayList]::Synchronized((New-Object System.Collections.ArrayList))
    $progressState = [hashtable]::Synchronized(@{
        Stage      = 1
        Done       = $false
        Stop       = $false
        Error      = $null
        RawOut     = $rawOut
        ActiveTask = if ($Language -eq 'tr') { 'Kiracı oturumu ve ZeroTrustAssessment başlatılıyor...' } else { 'Initializing tenant session and ZeroTrustAssessment...' }
        Logs       = $logQueue
    })
    $addLog = {
        param([string]$Msg)
        $line = "[$(Get-Date -Format 'HH:mm:ss')] $Msg"
        [void]$progressState.Logs.Add($line)
        if ($progressState.Logs.Count -gt 40) { $progressState.Logs.RemoveAt(0) }
        $progressState.ActiveTask = $Msg
        Write-Host $line -ForegroundColor Cyan
    }

    $ztProgressDict = $null
    if (-not $InputReportJson) {
        try {
            $ztProgressDict = & (Get-Module ZeroTrustAssessment) {
                if ($script:__ZtSession -and $script:__ZtSession.ProgressState) { $script:__ZtSession.ProgressState.Value } else { $null }
            }
        } catch { $ztProgressDict = $null }
    }

    try {
    $progressJob = $null
    if (-not $NoBrowser -and -not $InputReportJson) {
        $progressJob = New-TenantBriefProgressDashboard -Language $Language -State $progressState -ZtDict $ztProgressDict
    }

    $sourceJsonPath = $InputReportJson
    if (-not $sourceJsonPath) {
        & $addLog "[Stage 1/5] Starting read-only ZeroTrustAssessment (using active session in main runspace)..."
        Set-StrictMode -Off
        try {
            Invoke-ZtAssessment -Path $rawOut -DisableTelemetry -NoBrowser 6>$null 3>$null
        } finally {
            Set-StrictMode -Version Latest
        }
        $sourceJsonPath = Join-Path $rawOut 'zt-export\ZeroTrustAssessmentReport.json'
        if (-not (Test-Path $sourceJsonPath)) {
            throw "ZeroTrustAssessment did not produce a report at '$sourceJsonPath'. Authentication may have been canceled or failed."
        }
        & $addLog "[Stage 1/5] ZeroTrustAssessment completed."
        & $markStage 1 'ZeroTrustAssessment' 'completed' "Report: $sourceJsonPath"
    }
    $progressState.Stage = 2

    if (-not (Test-Path $sourceJsonPath)) {
        throw "Assessment JSON report not found: $sourceJsonPath"
    }

    try {
        $raw = Get-Content -Path $sourceJsonPath -Raw -Encoding UTF8 | ConvertFrom-Json
    } catch {
        & $markStage 1 'ZeroTrustAssessment' 'failed' "Report could not be parsed: $($_.Exception.Message)"
        throw "Assessment JSON could not be parsed ('$sourceJsonPath'): $($_.Exception.Message)"
    }
    $fwConfig = (Get-Content -Path $script:FrameworkMapPath -Raw -Encoding UTF8 | ConvertFrom-Json).frameworks

    # Collect every engine first, then correlate once: ScubaGear and ORCA controls must be
    # de-duplicated against the ZeroTrustAssessment findings as well.
    $ztTests = @($raw.Tests)
    $collectedTests = @()
    if (-not $InputReportJson) {
        $accountName = if ($mgCheck -and $mgCheck.Account) { [string]$mgCheck.Account } else { '' }
        $collectedTests = @(Invoke-TenantBriefBaselineCollections -OutputPath $OutputPath -Account $accountName -Log $addLog -State $progressState -Diagnostics $diagnostics -Manifest $manifest -ManifestPath $manifestPath -SkipMaester:$SkipMaester)
    } else {
        $resumeScubaDir = Join-Path $OutputPath 'raw-scuba'
        $scubaLoaded = @()
        if (Test-Path $resumeScubaDir) {
            $scubaLoaded = @(Import-TenantBriefScubaResults -Path $resumeScubaDir | Where-Object { $null -ne $_ })
        }
        if ($scubaLoaded.Count -gt 0) {
            $collectedTests += $scubaLoaded
            & $markStage 2 'CISA ScubaGear' 'completed' "Reused cached ScubaGear output ($($scubaLoaded.Count) controls)."
        } else {
            & $markStage 2 'CISA ScubaGear' 'skipped' 'Offline mode: -InputReportJson supplied, ScubaGear was not executed.'
        }

        $resumeOrcaDir = Join-Path $OutputPath 'raw-orca'
        $orcaLoaded = @()
        if (Test-Path $resumeOrcaDir) {
            $orcaLoaded = @(Import-TenantBriefOrcaResults -Path $resumeOrcaDir | Where-Object { $null -ne $_ })
        }
        if ($orcaLoaded.Count -gt 0) {
            $collectedTests += $orcaLoaded
            & $markStage 3 'Microsoft ORCA & Maester' 'completed' "Reused cached ORCA output ($($orcaLoaded.Count) controls)."
        } else {
            & $markStage 3 'Microsoft ORCA' 'skipped' 'Offline mode: -InputReportJson supplied, ORCA was not executed.'
        }
    }
    if ($InputMaesterJsonPath) {
        if (Test-Path $InputMaesterJsonPath) {
            $collectedTests += @(Import-TenantBriefMaesterResults -JsonPath $InputMaesterJsonPath | Where-Object { $null -ne $_ })
        } else {
            Add-TenantBriefDiagnostic -Diagnostics $diagnostics -Stage 3 -Component 'Maester' -Message "Belirtilen Maester JSON bulunamadi: $InputMaesterJsonPath"
        }
    } elseif ($InputReportJson) {
        $resumeMaester = Join-Path $OutputPath 'raw-maester\MaesterResults.json'
        if (Test-Path $resumeMaester) {
            $maesterLoaded = @(Import-TenantBriefMaesterResults -JsonPath $resumeMaester | Where-Object { $null -ne $_ })
            if ($maesterLoaded.Count -gt 0) {
                $collectedTests += $maesterLoaded
                & $markStage 3 'Microsoft ORCA & Maester' 'completed' "Reused cached baseline outputs (Maester: $($maesterLoaded.Count) controls)."
            }
        }
    }
    if ($InputEntraFalconJsonPath) {
        if (Test-Path $InputEntraFalconJsonPath) {
            $collectedTests += @(Import-TenantBriefEntraFalconFindings -JsonPath $InputEntraFalconJsonPath | Where-Object { $null -ne $_ })
        } else {
            Add-TenantBriefDiagnostic -Diagnostics $diagnostics -Stage 3 -Component 'EntraFalcon' -Message "Belirtilen EntraFalcon JSON bulunamadi: $InputEntraFalconJsonPath"
        }
    } else {
        $efAuto = Get-ChildItem -Path $OutputPath -Filter 'tenant_findings_all_*.json' -File -ErrorAction SilentlyContinue |
            Sort-Object LastWriteTime -Descending | Select-Object -First 1
        if ($efAuto) {
            $collectedTests += @(Import-TenantBriefEntraFalconFindings -JsonPath $efAuto.FullName | Where-Object { $null -ne $_ })
        }
    }
    $tests = New-TenantBriefCorrelatedTests -Tests @((@($ztTests) + @($collectedTests)) | Where-Object { $null -ne $_ })
    $progressState.Stage = 4
    & $markStage 4 'Correlation & scoring' 'started' ''
    & $addLog "[Stage 4/5] Computing License ROI, Secure Score & Multi-Framework Scores..."

    $passedCount = @($tests | Where-Object { $_.TestStatus -eq 'Passed' }).Count
    $failedCount = @($tests | Where-Object { $_.TestStatus -eq 'Failed' }).Count
    $investigateCount = @($tests | Where-Object { $_.TestStatus -eq 'Investigate' }).Count
    $skippedCount = @($tests | Where-Object { $_.TestStatus -eq 'Skipped' }).Count
    $plannedCount = @($tests | Where-Object { $_.TestStatus -eq 'Planned' }).Count
    $errorCount = @($tests | Where-Object { $_.TestStatus -eq 'Error' }).Count
    $highRiskFailed = @($tests | Where-Object { $_.TestStatus -eq 'Failed' -and $_.TestRisk -eq 'High' }).Count
    $medRiskFailed = @($tests | Where-Object { $_.TestStatus -eq 'Failed' -and $_.TestRisk -eq 'Medium' }).Count
    $lowRiskFailed = @($tests | Where-Object { $_.TestStatus -eq 'Failed' -and $_.TestRisk -eq 'Low' }).Count

    # 'Error' controls should have been evaluated but the engine failed; they count as non-passes
    # so an unmeasured control never inflates the posture score.
    $evaluatedTotal = $passedCount + $failedCount + $errorCount
    $baseScore = if ($evaluatedTotal -gt 0) { [math]::Round(($passedCount / $evaluatedTotal) * 100, 1) } else { 0 }

    $selectedFwIds = if ($Framework -eq 'All') { @('ZeroTrust', 'ISO27001', 'NIST_CSF_2', 'CIS_M365', 'KVKK_TR') } else { @($Framework) }
    $frameworkCards = Get-TenantBriefFrameworkScorecard -Tests $tests -FrameworkConfig $fwConfig -FrameworkIds $selectedFwIds -Language $Language

    # License ROI & Blind Spot Analysis from SkippedReason
    $licenseGaps = @{}
    foreach ($t in ($tests | Where-Object { $_.TestStatus -eq 'Skipped' -and $_.SkippedReason })) {
        $reason = [string]$t.SkippedReason
        $key = if ($reason -match 'Entra_Premium_Internet_Access|Entra_Premium_Private_Access') {
            'Microsoft Entra Internet / Private Access (SSE)'
        } elseif ($reason -match 'WINDEFATP|MDE_LITE') {
            'Microsoft Defender for Endpoint (P1/P2)'
        } elseif ($reason -match 'Workload ID') {
            'Microsoft Entra Workload ID'
        } elseif ($reason -match 'SharePointOnline') {
            if ($Language -eq 'tr') { 'Bağlantı Eksikliği: SharePointOnline Modülü' } else { 'Disconnected Service: SharePointOnline' }
        } elseif ($reason -match 'EXCHANGE_S_STANDARD') {
            'Exchange Online Standard / Plan'
        } else {
            if ($Language -eq 'tr') { 'Ortam / Kapsam Dışı (Not Applicable)' } else { 'Not Applicable to Current Environment' }
        }
        if (-not $licenseGaps.ContainsKey($key)) { $licenseGaps[$key] = 0 }
        $licenseGaps[$key]++
    }

    $roiGapsList = $licenseGaps.GetEnumerator() | Sort-Object Value -Descending | ForEach-Object {
        [PSCustomObject]@{ License = $_.Key; Count = $_.Value }
    }

    $roiSummary = if ($Language -eq 'tr') {
        "Toplam $skippedCount kontrol lisans eksikliği veya servis bağlantısı nedeniyle atlandı. Bu alanlar 'güvenli' değil, ölçülemeyen risk yüzeyi olarak değerlendirilmelidir."
    } else {
        "A total of $skippedCount checks were skipped due to missing licenses or disconnected services. These areas represent unmeasured attack surface rather than verified compliance."
    }

    $roadmap = if ($Language -eq 'tr') {
        @(
            [PSCustomObject]@{ Phase = '0–30 Gün (Kritik / Quick Wins)'; Count = $highRiskFailed; Focus = 'Yüksek riskli Kimlik, Passkey, Break-Glass ve Defender temel açıkları' },
            [PSCustomObject]@{ Phase = '31–60 Gün (Orta Risk)'; Count = $medRiskFailed; Focus = 'Intune uyumluluk, DLP/Purview etiketleme ve ağ segmentasyonu' },
            [PSCustomObject]@{ Phase = '61–90 Gün (İnceleme & Düşük)'; Count = ($lowRiskFailed + $investigateCount); Focus = 'Investigate bulguları, SOC triyaj SLA ve sürekli drift takibi' }
        )
    } else {
        @(
            [PSCustomObject]@{ Phase = 'Days 0–30 (Critical / Quick Wins)'; Count = $highRiskFailed; Focus = 'High-risk Identity, Passkeys, Break-Glass, and Defender baselines' },
            [PSCustomObject]@{ Phase = 'Days 31–60 (Medium Risk)'; Count = $medRiskFailed; Focus = 'Intune compliance, Purview labeling/DLP, and network segmentation' },
            [PSCustomObject]@{ Phase = 'Days 61–90 (Investigate & Low)'; Count = ($lowRiskFailed + $investigateCount); Focus = 'Manual Investigate items, SOC triage SLAs, and drift monitoring' }
        )
    }

    $activeFwForTable = if ($Framework -eq 'All') { 'ISO27001' } else { $Framework }
    $pillarMap = $fwConfig.$activeFwForTable.pillarMap

    # Batch-translate titles & descriptions in chunks of 40 when TranslatorKey is set
    $trCachePath = Join-Path $PSScriptRoot 'data\tr-translation-cache.json'
    $trCache = @{}
    if ($Language -eq 'tr' -and (Test-Path $trCachePath)) {
        try {
            $loaded = Get-Content -Path $trCachePath -Raw -Encoding UTF8 | ConvertFrom-Json
            foreach ($p in $loaded.PSObject.Properties) { $trCache[$p.Name] = $p.Value }
        } catch {}
    }

    if ($Language -eq 'tr' -and $TranslatorKey) {
        $toTranslate = @()
        foreach ($t in $tests) {
            $k = [string]$t.TestId
            if ($k -and -not $trCache.ContainsKey($k)) { $toTranslate += $t }
        }
        if ($toTranslate.Count -gt 0) {
            Write-Host "[TenantBrief] Translating $($toTranslate.Count) controls via Azure AI Translator..." -ForegroundColor Cyan
            for ($i = 0; $i -lt $toTranslate.Count; $i += 15) {
                $chunk = $toTranslate[$i..([Math]::Min($i + 14, $toTranslate.Count - 1))]
                $payload = @()
                foreach ($item in $chunk) {
                    $dText = [string]$item.TestDescription
                    if ($dText.Length -gt 1000) { $dText = $dText.Substring(0, 1000) }
                    $payload += @{ Text = [string]$item.TestTitle }
                    $payload += @{ Text = $dText }
                }
                $jsonBody = $payload | ConvertTo-Json -Compress
                $trResp = $null
                for ($attempt = 1; $attempt -le 2; $attempt++) {
                    try {
                        $trResp = Invoke-RestMethod -Method Post -Uri 'https://api.cognitive.microsofttranslator.com/translate?api-version=3.0&from=en&to=tr' -Headers @{
                            'Ocp-Apim-Subscription-Key'    = $TranslatorKey
                            'Ocp-Apim-Subscription-Region' = 'global'
                            'Content-Type'                 = 'application/json; charset=utf-8'
                        } -Body ([System.Text.Encoding]::UTF8.GetBytes($jsonBody)) -ErrorAction Stop
                        break
                    } catch {
                        if ($attempt -eq 1 -and $_.Exception.Message -match '429') {
                            Start-Sleep -Seconds 25
                        } else {
                            Write-Warning "[TenantBrief] Translator batch skipped: $($_.Exception.Message)"
                        }
                    }
                }
                if ($trResp) {
                    for ($j = 0; $j -lt $chunk.Count; $j++) {
                        $tItem = $chunk[$j]
                        $trCache[[string]$tItem.TestId] = [PSCustomObject]@{
                            Title = [string]$trResp[$j * 2].translations[0].text
                            Desc  = [string]$trResp[$j * 2 + 1].translations[0].text
                        }
                    }
                }
                Start-Sleep -Seconds 4
            }
            try { $trCache | ConvertTo-Json -Depth 3 | Out-File -FilePath $trCachePath -Encoding UTF8 } catch {}
        }
    }

    $findings = New-TenantBriefFindings -Tests $tests -PillarMap $pillarMap -Language $Language -TranslationCache $trCache

    $tenantDisplay = if ($Anonymize) { 'contoso.onmicrosoft.com (Anonymized)' } else { [string]$raw.Domain }
    $ti = $raw.PSObject.Properties['TenantInfo'].Value
    $tOverview = if ($ti -and $ti.PSObject.Properties['TenantOverview'].Value) { $ti.TenantOverview } else { $null }
    $mfaDesc = if ($ti -and $ti.PSObject.Properties['OverviewCaMfaAllUsers'].Value) { [string]$ti.OverviewCaMfaAllUsers.description } else { '' }
    if ($Language -eq 'tr' -and $mfaDesc -match 'Over the past (\d+) days,\s*([\d.,]+)%\s*of sign-ins were protected by conditional access policies enforcing multifactor') {
        $mfaDesc = "Son $($Matches[1]) günde oturum açmaların %$($Matches[2]) kadarı çok faktörlü kimlik doğrulama (MFA) zorunlu kılan Koşullu Erişim politikaları ile korundu."
    }
    $devComp = if ($ti -and $ti.PSObject.Properties['DeviceOverview'].Value -and $ti.DeviceOverview.PSObject.Properties['DeviceCompliance'].Value) { $ti.DeviceOverview.DeviceCompliance } else { $null }
    $agentOv = if ($ti -and $ti.PSObject.Properties['AgentOverview'].Value) { $ti.AgentOverview } else { $null }
    $privAuth = if ($ti -and $ti.PSObject.Properties['OverviewAuthMethodsPrivilegedUsers'].Value) { $ti.OverviewAuthMethodsPrivilegedUsers } else { $null }

    $privSingle = 0; $privPhishable = 0; $privPhishRes = 0
    if ($privAuth -and $privAuth.nodes) {
        foreach ($n in $privAuth.nodes) {
            if ($n.source -eq 'Users' -and $n.target -eq 'Single factor') { $privSingle = [int]$n.value }
            elseif ($n.source -eq 'Users' -and $n.target -eq 'Phishable') { $privPhishable = [int]$n.value }
            elseif ($n.source -eq 'Users' -and $n.target -eq 'Phish resistant') { $privPhishRes = [int]$n.value }
        }
    }

    $skuRoiList = @()
    $licenseWaste = $null
    $copilotReadiness = $null
    $secureCurrent = $null
    $secureMax = $null

    $tenantInsightObj = [PSCustomObject]@{
        UserCount            = if ($tOverview) { [int]$tOverview.UserCount } else { 0 }
        GuestCount           = if ($tOverview) { [int]$tOverview.GuestCount } else { 0 }
        GroupCount           = if ($tOverview) { [int]$tOverview.GroupCount } else { 0 }
        ApplicationCount     = if ($tOverview) { [int]$tOverview.ApplicationCount } else { 0 }
        DeviceCount          = if ($tOverview) { [int]$tOverview.DeviceCount } else { 0 }
        ManagedDeviceCount   = if ($tOverview) { [int]$tOverview.ManagedDeviceCount } else { 0 }
        CompliantDevices     = if ($devComp) { [int]$devComp.compliantDeviceCount } else { 0 }
        NonCompliantDevices  = if ($devComp) { [int]$devComp.nonCompliantDeviceCount } else { 0 }
        TotalAgents          = if ($agentOv) { [int]$agentOv.TotalAgents } else { 0 }
        PrivSingleFactor     = $privSingle
        PrivPhishable        = $privPhishable
        PrivPhishResistant   = $privPhishRes
        SecureScoreCurrent   = $secureCurrent
        SecureScoreMax       = $secureMax
        MfaCoverageDesc      = $mfaDesc
    }

    $liveTelemetryPath = Join-Path $rawOut 'tenant-live-telemetry.json'
    if (-not $InputReportJson) {
        try {
            if (Get-MgContext -ErrorAction SilentlyContinue) {
                $subResp = Invoke-MgGraphRequest -Method GET -Uri 'https://graph.microsoft.com/v1.0/subscribedSkus' -ErrorAction SilentlyContinue
                $liveSkus = if ($subResp -and $subResp.value) { @($subResp.value) } else { @() }
                if ($liveSkus.Count -gt 0) {
                    $skuRoiList = @(Get-TenantBriefLicenseRoi -SubscribedSkus $liveSkus)
                    try { $licenseWaste = Get-TenantBriefLicenseWaste -SubscribedSkus $liveSkus -Language $Language }
                    catch {
                        Add-TenantBriefDiagnostic -Diagnostics $diagnostics -Stage 4 -Component 'LicenseWaste' -Message "R1-R7 lisans israfi analizi tamamlanamadi: $($_.Exception.Message)"
                        Write-Warning "[TenantBrief] License waste analysis failed: $($_.Exception.Message)"
                    }
                } else {
                    Add-TenantBriefDiagnostic -Diagnostics $diagnostics -Stage 4 -Component 'LicenseROI' -Message 'Graph /subscribedSkus bos dondu: lisans ROI ve israf bolumleri bu raporda yok.'
                }
                try {
                    $crParams = @{ Language = $Language; TenantInsights = $tenantInsightObj }
                    if ($liveSkus.Count -gt 0) { $crParams['SubscribedSkus'] = $liveSkus }
                    if ($InputFastTrackJsonPath) { $crParams['InputFastTrackJsonPath'] = $InputFastTrackJsonPath }
                    $copilotReadiness = Get-TenantBriefCopilotReadiness @crParams
                } catch {
                    Add-TenantBriefDiagnostic -Diagnostics $diagnostics -Stage 4 -Component 'CopilotReadiness' -Message "Copilot hazirlik degerlendirmesi basarisiz: $($_.Exception.Message)"
                    Write-Warning "[TenantBrief] Copilot readiness evaluation failed: $($_.Exception.Message)"
                }
                $scResp = Invoke-MgGraphRequest -Method GET -Uri 'https://graph.microsoft.com/v1.0/security/secureScores?$top=1' -ErrorAction SilentlyContinue
                if ($scResp -and $scResp.value -and $scResp.value.Count -gt 0) {
                    $secureCurrent = [Math]::Round([double]$scResp.value[0].currentScore, 1)
                    $secureMax = [Math]::Round([double]$scResp.value[0].maxScore, 1)
                    $tenantInsightObj.SecureScoreCurrent = $secureCurrent
                    $tenantInsightObj.SecureScoreMax = $secureMax
                }
                try {
                    if (-not (Test-Path $rawOut)) { New-Item -ItemType Directory -Path $rawOut -Force | Out-Null }
                    [PSCustomObject]@{
                        SubscribedSkus     = @($liveSkus)
                        Skus               = @($skuRoiList)
                        WasteAnalysis      = $licenseWaste
                        CopilotReadiness   = $copilotReadiness
                        SecureScoreCurrent = $secureCurrent
                        SecureScoreMax     = $secureMax
                    } | ConvertTo-Json -Depth 6 | Set-Content -Path $liveTelemetryPath -Encoding UTF8
                } catch {}
            } else {
                Add-TenantBriefDiagnostic -Diagnostics $diagnostics -Stage 4 -Component 'Graph' -Message 'Aktif Graph oturumu bulunamadi: lisans ROI, israf ve Copilot bolumleri uretilemedi.'
            }
        } catch {
            Add-TenantBriefDiagnostic -Diagnostics $diagnostics -Stage 4 -Component 'Graph' -Message "Lisans/Copilot verisi alinamadi: $($_.Exception.Message)"
            Write-Warning "[TenantBrief] Stage 4 data collection failed: $($_.Exception.Message)"
        }
    } elseif (Test-Path $liveTelemetryPath) {
        try {
            $cachedTel = Get-Content -Path $liveTelemetryPath -Raw -Encoding UTF8 | ConvertFrom-Json
            if ($cachedTel.PSObject.Properties['Skus'] -and $cachedTel.Skus) { $skuRoiList = @($cachedTel.Skus) }
            if ($cachedTel.PSObject.Properties['WasteAnalysis'] -and $cachedTel.WasteAnalysis) { $licenseWaste = $cachedTel.WasteAnalysis }
            if ($cachedTel.PSObject.Properties['CopilotReadiness'] -and $cachedTel.CopilotReadiness) { $copilotReadiness = $cachedTel.CopilotReadiness }
            if ($cachedTel.PSObject.Properties['SecureScoreCurrent'] -and $null -ne $cachedTel.SecureScoreCurrent) {
                $tenantInsightObj.SecureScoreCurrent = $cachedTel.SecureScoreCurrent
                $tenantInsightObj.SecureScoreMax = $cachedTel.SecureScoreMax
            }
        } catch {}
    }

    if (-not $copilotReadiness) {
        try {
            $offParams = @{ Language = $Language; TenantInsights = $tenantInsightObj; OfflineOnly = $true }
            if ($InputFastTrackJsonPath) { $offParams['InputFastTrackJsonPath'] = $InputFastTrackJsonPath }
            $copilotReadiness = Get-TenantBriefCopilotReadiness @offParams
        } catch {
            Add-TenantBriefDiagnostic -Diagnostics $diagnostics -Stage 4 -Component 'CopilotReadiness' -Message "Cevrimdisi Copilot degerlendirmesi de basarisiz: $($_.Exception.Message)"
            Write-Warning "[TenantBrief] Copilot readiness evaluation warning: $($_.Exception.Message)"
        }
    }
    if (-not $licenseWaste -and -not $InputReportJson) {
        Add-TenantBriefDiagnostic -Diagnostics $diagnostics -Stage 4 -Component 'LicenseWaste' -Message 'Lisans israfi (R1-R7) bolumu bu raporda bos.'
    }

    $totalIdleMo = if ($skuRoiList.Count -gt 0) {
        [Math]::Round((($skuRoiList | Measure-Object -Property EstimatedIdleUsdMo -Sum).Sum), 2)
    } else { 0 }
    $totalIdleYr = [Math]::Round($totalIdleMo * 12, 2)

    & $markStage 4 'Correlation & scoring' 'completed' "Findings: $(@($tests).Count)"
    # A resumed Stage 1 is an audit note, not a degraded report; only real failures make it 'partial'.
    $degraded = @($diagnostics | Where-Object { $_.Component -ne 'Resume' })
    $runStatus = if ($degraded.Count -gt 0) { 'partial' } else { 'completed' }

    $reportObj = [PSCustomObject]@{
        Tenant           = $tenantDisplay
        Language         = $Language
        Framework        = $Framework
        TenantInsights   = $tenantInsightObj
        Summary          = [PSCustomObject]@{
            Total          = $tests.Count
            Passed         = $passedCount
            Failed         = $failedCount
            Investigate    = $investigateCount
            Skipped        = $skippedCount
            Planned        = $plannedCount
            Error          = $errorCount
            HighRiskFailed = $highRiskFailed
        }
        Run              = [PSCustomObject]@{
            Status        = $runStatus
            StartedAt     = $manifest.StartedAt
            CompletedAt   = (Get-Date).ToString('o')
            Resumed       = [bool]$resumeNote
            SourceReport  = if ($Anonymize -and $InputReportJson) { Split-Path -Path $InputReportJson -Leaf } else { $InputReportJson }
            Stages        = @($manifest.Stages)
        }
        Diagnostics      = @($diagnostics)
        Frameworks       = @($frameworkCards)
        LicenseROI       = [PSCustomObject]@{
            Summary         = $roiSummary
            Gaps            = @($roiGapsList)
            Skus            = @($skuRoiList)
            TotalIdleUsdMo  = $totalIdleMo
            TotalIdleUsdYr  = $totalIdleYr
            WasteAnalysis   = $licenseWaste
        }
        CopilotReadiness = $copilotReadiness
        Roadmap          = @($roadmap)
        Findings         = @($findings)
        Labels     = if ($Language -eq 'tr') {
            [PSCustomObject]@{
                TotalChecks        = 'Toplam Kontrol'
                HighRiskFailed     = 'Yüksek Riskli Açık'
                PassedLabel        = 'Geçen Kontrol'
                SkippedChecksLabel = 'atlanan kontrol'
            }
        } else {
            [PSCustomObject]@{
                TotalChecks        = 'Total Checks'
                HighRiskFailed     = 'High-Risk Failed'
                PassedLabel        = 'Passed'
                SkippedChecksLabel = 'skipped checks'
            }
        }
    }

    $reportJsonPath = Join-Path $OutputPath "TenantBriefReport-$($Language.ToUpper()).json"
    $reportObj | ConvertTo-Json -Depth 6 | Set-Content -Path $reportJsonPath -Encoding UTF8

    $template = Get-Content -Path $script:ReportTemplatePath -Raw -Encoding UTF8
    $isTr = $Language -eq 'tr'
    $replacements = @{
        '{{LANG}}'               = $Language
        '{{TITLE}}'              = if ($isTr) { "TenantBrief Raporu — $tenantDisplay" } else { "TenantBrief Report — $tenantDisplay" }
        '{{HEADER_TITLE}}'       = if ($isTr) { 'Sıfır Güven, Lisans ROI ve Uyumluluk Analizi' } else { 'Zero Trust, License ROI & Compliance Assessment' }
        '{{SUBTITLE}}'           = if ($isTr) { "Kiracı: $tenantDisplay · Çerçeve: $Framework" } else { "Tenant: $tenantDisplay · Framework: $Framework" }
        '{{READONLY_BADGE}}'     = if ($isTr) { 'Salt Okunur (Read-Only)' } else { 'Read-Only Mode' }
        '{{GENERATED_AT}}'       = (Get-Date -Format 'yyyy-MM-dd HH:mm')
        '{{FW_TITLE}}'           = if ($isTr) { 'Uyumluluk Çerçevesi Puanlaması' } else { 'Compliance Framework Scoring' }
        '{{ROI_TITLE}}'          = if ($isTr) { 'M365 Lisans ROI ve Kör Nokta Analizi' } else { 'M365 License ROI & Blind Spot Analysis' }
        '{{ROADMAP_TITLE}}'      = if ($isTr) { '30-60-90 Günlük CISO İyileştirme Yol Haritası' } else { '30-60-90 Day CISO Remediation Roadmap' }
        '{{FINDINGS_TITLE}}'     = if ($isTr) { 'Ayrıntılı Kontrol Bulguları' } else { 'Detailed Control Findings' }
        '{{SEARCH_PLACEHOLDER}}' = if ($isTr) { 'Test ID, sütun veya başlık ara...' } else { 'Search Test ID, pillar, or title...' }
        '{{ALL_STATUSES}}'       = if ($isTr) { 'Tüm Durumlar' } else { 'All Statuses' }
        '{{ALL_RISKS}}'          = if ($isTr) { 'Tüm Riskler' } else { 'All Risks' }
        '{{COL_PILLAR}}'         = if ($isTr) { 'Sütun' } else { 'Pillar' }
        '{{COL_STATUS}}'         = if ($isTr) { 'Durum' } else { 'Status' }
        '{{COL_RISK}}'           = 'Risk'
        '{{COL_TITLE}}'          = if ($isTr) { 'Kontrol Başlığı' } else { 'Control Title' }
        '{{COL_FRAMEWORK}}'      = if ($isTr) { 'Çerçeve Eşleşmesi' } else { 'Framework Mapping' }
        '{{FOOTER_NOTE}}'        = if ($isTr) { 'Yerel, salt okunur analiz — hiçbir veri dışarı gönderilmez' } else { 'Local, read-only analysis — zero telemetry' }
        '{{DIAGNOSTICS_BANNER}}' = if (@($diagnostics).Count -gt 0) {
            $resumeNotes = @($diagnostics | Where-Object { $_.Component -eq 'Resume' })
            $warnings = @($diagnostics | Where-Object { $_.Component -ne 'Resume' })
            $blocks = @()
            if ($warnings.Count -gt 0) {
                $dHead = if ($isTr) {
                    'Bu rapor kismi veriyle olusturuldu. Asagidaki adimlar tamamlanamadi; eksik bolum "sorun yok" anlamina gelmez.'
                } else {
                    'This report was generated from partial data. The steps below did not complete; a missing section does not mean "no findings".'
                }
                $dItems = (@($warnings) | Select-Object -First 10 | ForEach-Object {
                    "<li><strong>Stage $($_.Stage) &middot; $( [System.Net.WebUtility]::HtmlEncode([string]$_.Component)):</strong> $( [System.Net.WebUtility]::HtmlEncode([string]$_.Message))</li>"
                }) -join ''
                $dMore = if ($warnings.Count -gt 10) { "<div style='font-size:12px;margin-top:6px'>+ $($warnings.Count - 10) more in run-manifest.json</div>" } else { '' }
                $blocks += "<div class='card' style='border-color:#f59e0b;background:rgba(245,158,11,.10);margin-bottom:14px;'><strong>$dHead</strong><ul style='margin:10px 0 0 18px;font-size:12.5px;line-height:1.55;'>$dItems</ul>$dMore</div>"
            }
            if ($resumeNotes.Count -gt 0) {
                $rHead = if ($isTr) {
                    'Bu rapor mevcut bir Stage 1 cikisi uzerine kuruldu; kiraci yeniden taranmadi.'
                } else {
                    'This report was built on a previous Stage 1 output; the tenant was not rescanned.'
                }
                $blocks += "<div class='card' style='border-color:#38bdf8;background:rgba(56,189,248,.10);margin-bottom:14px;'><strong>$rHead</strong></div>"
            }
            $blocks -join ''
        } else { '' }
        '{{REPORT_JSON}}'        = ($reportObj | ConvertTo-Json -Depth 6 -Compress)
    }

    $html = $template
    foreach ($k in $replacements.Keys) {
        $html = $html.Replace($k, $replacements[$k])
    }

    $progressState.Stage = 5
    & $markStage 5 'Report generation' 'started' ''
    & $addLog "[Stage 5/5] Writing HTML, JSON and Executive Summary reports..."
    $reportHtmlPath = Join-Path $OutputPath "TenantBriefReport-$($Language.ToUpper()).html"
    $html | Set-Content -Path $reportHtmlPath -Encoding UTF8

    $execSummaryPath = Join-Path $OutputPath "TenantBrief-ExecutiveSummary-$($Language.ToUpper()).html"
    $null = Export-TenantBriefExecutiveSummary -InputJsonPath $reportJsonPath -OutputHtmlPath $execSummaryPath -Language $Language

    & $markStage 5 'Report generation' 'completed' "HTML/JSON/ExecutiveSummary written to $OutputPath"
    Save-TenantBriefRunManifest -Manifest $manifest -Path $manifestPath -Status $runStatus -Diagnostics $diagnostics

    $progressState.Done = $true
    Start-Sleep -Seconds 2
    } catch {
        $failedStage = [int]$progressState.Stage
        $progressState.Error = $_.Exception.Message
        Add-TenantBriefDiagnostic -Diagnostics $diagnostics -Stage $failedStage -Component 'Pipeline' -Message $_.Exception.Message
        try {
            Set-TenantBriefStage -Manifest $manifest -Stage $failedStage -Name "Stage $failedStage" -Status 'failed' -Message $_.Exception.Message
            Save-TenantBriefRunManifest -Manifest $manifest -Path $manifestPath -Status 'failed' -Diagnostics $diagnostics
        } catch {}
        Start-Sleep -Seconds 3
        throw
    } finally {
        if ($progressJob) {
            $progressState.Stop = $true
            try { $progressJob.Ps.EndInvoke($progressJob.Handle) } catch {}
            try { $progressJob.Ps.Dispose(); $progressJob.Rs.Close(); $progressJob.Rs.Dispose() } catch {}
        }
    }

    Write-Host "[TenantBrief] Report generated: $reportHtmlPath" -ForegroundColor Green
    if (-not $NoBrowser) {
        Start-Process $reportHtmlPath
    }

    return [PSCustomObject]@{
        HtmlPath             = $reportHtmlPath
        JsonPath             = $reportJsonPath
        ExecutiveSummaryPath = $execSummaryPath
        Summary              = $reportObj.Summary
    }
}

function Get-TenantBriefLicenseRoi {
    <#
    .SYNOPSIS
    Computes purchased/assigned/idle seat ratios and idle USD estimate per SKU.

    .DESCRIPTION
    Reads Graph /v1.0/subscribedSkus (or accepts -SubscribedSkus) and prices each SKU from
    data/sku-catalog.json to estimate unused spend per month.

    .EXAMPLE
    Get-TenantBriefLicenseRoi | Format-Table ProductName, Purchased, Assigned, Unassigned, EstimatedIdleUsdMo
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory = $false)]
        [object[]]$SubscribedSkus
    )

    $catalogPath = Join-Path $PSScriptRoot 'data\sku-catalog.json'
    $catalog = (Get-Content -Path $catalogPath -Raw -Encoding UTF8 | ConvertFrom-Json).skus
    $skuIndex = @{}
    foreach ($c in $catalog) { $skuIndex[$c.skuPartNumber] = $c }

    if (-not $SubscribedSkus) {
        $resp = Invoke-MgGraphRequest -Method GET -Uri 'https://graph.microsoft.com/v1.0/subscribedSkus'
        $SubscribedSkus = @($resp.value)
    }

    $results = foreach ($s in $SubscribedSkus) {
        $part = [string]$s.skuPartNumber
        $enabled = [int]$s.prepaidUnits.enabled
        $consumed = [int]$s.consumedUnits
        if ($enabled -le 0) { continue }

        $unassigned = [Math]::Max(0, $enabled - $consumed)
        $utilPct = [Math]::Round(($consumed / $enabled) * 100, 1)
        $meta = $skuIndex[$part]
        $unitUsd = if ($meta) { [double]$meta.usdPerUserMonth } else { 0.0 }
        $idleUsdMonth = [Math]::Round($unassigned * $unitUsd, 2)
        $billableProp = if ($meta) { $meta.PSObject.Properties['countsAsWaste'] } else { $null }
        $billable = if ($billableProp) { [bool]$billableProp.Value } else { $unitUsd -gt 0 }

        [PSCustomObject]@{
            SkuPartNumber       = $part
            ProductName         = if ($meta) { $meta.name } else { $part }
            Category            = if ($meta) { $meta.category } else { 'Other' }
            Purchased           = $enabled
            Assigned            = $consumed
            Unassigned          = $unassigned
            UtilizationPercent  = $utilPct
            Billable            = $billable
            EstimatedIdleUsdMo  = $idleUsdMonth
        }
    }
    return @($results)
}

function Compare-TenantBriefReports {
    <#
    .SYNOPSIS
    Compares two TenantBrief JSON reports and lists improved and regressed controls.

    .DESCRIPTION
    Matches findings by control Id. A control that moves to Passed is reported as improved;
    a control that leaves Passed is reported as regressed. Use it for drift tracking between
    two assessment runs.

    .EXAMPLE
    Compare-TenantBriefReports -BaselineJsonPath .\old\TenantBriefReport-TR.json `
    -CurrentJsonPath .\new\TenantBriefReport-TR.json
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$BaselineJsonPath,

        [Parameter(Mandatory = $true)]
        [string]$CurrentJsonPath
    )

    if (-not (Test-Path $BaselineJsonPath)) { throw "Baseline JSON not found: $BaselineJsonPath" }
    if (-not (Test-Path $CurrentJsonPath)) { throw "Current JSON not found: $CurrentJsonPath" }

    $base = Get-Content -Path $BaselineJsonPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $curr = Get-Content -Path $CurrentJsonPath -Raw -Encoding UTF8 | ConvertFrom-Json

    $baseMap = @{}
    foreach ($t in @($base.Findings)) { $baseMap[[string]$t.Id] = $t }

    $improved = @()
    $regressed = @()
    $unchanged = 0

    foreach ($t in @($curr.Findings)) {
        $id = [string]$t.Id
        if (-not $id -or -not $baseMap.ContainsKey($id)) { continue }
        $prev = $baseMap[$id]
        if ($prev.Status -ne 'Passed' -and $t.Status -eq 'Passed') {
            $improved += [PSCustomObject]@{ Id = $id; Title = $t.Title; From = $prev.Status; To = $t.Status; Risk = $t.Risk }
        } elseif ($prev.Status -eq 'Passed' -and $t.Status -ne 'Passed') {
            $regressed += [PSCustomObject]@{ Id = $id; Title = $t.Title; From = $prev.Status; To = $t.Status; Risk = $t.Risk }
        } else {
            $unchanged++
        }
    }

    return [PSCustomObject]@{
        BaselineTotal  = $base.Summary.Total
        CurrentTotal   = $curr.Summary.Total
        ImprovedCount  = $improved.Count
        RegressedCount = $regressed.Count
        UnchangedCount = $unchanged
        Improved       = $improved
        Regressed      = $regressed
    }
}

function Export-TenantBriefExecutiveSummary {
    <#
    .SYNOPSIS
    Builds an offline Print-to-PDF executive brief from a report JSON.

    .DESCRIPTION
    Produces a compact, dependency-free HTML brief (framework scores, headline counts and
    the top high-risk remediations) that can be printed to PDF without any network access.

    .EXAMPLE
    Export-TenantBriefExecutiveSummary -InputJsonPath .\TenantBriefReport-TR.json -Language tr
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [Alias('InputLensJsonPath')][string]$InputJsonPath,

        [Parameter(Mandatory = $false)]
        [string]$OutputHtmlPath = '.\TenantBrief-ExecutiveSummary.html',

        [Parameter(Mandatory = $false)]
        [ValidateSet('tr', 'en')]
        [string]$Language = 'tr'
    )

    if (-not (Test-Path $InputJsonPath)) { throw "TenantBrief JSON not found: $InputJsonPath" }
    $data = Get-Content -Path $InputJsonPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $title = if ($Language -eq 'tr') { 'Yönetici Özeti — Güvenlik Duruşu ve Lisans ROI' } else { 'Executive Summary — Security Posture & License ROI' }

    $diagProp = $data.PSObject.Properties['Diagnostics']
    $diagCount = if ($diagProp -and $diagProp.Value) {
        @($diagProp.Value | Where-Object { $_ -and $_.Component -ne 'Resume' }).Count
    } else { 0 }
    $diagNote = if ($diagCount -gt 0) {
        $diagText = if ($Language -eq 'tr') {
            "Rapor kısmi veriyle üretildi: $diagCount adım tamamlanamadı. Eksik bölümler 'sorun yok' anlamına gelmez; ayrıntı run-manifest.json içinde."
        } else {
            "Generated from partial data: $diagCount step(s) did not complete. Missing sections do not mean 'no findings'; see run-manifest.json."
        }
        "<div style='border:1px solid #f59e0b;background:#fffbeb;color:#92400e;padding:8px 12px;border-radius:6px;font-size:12.5px;margin-bottom:16px;'>$diagText</div>"
    } else { '' }

    $fwRows = ($data.Frameworks | ForEach-Object {
        "<tr><td>$($_.Name)</td><td>$($_.Passed) / $($_.Evaluated)</td><td><strong>$($_.Score)%</strong></td></tr>"
    }) -join "`n"

    # Priority order for the printable brief: cheapest high-risk fixes first, then by control id so
    # the output is stable between runs.
    $isTr = ($Language -eq 'tr')
    $costRank = @{ 'Low' = 0; 'Medium' = 1; 'High' = 2; 'Unknown' = 3 }
    $costMap = @{ 'Low' = 'Düşük'; 'Medium' = 'Orta'; 'High' = 'Yüksek'; 'Unknown' = 'Bilinmiyor' }
    $topHigh = @($data.Findings |
        Where-Object { $_.Status -eq 'Failed' -and $_.Risk -eq 'High' } |
        Sort-Object `
            @{ Expression = { $cost = [string]$_.ImplementationCost; if ($costRank.ContainsKey($cost)) { $costRank[$cost] } else { 3 } } },
            @{ Expression = { [string]$_.Id } } |
        Select-Object -First 15)
    $actionRows = ($topHigh | ForEach-Object {
        $remText = if ($isTr) { $_.RemediationTr } else { [string]$_.Description }
        if ($remText.Length -gt 220) { $remText = $remText.Substring(0, 220) + '...' }
        $domLbl = if ($_.PSObject.Properties['DomainPillar'] -and $_.DomainPillar) { [string]$_.DomainPillar } else { [string]$_.Pillar }
        $costStr = [string]$_.ImplementationCost
        $costLbl = if ($isTr -and $costMap.ContainsKey($costStr)) { $costMap[$costStr] } else { $costStr }
        "<tr><td><code>$($_.Id)</code> <strong>$($_.Title)</strong><br/><span style='color:#64748b;font-size:11px;'>$domLbl · $($_.Category)</span></td><td>$costLbl</td><td>$remText</td></tr>"
    }) -join "`n"

    $subLine = if ($isTr) { "Üretim: $(Get-Date -Format 'yyyy-MM-dd HH:mm') | Salt Okunur Değerlendirme" } else { "Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm') | Read-Only Assessment" }
    $lblTotal  = if ($isTr) { 'Toplam Kontrol' } else { 'Total' }
    $lblPass   = if ($isTr) { 'Başarılı' } else { 'Passed' }
    $lblFail   = if ($isTr) { 'Başarısız (Yüksek)' } else { 'Failed (High)' }
    $lblIdle   = if ($isTr) { 'Atıl Lisans (Yıllık USD)' } else { 'Idle License (Annual USD)' }
    $thFw      = if ($isTr) { 'Uyumluluk Çerçevesi (Framework)' } else { 'Framework' }
    $thRatio   = if ($isTr) { 'Geçen / Ölçülen' } else { 'Passed / Total' }
    $thScore   = if ($isTr) { 'Puan' } else { 'Score' }

    $html = @"
<!DOCTYPE html>
<html lang="$Language">
<head>
<meta charset="UTF-8" />
<title>TenantBrief - $title</title>
<style>
  body { font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif; color: #0f172a; margin: 32px; }
  h1 { font-size: 22px; margin-bottom: 4px; }
  .sub { color: #475569; margin-bottom: 20px; font-size: 13px; }
  .grid { display: grid; grid-template-columns: repeat(4, 1fr); gap: 12px; margin-bottom: 20px; }
  .card { border: 1px solid #cbd5e1; border-radius: 8px; padding: 12px; }
  .val { font-size: 24px; font-weight: 700; }
  table { width: 100%; border-collapse: collapse; margin-top: 12px; }
  th, td { border: 1px solid #cbd5e1; padding: 8px 10px; text-align: left; font-size: 13px; }
  th { background: #f1f5f9; }
  code { background: #f1f5f9; padding: 1px 5px; border-radius: 4px; font-size: 11px; }
  @media print { body { margin: 12mm; } }
</style>
</head>
<body>
  <h1>TenantBrief — $title</h1>
  <div class="sub">$subLine</div>
  $diagNote
  <div class="grid">
    <div class="card"><div>$lblTotal</div><div class="val">$($data.Summary.Total)</div></div>
    <div class="card"><div>$lblPass</div><div class="val">$($data.Summary.Passed)</div></div>
    <div class="card"><div>$lblFail</div><div class="val">$($data.Summary.Failed) ($($data.Summary.HighRiskFailed))</div></div>
    <div class="card"><div>$lblIdle</div><div class="val">`$$($data.LicenseROI.TotalIdleUsdYr)</div></div>
  </div>
  <table>
    <thead><tr><th>$thFw</th><th>$thRatio</th><th>$thScore</th></tr></thead>
    <tbody>$fwRows</tbody>
  </table>
  <h2 style="font-size:17px;margin-top:24px;">$(if ($isTr) { 'Öncelikli İlk 15 İyileştirme Adımı — düşük efor önce (Çevrimdışı Analiz)' } else { 'Top 15 Priority Remediations — lowest effort first (Offline Analysis)' })</h2>
  <table>
    <thead><tr><th>$(if ($isTr) { 'Kontrol' } else { 'Control' })</th><th>$(if ($isTr) { 'Maliyet' } else { 'Cost' })</th><th>$(if ($isTr) { 'Önerilen Aksiyon' } else { 'Recommended Action' })</th></tr></thead>
    <tbody>$actionRows</tbody>
  </table>
</body>
</html>
"@
    $html | Out-File -FilePath $OutputHtmlPath -Encoding UTF8
    return (Resolve-Path $OutputHtmlPath).Path
}

function Get-TenantBriefGraphCollection {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Uri,

        [Parameter(Mandatory = $false)]
        [int]$PageLimit = 200
    )

    $items = New-Object System.Collections.Generic.List[object]
    $nextLink = $Uri
    $page = 0

    while ($nextLink -and $page -lt $PageLimit) {
        $page++
        $response = Invoke-MgGraphRequest -Method GET -Uri $nextLink -ErrorAction Stop
        if ($null -eq $response) { break }

        $values = $null
        if ($response -is [hashtable]) {
            if ($response.ContainsKey('value')) { $values = $response['value'] }
        } elseif ($response.PSObject.Properties['value']) {
            $values = $response.value
        }
        foreach ($v in @($values)) {
            if ($null -ne $v) { $items.Add($v) }
        }

        $nextLink = $null
        if ($response -is [hashtable]) {
            if ($response.ContainsKey('@odata.nextLink')) { $nextLink = [string]$response['@odata.nextLink'] }
        } elseif ($response.PSObject.Properties['@odata.nextLink']) {
            $nextLink = [string]$response.'@odata.nextLink'
        }

        if ($nextLink) {
            Write-Verbose "Graph sayfalamasi devam ediyor (sayfa $page, $($items.Count) kayit): $nextLink"
        }
    }

    if ($nextLink) {
        Write-Warning "Graph sayfalama siniri ($PageLimit sayfa) asildi; sonuc kismi olabilir."
    }

    return $items.ToArray()
}

function Get-TenantBriefLicenseWaste {
    <#
    .SYNOPSIS
    Audits disabled, inactive, guest and overlapping licensed users (R1-R7).

    .DESCRIPTION
    Follows Graph @odata.nextLink pagination when enumerating users, so tenants larger than
    one page are analysed completely. Detects disabled licensed accounts (R1), 90+ day
    inactive licensed users (R2, requires AuditLog.Read.All), unassigned seats (R3),
    overlapping SKUs (R4) and licensed guests (R7).

    .EXAMPLE
    Get-TenantBriefLicenseWaste -InactiveDays 90 | Format-List
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory = $false)]
        [object[]]$SubscribedSkus,

        [Parameter(Mandatory = $false)]
        [object[]]$Users,

        [Parameter(Mandatory = $false)]
        [ValidateSet('tr', 'en')]
        [string]$Language = 'tr',

        [Parameter(Mandatory = $false)]
        [int]$InactiveDays = 90
    )

    $catalogPath = Join-Path $PSScriptRoot 'data\sku-catalog.json'
    $catalogJson = Get-Content -Path $catalogPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $skuPriceMap = @{}
    $skuNameMap = @{}
    $skuGuidToPart = @{}
    # SKUs explicitly marked as non-billable (free tiers, developer sandboxes) must not be reported
    # as recoverable waste; 10,000 free seats would otherwise dominate the R3 counter.
    $skuBillableMap = @{}
    foreach ($c in @($catalogJson.skus)) {
        $skuPartKey = [string]$c.skuPartNumber
        $skuPriceMap[$skuPartKey] = [double]$c.usdPerUserMonth
        $skuNameMap[$skuPartKey]  = [string]$c.name
        $wasteProp = $c.PSObject.Properties['countsAsWaste']
        $skuBillableMap[$skuPartKey] = if ($wasteProp) { [bool]$wasteProp.Value } else { $true }
    }

    if (-not $SubscribedSkus -and (Get-MgContext -ErrorAction SilentlyContinue)) {
        $subResp = Invoke-MgGraphRequest -Method GET -Uri 'https://graph.microsoft.com/v1.0/subscribedSkus' -ErrorAction SilentlyContinue
        if ($subResp -and $subResp.value) { $SubscribedSkus = @($subResp.value) }
    }
    foreach ($s in @($SubscribedSkus | Where-Object { $null -ne $_ })) {
        if ($s.PSObject.Properties['skuId'] -and $s.skuId) {
            $skuGuidToPart[[string]$s.skuId] = [string]$s.skuPartNumber
        } elseif ($s -is [hashtable] -and $s['skuId']) {
            $skuGuidToPart[[string]$s['skuId']] = [string]$s['skuPartNumber']
        }
    }

    $signInChecked = $false
    if (-not $Users -and (Get-MgContext -ErrorAction SilentlyContinue)) {
        try {
            $Users = @(Get-TenantBriefGraphCollection -Uri 'https://graph.microsoft.com/v1.0/users?$select=id,displayName,userPrincipalName,accountEnabled,userType,assignedLicenses,signInActivity&$top=999' -ErrorAction Stop)
            $signInChecked = $true
        } catch {
            Write-Verbose "signInActivity alani okunamadi, pasif kullanici analizi atlanacak: $($_.Exception.Message)"
            $signInChecked = $false
            try {
                $Users = @(Get-TenantBriefGraphCollection -Uri 'https://graph.microsoft.com/v1.0/users?$select=id,displayName,userPrincipalName,accountEnabled,userType,assignedLicenses&$top=999' -ErrorAction SilentlyContinue)
            } catch {
                Write-Verbose "Kullanici listesi okunamadi: $($_.Exception.Message)"
                $Users = $null
            }
        }
        if ($Users -and $Users.Count -eq 0) { $Users = $null }
    } else {
        $signInChecked = $true
    }

    $disabledCount = 0; $disabledUsdMo = 0.0
    $inactiveCount = 0; $inactiveUsdMo = 0.0
    $guestCount = 0;    $guestUsdMo = 0.0
    $overlapCount = 0;  $overlapUsdMo = 0.0
    $overlapDetails = @()
    $cutoff = (Get-Date).ToUniversalTime().AddDays(-$InactiveDays)
    $overlaps = @($catalogJson.overlaps)

    foreach ($u in @($Users)) {
        $assigned = @($u.assignedLicenses)
        if ($assigned.Count -eq 0) { continue }

        $parts = @()
        $userMonthlyCost = 0.0
        foreach ($lic in $assigned) {
            $part = $null
            if ($lic.PSObject.Properties['skuPartNumber'] -and $lic.skuPartNumber) { $part = [string]$lic.skuPartNumber }
            elseif ($lic.PSObject.Properties['skuId'] -and $skuGuidToPart.ContainsKey([string]$lic.skuId)) { $part = $skuGuidToPart[[string]$lic.skuId] }
            elseif ($lic -is [hashtable] -and $lic['skuPartNumber']) { $part = [string]$lic['skuPartNumber'] }
            elseif ($lic -is [hashtable] -and $lic['skuId'] -and $skuGuidToPart.ContainsKey([string]$lic['skuId'])) { $part = $skuGuidToPart[[string]$lic['skuId']] }
            if ($part) {
                $parts += $part
                if ($skuPriceMap.ContainsKey($part)) { $userMonthlyCost += $skuPriceMap[$part] }
            }
        }

        $isEnabled = if ($u.PSObject.Properties['accountEnabled']) { [bool]$u.accountEnabled } else { $true }
        $uType = if ($u.PSObject.Properties['userType']) { [string]$u.userType } else { 'Member' }

        if (-not $isEnabled) {
            $disabledCount++
            $disabledUsdMo += $userMonthlyCost
        } elseif ($uType -eq 'Guest') {
            $guestCount++
            $guestUsdMo += $userMonthlyCost
        } elseif ($signInChecked -and $u.PSObject.Properties['signInActivity'] -and $u.signInActivity -and $u.signInActivity.PSObject.Properties['lastSignInDateTime'] -and $u.signInActivity.lastSignInDateTime) {
            try {
                $lastDt = [DateTime]::Parse([string]$u.signInActivity.lastSignInDateTime).ToUniversalTime()
                if ($lastDt -lt $cutoff) {
                    $inactiveCount++
                    $inactiveUsdMo += $userMonthlyCost
                }
            } catch {}
        }

        if ($parts.Count -gt 1) {
            foreach ($ov in $overlaps) {
                if (($parts -contains [string]$ov.skuA) -and ($parts -contains [string]$ov.skuB)) {
                    $overlapCount++
                    $redCost = if ($skuPriceMap.ContainsKey([string]$ov.redundant)) { $skuPriceMap[[string]$ov.redundant] } else { 0.0 }
                    $overlapUsdMo += $redCost
                    if ($overlapDetails.Count -lt 25) {
                        $overlapDetails += [PSCustomObject]@{
                            Pair      = "$($ov.skuA) + $($ov.skuB)"
                            Redundant = [string]$ov.redundant
                            SavedMo   = $redCost
                            Reason    = if ($Language -eq 'tr') { [string]$ov.reasonTr } else { [string]$ov.reasonEn }
                        }
                    }
                }
            }
        }
    }

    $unassignedUsdMo = 0.0
    $unassignedSeats = 0
    foreach ($s in @($SubscribedSkus | Where-Object { $null -ne $_ -and $_.PSObject.Properties['skuPartNumber'] })) {
        $part = [string]$s.skuPartNumber
        $en = [int]$s.prepaidUnits.enabled
        $con = [int]$s.consumedUnits
        $isBillable = if ($skuBillableMap.ContainsKey($part)) { [bool]$skuBillableMap[$part] } else { $true }
        if ($isBillable -and $en -gt $con) {
            $diff = $en - $con
            $unassignedSeats += $diff
            if ($skuPriceMap.ContainsKey($part)) { $unassignedUsdMo += ($diff * $skuPriceMap[$part]) }
        }
    }

    $totalRecMo = [Math]::Round($unassignedUsdMo + $disabledUsdMo + $overlapUsdMo, 2)
    return [PSCustomObject]@{
        SignInActivityAvailable = $signInChecked
        UnassignedSeats         = $unassignedSeats
        UnassignedUsdMo         = [Math]::Round($unassignedUsdMo, 2)
        DisabledLicensedUsers   = $disabledCount
        DisabledUsdMo           = [Math]::Round($disabledUsdMo, 2)
        Inactive90dUsers        = $inactiveCount
        InactiveUsdMo           = [Math]::Round($inactiveUsdMo, 2)
        LicensedGuests          = $guestCount
        GuestUsdMo              = [Math]::Round($guestUsdMo, 2)
        DuplicateOverlapCount   = $overlapCount
        DuplicateOverlapUsdMo   = [Math]::Round($overlapUsdMo, 2)
        OverlapSamples          = @($overlapDetails)
        TotalRecoverableUsdMo   = $totalRecMo
        TotalRecoverableUsdYr   = [Math]::Round($totalRecMo * 12, 2)
    }
}

function Get-TenantBriefCopilotReadiness {
    <#
    .SYNOPSIS
    Evaluates M365 Copilot / Agent 365 readiness with L1-L4 maturity and warnings.

    .DESCRIPTION
    Combines live Graph signals (eligible base suites, Copilot seats, guest boundaries,
    Purview labels, app consent) with optional FastTrack JSON input via
    -InputFastTrackJsonPath. Use -OfflineOnly to evaluate purely from supplied data.

    .EXAMPLE
    Get-TenantBriefCopilotReadiness -Language tr -OfflineOnly
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory = $false)]
        [object[]]$SubscribedSkus,

        [Parameter(Mandatory = $false)]
        [object]$TenantInsights,

        [Parameter(Mandatory = $false)]
        [string]$InputFastTrackJsonPath,

        [Parameter(Mandatory = $false)]
        [ValidateSet('tr', 'en')]
        [string]$Language = 'tr',

        [Parameter(Mandatory = $false)]
        [switch]$OfflineOnly
    )

    $isTr = ($Language -eq 'tr')
    $checks = @()
    $warnings = @()
    $copilotSeats = 0
    $eligibleBaseSeats = 0
    $eligibleList = @('SPE_E5','SPE_E3','SPB','O365_BUSINESS_PREMIUM','O365_BUSINESS_ESSENTIALS','ENTERPRISEPACK','ENTERPRISEPREMIUM','STANDARDPACK','M365_F3','SPE_F1','O365_BUSINESS','OFFICESUBSCRIPTION','DEVELOPERPACK_E5','M365EDU_A3_FACULTY','M365EDU_A5_FACULTY')

    $ftData = $null
    if ($InputFastTrackJsonPath -and (Test-Path $InputFastTrackJsonPath)) {
        try { $ftData = Get-Content -Path $InputFastTrackJsonPath -Raw -Encoding UTF8 | ConvertFrom-Json } catch {}
    }

    $hasLiveGraph = (-not $OfflineOnly) -and [bool](Get-MgContext -ErrorAction SilentlyContinue)
    if ($hasLiveGraph -and -not $SubscribedSkus) {
        try {
            $subResp = Invoke-MgGraphRequest -Method GET -Uri 'https://graph.microsoft.com/v1.0/subscribedSkus' -ErrorAction SilentlyContinue
            if ($subResp -and $subResp.value) { $SubscribedSkus = @($subResp.value) }
        } catch {}
    }

    $validSkus = @($SubscribedSkus | Where-Object { $null -ne $_ -and ($_.PSObject.Properties['skuPartNumber'] -or ($_ -is [hashtable] -and $_['skuPartNumber'])) })
    if ($validSkus.Count -gt 0) {
        foreach ($s in $validSkus) {
            $part = [string]$s.skuPartNumber
            $en = if ($s.PSObject.Properties['prepaidUnits'] -and $s.prepaidUnits) { [int]$s.prepaidUnits.enabled } else { 0 }
            if ($eligibleList -contains $part) { $eligibleBaseSeats += $en }
            if ($part -match 'Copilot|COPILOT') { $copilotSeats += $en }
        }
        $checks += [PSCustomObject]@{
            Id          = 'COP-LIC-01'
            Category    = if ($isTr) { 'Lisans Uygunluğu' } else { 'License Eligibility' }
            Status      = if ($eligibleBaseSeats -gt 0) { 'Pass' } else { 'Fail' }
            Title       = if ($isTr) { 'Copilot Temel Lisans Önkoşulu' } else { 'Copilot Eligible Base Licenses' }
            Detail      = if ($isTr) { "Uygun temel koltuk: $eligibleBaseSeats · Aktif Copilot lisansı: $copilotSeats" } else { "Eligible base seats: $eligibleBaseSeats · Copilot seats: $copilotSeats" }
            Explanation = if ($isTr) { 'Microsoft 365 Copilot eklentisi yalnızca E3/E5, Business Standard/Premium veya F1/F3 temel paketlerinin üzerine atanabilir.' } else { 'Microsoft 365 Copilot add-ons require qualifying E3/E5, Business Standard/Premium, or F1/F3 base suites.' }
            Warning     = if ($eligibleBaseSeats -eq 0) { if ($isTr) { 'Uygun temel M365/O365 paketi bulunamadı.' } else { 'No qualifying base Microsoft 365 suite found.' } } else { '' }
        }
    } elseif ($ftData -and $ftData.PSObject.Properties['Licensing']) {
        $checks += [PSCustomObject]@{
            Id          = 'COP-LIC-FT'
            Category    = if ($isTr) { 'Lisans Uygunluğu (FastTrack)' } else { 'License Eligibility (FastTrack)' }
            Status      = if ($ftData.Licensing.EligibleBaseLicenses) { 'Pass' } else { 'Warning' }
            Title       = if ($isTr) { 'FastTrack Lisans Envanteri İçe Aktarıldı' } else { 'FastTrack Licensing Snapshot Imported' }
            Detail      = "Eligible SKUs: $(@($ftData.Licensing.EligibleBaseLicenses).Count)"
            Explanation = if ($isTr) { 'Harici FastTrack Get-M365CopilotReadiness JSON çıktısından lisans uygunluğu okundu.' } else { 'Imported base license readiness from FastTrack Get-M365CopilotReadiness JSON.' }
            Warning     = ''
        }
    } else {
        $checks += [PSCustomObject]@{
            Id          = 'COP-LIC-01'
            Category    = if ($isTr) { 'Lisans Uygunluğu' } else { 'License Eligibility' }
            Status      = 'Warning'
            Title       = if ($isTr) { 'Copilot ve Temel Lisans Kontrolü (Canlı Oturum Gerekir)' } else { 'Copilot Base License Check (Requires Live Session)' }
            Detail      = if ($isTr) { 'Çevrimdışı analizde subscribedSkus verisi yer almaz.' } else { 'Offline report mode lacks subscribedSkus Graph payload.' }
            Explanation = if ($isTr) { 'Gerçek satın alınan/atanan Copilot ve E3/E5 koltuk sayıları Connect-TenantBrief sonrası canlı çekilir.' } else { 'Actual purchased vs. assigned Copilot & E3/E5 seats are pulled live after Connect-TenantBrief.' }
            Warning     = if ($isTr) { 'Gerçek lisans dağılımı için canlı tarama çalıştırın.' } else { 'Run a live tenant scan for actual SKU counts.' }
        }
    }

    # 2. Entra ID AuthorizationPolicy & External Guest Sharing
    if ($hasLiveGraph) {
        try {
            $authPol = Invoke-MgGraphRequest -Method GET -Uri 'https://graph.microsoft.com/v1.0/policies/authorizationPolicy' -ErrorAction Stop
            $invFrom = [string]$authPol.allowInvitesFrom
            $guestRole = [string]$authPol.guestUserRoleId
            $restrictedGuestRole = '2af84b1e-32c8-42b7-82bc-daa82404023b'
            $invSafe = ($invFrom -in @('adminsAndGuestInviters', 'adminsGuestInvitersAndAllMembers', 'none')) -and ($invFrom -ne 'everyone')
            $roleSafe = ($guestRole -eq $restrictedGuestRole)
            $checks += [PSCustomObject]@{
                Id          = 'COP-ENTRA-01'
                Category    = if ($isTr) { 'Dış Paylaşım & Misafir Sınırı' } else { 'Guest & External Sharing Boundary' }
                Status      = if ($invSafe -and $roleSafe) { 'Pass' } elseif ($invFrom -eq 'everyone') { 'Fail' } else { 'Warning' }
                Title       = if ($isTr) { 'Entra ID Misafir Davet ve Dizin Erişim İzni' } else { 'Entra ID Guest Invitations & Directory Access' }
                Detail      = "allowInvitesFrom=$invFrom | guestUserRoleId=$guestRole"
                Explanation = if ($isTr) { 'Copilot içerik indeksleme sırasında dış konuk kullanıcıların bulunduğu Teams kanalları ve SharePoint siteleri aşırı paylaşım riskini artırır.' } else { 'Overly permissive guest invitations and member-level guest directory permissions widen Copilot oversharing blast radius.' }
                Warning     = if ($invFrom -eq 'everyone') {
                    $w = if ($isTr) { 'KRİTİK UYARI: Misafir davet politikası "everyone" (herkes) olarak açık — Copilot öncesi yalnızca yöneticilerle sınırlandırılmalıdır.' } else { 'CRITICAL WARNING: Guest invitations allow "everyone" — restrict before Copilot rollout.' }
                    $warnings += $w; $w
                } elseif (-not $roleSafe) {
                    $w = if ($isTr) { 'UYARI: Misafir rolü en kısıtlı düzeye (2af84b1e...) çekilmemiş; dizin taraması açık olabilir.' } else { 'WARNING: Guest user role is not set to most restricted (2af84b1e...).' }
                    $warnings += $w; $w
                } else { '' }
            }
        } catch {}

        try {
            $permPol = Invoke-MgGraphRequest -Method GET -Uri 'https://graph.microsoft.com/v1.0/policies/authorizationPolicy' -ErrorAction SilentlyContinue
            $defRole = Get-TenantBriefPropertyValue -Object $permPol -Name 'defaultUserRolePermissions'
            $defaultPerms = @(Get-TenantBriefPropertyValue -Object $defRole -Name 'permissionGrantPoliciesAssigned' | Where-Object { $_ })
            $userCanConsent = @($defaultPerms | Where-Object { $_ -like 'ManagePermissionGrantsForSelf.microsoft-user-default-legacy*' }).Count -gt 0
            $polText = if ($defaultPerms.Count -gt 0) { $defaultPerms -join ', ' } else { if ($isTr) { 'Kullanıcı onayı kısıtlı (boş liste)' } else { 'Restricted (empty policy list)' } }
            $checks += [PSCustomObject]@{
                Id          = 'COP-APP-01'
                Category    = if ($isTr) { 'Uygulama & Ajan Onay Yönetişimi' } else { 'App & Agent Consent Governance' }
                Status      = if (-not $userCanConsent) { 'Pass' } else { 'Fail' }
                Title       = if ($isTr) { 'Kullanıcıların Üçüncü Taraf Uygulama / Ajan Onay Yetkisi' } else { 'End-User Third-Party App & Plugin Consent' }
                Detail      = "Policies: $polText"
                Explanation = if ($isTr) { 'Son kullanıcıların onayı serbestse kontrolsüz Copilot eklentileri ve OAuth ajanları kurumsal verilere erişim talep edebilir.' } else { 'Unrestricted user OAuth consent allows unvetted Copilot plugins and third-party agents to access tenant data.' }
                Warning     = if ($userCanConsent) {
                    $w = if ($isTr) { 'UYARI: Son kullanıcılar varsayılan uygulama onayı verebiliyor; Yönetici Onay İş Akışı (Admin Consent) açılmalıdır.' } else { 'WARNING: Legacy user app consent is enabled; enforce Admin Consent Workflow.' }
                    $warnings += $w; $w
                } else { '' }
            }
        } catch {}

        $labelCount = 0
        try {
            $lblResp = Invoke-MgGraphRequest -Method GET -Uri 'https://graph.microsoft.com/beta/security/informationProtection/sensitivityLabels' -ErrorAction Stop
            if ($lblResp -and $lblResp.value) { $labelCount = @($lblResp.value).Count }
        } catch {
            try {
                if (Get-Command Get-Label -ErrorAction SilentlyContinue) { $labelCount = @(Get-Label -ErrorAction SilentlyContinue).Count }
            } catch {}
        }
        $checks += [PSCustomObject]@{
            Id          = 'COP-PURVIEW-01'
            Category    = if ($isTr) { 'Purview Etiketleme & Aşırı Paylaşım Kalkanı' } else { 'Purview Labels & Oversharing Shield' }
            Status      = if ($labelCount -gt 0) { 'Pass' } else { 'Fail' }
            Title       = if ($isTr) { 'Microsoft Purview Hassasiyet Etiketleri (Sensitivity Labels)' } else { 'Microsoft Purview Sensitivity Labels Coverage' }
            Detail      = if ($isTr) { "Algılanan etiket sayısı: $labelCount" } else { "Detected sensitivity labels: $labelCount" }
            Explanation = if ($isTr) { 'Copilot yanıt üretirken dosya şifreleme ve etiket haklarını dikkate alır; etiketsiz ortamlarda hassas dokümanlar geniş kitlelerce özetlenebilir.' } else { 'Copilot honors Purview label encryption and extraction rights; without labels, sensitive files remain exposed to broad internal discovery.' }
            Warning     = if ($labelCount -eq 0) {
                $w = if ($isTr) { 'KRİTİK UYARI: Purview Hassasiyet Etiketi algılanmadı! Copilot dağıtımı öncesi etiketleme ve Restricted SharePoint Search değerlendirilmelidir.' } else { 'CRITICAL WARNING: Zero Purview sensitivity labels detected! Deploy labeling and Restricted Content Discovery before Copilot.' }
                $warnings += $w; $w
            } else { '' }
        }
    }

    # 3. SharePoint RAC / Restricted Content Discovery check (Live SPO or FastTrack snapshot or explicit warning)
    if ($ftData -and $ftData.PSObject.Properties['SharePoint']) {
        $racCount = if ($ftData.SharePoint.PSObject.Properties['RacPolicySites']) { @($ftData.SharePoint.RacPolicySites).Count } else { 0 }
        $rcdCount = if ($ftData.SharePoint.PSObject.Properties['RestrictedSites']) { @($ftData.SharePoint.RestrictedSites).Count } else { 0 }
        $checks += [PSCustomObject]@{
            Id          = 'COP-SPO-FT'
            Category    = if ($isTr) { 'SharePoint RAC & İçerik Kısıtlama' } else { 'SharePoint RAC & Content Discovery' }
            Status      = if ($racCount -gt 0 -or $rcdCount -gt 0) { 'Pass' } else { 'Warning' }
            Title       = if ($isTr) { 'SharePoint RAC ve Kısıtlı İçerik Keşfi (FastTrack)' } else { 'SharePoint RAC & Restricted Content Discovery' }
            Detail      = "RAC Sites: $racCount | Restricted Discovery Sites: $rcdCount"
            Explanation = if ($isTr) { 'FastTrack SharePoint verisine göre aşırı paylaşım koruması (SAM RAC / RCD) uygulanmış site sayıları.' } else { 'Site counts protected by Restricted Access Control (RAC) or Restricted Content Discovery from FastTrack export.' }
            Warning     = if ($racCount -eq 0 -and $rcdCount -eq 0) { if ($isTr) { 'UYARI: Hiçbir SharePoint sitesinde RAC/RCD kısıtı bulunmadı.' } else { 'WARNING: No SharePoint sites have RAC/RCD restrictions.' } } else { '' }
        }
    } else {
        $spoEvaluated = $false
        $spoAvail = [bool](Get-Command Get-SPOTenant -ErrorAction SilentlyContinue)
        if ($spoAvail -and $hasLiveGraph) {
            try {
                $spoT = Get-SPOTenant -ErrorAction Stop
                $rssMode = if ($spoT.PSObject.Properties['RestrictedSearchMode']) { [string]$spoT.RestrictedSearchMode } else { 'NotExposed' }
                $shCap = if ($spoT.PSObject.Properties['SharingCapability']) { [string]$spoT.SharingCapability } else { 'Unknown' }
                $aipInt = if ($spoT.PSObject.Properties['EnableAIPIntegration']) { [bool]$spoT.EnableAIPIntegration } else { $false }
                $rss = ($rssMode -eq 'Enabled')
                $spoPermissive = ($shCap -eq 'ExternalUserAndGuestSharing')
                $spoStatus = if ($rss -and -not $spoPermissive) { 'Pass' } else { 'Warning' }
                $spoWarn = if (-not $rss) {
                    if ($isTr) { 'UYARI: Restricted SharePoint Search etkin değil (veya kiracı özelliği kapalı); herkesle paylaşılan siteler taranabilir.' } else { 'WARNING: Restricted SharePoint Search is not enabled; broadly shared sites may be indexed.' }
                } elseif ($spoPermissive) {
                    if ($isTr) { 'UYARI: SharePoint paylaşım kapsamı dış/konuk erişimine açık (ExternalUserAndGuestSharing); RAC/RCD kısıtları doğrulanmalıdır.' } else { 'WARNING: SharePoint SharingCapability allows ExternalUserAndGuestSharing; verify site RAC/RCD restrictions.' }
                } else { '' }
                if ($spoWarn) { $warnings += $spoWarn }
                $checks += [PSCustomObject]@{
                    Id          = 'COP-SPO-01'
                    Category    = if ($isTr) { 'SharePoint Aşırı Paylaşım Kalkanı' } else { 'SharePoint Oversharing Shield' }
                    Status      = $spoStatus
                    Title       = if ($isTr) { 'Restricted SharePoint Search & Paylaşım Durumu' } else { 'Restricted SharePoint Search & Sharing Posture' }
                    Detail      = "SharingCapability=$shCap | RestrictedSearch=$rssMode | AIPIntegration=$aipInt"
                    Explanation = if ($isTr) { 'SharePoint varsayılan paylaşım kapsamı, AIP etiketi bütünleşmesi ve kısıtlı arama modu Copilot indeks sınırını belirler.' } else { 'SharePoint tenant sharing posture, AIP integration, and Restricted Search control Copilot search scope.' }
                    Warning     = $spoWarn
                }
                $spoEvaluated = $true
            } catch {
                $spoEvaluated = $false
            }
        }
        if (-not $spoEvaluated -and $hasLiveGraph) {
            try {
                $spoGraph = Invoke-MgGraphRequest -Method GET -Uri 'https://graph.microsoft.com/v1.0/admin/sharepoint/settings' -ErrorAction Stop
                $shCap = [string](Get-TenantBriefPropertyValue -Object $spoGraph -Name 'sharingCapability')
                $reshare = Get-TenantBriefPropertyValue -Object $spoGraph -Name 'isResharingByExternalUsersEnabled'
                $domMode = [string](Get-TenantBriefPropertyValue -Object $spoGraph -Name 'sharingDomainRestrictionMode')
                if (-not $domMode) { $domMode = 'none' }
                $permissive = ($shCap -eq 'externalUserAndGuestSharing') -or ($reshare -eq $true)
                $spoWarn = if ($permissive) {
                    $wTxt = if ($isTr) {
                        "UYARI: SharePoint dış paylaşımı ($shCap / reshare=$reshare) geniş açık; Copilot dağıtımı öncesi hassas sitelerde RAC/RCD kısıtlaması ve SharePoint Yönetim Merkezi kontrolü önerilir."
                    } else {
                        "WARNING: SharePoint external sharing posture ($shCap / reshare=$reshare) is permissive; verify site-level RAC/RCD restrictions before Copilot rollout."
                    }
                    $warnings += $wTxt
                    $wTxt
                } else { '' }
                $checks += [PSCustomObject]@{
                    Id          = 'COP-SPO-01'
                    Category    = if ($isTr) { 'SharePoint Aşırı Paylaşım Kalkanı' } else { 'SharePoint Oversharing Shield' }
                    Status      = if ($permissive) { 'Warning' } else { 'Pass' }
                    Title       = if ($isTr) { 'SharePoint Paylaşım Sınırı ve Dış Erişim Durumu (Graph API)' } else { 'SharePoint Sharing Boundary & External Access Posture (Graph API)' }
                    Detail      = "SharingCapability=$shCap | ExternalResharing=$reshare | DomainRestriction=$domMode (Graph API)"
                    Explanation = if ($isTr) { 'Microsoft Graph /admin/sharepoint/settings üzerinden okunan varsayılan paylaşım kapsamı ve dış yeniden paylaşım izni Copilot aşırı paylaşım sınırını gösterir; site düzeyi RAC/RCD için SharePoint Online oturumu veya FastTrack JSON bağlanabilir.' } else { 'Tenant sharing capability and external resharing settings retrieved via Microsoft Graph /admin/sharepoint/settings measure oversharing exposure; site-level RAC/RCD checks can be added via SharePoint Online or FastTrack JSON.' }
                    Warning     = $spoWarn
                }
                $spoEvaluated = $true
            } catch {
                $spoEvaluated = $false
            }
        }
        if (-not $spoEvaluated) {
            $w = if ($isTr) { 'BİLGİ/UYARI: SharePoint Online modülü bağlı olmadığı için RAC / Restricted Content Discovery kontrolü otomatik yapılamadı; FastTrack Get-M365CopilotReadiness.ps1 çıktısını -InputFastTrackJsonPath ile bağlayabilir veya SharePoint yönetim merkezinden doğrulayabilirsiniz.' } else { 'NOTICE/WARNING: SharePoint Online module is not connected; RAC / Restricted Content Discovery could not be queried directly. Pass -InputFastTrackJsonPath or verify in SharePoint Admin Center.' }
            $warnings += $w
            $checks += [PSCustomObject]@{
                Id          = 'COP-SPO-01'
                Category    = if ($isTr) { 'SharePoint Aşırı Paylaşım Kalkanı' } else { 'SharePoint Oversharing Shield' }
                Status      = 'Warning'
                Title       = if ($isTr) { 'SharePoint RAC / Restricted Content Discovery Kontrolü' } else { 'SharePoint RAC / Restricted Content Discovery' }
                Detail      = if ($isTr) { 'SharePoint Online bağlantısı yok (kısmi kapsam)' } else { 'SharePoint Online not connected (partial scope)' }
                Explanation = if ($isTr) { 'Copilot dağıtımında İK/Finans gibi hassas sitelerde Restricted Access Control (RAC) ve Site Permission Review zorunludur.' } else { 'Sensitive SharePoint sites require Restricted Access Control (RAC) and permission audits prior to Copilot enablement.' }
                Warning     = $w
            }
        }
    }

    # 4. AI Agents & Guest Ratios from TenantInsights
    if ($TenantInsights) {
        $uCnt = [int]$TenantInsights.UserCount
        $gCnt = [int]$TenantInsights.GuestCount
        $agCnt = [int]$TenantInsights.TotalAgents
        $guestPct = if ($uCnt -gt 0) { [Math]::Round(($gCnt / $uCnt) * 100, 1) } else { 0 }
        $checks += [PSCustomObject]@{
            Id          = 'COP-AGENT-01'
            Category    = if ($isTr) { 'Ajan 365 & Misafir Yoğunluğu' } else { 'Agent 365 & Guest Exposure' }
            Status      = if ($guestPct -le 15) { 'Pass' } else { 'Warning' }
            Title       = if ($isTr) { 'Kiracı Misafir Oranı ve Aktif AI Ajan Envanteri' } else { 'Tenant Guest Ratio & Active AI Agent Inventory' }
            Detail      = if ($isTr) { "Kullanıcı: $uCnt | Misafir: $gCnt (%$guestPct) | AI Ajanı: $agCnt" } else { "Users: $uCnt | Guests: $gCnt ($guestPct%) | AI Agents: $agCnt" }
            Explanation = if ($isTr) { 'Yüksek harici misafir oranı ve yönetişimsiz Copilot Studio / A365 ajanları veri sınırlarını zorlayabilir.' } else { 'High guest ratios and ungoverned AI Agents expand internal and external data access paths.' }
            Warning     = if ($guestPct -gt 15) { if ($isTr) { "UYARI: Kiracıdaki misafir oranı (%$guestPct) yüksek; düzenli Access Reviews önerilir." } else { "WARNING: High guest ratio ($guestPct%); enable Entra Access Reviews." } } else { '' }
        }
    }

    $passC = @($checks | Where-Object { $_.Status -eq 'Pass' }).Count
    $totC = [Math]::Max(1, $checks.Count)
    $readinessScore = [Math]::Round(($passC / $totC) * 100, 1)
    $maturity = if ($isTr) {
        if ($readinessScore -ge 85) { 'L4 - Yönetilen (Managed)' } elseif ($readinessScore -ge 65) { 'L3 - Tanımlı (Defined)' } elseif ($readinessScore -ge 40) { 'L2 - Tekrarlanabilir (Repeatable)' } else { 'L1 - Başlangıç (Initial)' }
    } else {
        if ($readinessScore -ge 85) { 'L4 - Managed' } elseif ($readinessScore -ge 65) { 'L3 - Defined' } elseif ($readinessScore -ge 40) { 'L2 - Repeatable' } else { 'L1 - Initial' }
    }

    return [PSCustomObject]@{
        Score              = $readinessScore
        MaturityLevel      = $maturity
        EligibleBaseSeats  = $eligibleBaseSeats
        CopilotSeats       = $copilotSeats
        FastTrackImported  = ($null -ne $ftData)
        Warnings           = @($warnings | Where-Object { $_ } | Select-Object -Unique)
        Checks             = @($checks)
    }
}

Set-Alias -Name Connect-ZtLens -Value Connect-TenantBrief -Force
Set-Alias -Name Invoke-ZtLensAssessment -Value Invoke-TenantBriefAssessment -Force
Set-Alias -Name Get-ZtLensFrameworks -Value Get-TenantBriefFrameworks -Force
Set-Alias -Name Get-ZtLensLicenseRoi -Value Get-TenantBriefLicenseRoi -Force
Set-Alias -Name Get-ZtLensLicenseWaste -Value Get-TenantBriefLicenseWaste -Force
Set-Alias -Name Get-ZtLensCopilotReadiness -Value Get-TenantBriefCopilotReadiness -Force
Set-Alias -Name Compare-ZtLensReports -Value Compare-TenantBriefReports -Force
Set-Alias -Name Export-ZtLensExecutiveSummary -Value Export-TenantBriefExecutiveSummary -Force

Export-ModuleMember `
    -Function Connect-TenantBrief, Invoke-TenantBriefAssessment, Get-TenantBriefFrameworks, Get-TenantBriefLicenseRoi, Get-TenantBriefLicenseWaste, Get-TenantBriefCopilotReadiness, Compare-TenantBriefReports, Export-TenantBriefExecutiveSummary `
    -Alias Connect-ZtLens, Invoke-ZtLensAssessment, Get-ZtLensFrameworks, Get-ZtLensLicenseRoi, Get-ZtLensLicenseWaste, Get-ZtLensCopilotReadiness, Compare-ZtLensReports, Export-ZtLensExecutiveSummary
