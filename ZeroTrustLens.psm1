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

    $sourceJsonPath = $InputReportJson
    if (-not $sourceJsonPath) {
        Import-Module ZeroTrustAssessment -ErrorAction Stop
        $rawOut = Join-Path $OutputPath 'raw-zt'
        Write-Host "[ZeroTrustLens] Running read-only ZeroTrustAssessment (telemetry disabled)..." -ForegroundColor Cyan
        Invoke-ZtAssessment -Path $rawOut -DisableTelemetry -NoBrowser
        $sourceJsonPath = Join-Path $rawOut 'zt-export\ZeroTrustAssessmentReport.json'
    }

    if (-not (Test-Path $sourceJsonPath)) {
        throw "Assessment JSON report not found: $sourceJsonPath"
    }

    $raw = Get-Content -Path $sourceJsonPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $fwConfig = (Get-Content -Path $script:FrameworkMapPath -Raw -Encoding UTF8 | ConvertFrom-Json).frameworks
    $tests = @($raw.Tests)

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

Export-ModuleMember -Function Connect-ZtLens, Invoke-ZtLensAssessment, Get-ZtLensFrameworks
