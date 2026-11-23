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
        [ValidateSet('All', 'ZeroTrust', 'CIS_M365', 'CISA_SCuBA', 'MDO_ORCA', 'EIDSCA', 'Maester', 'EntraFalcon', 'FastTrack')]
        [string]$Framework = 'All',

        [Parameter()]
        [switch]$Anonymize,

        [Parameter()]
        [switch]$NoBrowser,

        [Parameter()]
        [object]$TranslatorKey = $env:AZURE_TRANSLATOR_KEY,

        [Parameter()]
        [string]$InputFastTrackJsonPath,

        [Parameter()]
        [string]$InputSharePointRiskCsvPath,

        [Parameter()]
        [string]$InputPowerPlatformAgentsPath,

        [Parameter()]
        [string]$InputScubaJsonPath,

        [Parameter()]
        [string]$InputOrcaJsonPath,

        [Parameter()]
        [string]$InputMaesterJsonPath,

        [Parameter()]
        [string]$InputEntraFalconJsonPath,

        [Parameter()]
        [string]$PreviousReportJson,

        [Parameter()]
        [switch]$SkipMaester,

        [Parameter()]
        [switch]$ScubaInteractiveLogin,

        [Parameter()]
        [ValidateSet('aad', 'securitysuite', 'exo', 'sharepoint', 'teams', 'powerplatform', 'powerbi')]
        [string[]]$ScubaProducts = @('aad', 'securitysuite', 'exo', 'sharepoint', 'teams', 'powerplatform', 'powerbi'),

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
    $collectedTests = [System.Collections.Generic.List[object]]::new()
    if (-not $InputReportJson) {
        $accountName = if ($mgCheck -and $mgCheck.Account) { [string]$mgCheck.Account } else { '' }
        foreach ($ct in @(Invoke-TenantBriefBaselineCollections -OutputPath $OutputPath -Account $accountName -Log $addLog -State $progressState -Diagnostics $diagnostics -Manifest $manifest -ManifestPath $manifestPath -SkipMaester:$SkipMaester -ScubaInteractiveLogin:$ScubaInteractiveLogin -ScubaProducts $ScubaProducts)) {
            if ($null -ne $ct) { $collectedTests.Add($ct) }
        }
    } else {
        $scubaSource = if ($InputScubaJsonPath) { $InputScubaJsonPath } else { Join-Path $OutputPath 'raw-scuba' }
        $scubaLoaded = @()
        if ($scubaSource -and (Test-Path $scubaSource)) {
            $scubaLoaded = @(Import-TenantBriefScubaResults -Path $scubaSource | Where-Object { $null -ne $_ })
        }
        if ($scubaLoaded.Count -gt 0) {
            foreach ($sItem in $scubaLoaded) { $collectedTests.Add($sItem) }
            & $markStage 2 'CISA ScubaGear' 'completed' "Reused cached ScubaGear output ($($scubaLoaded.Count) controls)."
        } else {
            & $markStage 2 'CISA ScubaGear' 'skipped' 'Offline mode: -InputReportJson supplied, ScubaGear was not executed.'
        }

        $orcaSource = if ($InputOrcaJsonPath) { $InputOrcaJsonPath } else { Join-Path $OutputPath 'raw-orca' }
        $orcaLoaded = @()
        if ($orcaSource -and (Test-Path $orcaSource)) {
            $orcaLoaded = @(Import-TenantBriefOrcaResults -Path $orcaSource | Where-Object { $null -ne $_ })
        }
        if ($orcaLoaded.Count -gt 0) {
            foreach ($oItem in $orcaLoaded) { $collectedTests.Add($oItem) }
            & $markStage 3 'Microsoft ORCA & Maester' 'completed' "Reused cached ORCA output ($($orcaLoaded.Count) controls)."
        } else {
            & $markStage 3 'Microsoft ORCA' 'skipped' 'Offline mode: -InputReportJson supplied, ORCA was not executed.'
        }
    }
    if ($InputMaesterJsonPath) {
        if (Test-Path $InputMaesterJsonPath) {
            foreach ($mItem in @(Import-TenantBriefMaesterResults -JsonPath $InputMaesterJsonPath | Where-Object { $null -ne $_ })) { $collectedTests.Add($mItem) }
        } else {
            Add-TenantBriefDiagnostic -Diagnostics $diagnostics -Stage 3 -Component 'Maester' -Message "Belirtilen Maester JSON bulunamadi: $InputMaesterJsonPath"
        }
    } elseif ($InputReportJson) {
        $resumeMaester = Join-Path $OutputPath 'raw-maester/MaesterResults.json'
        if (Test-Path $resumeMaester) {
            $maesterLoaded = @(Import-TenantBriefMaesterResults -JsonPath $resumeMaester | Where-Object { $null -ne $_ })
            if ($maesterLoaded.Count -gt 0) {
                foreach ($mItem in $maesterLoaded) { $collectedTests.Add($mItem) }
                & $markStage 3 'Microsoft ORCA & Maester' 'completed' "Reused cached baseline outputs (Maester: $($maesterLoaded.Count) controls)."
            }
        }
    }
    if ($InputEntraFalconJsonPath) {
        if (Test-Path $InputEntraFalconJsonPath) {
            foreach ($efItem in @(Import-TenantBriefEntraFalconFindings -JsonPath $InputEntraFalconJsonPath | Where-Object { $null -ne $_ })) { $collectedTests.Add($efItem) }
        } else {
            Add-TenantBriefDiagnostic -Diagnostics $diagnostics -Stage 3 -Component 'EntraFalcon' -Message "Belirtilen EntraFalcon JSON bulunamadi: $InputEntraFalconJsonPath"
        }
    } else {
        $efAuto = Get-ChildItem -Path $OutputPath -Filter 'tenant_findings_all_*.json' -File -ErrorAction SilentlyContinue |
            Sort-Object LastWriteTime -Descending | Select-Object -First 1
        if ($efAuto) {
            foreach ($efItem in @(Import-TenantBriefEntraFalconFindings -JsonPath $efAuto.FullName | Where-Object { $null -ne $_ })) { $collectedTests.Add($efItem) }
        }
    }
    $sharePointRiskSummary = $null
    if ($InputSharePointRiskCsvPath) {
        if (Test-Path $InputSharePointRiskCsvPath) {
            $spRiskRes = Import-TenantBriefSharePointRisk -CsvPath $InputSharePointRiskCsvPath -Language $Language
            if ($spRiskRes) {
                $sharePointRiskSummary = $spRiskRes.Summary
                if ($spRiskRes.Findings) { foreach ($spItem in @($spRiskRes.Findings | Where-Object { $null -ne $_ })) { $collectedTests.Add($spItem) } }
            }
        } else {
            Add-TenantBriefDiagnostic -Diagnostics $diagnostics -Stage 3 -Component 'FastTrackSharePointRisk' -Message "Belirtilen SharePoint Risk CSV bulunamadi: $InputSharePointRiskCsvPath"
        }
    }
    $ppAgentsSummary = $null
    if ($InputPowerPlatformAgentsPath) {
        if (Test-Path $InputPowerPlatformAgentsPath) {
            $ppRes = Import-TenantBriefPowerPlatformAgents -Path $InputPowerPlatformAgentsPath -Language $Language
            if ($ppRes) {
                $ppAgentsSummary = $ppRes.Summary
                if ($ppRes.Findings) { foreach ($ppItem in @($ppRes.Findings | Where-Object { $null -ne $_ })) { $collectedTests.Add($ppItem) } }
            }
        } else {
            Add-TenantBriefDiagnostic -Diagnostics $diagnostics -Stage 3 -Component 'FastTrackPowerPlatformAgents' -Message "Belirtilen Power Platform ajan envanteri bulunamadi: $InputPowerPlatformAgentsPath"
        }
    }
    $rawAllTests = @((@($ztTests) + @($collectedTests.ToArray())) | Where-Object { $null -ne $_ })
    $allCorrelatedTests = @(New-TenantBriefCorrelatedTests -Tests $rawAllTests)
    $plannedTests = @($allCorrelatedTests | Where-Object { $_.TestStatus -eq 'Planned' })
    $tests = @($allCorrelatedTests | Where-Object { $_.TestStatus -ne 'Planned' })
    $progressState.Stage = 4
    & $markStage 4 'Correlation & scoring' 'started' ''
    & $addLog "[Stage 4/5] Computing License ROI, Secure Score & Multi-Framework Scores..."

    $passedCount = @($tests | Where-Object { $_.TestStatus -eq 'Passed' }).Count
    $failedCount = @($tests | Where-Object { $_.TestStatus -eq 'Failed' }).Count
    $investigateCount = @($tests | Where-Object { $_.TestStatus -eq 'Investigate' }).Count
    $skippedCount = @($tests | Where-Object { $_.TestStatus -eq 'Skipped' }).Count
    $plannedCount = 0
    $plannedExcludedCount = $plannedTests.Count
    $errorCount = @($tests | Where-Object { $_.TestStatus -eq 'Error' }).Count
    $highRiskFailed = @($tests | Where-Object { $_.TestStatus -eq 'Failed' -and $_.TestRisk -in @('Critical', 'High') }).Count

    $allFwIds = @($fwConfig.PSObject.Properties | ForEach-Object { $_.Name })
    $selectedFwIds = if ($Framework -eq 'All') { $allFwIds } else { @($Framework) }
    $frameworkCards = @(Get-TenantBriefFrameworkScorecard -Tests $rawAllTests -FrameworkConfig $fwConfig -FrameworkIds $selectedFwIds -Language $Language)
    if ($Framework -eq 'All') {
        $frameworkCards = @($frameworkCards | Where-Object { $_.Total -gt 0 })
    }
    $scubaProdManifest = if ($manifest -and $manifest.PSObject.Properties['ScubaProducts'] -and $manifest.ScubaProducts) { $manifest.ScubaProducts } else { $null }
    if ($scubaProdManifest -and @($scubaProdManifest.Skipped).Count -gt 0) {
        $execCnt = @($scubaProdManifest.Executed).Count
        $reqCnt  = @($scubaProdManifest.Requested).Count
        $covNote = if ($Language -eq 'tr') { "$execCnt/$reqCnt ürün tarandı" } else { "$execCnt/$reqCnt products scanned" }
        foreach ($fwCard in $frameworkCards) {
            if ($fwCard.Id -eq 'CISA_SCuBA') {
                $fwCard | Add-Member -NotePropertyName 'CoverageNote' -NotePropertyValue $covNote -Force
            }
        }
    }

    # License ROI & Blind Spot Analysis from SkippedReason
    $licenseGaps = @{}
    foreach ($t in ($tests | Where-Object { $_.TestStatus -eq 'Skipped' })) {
        $reason = [string]$t.SkippedReason
        $meta = if ($reason -match 'Entra_Premium_Internet_Access|Entra_Premium_Private_Access') {
            @{
                Key = if ($Language -eq 'tr') { 'Lisans: Microsoft Entra Internet / Private Access (SSE)' } else { 'License: Microsoft Entra Internet / Private Access (SSE)' }
                Category = 'License'
                Note = if ($Language -eq 'tr') { 'Global Secure Access (SSE) lisansı kiracıda bulunmadığı için ağ erişim kontrolleri atlandı.' } else { 'Global Secure Access (SSE) license is not assigned in this tenant.' }
                Search = 'Entra_Premium_'
            }
        } elseif ($reason -match 'WINDEFATP|MDE_LITE') {
            @{
                Key = if ($Language -eq 'tr') { 'Lisans: Microsoft Defender for Endpoint (P1/P2)' } else { 'License: Microsoft Defender for Endpoint (P1/P2)' }
                Category = 'License'
                Note = if ($Language -eq 'tr') { 'MDE planı kiracıda etkin olmadığı için uç nokta güvenlik kontrolleri çalıştırılamadı.' } else { 'Defender for Endpoint plan is not licensed in this tenant.' }
                Search = 'WINDEFATP'
            }
        } elseif ($reason -match 'Microsoft_365_Copilot|AGENT_365') {
            @{
                Key = if ($Language -eq 'tr') { 'Lisans: Microsoft 365 Copilot / Agent 365' } else { 'License: Microsoft 365 Copilot / Agent 365' }
                Category = 'License'
                Note = if ($Language -eq 'tr') { 'Copilot veya Agent 365 lisansı bulunmadığı için yapay zekâ yönetişim kontrolleri atlandı.' } else { 'Microsoft 365 Copilot or Agent 365 license is not present in the tenant.' }
                Search = 'AGENT_365'
            }
        } elseif ($reason -match 'Workload ID') {
            @{
                Key = if ($Language -eq 'tr') { 'Lisans: Microsoft Entra Workload ID' } else { 'License: Microsoft Entra Workload ID' }
                Category = 'License'
                Note = if ($Language -eq 'tr') { 'Workload ID Premium lisansı olmadığı için hizmet sorumlusu (SPN) risk kontrolleri atlandı.' } else { 'Entra Workload ID license is not present for service principal risk checks.' }
                Search = 'Workload'
            }
        } elseif ($reason -match 'EXCHANGE_S_STANDARD|non-trial licenses|Entra ID Premium') {
            @{
                Key = if ($Language -eq 'tr') { 'Lisans: Exchange Online / Entra ID Premium (Deneme Dışı)' } else { 'License: Exchange Online / Entra ID Premium (Non-Trial)' }
                Category = 'License'
                Note = if ($Language -eq 'tr') { 'Ücretli/deneme dışı Exchange Online veya Entra ID Premium lisansı yetersiz olduğu için atlandı.' } else { 'Required paid Exchange Online or Entra ID Premium license is unavailable.' }
                Search = 'EXCHANGE_S_STANDARD'
            }
        } elseif ($reason -match 'SharePointOnline|Not connected to SharePoint Online') {
            @{
                Key = if ($Language -eq 'tr') { 'Bağlantı Eksikliği: SharePoint Online' } else { 'Disconnected Service: SharePoint Online' }
                Category = 'Connection'
                Note = if ($Language -eq 'tr') { 'SharePoint Online yönetim oturumu bağlı olmadığı için SPO paylaşım ve erişim kontrolleri atlandı.' } else { 'SharePoint Online session was not connected during assessment.' }
                Search = 'SharePoint'
            }
        } elseif ($reason -match 'Not connected to Teams') {
            @{
                Key = if ($Language -eq 'tr') { 'Bağlantı Eksikliği: Microsoft Teams' } else { 'Disconnected Service: Microsoft Teams' }
                Category = 'Connection'
                Note = if ($Language -eq 'tr') { 'MicrosoftTeams PowerShell oturumu kurulmadığı için Teams dış erişim/toplantı kontrolleri atlandı.' } else { 'MicrosoftTeams PowerShell session was not connected.' }
                Search = 'Teams'
            }
        } elseif ($reason -match 'AipService') {
            @{
                Key = if ($Language -eq 'tr') { 'Emekliye Ayrılmış Modül: AIPService (Microsoft Tarafından Kaldırıldı)' } else { 'Retired Module: AIPService (Removed from PSGallery by Microsoft)' }
                Category = 'Scope'
                Note = if ($Language -eq 'tr') { 'Microsoft AIPService modülünü emekliye ayırıp PSGallery''den kaldırdığı için bu eski RMS testi çalıştırılamaz; Purview şifreleme kontrolleri Graph üzerinden ölçülür.' } else { 'Microsoft retired and removed the legacy AIPService module from PSGallery; modern Purview controls are evaluated via Graph.' }
                Search = 'AipService'
            }
        } elseif ($reason -match 'Missing permission scope|Missing Scope|S2SUnauthorized') {
            @{
                Key = if ($Language -eq 'tr') { 'API / Yetki Eksikliği (Graph Scope / S2S)' } else { 'Missing API Permission (Graph Scope / S2S)' }
                Category = 'Permission'
                Note = if ($Language -eq 'tr') { 'Oturumda ilgili salt okunur Graph/Exchange yetki kapsamı onaylanmadığı için sorgu atlandı.' } else { 'Required read-only Graph or Exchange permission scope was not granted to the session.' }
                Search = ''
            }
        } elseif ($reason -match 'No MDE-managed Windows devices|Apple |Android Enterprise|Intune Certificate|Mobile Threat Defense|Windows Feature Update') {
            @{
                Key = if ($Language -eq 'tr') { 'Platform Kullanılmıyor: MDM / Mobil / MDE Cihaz Profili Yok' } else { 'Not Configured: MDM / Mobile / MDE Device Profiles' }
                Category = 'Scope'
                Note = if ($Language -eq 'tr') { 'Kiracıda Apple ADE/APN/VPP, Android Enterprise veya MDE yönetimli Windows cihazı bulunmadığından uygulanamaz.' } else { 'No Apple, Android Enterprise, Intune connector, or MDE-managed devices exist in the tenant.' }
                Search = ''
            }
        } else {
            @{
                Key = if ($Language -eq 'tr') { 'Kapsam Dışı / Özellik Etkin Değil (Not Applicable)' } else { 'Not Applicable / Feature Disabled in Tenant' }
                Category = 'Scope'
                Note = if ($Language -eq 'tr') { 'İlgili özellik (ör. şirket içi AD senkronizasyonu, paylaşımlı posta kutusu, SMS/FIDO2 veya riskli CA) kiracıda kullanılmıyor.' } else { 'Target feature (e.g., on-prem AD sync, shared mailboxes, SMS/FIDO2, or risk CA) is disabled or unused.' }
                Search = ''
            }
        }
        if (-not $licenseGaps.ContainsKey($meta.Key)) {
            $licenseGaps[$meta.Key] = @{
                Count    = 0
                Category = $meta.Category
                Note     = $meta.Note
                Search   = $meta.Search
            }
        }
        $licenseGaps[$meta.Key].Count++
    }

    $roiGapsList = $licenseGaps.GetEnumerator() | Sort-Object -Property @(
        @{ Expression = { $_.Value.Count }; Descending = $true }
        @{ Expression = { $_.Key }; Ascending = $true }
    ) | ForEach-Object {
        [PSCustomObject]@{
            License  = $_.Key
            Count    = $_.Value.Count
            Category = $_.Value.Category
            Note     = $_.Value.Note
            Search   = $_.Value.Search
        }
    }

    $licGapTotal  = @($roiGapsList | Where-Object { $_.Category -eq 'License' } | ForEach-Object { $_.Count } | Measure-Object -Sum).Sum
    $connGapTotal = @($roiGapsList | Where-Object { $_.Category -in @('Connection', 'Permission') } | ForEach-Object { $_.Count } | Measure-Object -Sum).Sum
    $scopeGapTotal = @($roiGapsList | Where-Object { $_.Category -eq 'Scope' } | ForEach-Object { $_.Count } | Measure-Object -Sum).Sum

    $roiSummary = if ($Language -eq 'tr') {
        "Toplam $skippedCount kontrol atlandı: $licGapTotal tanesi lisans eksikliğinden, $connGapTotal tanesi servis bağlantısı veya API yetki eksikliğinden (ölçülemeyen kör nokta), $scopeGapTotal tanesi ise kiracıda ilgili platform/özellik kullanılmadığından kapsam dışı olarak işaretlendi."
    } else {
        "Out of $skippedCount skipped controls, $licGapTotal are blocked by missing licenses, $connGapTotal by disconnected services or missing API scopes (blind spots), and $scopeGapTotal are not applicable because those features/platforms are unused in the tenant."
    }

    $roadmap = @()

    $pillarMap = $null

    # Batch-translate titles & descriptions in chunks of 40 when TranslatorKey is set
    $trCachePath = Join-Path $script:ModuleRoot 'data/tr-translation-cache.json'
    $trCache = @{}
    if ($Language -eq 'tr' -and (Test-Path $trCachePath)) {
        try {
            $loaded = Get-Content -Path $trCachePath -Raw -Encoding UTF8 | ConvertFrom-Json
            foreach ($p in $loaded.PSObject.Properties) { $trCache[$p.Name] = $p.Value }
        } catch {}
    }

    if ($Language -eq 'tr' -and $TranslatorKey) {
        $plainTranslatorKey = ''
        if ($TranslatorKey -is [System.Security.SecureString]) {
            $plainTranslatorKey = [System.Net.NetworkCredential]::new('', $TranslatorKey).Password
        } elseif ($null -ne $TranslatorKey) {
            $plainTranslatorKey = [string]$TranslatorKey
        }
        try {
            $toTranslate = @()
            foreach ($t in $tests) {
                $k = [string]$t.TestId
                if ($k -and -not $trCache.ContainsKey($k)) { $toTranslate += $t }
            }
            if ($plainTranslatorKey -and $toTranslate.Count -gt 0) {
                $rawDomainForTr = if ($raw -and $raw.PSObject.Properties['Domain'] -and $raw.Domain) { [string]$raw.Domain } else { '' }
                Write-Host "[TenantBrief] Translating $($toTranslate.Count) controls via Azure AI Translator..." -ForegroundColor Cyan
                for ($i = 0; $i -lt $toTranslate.Count; $i += 15) {
                    $chunk = $toTranslate[$i..([Math]::Min($i + 14, $toTranslate.Count - 1))]
                    $payload = @()
                    foreach ($item in $chunk) {
                        $tTitle = Protect-TenantBriefSensitiveText -Text ([string]$item.TestTitle) -TenantDomain $rawDomainForTr
                        $dText = [string]$item.TestDescription
                        if ($dText.Length -gt 1000) { $dText = $dText.Substring(0, 1000) }
                        $dText = Protect-TenantBriefSensitiveText -Text $dText -TenantDomain $rawDomainForTr
                        $payload += @{ Text = $tTitle }
                        $payload += @{ Text = $dText }
                    }
                    $jsonBody = $payload | ConvertTo-Json -Compress
                    $trResp = $null
                    for ($attempt = 1; $attempt -le 2; $attempt++) {
                        try {
                            $trResp = Invoke-RestMethod -Method Post -Uri 'https://api.cognitive.microsofttranslator.com/translate?api-version=3.0&from=en&to=tr' -Headers @{
                                'Ocp-Apim-Subscription-Key'    = $plainTranslatorKey
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
                                Title    = [string]$trResp[$j * 2].translations[0].text
                                Desc     = [string]$trResp[$j * 2 + 1].translations[0].text
                                Source   = 'azure'
                                Reviewed = $false
                            }
                        }
                    }
                    Start-Sleep -Seconds 4
                }
                try { $trCache | ConvertTo-Json -Depth 3 | Out-File -FilePath $trCachePath -Encoding UTF8 } catch {}
            }
        } finally {
            $plainTranslatorKey = $null
        }
    }

    $findings = @(New-TenantBriefFindings -Tests $tests -PillarMap $pillarMap -Language $Language -TranslationCache $trCache)
    $plannedFindings = @(New-TenantBriefFindings -Tests $plannedTests -PillarMap $pillarMap -Language $Language -TranslationCache $trCache)

    if ($Anonymize) {
        $rawDomainForMask = if ($raw -and $raw.PSObject.Properties['Domain'] -and $raw.Domain) { [string]$raw.Domain } else { '' }
        $rawTenantNameForMask = if ($raw -and $raw.PSObject.Properties['TenantName'] -and $raw.TenantName) { [string]$raw.TenantName } else { '' }
        foreach ($item in (@($findings) + @($plannedFindings))) {
            foreach ($propName in @('Title', 'Result', 'Description', 'SkippedReason', 'Remediation', 'RemediationTr', 'ErrorRemedy')) {
                if ($item.PSObject.Properties[$propName] -and $item.$propName) {
                    $item.$propName = Protect-TenantBriefSensitiveText -Text ([string]$item.$propName) -TenantDomain $rawDomainForMask -TenantName $rawTenantNameForMask
                }
            }
        }
    }

    $buildPhaseFocus = {
        param([object[]]$Items, [string]$EmptyText)
        if (-not $Items -or $Items.Count -eq 0) { return $EmptyText }
        $topCats = @($Items | Where-Object { $_.Category } | Group-Object Category | Sort-Object -Property @(@{ Expression = 'Count'; Descending = $true }, 'Name') | Select-Object -First 3 | ForEach-Object { "$($_.Name) ($($_.Count))" })
        if ($topCats.Count -gt 0) { return ($topCats -join ' · ') }
        return $EmptyText
    }
    $sortByPrio = @(
        @{ Expression = { [int]$_.PriorityScore }; Descending = $true },
        @{ Expression = { [string]$_.Id }; Descending = $false }
    )
    $p0Items = @($findings | Where-Object { $_.Status -eq 'Failed' -and $_.Risk -in @('Critical', 'High') } | Sort-Object -Property $sortByPrio)
    $p1Items = @($findings | Where-Object { $_.Status -eq 'Failed' -and $_.Risk -eq 'Medium' } | Sort-Object -Property $sortByPrio)
    $p2Items = @($findings | Where-Object { ($_.Status -eq 'Failed' -and $_.Risk -eq 'Low') -or $_.Status -eq 'Investigate' } | Sort-Object -Property $sortByPrio)
    $emptyPhaseMsg = if ($Language -eq 'tr') { 'Bu fazda açık bulgu bulunmuyor' } else { 'No open findings in this phase' }
    $roadmap = @(
        [PSCustomObject]@{
            Phase      = if ($Language -eq 'tr') { '0–30 Gün (Kritik / Quick Wins)' } else { 'Days 0–30 (Critical / Quick Wins)' }
            Count      = $p0Items.Count
            Focus      = (& $buildPhaseFocus $p0Items $emptyPhaseMsg)
            FindingIds = @($p0Items | ForEach-Object { [string]$_.Id })
        },
        [PSCustomObject]@{
            Phase      = if ($Language -eq 'tr') { '31–60 Gün (Orta Risk)' } else { 'Days 31–60 (Medium Risk)' }
            Count      = $p1Items.Count
            Focus      = (& $buildPhaseFocus $p1Items $emptyPhaseMsg)
            FindingIds = @($p1Items | ForEach-Object { [string]$_.Id })
        },
        [PSCustomObject]@{
            Phase      = if ($Language -eq 'tr') { '61–90 Gün (İnceleme & Düşük)' } else { 'Days 61–90 (Investigate & Low)' }
            Count      = $p2Items.Count
            Focus      = (& $buildPhaseFocus $p2Items $emptyPhaseMsg)
            FindingIds = @($p2Items | ForEach-Object { [string]$_.Id })
        }
    )

    $tenantDisplay = if ($Anonymize) { 'contoso.onmicrosoft.com (Anonymized)' } else { [string]$raw.Domain }
    $ti = $raw.PSObject.Properties['TenantInfo'].Value
    $tOverview = if ($ti -and $ti.PSObject.Properties['TenantOverview'].Value) { $ti.TenantOverview } else { $null }
    $mfaDesc = if ($ti -and $ti.PSObject.Properties['OverviewCaMfaAllUsers'].Value) { [string]$ti.OverviewCaMfaAllUsers.description } else { '' }
    if ($Language -eq 'tr' -and $mfaDesc -match 'Over the past (\d+) days,\s*([\d.,]+)%\s*of sign-ins were protected by conditional access policies enforcing multifactor') {
        $mfaDesc = "Son $($Matches[1]) günde oturum açmaların %$($Matches[2]) kadarı çok faktörlü kimlik doğrulama (MFA) zorunlu kılan Koşullu Erişim politikaları ile korundu."
    }
    if ($Anonymize -and $mfaDesc) {
        $tNameMfa = if ($raw -and $raw.PSObject.Properties['TenantName'] -and $raw.TenantName) { [string]$raw.TenantName } else { '' }
        $mfaDesc = Protect-TenantBriefSensitiveText -Text $mfaDesc -TenantDomain ([string]$raw.Domain) -TenantName $tNameMfa
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
    $usageAdoption = $null
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
                try {
                    $usageAdoption = Get-TenantBriefUsageAdoption -Period 'D30' -Language $Language
                } catch {
                    Write-Warning "[TenantBrief] Usage & adoption telemetry warning: $($_.Exception.Message)"
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
                        UsageAdoption      = $usageAdoption
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
            if ($cachedTel.PSObject.Properties['UsageAdoption'] -and $cachedTel.UsageAdoption) { $usageAdoption = $cachedTel.UsageAdoption }
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

    if ($ppAgentsSummary -and $ppAgentsSummary.TotalAgents -gt [int]$tenantInsightObj.TotalAgents) {
        $tenantInsightObj.TotalAgents = [int]$ppAgentsSummary.TotalAgents
    }

    $unreviewedTrCount = if ($Language -eq 'tr') {
        @($findings | Where-Object { $_.PSObject.Properties['TranslationReviewed'] -and -not $_.TranslationReviewed }).Count
    } else { 0 }

    $reportObj = [PSCustomObject]@{
        SchemaVersion       = '2.0.0'
        Tenant              = $tenantDisplay
        Language            = $Language
        Framework           = $Framework
        TenantInsights      = $tenantInsightObj
        UsageAdoption       = $usageAdoption
        SharePointRisk      = $sharePointRiskSummary
        PowerPlatformAgents = $ppAgentsSummary
        Summary          = [PSCustomObject]@{
            Total           = $tests.Count
            UniqueControls  = $tests.Count
            SourceControls  = $rawAllTests.Count
            Passed          = $passedCount
            Failed          = $failedCount
            Investigate     = $investigateCount
            Skipped         = $skippedCount
            Planned         = $plannedCount
            PlannedExcluded        = $plannedExcludedCount
            Error                  = $errorCount
            HighRiskFailed         = $highRiskFailed
            UnreviewedTranslations = $unreviewedTrCount
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
        Prerequisites    = @(Test-TenantBriefPrerequisites)
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
        PlannedFindings  = @($plannedFindings)
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
    $reportObj | ConvertTo-Json -Depth 12 | Set-Content -Path $reportJsonPath -Encoding UTF8

    if ($PreviousReportJson -and (Test-Path -LiteralPath $PreviousReportJson)) {
        try {
            $cmp = Compare-TenantBriefReports -BaselineJsonPath $PreviousReportJson -CurrentJsonPath $reportJsonPath
            $prevDoc = Get-Content -LiteralPath $PreviousReportJson -Raw -Encoding UTF8 | ConvertFrom-Json
            $prevPassed = if ($prevDoc.Summary -and $prevDoc.Summary.PSObject.Properties['Passed']) { [int]$prevDoc.Summary.Passed } else { 0 }
            $prevTotal  = if ($prevDoc.Summary -and $prevDoc.Summary.PSObject.Properties['Total']) { [int]$prevDoc.Summary.Total } else { 0 }
            $prevScore  = if ($prevTotal -gt 0) { [math]::Round(($prevPassed / $prevTotal) * 100, 1) } else { 0 }
            $currScore  = if ($tests.Count -gt 0) { [math]::Round(($passedCount / $tests.Count) * 100, 1) } else { 0 }
            $trendObj = [PSCustomObject]@{
                PreviousDate  = if ($prevDoc.PSObject.Properties['GeneratedAt']) { [string]$prevDoc.GeneratedAt } else { '' }
                PreviousScore = $prevScore
                CurrentScore  = $currScore
                ScoreDelta    = [math]::Round($currScore - $prevScore, 1)
                Improved      = @($cmp.Improved)
                Regressed     = @($cmp.Regressed)
                NewFailed     = @($cmp.Regressed | Where-Object { $_.To -eq 'Failed' })
                Resolved      = @($cmp.Improved | Where-Object { $_.To -eq 'Passed' })
            }
            $reportObj | Add-Member -NotePropertyName 'Trend' -NotePropertyValue $trendObj -Force
            $reportObj | ConvertTo-Json -Depth 12 | Set-Content -Path $reportJsonPath -Encoding UTF8
        } catch {
            Add-TenantBriefDiagnostic -Diagnostics $diagnostics -Stage 5 -Component 'TrendCompare' -Message "PreviousReportJson comparison skipped: $($_.Exception.Message)" -Severity 'Warning'
        }
    }

    $template = Get-Content -Path $script:ReportTemplatePath -Raw -Encoding UTF8
    $isTr = $Language -eq 'tr'
    $tenantDisplayHtml = [System.Net.WebUtility]::HtmlEncode([string]$tenantDisplay)

    # S7.4: Build compact HTML-embedded projection (preserves full schema in JSON file on disk while stripping redundant/empty fields in HTML)
    $compactFindings = [System.Collections.Generic.List[object]]::new()
    foreach ($cf in @($reportObj.Findings)) {
        $entry = [ordered]@{}
        foreach ($p in $cf.PSObject.Properties) {
            $val = $p.Value
            if ($p.Name -eq 'RemediationTr' -and $cf.PSObject.Properties['Remediation'] -and [string]$val -eq [string]$cf.Remediation) { continue }
            if ($p.Name -in @('SkippedReason', 'ErrorRemedy', 'CanonicalId', 'MinimumLicense') -and [string]::IsNullOrEmpty([string]$val)) { continue }
            if ($p.Name -in @('Result', 'Description') -and $val -is [string] -and $val.Length -gt 4000) {
                $val = $val.Substring(0, 4000) + "`n..."
            }
            $entry[$p.Name] = $val
        }
        $compactFindings.Add([PSCustomObject]$entry)
    }
    $htmlObj = $reportObj.PSObject.Copy()
    $htmlObj.Findings = $compactFindings.ToArray()

    $embeddedJson = ($htmlObj | ConvertTo-Json -Depth 12 -Compress -EscapeHandling EscapeHtml)
    $embeddedJson = $embeddedJson.Replace([string][char]0x2028, '\u2028').Replace([string][char]0x2029, '\u2029')
    $replacements = @{
        '{{LANG}}'               = $Language
        '{{TITLE}}'              = if ($isTr) { "TenantBrief Raporu — $tenantDisplayHtml" } else { "TenantBrief Report — $tenantDisplayHtml" }
        '{{HEADER_TITLE}}'       = if ($isTr) { 'Sıfır Güven, Lisans ROI ve Uyumluluk Analizi' } else { 'Zero Trust, License ROI & Compliance Assessment' }
        '{{SUBTITLE}}'           = if ($isTr) { "Kiracı: $tenantDisplayHtml · Çerçeve: $Framework" } else { "Tenant: $tenantDisplayHtml · Framework: $Framework" }
        '{{READONLY_BADGE}}'     = if ($isTr) { 'Salt Okunur (Read-Only)' } else { 'Read-Only Mode' }
        '{{GENERATED_AT}}'       = (Get-Date -Format 'yyyy-MM-dd HH:mm')
        '{{FW_TITLE}}'           = if ($isTr) { 'Standart ve Motor Bazlı Uyumluluk Skorları' } else { 'Verified Benchmark & Engine Scores' }
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
        '{{REPORT_JSON}}'        = $embeddedJson
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
