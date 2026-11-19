function Import-TenantBriefSharePointRisk {
    <#
    .SYNOPSIS
    Read-only parser & risk scorer for SharePoint permissions CSV exports (Microsoft SAM DAG / FastTrack Analyze-SharePointRisk).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$CsvPath,

        [Parameter()]
        [ValidateSet('tr', 'en')]
        [string]$Language = 'tr'
    )

    if (-not (Test-Path $CsvPath)) { return $null }
    $isTr = ($Language -eq 'tr')
    try {
        $rows = @(Import-Csv -Path $CsvPath -Encoding UTF8)
    } catch {
        Write-Warning "[TenantBrief] Failed to parse SharePoint Risk CSV '$CsvPath': $($_.Exception.Message)"
        return $null
    }
    if ($rows.Count -eq 0) { return $null }

    $getCol = {
        param($Row, [string[]]$Candidates)
        foreach ($c in $Candidates) {
            foreach ($p in $Row.PSObject.Properties) {
                if ($p.Name -and $p.Name.Trim().ToLowerInvariant() -eq $c.ToLowerInvariant()) {
                    return [string]$p.Value
                }
            }
        }
        return ''
    }
    $toInt = {
        param([string]$Val)
        $n = 0
        if ([int]::TryParse(($Val -replace '[^\d-]', ''), [ref]$n)) { return $n }
        return 0
    }

    $sensitiveRx = '(?i)\b(hr|human.?resources|payroll|finance|legal|board|exec|executive|confidential|secret|salary|m&a|merger|ik|insan.?kaynak|finans|hukuk|yonetim|bordro|gizli)\b'
    $scoredSites = @()
    $eeeuHighSites = 0
    $privateEeeuSites = 0
    $everyoneSites = 0
    $anyoneSites = 0
    $noLabelSites = 0
    $highUniqueSites = 0
    $publicSensitiveSites = 0

    foreach ($r in $rows) {
        $name = & $getCol $r @('Site name', 'SiteName', 'Title')
        $url  = & $getCol $r @('Site URL', 'SiteUrl', 'Url')
        $priv = & $getCol $r @('Site privacy', 'Privacy')
        $sens = & $getCol $r @('Site sensitivity', 'SensitivityLabel', 'Sensitivity')
        $eeeu = & $toInt (& $getCol $r @('EEEU permission count', 'EEEUCount', 'EEEU'))
        $evry = & $toInt (& $getCol $r @('Everyone permission count', 'EveryoneCount', 'Everyone'))
        $any  = & $toInt (& $getCol $r @('Anyone link count', 'AnyoneLinks', 'Anyone'))
        $uniq = & $toInt (& $getCol $r @('Items with unique permissions count', 'UniquePermissionsCount'))
        $users = & $toInt (& $getCol $r @('Number of users having access', 'UserCount'))

        # Official Microsoft FastTrack Analyze-SharePointRisk.ps1 default weights
        $score = 0
        $reasons = @()
        if ($eeeu -ge 10) { $score += 4; $eeeuHighSites++; $reasons += "EEEU($eeeu)" }
        if ($priv -match '(?i)^private$' -and $eeeu -gt 0) { $score += 3; $privateEeeuSites++; $reasons += 'Private+EEEU' }
        if ($priv -match '(?i)^public$' -and $name -match $sensitiveRx) { $score += 5; $publicSensitiveSites++; $reasons += 'Public+SensitiveTitle' }
        if ($evry -gt 0) { $score += 3; $everyoneSites++; $reasons += "Everyone($evry)" }
        if ($any -gt 0) { $score += 2; $anyoneSites++; $reasons += "Anyone($any)" }
        if ($uniq -ge 50) { $score += 3; $highUniqueSites++; $reasons += "Unique($uniq)" }
        if ([string]::IsNullOrWhiteSpace($sens)) { $score += 1; $noLabelSites++; $reasons += 'NoLabel' }

        $level = if ($score -ge 10) { 'Critical' } elseif ($score -ge 7) { 'High' } elseif ($score -ge 4) { 'Medium' } elseif ($score -ge 1) { 'Low' } else { 'Minimal' }
        $scoredSites += [PSCustomObject]@{
            SiteName          = if ($name) { $name } else { $url }
            SiteUrl           = $url
            Privacy           = if ($priv) { $priv } else { '-' }
            SensitivityLabel  = if ($sens) { $sens } else { '-' }
            UsersWithAccess   = $users
            EEEUCount         = $eeeu
            EveryoneCount     = $evry
            AnyoneLinks       = $any
            UniquePermissions = $uniq
            RiskScore         = $score
            RiskLevel         = $level
            Reasons           = ($reasons -join ', ')
        }
    }

    $criticalCount = @($scoredSites | Where-Object { $_.RiskLevel -eq 'Critical' }).Count
    $highCount     = @($scoredSites | Where-Object { $_.RiskLevel -eq 'High' }).Count
    $mediumCount   = @($scoredSites | Where-Object { $_.RiskLevel -eq 'Medium' }).Count
    $topSites      = @($scoredSites | Sort-Object RiskScore, EEEUCount, AnyoneLinks -Descending | Select-Object -First 25)

    $findings = @()
    $eeeuTotalAffected = @($scoredSites | Where-Object { $_.EEEUCount -ge 10 -or ($_.Privacy -match '(?i)^private$' -and $_.EEEUCount -gt 0) }).Count
    $findings += [PSCustomObject]@{
        TestId                 = 'FT.SPO.001'
        TestTitle              = if ($isTr) { 'SharePoint EEEU (Everyone Except External Users) Aşırı Paylaşım Riski' } else { 'SharePoint EEEU (Everyone Except External Users) Oversharing Risk' }
        TestStatus             = if ($eeeuTotalAffected -gt 0) { 'Failed' } else { 'Passed' }
        TestRisk               = 'High'
        TestPillar             = 'FastTrack'
        TestDomainPillars      = @('Data', 'AI')
        TestSource             = 'FastTrack'
        TestCategory           = 'SharePoint Oversharing (FastTrack)'
        TestSfiPillar          = 'Protect tenants and isolate production systems'
        TestImplementationCost = 'Medium'
        TestMinimumLicense     = 'Microsoft_365_Copilot'
        TestResult             = if ($isTr) { "İncelenen $($scoredSites.Count) siteden $eeeuHighSites sitede yüksek EEEU (>=10), $privateEeeuSites özel sitede EEEU erişimi tespit edildi." } else { "Out of $($scoredSites.Count) sites, $eeeuHighSites have high EEEU (>=10) and $privateEeeuSites private sites expose EEEU access." }
        TestDescription        = if ($isTr) { 'Microsoft FastTrack Analyze-SharePointRisk modeline göre EEEU izinleri kurumdaki tüm kullanıcıların ve Microsoft 365 Copilot indekslemesinin hassas site içeriğine erişmesine yol açar.' } else { 'Per Microsoft FastTrack Analyze-SharePointRisk scoring, EEEU permissions expose site documents to every internal user and Microsoft 365 Copilot grounding.' }
        TestImpact             = if ($isTr) { 'Copilot yanıtlarında yetkisiz iç veri sızıntısı ve aşırı paylaşım riski.' } else { 'Internal oversharing and unintended sensitive data surfacing in Copilot responses.' }
        SkippedReason          = ''
    }

    $extBroadCount = @($scoredSites | Where-Object { $_.AnyoneLinks -gt 0 -or $_.EveryoneCount -gt 0 -or ($_.Privacy -match '(?i)^public$' -and $_.SiteName -match $sensitiveRx) }).Count
    $findings += [PSCustomObject]@{
        TestId                 = 'FT.SPO.002'
        TestTitle              = if ($isTr) { 'SharePoint Anonim Bağlantılar (Anyone), Everyone İzinleri ve Hassas Açık Siteler' } else { 'SharePoint Anyone Links, Everyone Permissions & Sensitive Public Sites' }
        TestStatus             = if ($extBroadCount -gt 0) { 'Failed' } else { 'Passed' }
        TestRisk               = 'High'
        TestPillar             = 'FastTrack'
        TestDomainPillars      = @('Data', 'AI')
        TestSource             = 'FastTrack'
        TestCategory           = 'SharePoint Oversharing (FastTrack)'
        TestSfiPillar          = 'Protect tenants and isolate production systems'
        TestImplementationCost = 'Low'
        TestMinimumLicense     = 'Microsoft_365_Copilot'
        TestResult             = if ($isTr) { "Anyone bağlantısı olan site: $anyoneSites · Everyone izni olan site: $everyoneSites · Hassas başlıklı açık site: $publicSensitiveSites." } else { "Sites with Anyone links: $anyoneSites · Everyone permissions: $everyoneSites · Public sites with sensitive titles: $publicSensitiveSites." }
        TestDescription        = if ($isTr) { 'Anonim paylaşım bağlantıları (Anyone) ve hassas içerikli açık siteler hem dış sızıntı hem de Copilot aşırı paylaşımı açısından en yüksek riskli yüzeydir.' } else { 'Anonymous Anyone links, Everyone grants, and public sites with sensitive names represent critical external and Copilot oversharing exposure.' }
        TestImpact             = if ($isTr) { 'Kimlik doğrulamasız dış erişim ve hassas dokümanların kontrolsüz paylaşımı.' } else { 'Unauthenticated external exposure and broad discovery of sensitive corporate content.' }
        SkippedReason          = ''
    }

    $findings += [PSCustomObject]@{
        TestId                 = 'FT.SPO.003'
        TestTitle              = if ($isTr) { 'Hassasiyet Etiketi Eksik ve Yüksek Benzersiz İzinli SharePoint Siteleri' } else { 'Unlabeled SharePoint Sites & High Unique Permission Sprawl' }
        TestStatus             = if ($highUniqueSites -gt 0 -or ($noLabelSites -gt 0 -and $noLabelSites -eq $scoredSites.Count)) { 'Failed' } elseif ($noLabelSites -gt 0) { 'Investigate' } else { 'Passed' }
        TestRisk               = if ($highUniqueSites -gt 0) { 'Medium' } else { 'Low' }
        TestPillar             = 'FastTrack'
        TestDomainPillars      = @('Data', 'AI')
        TestSource             = 'FastTrack'
        TestCategory           = 'SharePoint Governance (FastTrack)'
        TestSfiPillar          = 'Protect tenants and isolate production systems'
        TestImplementationCost = 'Medium'
        TestMinimumLicense     = 'RMS_S_PREMIUM'
        TestResult             = if ($isTr) { "Etiketsiz site: $noLabelSites / $($scoredSites.Count) · Yüksek benzersiz izinli (>=50) site: $highUniqueSites." } else { "Unlabeled sites: $noLabelSites / $($scoredSites.Count) · High unique permissions (>=50): $highUniqueSites." }
        TestDescription        = if ($isTr) { 'Purview hassasiyet etiketi bulunmayan ve 50+ kırık/benzersiz izin barındıran sitelerde erişim yönetişimi zorlaşır; RAC/RCD ve Site Access Review önerilir.' } else { 'Unlabeled sites and extensive unique permission sprawl (>=50 items) hinder governance; enforce Purview labels and Site Access Reviews.' }
        TestImpact             = if ($isTr) { 'Erişim denetimi kör noktası ve etiket bazlı Copilot/DLP kurallarının atlanması.' } else { 'Governance blind spots and inability to enforce label-based Copilot/DLP protections.' }
        SkippedReason          = ''
    }

    return [PSCustomObject]@{
        Summary = [PSCustomObject]@{
            TotalSites           = $scoredSites.Count
            CriticalSites        = $criticalCount
            HighRiskSites        = $highCount
            MediumRiskSites      = $mediumCount
            EEEUHighSites        = $eeeuHighSites
            PrivateEEEUSites     = $privateEeeuSites
            EveryoneSites        = $everyoneSites
            AnyoneLinkSites      = $anyoneSites
            PublicSensitiveSites = $publicSensitiveSites
            UnlabeledSites       = $noLabelSites
            HighUniquePermSites  = $highUniqueSites
            TopRiskySites        = @($topSites)
        }
        Findings = @($findings)
    }
}
