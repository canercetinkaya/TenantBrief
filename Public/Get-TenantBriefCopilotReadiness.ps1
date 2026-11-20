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

    # 3b. Extended FastTrack Get-M365CopilotReadiness signals (EXO, OneDrive, Teams, ManualChecks)
    if ($ftData -and $ftData.PSObject.Properties['Readiness'] -and $ftData.Readiness) {
        $rd = $ftData.Readiness
        $ftChecks = @(
            @{ Prop = 'EXO_PrimaryMailboxHostedInEXO'; Id = 'COP-EXO-FT'; CatTr = 'Exchange Online Hazırlığı (FastTrack)'; CatEn = 'Exchange Online Readiness (FastTrack)'; TitleTr = 'Birincil Posta Kutularının Exchange Online Barındırması'; TitleEn = 'Primary Mailboxes Hosted in Exchange Online'; ExpTr = 'Copilot Outlook ve takvim entegrasyonu için birincil posta kutularının Exchange Online üzerinde barındırılması gerekir.'; ExpEn = 'Copilot for Outlook and calendar requires primary mailboxes hosted in Exchange Online.' },
            @{ Prop = 'OneDrive_Provisioned'; Id = 'COP-OD-FT'; CatTr = 'OneDrive Hazırlığı (FastTrack)'; CatEn = 'OneDrive Readiness (FastTrack)'; TitleTr = 'OneDrive for Business Sağlama Durumu'; TitleEn = 'OneDrive for Business Provisioning'; ExpTr = 'Copilot dosya özetleme, Word/PowerPoint taslakları ve kullanıcı bazlı çalışma alanları OneDrive gerektirir.'; ExpEn = 'Copilot document grounding and creation workflows require provisioned OneDrive storage.' },
            @{ Prop = 'Teams_ServiceConnected'; Id = 'COP-TEAMS-FT'; CatTr = 'Microsoft Teams Hazırlığı (FastTrack)'; CatEn = 'Microsoft Teams Readiness (FastTrack)'; TitleTr = 'Microsoft Teams Servis & Transkripsiyon Hazırlığı'; TitleEn = 'Microsoft Teams Service Readiness'; ExpTr = 'Teams toplantı özetleri ve sohbet zekâsı için Teams bulut servis bağlantısı ve transkripsiyon politikaları gereklidir.'; ExpEn = 'Teams meeting recap and chat grounding require Teams cloud service readiness.' }
        )
        foreach ($fc in $ftChecks) {
            $val = [string](Get-TenantBriefPropertyValue -Object $rd -Name $fc.Prop)
            if ($val) {
                $st = if ($val -match '^Pass|^Success|^Enabled') { 'Pass' } elseif ($val -match '^Fail|^Error') { 'Fail' } else { 'Warning' }
                $checks += [PSCustomObject]@{
                    Id          = $fc.Id
                    Category    = if ($isTr) { $fc.CatTr } else { $fc.CatEn }
                    Status      = $st
                    Title       = if ($isTr) { $fc.TitleTr } else { $fc.TitleEn }
                    Detail      = "FastTrack Readiness.$($fc.Prop) = $val"
                    Explanation = if ($isTr) { $fc.ExpTr } else { $fc.ExpEn }
                    Warning     = if ($st -ne 'Pass') { if ($isTr) { "UYARI: FastTrack $($fc.Prop) durumu '$val'." } else { "WARNING: FastTrack $($fc.Prop) status is '$val'." } } else { '' }
                }
            }
        }
        $manList = @(Get-TenantBriefPropertyValue -Object $rd -Name 'ManualChecks' | Where-Object { $null -ne $_ })
        if ($manList.Count -gt 0) {
            $manNames = @($manList | ForEach-Object { [string](Get-TenantBriefPropertyValue -Object $_ -Name 'Name') } | Where-Object { $_ }) -join ' · '
            $checks += [PSCustomObject]@{
                Id          = 'COP-MANUAL-FT'
                Category    = if ($isTr) { 'İstemci & Ağ Önkoşulları (FastTrack)' } else { 'Client & Network Prerequisites (FastTrack)' }
                Status      = 'Warning'
                Title       = if ($isTr) { 'FastTrack Manuel Doğrulama Gerektiren Copilot Önkoşulları' } else { 'FastTrack Manual Verification Prerequisites' }
                Detail      = if ($isTr) { "$($manList.Count) manuel madde: $manNames" } else { "$($manList.Count) manual checks: $manNames" }
                Explanation = if ($isTr) { 'M365 Apps güncelleme kanalı (Current / Monthly Enterprise), web üçüncü taraf çerez/gizlilik ayarları ve cihaz bazlı lisanslama kısıtları elle doğrulanmalıdır.' } else { 'Verify M365 Apps update channel (Current/Monthly Enterprise), web third-party cookies/privacy controls, and device-based licensing exclusions.' }
                Warning     = if ($isTr) { 'BİLGİ: Bu maddeler Graph API üzerinden otomatik okunamadığından dağıtım öncesi manuel kontrol gerektirir.' } else { 'NOTICE: These prerequisites require manual confirmation prior to Copilot rollout.' }
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

    $scCfg = Get-TenantBriefScoringConfig
    $passW = if ($scCfg -and $scCfg.PSObject.Properties['copilotReadiness']) { [double]$scCfg.copilotReadiness.passWeight } else { 1.0 }
    $warnW = if ($scCfg -and $scCfg.PSObject.Properties['copilotReadiness']) { [double]$scCfg.copilotReadiness.warningWeight } else { 0.5 }
    $failW = if ($scCfg -and $scCfg.PSObject.Properties['copilotReadiness']) { [double]$scCfg.copilotReadiness.failWeight } else { 0.0 }
    $gateIds = if ($scCfg -and $scCfg.PSObject.Properties['copilotReadiness'] -and $scCfg.copilotReadiness.gateIds) { @($scCfg.copilotReadiness.gateIds) } else { @('COP-LIC-01') }

    $weightedSum = 0.0
    $gateFailed = $false
    foreach ($chk in @($checks)) {
        if ($chk.Status -eq 'Pass') { $weightedSum += $passW }
        elseif ($chk.Status -eq 'Warning') { $weightedSum += $warnW }
        else {
            $weightedSum += $failW
            if ($chk.Status -eq 'Fail' -and (($gateIds -contains $chk.Id) -or $chk.Id -eq 'COP-LIC-01')) {
                $gateFailed = $true
            }
        }
    }
    $totC = [Math]::Max(1, $checks.Count)
    $readinessScore = [Math]::Round(($weightedSum / $totC) * 100, 1)
    $maturity = if ($gateFailed) {
        if ($isTr) { 'L1 - Başlangıç (Initial)' } else { 'L1 - Initial' }
    } elseif ($isTr) {
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
