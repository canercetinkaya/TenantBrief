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

    $htmlEncode = { param($v) [System.Net.WebUtility]::HtmlEncode([string]$v) }

    $fwRows = ($data.Frameworks | ForEach-Object {
        $covBadge = ''
        if ($_.PSObject.Properties['CoverageNote'] -and $_.CoverageNote) {
            $covBadge = " <span style='display:inline-block;margin-left:6px;padding:1px 6px;border-radius:4px;background:#fef3c7;color:#92400e;border:1px solid #f59e0b;font-size:11px;font-weight:600;'>$(& $htmlEncode $_.CoverageNote)</span>"
        }
        $evalVal = if ($_.PSObject.Properties['Evaluated'] -and $null -ne $_.Evaluated) { $_.Evaluated } else { $_.Total }
        "<tr><td>$(& $htmlEncode $_.Name)$covBadge</td><td>$(& $htmlEncode $_.Passed) / $(& $htmlEncode $evalVal)</td><td><strong>$(& $htmlEncode $_.Score)%</strong></td></tr>"
    }) -join "`n"

    # Priority order for the printable brief: cheapest high-risk fixes first, then by control id so
    # the output is stable between runs.
    $isTr = ($Language -eq 'tr')
    $costRank = @{ 'Low' = 0; 'Medium' = 1; 'High' = 2; 'Unknown' = 3 }
    $costMap = @{ 'Low' = 'Düşük'; 'Medium' = 'Orta'; 'High' = 'Yüksek'; 'Unknown' = 'Bilinmiyor' }
    $riskRankExec = @{ 'Critical' = 0; 'High' = 1 }
    $topHigh = @($data.Findings |
        Where-Object { $_.Status -eq 'Failed' -and $_.Risk -in @('Critical', 'High') } |
        Sort-Object `
            @{ Expression = { $rk = [string]$_.Risk; if ($riskRankExec.ContainsKey($rk)) { $riskRankExec[$rk] } else { 2 } } },
            @{ Expression = { $cost = [string]$_.ImplementationCost; if ($costRank.ContainsKey($cost)) { $costRank[$cost] } else { 3 } } },
            @{ Expression = { [string]$_.Id } } |
        Select-Object -First 15)
    $actionRows = ($topHigh | ForEach-Object {
        $remText = if ($isTr) { [string]$_.RemediationTr } else { [string]$_.Description }
        if ($remText.Length -gt 220) { $remText = $remText.Substring(0, 220) + '...' }
        $domLbl = if ($_.PSObject.Properties['DomainPillar'] -and $_.DomainPillar) { [string]$_.DomainPillar } else { [string]$_.Pillar }
        $costStr = [string]$_.ImplementationCost
        $costLbl = if ($isTr -and $costMap.ContainsKey($costStr)) { $costMap[$costStr] } else { $costStr }
        "<tr><td><code>$(& $htmlEncode $_.Id)</code> <strong>$(& $htmlEncode $_.Title)</strong><br/><span style='color:#64748b;font-size:11px;'>$(& $htmlEncode $domLbl) · $(& $htmlEncode $_.Category)</span></td><td>$(& $htmlEncode $costLbl)</td><td>$(& $htmlEncode $remText)</td></tr>"
    }) -join "`n"

    $subLine = if ($isTr) { "Üretim: $(Get-Date -Format 'yyyy-MM-dd HH:mm') | Salt Okunur Değerlendirme" } else { "Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm') | Read-Only Assessment" }
    $lblTotal  = if ($isTr) { 'Toplam Kontrol' } else { 'Total' }
    $lblPass   = if ($isTr) { 'Başarılı' } else { 'Passed' }
    $lblFail   = if ($isTr) { 'Başarısız (Yüksek)' } else { 'Failed (High)' }
    $lblIdle   = if ($isTr) { 'Atıl Lisans (Yıllık USD)' } else { 'Idle License (Annual USD)' }
    $thFw      = if ($isTr) { 'Standart / Motor (Framework)' } else { 'Benchmark / Engine (Framework)' }
    $thRatio   = if ($isTr) { 'Geçen / Ölçülen' } else { 'Passed / Total' }
    $thScore   = if ($isTr) { 'Puan' } else { 'Score' }

    # Lab/Test tenant banner when UserCount < 25
    $tiProp = $data.PSObject.Properties['TenantInsights']
    $tiObj = if ($tiProp) { $tiProp.Value } else { $null }
    $labBanner = ''
    if ($tiObj -and $tiObj.PSObject.Properties['UserCount'] -and $null -ne $tiObj.UserCount -and [int]$tiObj.UserCount -gt 0 -and [int]$tiObj.UserCount -lt 25) {
        $uCountInt = [int]$tiObj.UserCount
        $labTxt = if ($isTr) { "Test / Lab Kiracısı Uyarısı: Kiracıda yalnızca $uCountInt kullanıcı tespit edildi; skorlar ve lisans metrikleri üretim ortamını temsil etmeyebilir." } else { "Test / Lab Tenant Notice: Only $uCountInt user(s) detected; scores and license metrics may not represent production scale." }
        $labBanner = "<div style='border:1px solid #38bdf8;background:#f0f9ff;color:#0369a1;padding:8px 12px;border-radius:6px;font-size:12.5px;margin-bottom:14px;'>$(& $htmlEncode $labTxt)</div>"
    }

    # Idle License ROI: show N/A (Uygulanamaz) when Skus is empty and TotalIdleUsdYr is 0
    $roiObj = if ($data.PSObject.Properties['LicenseROI']) { $data.LicenseROI } else { $null }
    $hasSkus = ($roiObj -and $roiObj.PSObject.Properties['Skus'] -and @($roiObj.Skus).Count -gt 0)
    $idleUsdYr = if ($roiObj -and $roiObj.PSObject.Properties['TotalIdleUsdYr'] -and $null -ne $roiObj.TotalIdleUsdYr) { $roiObj.TotalIdleUsdYr } else { 0 }
    $idleDisplay = if (-not $hasSkus -and [double]$idleUsdYr -eq 0) {
        if ($isTr) { 'Uygulanamaz' } else { 'N/A' }
    } else {
        "`$$idleUsdYr"
    }

    # Executive Signals strip (Secure Score, High Incidents, Copilot Maturity, MFA/CA)
    $sigCards = New-Object System.Collections.Generic.List[string]
    if ($tiObj -and $tiObj.PSObject.Properties['SecureScoreCurrent'] -and $null -ne $tiObj.SecureScoreCurrent -and $tiObj.PSObject.Properties['SecureScoreMax'] -and $null -ne $tiObj.SecureScoreMax -and [double]$tiObj.SecureScoreMax -gt 0) {
        $ssLbl = if ($isTr) { 'Microsoft Secure Score' } else { 'Microsoft Secure Score' }
        $sigCards.Add("<div class='card'><div>$ssLbl</div><div class='val' style='font-size:18px;'>$(& $htmlEncode $tiObj.SecureScoreCurrent) / $(& $htmlEncode $tiObj.SecureScoreMax)</div></div>")
    }
    $uaProp = $data.PSObject.Properties['UsageAdoption']
    $secObj = if ($uaProp -and $uaProp.Value -and $uaProp.Value.PSObject.Properties['SecOps']) { $uaProp.Value.SecOps } else { $null }
    if ($secObj -and $secObj.PSObject.Properties['IncidentsAvailable'] -and $secObj.IncidentsAvailable) {
        $incLbl = if ($isTr) { 'Aktif Yüksek Olay (SecOps)' } else { 'Active High Incidents' }
        $sigCards.Add("<div class='card'><div>$incLbl</div><div class='val' style='font-size:18px;'>$(& $htmlEncode $secObj.HighIncidents)</div></div>")
    }
    $copProp = $data.PSObject.Properties['CopilotReadiness']
    if ($copProp -and $copProp.Value -and $copProp.Value.PSObject.Properties['MaturityLevel'] -and $copProp.Value.MaturityLevel) {
        $copLbl = if ($isTr) { 'Copilot Olgunluk Seviyesi' } else { 'Copilot Readiness Maturity' }
        $sigCards.Add("<div class='card'><div>$copLbl</div><div class='val' style='font-size:15px;'>$(& $htmlEncode $copProp.Value.MaturityLevel)</div></div>")
    }
    $signalsHtml = if ($sigCards.Count -gt 0) { "<div class='grid' style='grid-template-columns:repeat($($sigCards.Count),1fr);'>$($sigCards -join '')</div>" } else { '' }

    $html = @"
<!DOCTYPE html>
<html lang="$Language">
<head>
<meta charset="UTF-8" />
<meta http-equiv="Content-Security-Policy" content="default-src 'none'; connect-src 'none'; img-src 'self' data:; style-src 'unsafe-inline'; script-src 'none'; font-src 'none'; base-uri 'none'; form-action 'none';" />
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
  @page { size: A4 portrait; margin: 10mm; }
  @media print {
    body { margin: 0; font-size: 11px; }
    h1 { font-size: 18px; }
    h2 { font-size: 14px; margin-top: 14px !important; }
    .grid { gap: 8px; margin-bottom: 10px; }
    .card { padding: 8px; break-inside: avoid; page-break-inside: avoid; }
    .val { font-size: 18px; }
    table { margin-top: 8px; }
    th, td { padding: 5px 7px; font-size: 10.5px; }
    tr { break-inside: avoid; page-break-inside: avoid; }
  }
</style>
</head>
<body>
  <h1>TenantBrief — $title</h1>
  <div class="sub">$subLine</div>
  $diagNote
  $labBanner
  <div class="grid">
    <div class="card"><div>$lblTotal</div><div class="val">$($data.Summary.Total)</div></div>
    <div class="card"><div>$lblPass</div><div class="val">$($data.Summary.Passed)</div></div>
    <div class="card"><div>$lblFail</div><div class="val">$($data.Summary.Failed) ($($data.Summary.HighRiskFailed))</div></div>
    <div class="card"><div>$lblIdle</div><div class="val">$(& $htmlEncode $idleDisplay)</div></div>
  </div>
  $signalsHtml
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
