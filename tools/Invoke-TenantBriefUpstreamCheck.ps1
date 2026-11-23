<#
.SYNOPSIS
Monthly read-only upstream dependency check for TenantBrief (S8.1).

.DESCRIPTION
Checks PSGallery (ZeroTrustAssessment, ScubaGear, ORCA, Maester) and GitHub Releases
(CompassSecurity/EntraFalcon) against pinned versions in data/upstream-versions.json.
Enforces strict monthly/daily attempt locks, runs sandboxed compatibility checks in %TEMP%
(using Save-Module and a detached git worktree, never touching user modules or the working tree),
writes a markdown report under %LOCALAPPDATA%\TenantBrief\, opens a deduplicated GitHub issue
with label "upstream" only when changes/breakages are found, and shows a built-in Windows toast/balloon.
Never commits, pushes, merges, connects to a live tenant, or calls Install-Module / Remove-Item.

.EXAMPLE
pwsh -NoProfile -File .\tools\Invoke-TenantBriefUpstreamCheck.ps1 -DryRun
#>
[CmdletBinding()]
param(
    [Parameter()]
    [datetime]$Now = (Get-Date),

    [Parameter()]
    [string]$StatePath = $(if ($env:LOCALAPPDATA) { Join-Path $env:LOCALAPPDATA 'TenantBrief/upstream-check.json' } else { Join-Path ([System.IO.Path]::GetTempPath()) 'TenantBrief/upstream-check.json' }),

    [Parameter()]
    [string]$ReportDir = $(if ($env:LOCALAPPDATA) { Join-Path $env:LOCALAPPDATA 'TenantBrief' } else { Join-Path ([System.IO.Path]::GetTempPath()) 'TenantBrief' }),

    [Parameter()]
    [string]$VersionsPath = (Join-Path (Split-Path -Path $PSScriptRoot -Parent) 'data/upstream-versions.json'),

    [Parameter()]
    [string]$RepoPath = (Split-Path -Path $PSScriptRoot -Parent),

    [Parameter()]
    [switch]$DryRun,

    [Parameter()]
    [switch]$SkipSandbox
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Send-UpstreamNotification {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Title,
        [Parameter(Mandatory = $true)][string]$Message
    )
    if ($env:TENANTBRIEF_SUPPRESS_NOTIFY -eq '1') { return }
    try {
        if ($IsWindows) {
            Add-Type -AssemblyName System.Windows.Forms -ErrorAction Stop
            Add-Type -AssemblyName System.Drawing -ErrorAction Stop
            $ni = [System.Windows.Forms.NotifyIcon]::new()
            $ni.Icon = [System.Drawing.SystemIcons]::Information
            $ni.BalloonTipTitle = $Title
            $ni.BalloonTipText = $Message
            $ni.Visible = $true
            $ni.ShowBalloonTip(5000)
            Start-Sleep -Milliseconds 300
            $ni.Dispose()
        }
    } catch {
        Write-Verbose "Notification skipped: $($_.Exception.Message)"
    }
}

function Read-UpstreamState {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$Path)
    $defaultState = [PSCustomObject]@{
        LastSuccessMonth     = ''
        AttemptMonth         = ''
        AttemptCount         = 0
        LastAttemptDate      = ''
        FailureNotifiedMonth = ''
    }
    if (-not (Test-Path -LiteralPath $Path)) { return $defaultState }
    try {
        $raw = Get-Content -LiteralPath $Path -Raw -Encoding UTF8
        if ([string]::IsNullOrWhiteSpace($raw)) { return $defaultState }
        $parsed = $raw | ConvertFrom-Json -ErrorAction Stop
        if ($null -eq $parsed) { return $defaultState }
        return [PSCustomObject]@{
            LastSuccessMonth     = if ($parsed.PSObject.Properties['LastSuccessMonth'] -and $parsed.LastSuccessMonth) { [string]$parsed.LastSuccessMonth } else { '' }
            AttemptMonth         = if ($parsed.PSObject.Properties['AttemptMonth'] -and $parsed.AttemptMonth) { [string]$parsed.AttemptMonth } else { '' }
            AttemptCount         = if ($parsed.PSObject.Properties['AttemptCount'] -and $null -ne $parsed.AttemptCount) { [int]$parsed.AttemptCount } else { 0 }
            LastAttemptDate      = if ($parsed.PSObject.Properties['LastAttemptDate'] -and $parsed.LastAttemptDate) { [string]$parsed.LastAttemptDate } else { '' }
            FailureNotifiedMonth = if ($parsed.PSObject.Properties['FailureNotifiedMonth'] -and $parsed.FailureNotifiedMonth) { [string]$parsed.FailureNotifiedMonth } else { '' }
        }
    } catch {
        Write-Verbose "Corrupted state file ignored; treating as first run: $($_.Exception.Message)"
        return $defaultState
    }
}

function Save-UpstreamState {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][PSCustomObject]$State
    )
    $parent = Split-Path -Path $Path -Parent
    if ($parent -and -not (Test-Path -LiteralPath $parent)) {
        [void][System.IO.Directory]::CreateDirectory($parent)
    }
    $json = $State | ConvertTo-Json -Depth 4
    [System.IO.File]::WriteAllText($Path, $json, [System.Text.UTF8Encoding]::new($false))
}

function Test-PsGalleryReachable {
    [CmdletBinding()]
    param()
    try {
        $null = Invoke-RestMethod -Uri 'https://www.powershellgallery.com/api/v2/' -Method Get -TimeoutSec 10 -ErrorAction Stop
        return $true
    } catch {
        Write-Verbose "PSGallery unreachable: $($_.Exception.Message)"
        return $false
    }
}

function Get-UpstreamLatestVersion {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][PSCustomObject]$Tool)
    if ($Tool.source -eq 'PSGallery') {
        $found = Find-Module -Name $Tool.moduleName -Repository PSGallery -ErrorAction Stop
        if ($null -eq $found) { throw "Module '$($Tool.moduleName)' not found on PSGallery." }
        return [string]$found.Version
    } elseif ($Tool.source -eq 'GitHubRelease') {
        $uri = "https://api.github.com/repos/$($Tool.repo)/releases/latest"
        $headers = @{ 'User-Agent' = 'TenantBrief-UpstreamCheck' }
        $rel = Invoke-RestMethod -Uri $uri -Headers $headers -TimeoutSec 15 -ErrorAction Stop
        if (-not $rel -or -not $rel.tag_name) { throw "No release tag returned for $($Tool.repo)." }
        return [string]$rel.tag_name
    }
    throw "Unsupported upstream source: $($Tool.source)"
}

function Invoke-UpstreamSandboxCheck {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][object[]]$ChangedTools,
        [Parameter(Mandatory = $true)][string]$RepoRoot
    )
    $notes = [System.Collections.Generic.List[string]]::new()
    $sandboxRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("tb-upstream-" + [guid]::NewGuid().ToString('N').Substring(0, 8))
    $modDir = Join-Path $sandboxRoot 'modules'
    $wtDir  = Join-Path $sandboxRoot 'worktree'
    [void][System.IO.Directory]::CreateDirectory($modDir)
    $worktreeAdded = $false
    $origPsModulePath = $env:PSModulePath

    try {
        foreach ($ct in $ChangedTools) {
            if ($ct.Source -eq 'PSGallery') {
                Save-Module -Name $ct.ModuleName -RequiredVersion $ct.LatestVersion -Path $modDir -Repository PSGallery -Force -ErrorAction Stop
                $notes.Add("Saved $($ct.ModuleName) $($ct.LatestVersion) to sandbox temp folder.")
            }
        }

        # Detached clean worktree of origin/master so working tree is never touched
        $null = & git -C $RepoRoot worktree add --detach $wtDir origin/master 2>&1
        if ($LASTEXITCODE -eq 0) {
            $worktreeAdded = $true
            $notes.Add('Created clean detached git worktree from origin/master in temp.')
        } else {
            $notes.Add('WARN: Could not create detached git worktree; falling back to read-only repo inspection.')
            $wtDir = $RepoRoot
        }

        # Crosswalk & catalog drift checks against saved temp modules
        $cwPath = Join-Path $wtDir 'data/control-crosswalk.json'
        $cw = if (Test-Path -LiteralPath $cwPath) { Get-Content -LiteralPath $cwPath -Raw -Encoding UTF8 | ConvertFrom-Json } else { $null }

        $scubaSaved = Join-Path $modDir 'ScubaGear'
        if (Test-Path -LiteralPath $scubaSaved) {
            $migCsv = Get-ChildItem -Path $scubaSaved -Filter '*migration*.csv' -Recurse -File -ErrorAction SilentlyContinue | Select-Object -First 1
            $notes.Add("ScubaGear migration CSV present: $([bool]$migCsv)")
            $regoFiles = @(Get-ChildItem -Path $scubaSaved -Filter '*.rego' -Recurse -File -ErrorAction SilentlyContinue)
            $notes.Add("ScubaGear Rego policy files found: $($regoFiles.Count)")
        }

        $maesterSaved = Join-Path $modDir 'Maester'
        if ((Test-Path -LiteralPath $maesterSaved) -and $cw) {
            $mtText = (Get-ChildItem -Path $maesterSaved -Filter '*.ps1' -Recurse -File -ErrorAction SilentlyContinue | ForEach-Object { Get-Content -LiteralPath $_.FullName -Raw -ErrorAction SilentlyContinue }) -join "`n"
            $missingMt = [System.Collections.Generic.List[string]]::new()
            foreach ($ctrl in @($cw.controls)) {
                foreach ($m in @($ctrl.mappings)) {
                    if ($m.engine -in @('Maester', 'CIS M365', 'EIDSCA') -and $m.id -and $mtText -notmatch [regex]::Escape([string]$m.id)) {
                        $missingMt.Add([string]$m.id)
                    }
                }
            }
            $notes.Add("Maester crosswalk IDs missing in new catalog: $($missingMt.Count)")
        }

        $orcaSaved = Join-Path $modDir 'ORCA'
        if (Test-Path -LiteralPath $orcaSaved) {
            $orcaFiles = Get-ChildItem -Path $orcaSaved -Include '*.ps1', '*.psm1' -Recurse -File -ErrorAction SilentlyContinue
            $hasChiEnum = @($orcaFiles | Select-String -Pattern 'enum\s+ORCACHI|ChiValue' -ErrorAction SilentlyContinue).Count -gt 0
            $notes.Add("ORCA ORCACHI/ChiValue enum detected: $hasChiEnum")
        }

        # Run Pester in isolated PSModulePath (temp modules prepended only for this call)
        $sep = [System.IO.Path]::PathSeparator
        $env:PSModulePath = "$modDir$sep$origPsModulePath"
        $pesterRes = Invoke-Pester -Path (Join-Path $wtDir 'tests') -Output None -PassThru
        $notes.Add("Sandbox Pester: Passed=$($pesterRes.PassedCount) Failed=$($pesterRes.FailedCount)")
    } finally {
        $env:PSModulePath = $origPsModulePath
        if ($worktreeAdded) {
            $null = & git -C $RepoRoot worktree remove --force $wtDir 2>&1
        }
        if ([System.IO.Directory]::Exists($sandboxRoot)) {
            try { [System.IO.Directory]::Delete($sandboxRoot, $true) } catch { Write-Verbose "Temp cleanup deferred: $($_.Exception.Message)" }
        }
    }
    return $notes.ToArray()
}

function Invoke-UpstreamGitHubIssue {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$IssueTitle,
        [Parameter(Mandatory = $true)][string]$ReportPath
    )
    $existingRaw = & gh issue list --state open --label upstream --search "`"$IssueTitle`" in:title" --json title 2>&1
    if ($LASTEXITCODE -eq 0 -and $existingRaw) {
        try {
            $existing = @($existingRaw | ConvertFrom-Json)
            if (@($existing | Where-Object { $_.title -eq $IssueTitle }).Count -gt 0) {
                return 'EXISTS'
            }
        } catch {
            Write-Verbose "Could not parse gh issue list output: $($_.Exception.Message)"
        }
    }
    $null = & gh issue create --title $IssueTitle --label upstream --body-file $ReportPath 2>&1
    if ($LASTEXITCODE -eq 0) { return 'CREATED' }
    return 'FAILED'
}

# --- Main monthly/daily lock execution ---
$thisMonth = $Now.ToString('yyyy-MM')
$today     = $Now.ToString('yyyy-MM-dd')
$state     = Read-UpstreamState -Path $StatePath

# Rule 1: Already succeeded this month -> exit immediately with zero network calls
if ($state.LastSuccessMonth -eq $thisMonth) {
    return [PSCustomObject]@{ Status = 'SkippedAlreadySucceeded'; Month = $thisMonth; Changes = @(); ReportPath = '' }
}

# Rule 3: Reset AttemptCount when entering a new month
if ($state.AttemptMonth -ne $thisMonth) {
    $state.AttemptMonth = $thisMonth
    $state.AttemptCount = 0
}

# Rule 2: At most 1 attempt per day
if ($state.LastAttemptDate -eq $today) {
    return [PSCustomObject]@{ Status = 'SkippedSameDayAttempt'; Month = $thisMonth; Changes = @(); ReportPath = '' }
}

# Rule 4: Max 3 attempts per month; notify once per month
if ($state.AttemptCount -ge 3) {
    $didNotify = $false
    $notifyMsg = ''
    if ($state.FailureNotifiedMonth -ne $thisMonth) {
        $notifyMsg = 'Upstream kontrolü bu ay yapılamadı.'
        Send-UpstreamNotification -Title 'TenantBrief Upstream Kontrolü' -Message $notifyMsg
        $didNotify = $true
        $state.FailureNotifiedMonth = $thisMonth
        if (-not $DryRun) { Save-UpstreamState -Path $StatePath -State $state }
    }
    return [PSCustomObject]@{ Status = 'SkippedMaxAttempts'; Month = $thisMonth; Changes = @(); ReportPath = ''; Notified = $didNotify; NotificationMessage = $notifyMsg }
}

# Check network / PSGallery reachability
if (-not (Test-PsGalleryReachable)) {
    $state.AttemptCount++
    $state.AttemptMonth = $thisMonth
    $state.LastAttemptDate = $today
    if (-not $DryRun) { Save-UpstreamState -Path $StatePath -State $state }
    return [PSCustomObject]@{ Status = 'FailedNetwork'; Month = $thisMonth; Changes = @(); ReportPath = '' }
}

try {
    $cfg = Get-Content -LiteralPath $VersionsPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $results = [System.Collections.Generic.List[object]]::new()
    $changes = [System.Collections.Generic.List[object]]::new()

    foreach ($tool in @($cfg.tools)) {
        $latest = Get-UpstreamLatestVersion -Tool $tool
        $changed = ($latest -ne [string]$tool.pinnedVersion)
        $row = [PSCustomObject]@{
            Name          = [string]$tool.name
            Source        = [string]$tool.source
            ModuleName    = if ($tool.PSObject.Properties['moduleName']) { [string]$tool.moduleName } else { '' }
            PinnedVersion = [string]$tool.pinnedVersion
            LatestVersion = $latest
            Changed       = $changed
            Status        = [string]$tool.status
        }
        $results.Add($row)
        if ($changed) { $changes.Add($row) }
    }

    $sandboxNotes = @()
    if ($changes.Count -gt 0 -and -not $SkipSandbox) {
        $sandboxNotes = @(Invoke-UpstreamSandboxCheck -ChangedTools $changes.ToArray() -RepoRoot $RepoPath)
    }

    if (-not (Test-Path -LiteralPath $ReportDir)) {
        [void][System.IO.Directory]::CreateDirectory($ReportDir)
    }
    $reportPath = Join-Path $ReportDir "upstream-$thisMonth.md"
    $mdLines = [System.Collections.Generic.List[string]]::new()
    $mdLines.Add("# TenantBrief Upstream Check — $thisMonth")
    $mdLines.Add('')
    $mdLines.Add("- **Checked At:** $($Now.ToString('yyyy-MM-dd HH:mm'))")
    $mdLines.Add("- **Mode:** $(if ($DryRun) { 'DryRun' } else { 'Scheduled/Live' })")
    $mdLines.Add("- **Updates Detected:** $($changes.Count)")
    $mdLines.Add('')
    $mdLines.Add('| Tool | Source | Pinned | Latest | Status |')
    $mdLines.Add('| --- | --- | --- | --- | --- |')
    foreach ($r in $results) {
        $st = if ($r.Changed) { 'UPDATE AVAILABLE' } else { 'Up-to-date' }
        $mdLines.Add("| $($r.Name) | $($r.Source) | $($r.PinnedVersion) | $($r.LatestVersion) | $st |")
    }
    if ($sandboxNotes.Count -gt 0) {
        $mdLines.Add('')
        $mdLines.Add('## Sandbox Compatibility Checks')
        foreach ($sn in $sandboxNotes) { $mdLines.Add("- $sn") }
    }
    [System.IO.File]::WriteAllText($reportPath, ($mdLines -join "`n"), [System.Text.UTF8Encoding]::new($false))

    $issueResult = 'NONE'
    if ($changes.Count -gt 0) {
        $issueTitle = "Upstream check $thisMonth"
        if ($DryRun) {
            $issueResult = 'DRY_RUN_WOULD_CREATE'
            $mdLines.Add('')
            $mdLines.Add("> **DRY-RUN:** Issue would be created: ``$issueTitle`` (label: ``upstream``). No GitHub issue was opened and no monthly state file was written.")
            [System.IO.File]::WriteAllText($reportPath, ($mdLines -join "`n"), [System.Text.UTF8Encoding]::new($false))
        } else {
            $issueResult = Invoke-UpstreamGitHubIssue -IssueTitle $issueTitle -ReportPath $reportPath
            Send-UpstreamNotification -Title "TenantBrief: $issueTitle" -Message "$($changes.Count) upstream aracında yeni sürüm tespit edildi. Ayrıntı: $reportPath"
        }
    }

    # Rule 5: On success, record LastSuccessMonth (skipped on -DryRun)
    $state.LastSuccessMonth = $thisMonth
    $state.AttemptMonth = $thisMonth
    $state.LastAttemptDate = $today
    if (-not $DryRun) { Save-UpstreamState -Path $StatePath -State $state }

    return [PSCustomObject]@{
        Status       = if ($changes.Count -gt 0) { 'UpdatesFound' } else { 'UpToDate' }
        Month        = $thisMonth
        Changes      = $changes.ToArray()
        Results      = $results.ToArray()
        SandboxNotes = $sandboxNotes
        IssueResult  = $issueResult
        ReportPath   = $reportPath
    }
} catch {
    # Rule 6: On error, do NOT write LastSuccessMonth; only update AttemptCount & LastAttemptDate
    $state.AttemptCount++
    $state.AttemptMonth = $thisMonth
    $state.LastAttemptDate = $today
    if (-not $DryRun) { Save-UpstreamState -Path $StatePath -State $state }
    Write-Warning "Upstream check failed: $($_.Exception.Message)"
    return [PSCustomObject]@{ Status = 'FailedError'; Month = $thisMonth; Error = $_.Exception.Message; Changes = @(); ReportPath = '' }
}
