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
        [switch]$SkipMaester,

        [Parameter(Mandatory = $false)]
        [string[]]$ScubaProducts = @('aad', 'securitysuite', 'exo', 'powerplatform', 'sharepoint', 'teams', 'powerbi'),

        [Parameter(Mandatory = $false)]
        [switch]$AutoFixDependencies,

        [Parameter(Mandatory = $false)]
        [switch]$ScubaInteractiveLogin
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
        if ($AutoFixDependencies) {
            & $Log "[Stage 2/5] ScubaGear not found — installing from PSGallery..."
            try { Install-Module -Name ScubaGear -Repository PSGallery -Scope CurrentUser -Force -AllowClobber -ErrorAction Stop } catch {
                & $note 2 'ScubaGear' "Module install failed: $($_.Exception.Message)"
            }
        } else {
            & $Log "[Stage 2/5] ScubaGear not installed (skipped). Run: Install-Module ScubaGear -Scope CurrentUser (or pass -AutoFixDependencies)."
            & $note 2 'ScubaGear' 'Module not installed. Run: Install-Module ScubaGear -Scope CurrentUser (or pass -AutoFixDependencies).'
        }
    }
    if (Get-Module -ListAvailable -Name 'ScubaGear') {
        $scubaOut = Join-Path $OutputPath 'raw-scuba'
        if (-not (Test-Path $scubaOut)) { New-Item -ItemType Directory -Path $scubaOut -Force | Out-Null }
        try {
            if (-not (Get-Module -ListAvailable -Name 'powershell-yaml')) {
                if ($AutoFixDependencies) {
                    Install-Module -Name 'powershell-yaml' -Repository PSGallery -Scope CurrentUser -Force -ErrorAction SilentlyContinue
                } else {
                    & $note 2 'ScubaGear' 'Optional dependency powershell-yaml missing. Run: Install-Module powershell-yaml -Scope CurrentUser.'
                }
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
                if ($AutoFixDependencies) {
                    & $Log "[Stage 2/5] Installing OPA executable for ScubaGear..."
                    Install-OPAforSCuBA | Out-Null
                } else {
                    throw "OPA executable missing at '$opaExePath'. Run: Install-OPAforSCuBA (or pass -AutoFixDependencies)."
                }
            }
            $requestedScuba = @($ScubaProducts | ForEach-Object { ([string]$_).Trim().ToLowerInvariant() } | Where-Object { $_ } | Select-Object -Unique)
            if ($requestedScuba.Count -eq 0) { $requestedScuba = @('aad', 'securitysuite', 'exo', 'powerplatform', 'sharepoint', 'teams', 'powerbi') }
            & $Log "[Stage 2/5] Running CISA ScubaGear checks ($($requestedScuba -join ', ') — LogIn=$([bool]$ScubaInteractiveLogin))..."
            $null = Invoke-SCuBA -ProductNames $requestedScuba -LogIn:([bool]$ScubaInteractiveLogin) -DisconnectOnExit:$false -OPAPath $opaDir -OutPath $scubaOut -Quiet 6>$null 3>$null
            $scubaItems = @(Import-TenantBriefScubaResults -Path $scubaOut)
            $executedScuba = @($scubaItems | ForEach-Object { ([string]$_.TestCategory).Trim().ToLowerInvariant() } | Where-Object { $_ } | Select-Object -Unique)
            $skippedScuba = @($requestedScuba | Where-Object { $executedScuba -notcontains $_ })
            if ($Manifest) {
                $scubaSummaryObj = [PSCustomObject]@{
                    Requested = @($requestedScuba)
                    Executed  = @($executedScuba)
                    Skipped   = @($skippedScuba)
                }
                $Manifest | Add-Member -NotePropertyName 'ScubaProducts' -NotePropertyValue $scubaSummaryObj -Force
            }
            if ($skippedScuba.Count -gt 0 -and $null -ne $Diagnostics) {
                $skipListStr = $skippedScuba -join ', '
                $msgScuba = "ScubaGear partial coverage ($($executedScuba.Count)/$($requestedScuba.Count) products executed). Skipped: $skipListStr."
                $remScuba = "ScubaGear 2.0 requires its own authentication context for non-AAD providers. Re-run with -ScubaInteractiveLogin for interactive full 7-product coverage, or run Invoke-SCuBA directly with -AppID, -CertificateThumbprint, and -Organization for non-interactive coverage."
                Add-TenantBriefDiagnostic -Diagnostics $Diagnostics -Stage 2 -Component 'ScubaGear' -Message $msgScuba -Severity 'Warning' -Remedy $remScuba
            }
            if ($scubaItems.Count -gt 0) {
                $collected += $scubaItems
                & $Log "[Stage 2/5] ScubaGear completed: $($scubaItems.Count) controls merged ($($executedScuba.Count)/$($requestedScuba.Count) products)."
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
        if ($AutoFixDependencies) {
            & $Log "[Stage 3/5] ORCA not found — installing from PSGallery..."
            try { Install-Module -Name ORCA -Repository PSGallery -Scope CurrentUser -Force -AllowClobber -ErrorAction Stop } catch {
                & $note 3 'ORCA' "Module install failed: $($_.Exception.Message)"
            }
        } else {
            & $Log "[Stage 3/5] ORCA not installed (skipped). Run: Install-Module ORCA -Scope CurrentUser (or pass -AutoFixDependencies)."
            & $note 3 'ORCA' 'Module not installed. Run: Install-Module ORCA -Scope CurrentUser (or pass -AutoFixDependencies).'
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
