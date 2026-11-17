Set-StrictMode -Version Latest

$script:ModuleRoot = $PSScriptRoot
$script:FrameworkMapPath = Join-Path $script:ModuleRoot 'data\framework-mappings.json'
$script:ReportTemplatePath = Join-Path $script:ModuleRoot 'assets\report-template.html'

function Get-ZtLensFrameworks {
    [CmdletBinding()]
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

function Connect-ZtLens {
    [CmdletBinding()]
    param(
        [Parameter()]
        [string]$Tenant,

        [Parameter()]
        [ValidateSet('Graph', 'Azure', 'ExchangeOnline', 'SecurityCompliance', 'SharePointOnline')]
        [string[]]$Service = @('Graph', 'Azure', 'ExchangeOnline', 'SecurityCompliance', 'SharePointOnline'),

        [Parameter()]
        [switch]$UseDeviceCode
    )

    Write-Host "[ZeroTrustLens] Cleaning any previous tenant sessions..." -ForegroundColor DarkGray
    try { Disconnect-MgGraph -ErrorAction SilentlyContinue | Out-Null } catch {}
    try { Clear-AzContext -Force -ErrorAction SilentlyContinue | Out-Null } catch {}
    try { Disconnect-AzAccount -ErrorAction SilentlyContinue | Out-Null } catch {}
    try { Disconnect-ExchangeOnline -Confirm:$false -ErrorAction SilentlyContinue | Out-Null } catch {}

    Write-Host "[ZeroTrustLens] Checking ZeroTrustAssessment, ScubaGear, ORCA & PSGallery dependencies..." -ForegroundColor Cyan
    foreach ($dep in @('Microsoft.Graph.Beta.Teams', 'Microsoft.Online.SharePoint.PowerShell', 'powershell-yaml', 'ScubaGear', 'ORCA')) {
        if (-not (Get-Module -ListAvailable -Name $dep)) {
            Write-Host "[ZeroTrustLens] Installing missing module '$dep' from PSGallery..." -ForegroundColor Yellow
            try {
                Install-Module -Name $dep -Repository PSGallery -Scope CurrentUser -Force -AllowClobber -ErrorAction Stop
            } catch {
                Write-Warning "Could not auto-install '$dep': $($_.Exception.Message)"
            }
        }
    }
    $opaExe = Join-Path $env:USERPROFILE '.scubagear\Tools\opa_windows_amd64.exe'
    if (-not (Test-Path $opaExe) -and (Get-Module -ListAvailable -Name 'ScubaGear')) {
        Write-Host "[ZeroTrustLens] Installing OPA executable for ScubaGear..." -ForegroundColor Yellow
        try {
            Import-Module ScubaGear -ErrorAction SilentlyContinue 2>$null 3>$null | Out-Null
            Install-OPAforSCuBA | Out-Null
        } catch {
            Write-Warning "Could not auto-install OPA: $($_.Exception.Message)"
        }
    }

    if (-not (Get-Module -ListAvailable -Name 'ZeroTrustAssessment')) {
        throw "Required module 'ZeroTrustAssessment' is not installed. Run: Install-Module ZeroTrustAssessment -Scope CurrentUser"
    }
    Import-Module ZeroTrustAssessment -ErrorAction SilentlyContinue 2>$null 3>$null | Out-Null
    $params = @{ Service = $Service }
    if ($Tenant) { $params['TenantId'] = $Tenant }
    if ($UseDeviceCode) { $params['UseDeviceCode'] = $true }

    Write-Host "[ZeroTrustLens] Connecting in Read-Only mode..." -ForegroundColor Green
    Connect-ZtAssessment @params
}

function ConvertTo-ZtLensTurkish {
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

function Invoke-ZtLensAssessment {
    [CmdletBinding()]
    param(
        [Parameter()]
        [string]$InputReportJson,

        [Parameter()]
        [string]$OutputPath = (Join-Path (Get-Location).Path 'ZeroTrustLensReport'),

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
        [string]$TranslatorKey = $env:AZURE_TRANSLATOR_KEY
    )

    if (-not $InputReportJson) {
        $tenantFolder = 'tenant'
        try {
            $ctx = Get-MgContext -ErrorAction SilentlyContinue
            if ($ctx -and $ctx.Account -and $ctx.Account -match '@(.+)$') {
                $tenantFolder = ($Matches[1] -replace '[^a-zA-Z0-9\.-]', '_')
            }
        } catch {}
        $OutputPath = Join-Path $OutputPath ("{0}_{1}" -f $tenantFolder, (Get-Date -Format 'yyyyMMdd_HHmm'))
    }

    if (-not (Test-Path $OutputPath)) {
        New-Item -ItemType Directory -Path $OutputPath -Force | Out-Null
    }

    $rawOut = Join-Path $OutputPath 'raw-zt'
    $progressJob = $null
    $logQueue = [System.Collections.ArrayList]::Synchronized((New-Object System.Collections.ArrayList))
    $progressState = [hashtable]::Synchronized(@{ Stage = 1; Done = $false; Stop = $false; RawOut = $rawOut; Logs = $logQueue })
    $addLog = {
        param([string]$Msg)
        $line = "[$(Get-Date -Format 'HH:mm:ss')] $Msg"
        [void]$progressState.Logs.Add($line)
        if ($progressState.Logs.Count -gt 30) { $progressState.Logs.RemoveAt(0) }
        Write-Host $line -ForegroundColor Cyan
    }

    if (-not $NoBrowser -and -not $InputReportJson) {
        $port = 8925
        $progressHtmlPath = Join-Path $PSScriptRoot 'assets\progress-template.html'
        if (Test-Path $progressHtmlPath) {
            $pHtml = Get-Content -Path $progressHtmlPath -Raw -Encoding UTF8
            $labelsJson = if ($Language -eq 'tr') {
                '["1. ZeroTrustAssessment (Kiracı Veri Toplama & Testler)","2. CISA ScubaGear (Güvenlik Taban Hattı)","3. Microsoft ORCA (Defender for Office 365)","4. Korelasyon, Lisans ROI & Çerçeve Puanlama","5. ZeroTrustLens Rapor Üretimi"]'
            } else {
                '["1. ZeroTrustAssessment (Tenant Data & Checks)","2. CISA ScubaGear (Security Baselines)","3. Microsoft ORCA (Defender for Office 365)","4. Correlation, License ROI & Framework Scoring","5. Generating ZeroTrustLens Reports"]'
            }
            $pHtml = $pHtml.Replace('{{LANG}}', $Language).Replace('{{TITLE}}', $(if ($Language -eq 'tr') { 'Canlı Değerlendirme' } else { 'Live Assessment' })).Replace('{{RUNNING}}', $(if ($Language -eq 'tr') { 'Çalışıyor' } else { 'Running' })).Replace('{{LABELS_JSON}}', $labelsJson)
            $doneLbl = if ($Language -eq 'tr') { 'Tamamlandı' } else { 'Completed' }
            $rs = [runspacefactory]::CreateRunspace()
            $rs.Open()
            $rs.SessionStateProxy.SetVariable('State', $progressState)
            $rs.SessionStateProxy.SetVariable('Html', $pHtml)
            $rs.SessionStateProxy.SetVariable('DoneLbl', $doneLbl)
            $rs.SessionStateProxy.SetVariable('Port', $port)
            $ps = [powershell]::Create()
            $ps.Runspace = $rs
            [void]$ps.AddScript({
                $listener = New-Object System.Net.HttpListener
                $listener.Prefixes.Add("http://localhost:$Port/")
                try {
                    $listener.Start()
                    while (-not $State.Stop -and $listener.IsListening) {
                        $ctxTask = $listener.GetContextAsync()
                        while (-not $ctxTask.AsyncWaitHandle.WaitOne(200)) {
                            if ($State.Stop) { break }
                        }
                        if ($State.Stop) { break }
                        $ctx = $ctxTask.GetAwaiter().GetResult()
                        $reqPath = $ctx.Request.Url.AbsolutePath
                        $body = if ($reqPath -eq '/status.json') {
                            $ctx.Response.ContentType = 'application/json; charset=utf-8'
                            $detail = ''
                            if ($State.RawOut -and (Test-Path $State.RawOut)) {
                                $allFiles = @(Get-ChildItem -Path $State.RawOut -Recurse -File -ErrorAction SilentlyContinue)
                                $latest = $allFiles | Sort-Object LastWriteTime -Descending | Select-Object -First 1
                                if ($latest) {
                                    $detail = "$($allFiles.Count) items processed | active: $($latest.Name)"
                                }
                            }
                            (@{ stage = $State.Stage; done = $State.Done; doneLabel = $DoneLbl; detail = $detail; logs = @($State.Logs) } | ConvertTo-Json -Compress)
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
            Start-Process "http://localhost:$port/"
        }
    }

    $sourceJsonPath = $InputReportJson
    if (-not $sourceJsonPath) {
        if (-not (Get-Module -ListAvailable -Name 'ZeroTrustAssessment')) {
            throw "Required module 'ZeroTrustAssessment' is not installed. Run: Install-Module ZeroTrustAssessment -Scope CurrentUser"
        }
        & $addLog "[Stage 1/5] Starting read-only ZeroTrustAssessment (ZeroTrustLens dashboard active)..."
        $ztRs = [runspacefactory]::CreateRunspace()
        $ztRs.Open()
        $ztPs = [powershell]::Create()
        $ztPs.Runspace = $ztRs
        $ztPs.AddScript({
            param($OutDir)
            Import-Module ZeroTrustAssessment -ErrorAction SilentlyContinue 2>$null 3>$null | Out-Null
            Invoke-ZtAssessment -Path $OutDir -DisableTelemetry -NoBrowser 6>$null 3>$null 2>$null
        }).AddArgument($rawOut) | Out-Null
        $ztHandle = $ztPs.BeginInvoke()
        $lastCnt = -1
        while (-not $ztHandle.IsCompleted) {
            Start-Sleep -Seconds 6
            if (Test-Path $rawOut) {
                $files = @(Get-ChildItem -Path $rawOut -Recurse -File -ErrorAction SilentlyContinue)
                if ($files.Count -ne $lastCnt -and $files.Count -gt 0) {
                    $lastCnt = $files.Count
                    $latest = $files | Sort-Object LastWriteTime -Descending | Select-Object -First 1
                    & $addLog "[Stage 1/5] Processed $lastCnt artifacts (latest: $($latest.Name))"
                }
            }
        }
        try { $ztPs.EndInvoke($ztHandle) } catch {}
        $ztPs.Dispose(); $ztRs.Close(); $ztRs.Dispose()
        $sourceJsonPath = Join-Path $rawOut 'zt-export\ZeroTrustAssessmentReport.json'
    }
    $progressState.Stage = 2

    if (-not (Test-Path $sourceJsonPath)) {
        throw "Assessment JSON report not found: $sourceJsonPath"
    }

    $raw = Get-Content -Path $sourceJsonPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $fwConfig = (Get-Content -Path $script:FrameworkMapPath -Raw -Encoding UTF8 | ConvertFrom-Json).frameworks
    $tests = @($raw.Tests)

    # Deduplicate / Correlate findings with identical normalized titles across engines
    $correlated = @{}
    foreach ($t in $tests) {
        $normTitle = ([string]$t.TestTitle).ToLowerInvariant().Trim() -replace '[^a-z0-9]+', ' '
        if (-not $normTitle) { $normTitle = [string]$t.TestId }
        if ($correlated.ContainsKey($normTitle)) {
            $existing = $correlated[$normTitle]
            if ($existing.TestPillar -notlike "*$($t.TestPillar)*") {
                $existing.TestPillar = "$($existing.TestPillar), $($t.TestPillar)"
            }
            if ($t.TestStatus -eq 'Failed' -and $existing.TestStatus -eq 'Passed') {
                $existing.TestStatus = 'Failed'
            }
        } else {
            $correlated[$normTitle] = [PSCustomObject]@{
                TestId        = $t.TestId
                TestTitle     = $t.TestTitle
                TestStatus    = $t.TestStatus
                TestRisk      = $t.TestRisk
                TestPillar    = $t.TestPillar
                TestCategory  = $t.PSObject.Properties['TestCategory'].Value
                TestSfiPillar = $t.PSObject.Properties['TestSfiPillar'].Value
                TestImplCost  = $t.PSObject.Properties['TestImplementationCost'].Value
                TestMinLic    = $t.PSObject.Properties['TestMinimumLicense'].Value
                SkippedReason = $t.PSObject.Properties['SkippedReason'].Value
                TestResult    = $t.PSObject.Properties['TestResult'].Value
                TestImpact    = $t.PSObject.Properties['TestImpact'].Value
                TestDesc      = $t.PSObject.Properties['TestDescription'].Value
            }
        }
    }
    $tests = @($correlated.Values)

    if (-not $InputReportJson) {
        if (Get-Module -ListAvailable -Name 'ScubaGear') {
            try {
                & $addLog "[Stage 2/5] Running CISA ScubaGear checks (aad, exo, defender — reusing active session)..."
                $scubaOut = Join-Path $OutputPath 'raw-scuba'
                Import-Module ScubaGear -ErrorAction Stop
                $null = Invoke-SCuBA -ProductNames @('aad', 'exo', 'defender') -LogIn:$false -DisconnectOnExit:$false -OutPath $scubaOut -Quiet 6>$null 3>$null 2>$null
                $scubaJson = Get-ChildItem -Path $scubaOut -Filter 'ScubaResults.json' -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
                if ($scubaJson) {
                    $scubaData = Get-Content -Path $scubaJson.FullName -Raw -Encoding UTF8 | ConvertFrom-Json
                    $scCount = 0
                    foreach ($prop in $scubaData.Results.PSObject.Properties) {
                        foreach ($item in @($prop.Value)) {
                            $scCount++
                            $tests += [PSCustomObject]@{
                                TestId          = "SCUBA-$($item.Control)"
                                TestTitle       = [string]$item.Requirement
                                TestStatus      = if ($item.Result -eq 'Pass') { 'Passed' } else { 'Failed' }
                                TestRisk        = if ($item.Criticality -eq 'Shall') { 'High' } else { 'Medium' }
                                TestPillar      = 'CISA SCuBA'
                                TestCategory    = [string]$prop.Name
                                TestResult      = [string]$item.Details
                                TestDescription = [string]$item.Requirement
                            }
                        }
                    }
                    & $addLog "[Stage 2/5] ScubaGear completed: $scCount controls merged."
                }
            } catch {
                & $addLog "[Stage 2/5] ScubaGear skipped: $($_.Exception.Message)"
            }
        }

        $progressState.Stage = 3
        if (Get-Module -ListAvailable -Name 'ORCA') {
            try {
                & $addLog "[Stage 3/5] Running Microsoft ORCA checks (Defender for Office 365)..."
                $orcaOut = Join-Path $OutputPath 'raw-orca'
                if (-not (Test-Path $orcaOut)) { New-Item -ItemType Directory -Path $orcaOut -Force | Out-Null }
                Import-Module ORCA -ErrorAction Stop
                $null = Invoke-ORCA -Connect:$false -SCC:$false -PerformVersionCheck:$false -InstallModules:$false -ShowSurvey:$false -Output @('JSON') -OutputOptions @{ JSON = @{ OutputDirectory = $orcaOut } } 6>$null 3>$null 2>$null
                $orcaFile = Get-ChildItem -Path $orcaOut -Filter '*.json' -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
                if ($orcaFile) {
                    $orcaData = Get-Content -Path $orcaFile.FullName -Raw -Encoding UTF8 | ConvertFrom-Json
                    $orcaItems = if ($orcaData.Checks) { @($orcaData.Checks) } else { @($orcaData) }
                    $ocCount = 0
                    foreach ($item in $orcaItems) {
                        $cName = if ($item.Name) { [string]$item.Name } else { [string]$item.CheckName }
                        if (-not $cName) { continue }
                        $ocCount++
                        $st = [string]$item.Result
                        $tests += [PSCustomObject]@{
                            TestId          = "ORCA-$($item.Control)"
                            TestTitle       = $cName
                            TestStatus      = if ($st -match 'Pass|OK') { 'Passed' } else { 'Failed' }
                            TestRisk        = 'Medium'
                            TestPillar      = 'Defender for Office 365 (ORCA)'
                            TestCategory    = if ($item.Area) { [string]$item.Area } else { 'Defender for Office 365' }
                            TestResult      = [string]$item.FailRecommendation
                            TestDescription = [string]$item.Importance
                        }
                    }
                    & $addLog "[Stage 3/5] ORCA completed: $ocCount controls merged."
                }
            } catch {
                & $addLog "[Stage 3/5] ORCA skipped: $($_.Exception.Message)"
            }
        }
    }
    $progressState.Stage = 4
    & $addLog "[Stage 4/5] Computing License ROI, Secure Score & Multi-Framework Scores..."

    $passedCount = @($tests | Where-Object { $_.TestStatus -eq 'Passed' }).Count
    $failedCount = @($tests | Where-Object { $_.TestStatus -eq 'Failed' }).Count
    $investigateCount = @($tests | Where-Object { $_.TestStatus -eq 'Investigate' }).Count
    $skippedCount = @($tests | Where-Object { $_.TestStatus -eq 'Skipped' }).Count
    $plannedCount = @($tests | Where-Object { $_.TestStatus -eq 'Planned' }).Count
    $highRiskFailed = @($tests | Where-Object { $_.TestStatus -eq 'Failed' -and $_.TestRisk -eq 'High' }).Count
    $medRiskFailed = @($tests | Where-Object { $_.TestStatus -eq 'Failed' -and $_.TestRisk -eq 'Medium' }).Count
    $lowRiskFailed = @($tests | Where-Object { $_.TestStatus -eq 'Failed' -and $_.TestRisk -eq 'Low' }).Count

    $evaluatedTotal = $passedCount + $failedCount
    $baseScore = if ($evaluatedTotal -gt 0) { [math]::Round(($passedCount / $evaluatedTotal) * 100, 1) } else { 0 }

    $selectedFwIds = if ($Framework -eq 'All') { @('ZeroTrust', 'ISO27001', 'NIST_CSF_2', 'CIS_M365', 'KVKK_TR') } else { @($Framework) }
    $fwPillars = @{
        'ZeroTrust'  = @('Identity', 'Devices', 'Network', 'Data', 'Infrastructure', 'SecOps', 'AI', 'CISA SCuBA', 'Defender for Office 365 (ORCA)')
        'ISO27001'   = @('Identity', 'Devices', 'Network', 'Data', 'Infrastructure', 'SecOps')
        'NIST_CSF_2' = @('Identity', 'Devices', 'Network', 'SecOps', 'AI')
        'CIS_M365'   = @('Identity', 'Devices', 'Data', 'CISA SCuBA', 'Defender for Office 365 (ORCA)')
        'KVKK_TR'    = @('Identity', 'Data', 'SecOps', 'Devices')
    }

    $frameworkCards = foreach ($fwId in $selectedFwIds) {
        $fwMeta = $fwConfig.$fwId
        $fwName = if ($Language -eq 'tr') { $fwMeta.nameTr } else { $fwMeta.nameEn }
        $allowed = $fwPillars[$fwId]
        $fwTests = if ($allowed) {
            @($tests | Where-Object {
                $p = if ($_.TestPillar -is [System.Array]) { [string]$_.TestPillar[0] } else { [string]$_.TestPillar }
                $allowed -contains $p
            })
        } else { $tests }
        $fwPass = @($fwTests | Where-Object { $_.TestStatus -eq 'Passed' }).Count
        $fwFail = @($fwTests | Where-Object { $_.TestStatus -eq 'Failed' }).Count
        $fwInv  = @($fwTests | Where-Object { $_.TestStatus -eq 'Investigate' }).Count
        $fwEval = $fwPass + $fwFail + $fwInv
        $fwScore = if ($fwEval -gt 0) { [Math]::Round(($fwPass / $fwEval) * 100, 1) } else { 0 }
        [PSCustomObject]@{
            Id        = $fwId
            Name      = $fwName
            Score     = $fwScore
            Passed    = $fwPass
            Evaluated = $fwEval
        }
    }

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
            Write-Host "[ZeroTrustLens] Translating $($toTranslate.Count) controls via Azure AI Translator..." -ForegroundColor Cyan
            for ($i = 0; $i -lt $toTranslate.Count; $i += 15) {
                $chunk = $toTranslate[$i..([Math]::Min($i + 14, $toTranslate.Count - 1))]
                $payload = @()
                foreach ($item in $chunk) {
                    $dText = [string]$item.TestDesc
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
                            Write-Warning "[ZeroTrustLens] Translator batch skipped: $($_.Exception.Message)"
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

    $findings = foreach ($t in $tests) {
        $pillarStr = if ($t.TestPillar -is [System.Array]) { ($t.TestPillar -join ', ') } else { [string]$t.TestPillar }
        $primaryPillar = if ($t.TestPillar -is [System.Array]) { [string]$t.TestPillar[0] } else { [string]$t.TestPillar }
        $fwRef = if ($pillarMap -and $primaryPillar -and $pillarMap.PSObject.Properties[$primaryPillar]) {
            [string]$pillarMap.$primaryPillar
        } else {
            'General Control'
        }
        $fTitle = [string]$t.TestTitle
        $fDesc  = [string]$t.TestDesc
        $fImp   = [string]$t.TestImpact
        $tid    = [string]$t.TestId
        if ($Language -eq 'tr' -and $trCache.ContainsKey($tid)) {
            if ($trCache[$tid].Title) { $fTitle = [string]$trCache[$tid].Title }
            if ($trCache[$tid].Desc)  { $fDesc  = [string]$trCache[$tid].Desc }
        }
        if ($Language -eq 'tr' -and $fImp) {
            $fImp = $fImp -replace '^High$', 'Yüksek' -replace '^Medium$', 'Orta' -replace '^Low$', 'Düşük'
        }
        $portalName = switch ($primaryPillar) {
            'Identity'       { 'Microsoft Entra yönetim merkezi (entra.microsoft.com)' }
            'Devices'        { 'Microsoft Intune yönetim merkezi (intune.microsoft.com)' }
            'Network'        { 'Global Secure Access / Azure Portal (portal.azure.com)' }
            'Data'           { 'Microsoft Purview portalı (purview.microsoft.com)' }
            'Infrastructure' { 'Azure Portal (portal.azure.com)' }
            'SecOps'         { 'Microsoft Defender XDR / Sentinel (security.microsoft.com)' }
            'AI'             { 'Microsoft Purview / Entra Agent ID (entra.microsoft.com)' }
            default          { 'Microsoft 365 Yönetim Merkezi' }
        }
        $remTr = "1. $portalName üzerinden '$fTitle' kontrolüne karşılık gelen ilkeyi açın. 2. Değişikliği önce Denetim (Report-only) kipinde pilot gruba uygulayıp oturum açma/olay günlüklerini doğrulayın. 3. Etki analizi sonrası kademeli olarak Zorunlu (Enforce) durumuna geçin."
        $minLicStr = if ($t.TestMinLic -is [System.Array]) { ($t.TestMinLic -join ', ') } else { [string]$t.TestMinLic }
        [PSCustomObject]@{
            Id                 = $t.TestId
            Pillar             = if ($pillarStr) { $pillarStr } else { 'General' }
            PrimaryPillar      = if ($primaryPillar) { $primaryPillar } else { 'General' }
            Category           = if ($t.TestCategory) { [string]$t.TestCategory } else { 'General' }
            SfiPillar          = if ($t.TestSfiPillar) { [string]$t.TestSfiPillar } else { '' }
            ImplementationCost = if ($t.TestImplCost) { [string]$t.TestImplCost } else { 'Medium' }
            MinimumLicense     = $minLicStr
            Status             = [string]$t.TestStatus
            Risk               = if ($t.TestRisk) { [string]$t.TestRisk } else { 'Low' }
            Title              = $fTitle
            FrameworkRef       = $fwRef
            Result             = [string]$t.TestResult
            Impact             = $fImp
            Description        = $fDesc
            SkippedReason      = [string]$t.SkippedReason
            RemediationTr      = $remTr
        }
    }

    $tenantDisplay = if ($Anonymize) { 'contoso.onmicrosoft.com (Anonymized)' } else { [string]$raw.Domain }
    $ti = $raw.PSObject.Properties['TenantInfo'].Value
    $tOverview = if ($ti -and $ti.PSObject.Properties['TenantOverview'].Value) { $ti.TenantOverview } else { $null }
    $mfaDesc = if ($ti -and $ti.PSObject.Properties['OverviewCaMfaAllUsers'].Value) { [string]$ti.OverviewCaMfaAllUsers.description } else { '' }
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
    $secureCurrent = $null
    $secureMax = $null
    if (-not $InputReportJson) {
        try {
            if (Get-MgContext -ErrorAction SilentlyContinue) {
                $skuRoiList = @(Get-ZtLensLicenseRoi)
                $scResp = Invoke-MgGraphRequest -Method GET -Uri 'https://graph.microsoft.com/v1.0/security/secureScores?$top=1' -ErrorAction SilentlyContinue
                if ($scResp -and $scResp.value -and $scResp.value.Count -gt 0) {
                    $secureCurrent = [Math]::Round([double]$scResp.value[0].currentScore, 1)
                    $secureMax = [Math]::Round([double]$scResp.value[0].maxScore, 1)
                }
            }
        } catch {}
    }
    $totalIdleMo = if ($skuRoiList.Count -gt 0) {
        [Math]::Round((($skuRoiList | Measure-Object -Property EstimatedIdleUsdMo -Sum).Sum), 2)
    } else { 0 }
    $totalIdleYr = [Math]::Round($totalIdleMo * 12, 2)

    $reportObj = [PSCustomObject]@{
        Tenant         = $tenantDisplay
        Language       = $Language
        Framework      = $Framework
        TenantInsights = [PSCustomObject]@{
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
        Summary        = [PSCustomObject]@{
            Total          = $tests.Count
            Passed         = $passedCount
            Failed         = $failedCount
            Investigate    = $investigateCount
            Skipped        = $skippedCount
            Planned        = $plannedCount
            HighRiskFailed = $highRiskFailed
        }
        Frameworks = @($frameworkCards)
        LicenseROI = [PSCustomObject]@{
            Summary         = $roiSummary
            Gaps            = @($roiGapsList)
            Skus            = @($skuRoiList)
            TotalIdleUsdMo  = $totalIdleMo
            TotalIdleUsdYr  = $totalIdleYr
        }
        Roadmap    = @($roadmap)
        Findings   = @($findings)
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

    $reportJsonPath = Join-Path $OutputPath "ZeroTrustLensReport-$($Language.ToUpper()).json"
    $reportObj | ConvertTo-Json -Depth 6 | Set-Content -Path $reportJsonPath -Encoding UTF8

    $template = Get-Content -Path $script:ReportTemplatePath -Raw -Encoding UTF8
    $isTr = $Language -eq 'tr'
    $replacements = @{
        '{{LANG}}'               = $Language
        '{{TITLE}}'              = if ($isTr) { "ZeroTrustLens Raporu — $tenantDisplay" } else { "ZeroTrustLens Report — $tenantDisplay" }
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
        '{{REPORT_JSON}}'        = ($reportObj | ConvertTo-Json -Depth 6 -Compress)
    }

    $html = $template
    foreach ($k in $replacements.Keys) {
        $html = $html.Replace($k, $replacements[$k])
    }

    $progressState.Stage = 5
    & $addLog "[Stage 5/5] Writing HTML, JSON and Executive Summary reports..."
    $reportHtmlPath = Join-Path $OutputPath "ZeroTrustLensReport-$($Language.ToUpper()).html"
    $html | Set-Content -Path $reportHtmlPath -Encoding UTF8

    $execSummaryPath = Join-Path $OutputPath "ZeroTrustLens-ExecutiveSummary-$($Language.ToUpper()).html"
    $null = Export-ZtLensExecutiveSummary -InputLensJsonPath $reportJsonPath -OutputHtmlPath $execSummaryPath -Language $Language

    $progressState.Done = $true
    if ($progressJob) {
        Start-Sleep -Seconds 2
        $progressState.Stop = $true
        try { $progressJob.Ps.EndInvoke($progressJob.Handle) } catch {}
        try { $progressJob.Ps.Dispose(); $progressJob.Rs.Close(); $progressJob.Rs.Dispose() } catch {}
    }

    Write-Host "[ZeroTrustLens] Report generated: $reportHtmlPath" -ForegroundColor Green
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

function Get-ZtLensLicenseRoi {
    [CmdletBinding()]
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

        [PSCustomObject]@{
            SkuPartNumber       = $part
            ProductName         = if ($meta) { $meta.name } else { $part }
            Category            = if ($meta) { $meta.category } else { 'Other' }
            Purchased           = $enabled
            Assigned            = $consumed
            Unassigned          = $unassigned
            UtilizationPercent  = $utilPct
            EstimatedIdleUsdMo  = $idleUsdMonth
        }
    }
    return @($results)
}

function Compare-ZtLensReports {
    [CmdletBinding()]
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

function Export-ZtLensExecutiveSummary {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$InputLensJsonPath,

        [Parameter(Mandatory = $false)]
        [string]$OutputHtmlPath = '.\ZeroTrustLens-ExecutiveSummary.html',

        [Parameter(Mandatory = $false)]
        [ValidateSet('tr', 'en')]
        [string]$Language = 'tr'
    )

    if (-not (Test-Path $InputLensJsonPath)) { throw "ZeroTrustLens JSON not found: $InputLensJsonPath" }
    $data = Get-Content -Path $InputLensJsonPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $title = if ($Language -eq 'tr') { 'Yönetici Özeti — Güvenlik Duruşu ve Lisans ROI' } else { 'Executive Summary — Security Posture & License ROI' }

    $fwRows = ($data.Frameworks | ForEach-Object {
        "<tr><td>$($_.Name)</td><td>$($_.Passed) / $($_.Evaluated)</td><td><strong>$($_.Score)%</strong></td></tr>"
    }) -join "`n"

    $topHigh = @($data.Findings | Where-Object { $_.Status -eq 'Failed' -and $_.Risk -eq 'High' } | Select-Object -First 15)
    $actionRows = ($topHigh | ForEach-Object {
        $remText = if ($Language -eq 'tr') { $_.RemediationTr } else { [string]$_.Description }
        if ($remText.Length -gt 220) { $remText = $remText.Substring(0, 220) + '...' }
        "<tr><td><strong>$($_.Title)</strong><br/><span style='color:#64748b;font-size:11px;'>$($_.Pillar) · $($_.Category)</span></td><td>$($_.ImplementationCost)</td><td>$remText</td></tr>"
    }) -join "`n"

    $html = @"
<!DOCTYPE html>
<html lang="$Language">
<head>
<meta charset="UTF-8" />
<title>ZeroTrustLens - $title</title>
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
  @media print { body { margin: 12mm; } }
</style>
</head>
<body>
  <h1>ZeroTrustLens — $title</h1>
  <div class="sub">Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm') | Read-Only Assessment</div>
  <div class="grid">
    <div class="card"><div>Total</div><div class="val">$($data.Summary.Total)</div></div>
    <div class="card"><div>Passed</div><div class="val">$($data.Summary.Passed)</div></div>
    <div class="card"><div>Failed (High)</div><div class="val">$($data.Summary.Failed) ($($data.Summary.HighRiskFailed))</div></div>
    <div class="card"><div>$(if ($Language -eq 'tr') { 'Atıl Lisans (Yıllık USD)' } else { 'Idle License (Annual USD)' })</div><div class="val">`$$($data.LicenseROI.TotalIdleUsdYr)</div></div>
  </div>
  <table>
    <thead><tr><th>Framework</th><th>Passed / Total</th><th>Score</th></tr></thead>
    <tbody>$fwRows</tbody>
  </table>
  <h2 style="font-size:17px;margin-top:24px;">$(if ($Language -eq 'tr') { 'Öncelikli İlk 15 İyileştirme Adımı (Çevrimdışı Analiz)' } else { 'Top 15 Priority Remediations (Offline Analysis)' })</h2>
  <table>
    <thead><tr><th>$(if ($Language -eq 'tr') { 'Kontrol' } else { 'Control' })</th><th>$(if ($Language -eq 'tr') { 'Maliyet' } else { 'Cost' })</th><th>$(if ($Language -eq 'tr') { 'Önerilen Aksiyon' } else { 'Recommended Action' })</th></tr></thead>
    <tbody>$actionRows</tbody>
  </table>
</body>
</html>
"@
    $html | Out-File -FilePath $OutputHtmlPath -Encoding UTF8
    return (Resolve-Path $OutputHtmlPath).Path
}

Export-ModuleMember -Function Connect-ZtLens, Invoke-ZtLensAssessment, Get-ZtLensFrameworks, Get-ZtLensLicenseRoi, Compare-ZtLensReports, Export-ZtLensExecutiveSummary
