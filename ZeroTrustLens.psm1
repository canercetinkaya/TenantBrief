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

    Write-Host "[ZeroTrustLens] Checking ZeroTrustAssessment & PSGallery dependencies..." -ForegroundColor Cyan
    foreach ($dep in @('Microsoft.Graph.Beta.Teams', 'Microsoft.Online.SharePoint.PowerShell')) {
        if (-not (Get-Module -ListAvailable -Name $dep)) {
            Write-Warning "Module '$dep' is not installed. Installing from PSGallery (CurrentUser)..."
            try {
                Install-Module -Name $dep -Repository PSGallery -Scope CurrentUser -Force -AllowClobber -ErrorAction Stop
            } catch {
                Write-Warning "Could not auto-install '$dep': $($_.Exception.Message)"
            }
        }
    }

    Import-Module ZeroTrustAssessment -ErrorAction Stop
    $params = @{ Service = $Service }
    if ($Tenant) { $params['TenantId'] = $Tenant }
    if ($UseDeviceCode) { $params['UseDeviceCode'] = $true }

    Write-Host "[ZeroTrustLens] Connecting in Read-Only mode..." -ForegroundColor Green
    Connect-ZtAssessment @params
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
        [switch]$NoBrowser
    )

    if (-not (Test-Path $OutputPath)) {
        New-Item -ItemType Directory -Path $OutputPath -Force | Out-Null
    }

    $progressJob = $null
    $progressState = [hashtable]::Synchronized(@{ Stage = 1; Done = $false; Stop = $false })
    if (-not $NoBrowser -and -not $InputReportJson) {
        $port = 8925
        $progressHtmlPath = Join-Path $PSScriptRoot 'assets\progress-template.html'
        if (Test-Path $progressHtmlPath) {
            $pHtml = Get-Content -Path $progressHtmlPath -Raw -Encoding UTF8
            $labelsJson = if ($Language -eq 'tr') {
                '["1. Kiraci Verileri ve Guvenlik Kontrolleri","2. Lisans ROI ve Kor Nokta Analizi","3. Uyumluluk Cerceveleri Puanlamasi","4. ZeroTrustLens Rapor Uretimi"]'
            } else {
                '["1. Tenant Data & Security Checks","2. License ROI & Blind-Spot Analysis","3. Compliance Framework Scoring","4. Generating ZeroTrustLens Report"]'
            }
            $pHtml = $pHtml.Replace('{{LANG}}', $Language).Replace('{{TITLE}}', $(if ($Language -eq 'tr') { 'Canli Degerlendirme' } else { 'Live Assessment' })).Replace('{{RUNNING}}', $(if ($Language -eq 'tr') { 'Calisiyor' } else { 'Running' })).Replace('{{LABELS_JSON}}', $labelsJson)
            $doneLbl = if ($Language -eq 'tr') { 'Tamamlandi' } else { 'Completed' }
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
                            (@{ stage = $State.Stage; done = $State.Done; doneLabel = $DoneLbl } | ConvertTo-Json -Compress)
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
        Import-Module ZeroTrustAssessment -ErrorAction Stop
        $rawOut = Join-Path $OutputPath 'raw-zt'
        Write-Host "[ZeroTrustLens] Running read-only tenant assessment (this may take a few minutes)..." -ForegroundColor Cyan
        $null = Invoke-ZtAssessment -Path $rawOut -DisableTelemetry -NoBrowser 6>$null 3>$null 2>$null
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
                SkippedReason = $t.PSObject.Properties['SkippedReason'].Value
            }
        }
    }
    $tests = @($correlated.Values)

    if (-not $InputReportJson) {
        if (Get-Module -ListAvailable -Name 'ScubaGear') {
            try {
                Write-Host "[ZeroTrustLens] ScubaGear detected. Running CISA SCuBA checks (read-only)..." -ForegroundColor Cyan
                $scubaOut = Join-Path $OutputPath 'raw-scuba'
                Import-Module ScubaGear -ErrorAction Stop
                $null = Invoke-SCuBA -OutPath $scubaOut -Quiet 6>$null 3>$null 2>$null
                $scubaJson = Get-ChildItem -Path $scubaOut -Filter 'ScubaResults.json' -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
                if ($scubaJson) {
                    $scubaData = Get-Content -Path $scubaJson.FullName -Raw -Encoding UTF8 | ConvertFrom-Json
                    foreach ($prop in $scubaData.Results.PSObject.Properties) {
                        foreach ($item in @($prop.Value)) {
                            $tests += [PSCustomObject]@{
                                TestId       = "SCUBA-$($item.Control)"
                                TestTitle    = [string]$item.Requirement
                                TestStatus   = if ($item.Result -eq 'Pass') { 'Passed' } else { 'Failed' }
                                TestRisk     = if ($item.Criticality -eq 'Shall') { 'High' } else { 'Medium' }
                                TestPillar   = 'CISA SCuBA'
                            }
                        }
                    }
                }
            } catch {
                Write-Warning "[ZeroTrustLens] ScubaGear execution skipped: $($_.Exception.Message)"
            }
        }

        if (Get-Module -ListAvailable -Name 'ORCA') {
            try {
                Write-Host "[ZeroTrustLens] ORCA detected. Running Defender for Office 365 checks (read-only)..." -ForegroundColor Cyan
                $orcaOut = Join-Path $OutputPath 'raw-orca'
                if (-not (Test-Path $orcaOut)) { New-Item -ItemType Directory -Path $orcaOut -Force | Out-Null }
                Import-Module ORCA -ErrorAction Stop
                $orcaJsonPath = Join-Path $orcaOut 'orca.json'
                $null = Get-ORCAReport -Output JSON -OutputOptions @{ FilePath = $orcaJsonPath } 6>$null 3>$null 2>$null
                if (Test-Path $orcaJsonPath) {
                    $orcaData = Get-Content -Path $orcaJsonPath -Raw -Encoding UTF8 | ConvertFrom-Json
                    foreach ($item in @($orcaData.Checks)) {
                        $tests += [PSCustomObject]@{
                            TestId     = "ORCA-$($item.CheckName)"
                            TestTitle  = [string]$item.CheckName
                            TestStatus = if ($item.Status -eq 'OK') { 'Passed' } else { 'Failed' }
                            TestRisk   = 'Medium'
                            TestPillar = 'Defender for Office 365 (ORCA)'
                        }
                    }
                }
            } catch {
                Write-Warning "[ZeroTrustLens] ORCA execution skipped: $($_.Exception.Message)"
            }
        }
    }

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
    $frameworkCards = foreach ($fwId in $selectedFwIds) {
        $fwMeta = $fwConfig.$fwId
        $fwName = if ($Language -eq 'tr') { $fwMeta.nameTr } else { $fwMeta.nameEn }
        [PSCustomObject]@{
            Id        = $fwId
            Name      = $fwName
            Score     = $baseScore
            Passed    = $passedCount
            Evaluated = $evaluatedTotal
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

    $findings = foreach ($t in $tests) {
        $pillarStr = if ($t.TestPillar -is [System.Array]) { ($t.TestPillar -join ', ') } else { [string]$t.TestPillar }
        $primaryPillar = if ($t.TestPillar -is [System.Array]) { [string]$t.TestPillar[0] } else { [string]$t.TestPillar }
        $fwRef = if ($pillarMap -and $primaryPillar -and $pillarMap.PSObject.Properties[$primaryPillar]) {
            [string]$pillarMap.$primaryPillar
        } else {
            'General Control'
        }
        [PSCustomObject]@{
            Id           = $t.TestId
            Pillar       = if ($pillarStr) { $pillarStr } else { 'General' }
            Status       = [string]$t.TestStatus
            Risk         = if ($t.TestRisk) { [string]$t.TestRisk } else { 'Low' }
            Title        = [string]$t.TestTitle
            FrameworkRef = $fwRef
        }
    }

    $tenantDisplay = if ($Anonymize) { 'contoso.onmicrosoft.com (Anonymized)' } else { [string]$raw.Domain }

    $reportObj = [PSCustomObject]@{
        Tenant     = $tenantDisplay
        Language   = $Language
        Framework  = $Framework
        Summary    = [PSCustomObject]@{
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
            Summary = $roiSummary
            Gaps    = @($roiGapsList)
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

    $reportHtmlPath = Join-Path $OutputPath "ZeroTrustLensReport-$($Language.ToUpper()).html"
    $html | Set-Content -Path $reportHtmlPath -Encoding UTF8

    Write-Host "[ZeroTrustLens] Report generated: $reportHtmlPath" -ForegroundColor Green
    if (-not $NoBrowser) {
        Start-Process $reportHtmlPath
    }

    return [PSCustomObject]@{
        HtmlPath = $reportHtmlPath
        JsonPath = $reportJsonPath
        Summary  = $reportObj.Summary
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
    <div class="card"><div>Skipped (ROI Blind Spot)</div><div class="val">$($data.Summary.Skipped)</div></div>
  </div>
  <table>
    <thead><tr><th>Framework</th><th>Passed / Total</th><th>Score</th></tr></thead>
    <tbody>$fwRows</tbody>
  </table>
</body>
</html>
"@
    $html | Out-File -FilePath $OutputHtmlPath -Encoding UTF8
    return (Resolve-Path $OutputHtmlPath).Path
}

Export-ModuleMember -Function Connect-ZtLens, Invoke-ZtLensAssessment, Get-ZtLensFrameworks, Get-ZtLensLicenseRoi, Compare-ZtLensReports, Export-ZtLensExecutiveSummary
