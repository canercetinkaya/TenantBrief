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

        $catRaw = [string](Get-TenantBriefPropertyValue -Object $t -Name 'TestCategory')
        $pickId = {
            param([string]$Pattern)
            $m = @($corrList | Where-Object { $_ -match $Pattern } | Select-Object -First 1)
            if ($m.Count -gt 0 -and $m[0]) { [string]$m[0] } else { $tid }
        }
        $refParts = [System.Collections.Generic.List[string]]::new()
        foreach ($src in $sourceList) {
            $refVal = switch ($src) {
                'CIS M365'    { "CIS Microsoft 365 Foundations v7.0.0 ($(& $pickId '^CIS\.M365\.'))" }
                'CISA SCuBA'  { "CISA SCuBA M365 Baseline ($(& $pickId '^SCUBA-'))" }
                'MDO / ORCA'  { "Microsoft Defender for Office 365 / ORCA ($(& $pickId '^ORCA-'))" }
                'EIDSCA'      { "Entra ID Security Config Analyzer ($(& $pickId '^EIDSCA\.'))" }
                'Maester'     { $mId = & $pickId '^MT\.'; if ($catRaw) { "Maester · $catRaw ($mId)" } else { "Maester Security Baseline ($mId)" } }
                'EntraFalcon' { $eId = & $pickId '^EF-'; if ($catRaw) { "EntraFalcon · $catRaw ($eId)" } else { "EntraFalcon Privilege Audit ($eId)" } }
                'ZeroTrust'   { "Microsoft Zero Trust ($domainStr · $(& $pickId '^\d+$'))" }
                default       { "$src ($tid)" }
            }
            $refParts.Add([string]$refVal)
        }
        $fwRef = if ($refParts.Count -gt 0) { $refParts -join ' + ' } else { "Microsoft Zero Trust ($tid)" }

        $fTitle = [string](Get-TenantBriefPropertyValue -Object $t -Name 'TestTitle')
        $fDesc  = [string](Get-TenantBriefPropertyValue -Object $t -Name 'TestDescription')
        $fImp   = [string](Get-TenantBriefPropertyValue -Object $t -Name 'TestImpact')
        $trEntry = $null
        $trReviewed = $true
        if ($Language -eq 'tr' -and $TranslationCache.Count -gt 0) {
            foreach ($sTag in $sourceList) {
                $compositeKey = "$sTag|$tid"
                if ($TranslationCache.ContainsKey($compositeKey)) { $trEntry = $TranslationCache[$compositeKey]; break }
            }
            if (-not $trEntry) {
                foreach ($cid in $corrList) {
                    foreach ($sTag in $sourceList) {
                        $ck = "$sTag|$cid"
                        if ($TranslationCache.ContainsKey($ck)) { $trEntry = $TranslationCache[$ck]; break }
                    }
                    if ($trEntry) { break }
                }
            }
            if (-not $trEntry -and $TranslationCache.ContainsKey($tid)) {
                $trEntry = $TranslationCache[$tid]
            }
            if ($trEntry) {
                if ($trEntry.PSObject.Properties['Title'] -and $trEntry.Title) { $fTitle = [string]$trEntry.Title }
                if ($trEntry.PSObject.Properties['Desc'] -and $trEntry.Desc) { $fDesc = [string]$trEntry.Desc }
                $trReviewed = if ($trEntry.PSObject.Properties['Reviewed']) { [bool]$trEntry.Reviewed } else { $false }
            }
        }
        if ($Language -eq 'tr') {
            $fTitle = ConvertTo-TenantBriefTurkish -Text $fTitle
            $fDesc  = ConvertTo-TenantBriefTurkish -Text $fDesc
        }
        if ($Language -eq 'tr' -and $fImp) {
            $fImp = $fImp -replace '^High$', 'Yüksek' -replace '^Medium$', 'Orta' -replace '^Low$', 'Düşük'
        }

        $statusRaw = [string](Get-TenantBriefPropertyValue -Object $t -Name 'TestStatus')
        $catRaw = [string](Get-TenantBriefPropertyValue -Object $t -Name 'TestCategory')
        $domPrimary = if ($domainList.Count -gt 0) { [string]$domainList[0] } else { $primaryPillar }

        # Determine admin portal & least-privilege role from Control ID, Sources, Category, and canonical DomainPillar
        $i18n = Get-TenantBriefI18n -Language $Language
        $portalKey = if (($sourceList -contains 'MDO / ORCA') -or $tid -like 'ORCA-*' -or $tid -match '^SCUBA-MS\.EXO\.' -or $catRaw -match 'Exchange|EXO|Anti-Phish|Safe Links|Safe Attachments|DKIM|DMARC|SPF|OWA') {
            'defenderExchange'
        } elseif ($tid -match '^(CIS\.M365\.8\.|SCUBA-MS\.TEAMS\.)' -or $catRaw -match 'Teams') {
            'teams'
        } elseif ($domPrimary -eq 'Devices' -or ($domPrimary -ne 'Identity' -and $catRaw -match 'Intune|BitLocker|Device|Compliance')) {
            'intune'
        } elseif ($tid -match '^SCUBA-MS\.SHAREPOINT\.' -or $catRaw -match 'SharePoint|OneDrive') {
            'sharePointPurview'
        } elseif ($domPrimary -eq 'AI' -or $catRaw -match 'Copilot|Agent') {
            'aiPurviewEntra'
        } elseif ($domPrimary -eq 'Data' -or $tid -match '^SCUBA-MS\.SECURITYSUITE\.3\.' -or $catRaw -match 'Purview|Sensitivity|DLP|Information Protection|Encryption|Lockbox|Storage') {
            'purview'
        } elseif ($catRaw -match 'Defender for Cloud|AzureConfig|Azure Network') {
            'azure'
        } elseif ($domPrimary -eq 'Network' -or $catRaw -match 'Global Secure Access|Private Access|Application Proxy') {
            'globalSecureAccess'
        } elseif ($domPrimary -eq 'SecOps' -or $tid -match '^SCUBA-MS\.SECURITYSUITE\.' -or $catRaw -match 'Defender|Exposure|Audit|Sentinel|Incident|Threat') {
            'defenderXdr'
        } elseif ($domPrimary -eq 'Identity') {
            'entra'
        } else {
            'm365Admin'
        }
        $portalName = if ($i18n -and $i18n.portals.PSObject.Properties[$portalKey]) { [string]$i18n.portals.$portalKey } else { 'Microsoft 365 Admin Center' }
        $requiredRole = if ($i18n -and $i18n.roles.PSObject.Properties[$portalKey]) { [string]$i18n.roles.$portalKey } else { 'Security Administrator' }

        # Extract concrete remediation bullet/step from Description on sentence boundaries (no ellipsis, no Learn/öğrenin artifacts).
        $remTr = ''
        $remLocalized = ''
        if ($statusRaw -in @('Failed', 'Investigate')) {
            $extractedStep = ''
            if ($fDesc -match '(?is)(?:\*\*Düzeltme işlemi\*\*|####\s*Remediation action|\*\*Remediation action\*\*)(.+)$') {
                $rawLines = @($Matches[1] -split '\r?\n' | Where-Object {
                    $ln = $_.Trim()
                    $ln -and ($ln -notmatch '(?i)(Related links|İlgili bağlantılar|Learn|Daha fazla bilgi|öğrenin|For more information|See also)')
                })
                $remBlock = (($rawLines -join ' ') -replace '```[\s\S]*?```', ' ' -replace '\[([^\]]+)\]\([^\)]+\)', '$1' -replace 'https?://\S+', ' ' -replace '[#*_`>|\[\]]', ' ' -replace '\.\.\.+', '.' -replace '\s+', ' ').Trim()
                # Keep complete sentences up to 220 chars without mid-word ellipsis
                $sentences = @($remBlock -split '(?<=[.!?])\s+' | Where-Object {
                    $_ -and ($_ -notmatch '(?i)(Related links|İlgili bağlantılar|Learn|Daha fazla bilgi|öğrenin|For more information)')
                })
                $acc = ''
                foreach ($sent in $sentences) {
                    $cand = if ($acc) { "$acc $sent" } else { $sent }
                    if ($cand.Length -le 220) {
                        $acc = $cand
                    } else {
                        if (-not $acc) {
                            $cut = $sent.Substring(0, [Math]::Min(215, $sent.Length))
                            $lastSp = $cut.LastIndexOf(' ')
                            if ($lastSp -gt 40) { $cut = $cut.Substring(0, $lastSp) }
                            $acc = $cut.TrimEnd(' ', ',', ';', ':', '.') + '.'
                        }
                        break
                    }
                }
                if ($acc -and $acc -notmatch '[.!?]$') { $acc = "$acc." }
                $extractedStep = $acc.Trim()
            }
            if ($extractedStep -and $extractedStep.Length -gt 12) {
                $remTr = "$portalName üzerinden uygulayın: $extractedStep Pilot gruba Denetim (Report-only) kipinde uygulayıp doğruladıktan sonra Zorunlu (Enforce) durumuna geçin. [En Az Ayrıcalıklı Rol: $requiredRole]"
                $remEn = "Apply in $portalName`: $extractedStep Roll out in Report-only mode to a pilot group, verify sign-in/audit logs, then switch to Enforce. [Least-Privilege Role: $requiredRole]"
            } else {
                $remTr = "1. $portalName üzerinden '$fTitle' kontrolünü açın. 2. Değişikliği önce Denetim (Report-only) kipinde pilot gruba uygulayıp oturum açma/olay günlüklerini doğrulayın. 3. Etki analizi sonrası kademeli olarak Zorunlu (Enforce) durumuna geçin. [En Az Ayrıcalıklı Rol: $requiredRole]"
                $remEn = "1. Open '$fTitle' in $portalName. 2. Apply the change to a pilot group in Report-only mode and verify sign-in/audit logs. 3. Enforce incrementally after impact validation. [Least-Privilege Role: $requiredRole]"
            }
            $remLocalized = if ($Language -eq 'tr') { $remTr } else { $remEn }
        }

        $minLicRaw = Get-TenantBriefPropertyValue -Object $t -Name 'TestMinimumLicense'
        $minLicStr = if ($minLicRaw -is [System.Array]) { ($minLicRaw -join ', ') } else { [string]$minLicRaw }
        $implCostRaw = Get-TenantBriefPropertyValue -Object $t -Name 'TestImplementationCost'
        $sfiRaw      = Get-TenantBriefPropertyValue -Object $t -Name 'TestSfiPillar'
        $riskRaw     = Get-TenantBriefPropertyValue -Object $t -Name 'TestRisk'
        $resultRaw   = Get-TenantBriefPropertyValue -Object $t -Name 'TestResult'
        $skippedRaw  = Get-TenantBriefPropertyValue -Object $t -Name 'SkippedReason'
        $errRemedy = ''
        if ($statusRaw -eq 'Error') {
            $resStr = [string]$resultRaw
            $scopeMatch = [regex]::Match($resStr, '\b([A-Za-z][A-Za-z0-9]+\.(?:Read|ReadBasic)(?:\.All)?)\b')
            $scopeHint = if ($scopeMatch.Success) { " ($($scopeMatch.Groups[1].Value))" } else { '' }
            if ($resStr -match '403|Forbidden|Authorization_RequestDenied|Insufficient privileges|Missing.*scope|Unauthorized') {
                $errRemedy = if ($Language -eq 'tr') {
                    "HTTP 403 / Yetki eksikliği tespit edildi$scopeHint. Oturumu gerekli salt okunur Graph/M365 izniyle yeniden bağlayın (Connect-TenantBrief) ve yönetici onayını doğrulayın."
                } else {
                    "HTTP 403 / Missing permission detected$scopeHint. Reconnect with the required read-only Graph/M365 scope (Connect-TenantBrief) and verify admin consent."
                }
            } else {
                $errRemedy = if ($Language -eq 'tr') {
                    "Denetim motoru hata döndürdü; ayrıntı için run-manifest.json ve ham motor günlüklerini inceleyin."
                } else {
                    "Assessment engine returned an error; inspect run-manifest.json and raw engine logs."
                }
            }
        }

        $canonicalRaw = [string](Get-TenantBriefPropertyValue -Object $t -Name 'CanonicalId')
        $srcStatusesRaw = Get-TenantBriefPropertyValue -Object $t -Name 'SourceStatuses'
        if ($null -eq $srcStatusesRaw) {
            $srcStatusesRaw = [ordered]@{}
            foreach ($s in $sourceList) { if ($s) { $srcStatusesRaw[$s] = $statusRaw } }
        }
        $conflictRaw = [bool](Get-TenantBriefPropertyValue -Object $t -Name 'StatusConflict')

        $riskFinal = if ($riskRaw) { [string]$riskRaw } else { 'Low' }
        $costFinal = if ($implCostRaw) { [string]$implCostRaw } else { 'Unknown' }
        $prioScore = Get-TenantBriefPriorityScore -Status $statusRaw -Risk $riskFinal -ImplementationCost $costFinal -SourceCount $sourceList.Count -StatusConflict $conflictRaw
        $canonicalPrimary = if ($domainList.Count -gt 0) { [string]$domainList[0] } else { 'Identity' }
        [PSCustomObject]@{
            Id                 = $tid
            CanonicalId        = $canonicalRaw
            CorrelatedIds      = @($corrList)
            Pillar             = $canonicalPrimary
            PrimaryPillar      = $canonicalPrimary
            DomainPillar       = $canonicalPrimary
            DomainPillars      = @($domainList)
            EngineLabel        = if ($pillarStr) { $pillarStr } else { $canonicalPrimary }
            Source             = $sourceStr
            Sources            = @($sourceList)
            SourceStatuses     = $srcStatusesRaw
            StatusConflict     = $conflictRaw
            Category           = if ($catRaw) { $catRaw } else { 'General' }
            SfiPillar          = if ($sfiRaw) { [string]$sfiRaw } else { '' }
            ImplementationCost = $costFinal
            MinimumLicense     = $minLicStr
            RequiredRole       = $requiredRole
            AdminPortal        = $portalName
            Status             = $statusRaw
            Risk               = $riskFinal
            PriorityScore      = $prioScore
            Title              = $fTitle
            FrameworkRef       = $fwRef
            Result             = [string]$resultRaw
            UserImpact         = $fImp
            Impact             = $fImp
            Description        = $fDesc
            SkippedReason      = [string]$skippedRaw
            ErrorRemedy        = $errRemedy
            Remediation         = $remLocalized
            RemediationTr       = $remTr
            TranslationReviewed = $trReviewed
        }
    }
}
