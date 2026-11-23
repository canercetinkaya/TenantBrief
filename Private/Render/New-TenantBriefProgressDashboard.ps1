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

    $progressHtmlPath = Join-Path $script:ModuleRoot 'assets/progress-template.html'
    if ($selectedPort -and (Test-Path $progressHtmlPath)) {
        $pHtml = Get-Content -Path $progressHtmlPath -Raw -Encoding UTF8
        $isTrUi = ($Language -eq 'tr')
        $labelsJson = if ($isTrUi) {
            '["1. ZeroTrustAssessment (Kiracı Veri Toplama & Testler)","2. CISA ScubaGear (Güvenlik Taban Hattı)","3. Microsoft ORCA & Maester (MDO, EIDSCA & CIS)","4. Korelasyon, Lisans ROI/İsraf, Copilot & Doğrulanmış Skorlar","5. TenantBrief Rapor Üretimi"]'
        } else {
            '["1. ZeroTrustAssessment (Tenant Data & Checks)","2. CISA ScubaGear (Security Baselines)","3. Microsoft ORCA & Maester (MDO, EIDSCA & CIS)","4. Correlation, License ROI/Waste, Copilot & Verified Scores","5. Generating TenantBrief Reports"]'
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
