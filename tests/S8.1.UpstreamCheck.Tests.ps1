BeforeAll {
    $script:RepoRoot = Split-Path -Path $PSScriptRoot -Parent
    $script:CheckScript = Join-Path $script:RepoRoot 'tools/Invoke-TenantBriefUpstreamCheck.ps1'
    $script:RegisterScript = Join-Path $script:RepoRoot 'tools/Register-TenantBriefUpstreamCheck.ps1'
    $script:VersionsJson = Join-Path $script:RepoRoot 'data/upstream-versions.json'
    $env:TENANTBRIEF_SUPPRESS_NOTIFY = '1'
}

AfterAll {
    Remove-Item Env:TENANTBRIEF_SUPPRESS_NOTIFY -ErrorAction SilentlyContinue
}

Describe 'S8.1 - Monthly Upstream Check (7 Lock Rules, Issue Deduplication & Safety)' {
    BeforeEach {
        $script:TmpDir = Join-Path ([System.IO.Path]::GetTempPath()) ("tb-s81-" + [guid]::NewGuid().ToString('N').Substring(0, 8))
        New-Item -ItemType Directory -Path $script:TmpDir -Force | Out-Null
        $script:StatePath = Join-Path $script:TmpDir 'upstream-check.json'
        $script:ReportDir = Join-Path $script:TmpDir 'reports'
    }

    AfterEach {
        if (Test-Path -LiteralPath $script:TmpDir) {
            [System.IO.Directory]::Delete($script:TmpDir, $true)
        }
    }

    It 'Rule 1: exits immediately with zero network calls when LastSuccessMonth is current month' {
        [PSCustomObject]@{ LastSuccessMonth = '2026-11'; AttemptMonth = '2026-11'; AttemptCount = 0; LastAttemptDate = '2026-11-01' } |
            ConvertTo-Json | Set-Content -Path $script:StatePath -Encoding UTF8

        Mock Invoke-RestMethod { throw 'Network must not be called when already succeeded this month' }
        Mock Find-Module { throw 'Find-Module must not be called when already succeeded this month' }

        $res = & $script:CheckScript -Now ([datetime]'2026-11-20T10:00:00') -StatePath $script:StatePath -ReportDir $script:ReportDir -VersionsPath $script:VersionsJson -SkipSandbox
        $res.Status | Should -Be 'SkippedAlreadySucceeded'
        Should -Invoke Invoke-RestMethod -Times 0
        Should -Invoke Find-Module -Times 0
    }

    It 'Rule 2: exits immediately when LastAttemptDate is today (max 1 attempt per day)' {
        [PSCustomObject]@{ LastSuccessMonth = '2026-10'; AttemptMonth = '2026-11'; AttemptCount = 1; LastAttemptDate = '2026-11-20' } |
            ConvertTo-Json | Set-Content -Path $script:StatePath -Encoding UTF8

        Mock Invoke-RestMethod { throw 'Network must not be called twice on the same day' }
        $res = & $script:CheckScript -Now ([datetime]'2026-11-20T18:00:00') -StatePath $script:StatePath -ReportDir $script:ReportDir -VersionsPath $script:VersionsJson -SkipSandbox
        $res.Status | Should -Be 'SkippedSameDayAttempt'
        Should -Invoke Invoke-RestMethod -Times 0
    }

    It 'Rule 3: resets AttemptCount when AttemptMonth is not the current month' {
        [PSCustomObject]@{ LastSuccessMonth = '2026-09'; AttemptMonth = '2026-10'; AttemptCount = 3; LastAttemptDate = '2026-10-28' } |
            ConvertTo-Json | Set-Content -Path $script:StatePath -Encoding UTF8

        Mock Invoke-RestMethod { throw 'Simulated offline network' }
        $res = & $script:CheckScript -Now ([datetime]'2026-11-05T09:00:00') -StatePath $script:StatePath -ReportDir $script:ReportDir -VersionsPath $script:VersionsJson -SkipSandbox
        $res.Status | Should -Be 'FailedNetwork'
        $saved = Get-Content -LiteralPath $script:StatePath -Raw -Encoding UTF8 | ConvertFrom-Json
        $saved.AttemptMonth | Should -Be '2026-11'
        $saved.AttemptCount | Should -Be 1
        $saved.LastSuccessMonth | Should -Be '2026-09'
    }

    It 'Rule 4: stops attempting when AttemptCount >= 3 and notifies at most once per month' {
        [PSCustomObject]@{ LastSuccessMonth = '2026-10'; AttemptMonth = '2026-11'; AttemptCount = 3; LastAttemptDate = '2026-11-18'; FailureNotifiedMonth = '' } |
            ConvertTo-Json | Set-Content -Path $script:StatePath -Encoding UTF8

        Mock Invoke-RestMethod { throw 'Network must not be called when AttemptCount >= 3' }
        $r1 = & $script:CheckScript -Now ([datetime]'2026-11-20T09:00:00') -StatePath $script:StatePath -ReportDir $script:ReportDir -VersionsPath $script:VersionsJson -SkipSandbox
        $r1.Status | Should -Be 'SkippedMaxAttempts'
        $r1.Notified | Should -BeTrue
        $r1.NotificationMessage | Should -Match 'Upstream kontrolü bu ay yapılamadı'

        # Second call next day in the same month must NOT notify again
        $r2 = & $script:CheckScript -Now ([datetime]'2026-11-21T09:00:00') -StatePath $script:StatePath -ReportDir $script:ReportDir -VersionsPath $script:VersionsJson -SkipSandbox
        $r2.Status | Should -Be 'SkippedMaxAttempts'
        $r2.Notified | Should -BeFalse
    }

    It 'Rule 5 & No-Diff: writes LastSuccessMonth on success and does NOT open a GitHub issue when all versions match' {
        $cfg = Get-Content -LiteralPath $script:VersionsJson -Raw -Encoding UTF8 | ConvertFrom-Json
        $verMap = @{}
        foreach ($t in $cfg.tools) { $verMap[$t.name] = $t.pinnedVersion }

        Mock Invoke-RestMethod {
            param($Uri)
            if ($Uri -like '*github.com*') { return [PSCustomObject]@{ tag_name = $verMap['EntraFalcon'] } }
            return 'OK'
        }
        Mock Find-Module {
            param($Name)
            return [PSCustomObject]@{ Name = $Name; Version = $verMap[$Name] }
        }
        $script:GhCalls = [System.Collections.Generic.List[string]]::new()
        function gh { $script:GhCalls.Add(($args -join ' ')); $global:LASTEXITCODE = 0; return '[]' }

        $res = & $script:CheckScript -Now ([datetime]'2026-11-20T12:00:00') -StatePath $script:StatePath -ReportDir $script:ReportDir -VersionsPath $script:VersionsJson -SkipSandbox
        $res.Status | Should -Be 'UpToDate'
        @($res.Changes).Count | Should -Be 0
        $res.IssueResult | Should -Be 'NONE'
        $script:GhCalls.Count | Should -Be 0

        $saved = Get-Content -LiteralPath $script:StatePath -Raw -Encoding UTF8 | ConvertFrom-Json
        $saved.LastSuccessMonth | Should -Be '2026-11'
        Test-Path -LiteralPath (Join-Path $script:ReportDir 'upstream-2026-11.md') | Should -BeTrue
    }

    It 'Rule 6: does NOT write LastSuccessMonth on error; only increments AttemptCount and updates LastAttemptDate' {
        Mock Invoke-RestMethod { return 'OK' }
        Mock Find-Module { throw 'PSGallery 503 transient failure' }

        $res = & $script:CheckScript -Now ([datetime]'2026-11-20T12:00:00') -StatePath $script:StatePath -ReportDir $script:ReportDir -VersionsPath $script:VersionsJson -SkipSandbox -WarningAction SilentlyContinue
        $res.Status | Should -Be 'FailedError'
        $saved = Get-Content -LiteralPath $script:StatePath -Raw -Encoding UTF8 | ConvertFrom-Json
        $saved.LastSuccessMonth | Should -Be ''
        $saved.AttemptCount | Should -Be 1
        $saved.LastAttemptDate | Should -Be '2026-11-20'
    }

    It 'Rule 7: treats corrupted or missing state file as first run without crashing' {
        Set-Content -Path $script:StatePath -Value '{CORRUPT_JSON!!!' -Encoding UTF8
        Mock Invoke-RestMethod { throw 'Offline' }

        $res = & $script:CheckScript -Now ([datetime]'2026-11-20T12:00:00') -StatePath $script:StatePath -ReportDir $script:ReportDir -VersionsPath $script:VersionsJson -SkipSandbox
        $res.Status | Should -Be 'FailedNetwork'
        $saved = Get-Content -LiteralPath $script:StatePath -Raw -Encoding UTF8 | ConvertFrom-Json
        $saved.AttemptCount | Should -Be 1
    }

    It 'opens a deduplicated GitHub issue when an upstream version changes and skips duplicate open issues for the same month' {
        $cfg = Get-Content -LiteralPath $script:VersionsJson -Raw -Encoding UTF8 | ConvertFrom-Json
        $verMap = @{}
        foreach ($t in $cfg.tools) { $verMap[$t.name] = $t.pinnedVersion }

        Mock Invoke-RestMethod {
            param($Uri)
            if ($Uri -like '*github.com*') { return [PSCustomObject]@{ tag_name = $verMap['EntraFalcon'] } }
            return 'OK'
        }
        Mock Find-Module {
            param($Name)
            $v = if ($Name -eq 'ScubaGear') { '2.1.0' } else { $verMap[$Name] }
            return [PSCustomObject]@{ Name = $Name; Version = $v }
        }

        $ghLogPath = Join-Path $script:TmpDir 'gh-create.log'
        $env:TB_TEST_GH_LOG = $ghLogPath
        $env:TB_TEST_OPEN_ISSUE = '0'
        function gh {
            $joined = $args -join ' '
            $global:LASTEXITCODE = 0
            if ($joined -like 'issue list*') {
                if ($env:TB_TEST_OPEN_ISSUE -eq '1') { return '[{"title":"Upstream check 2026-11"}]' }
                return '[]'
            }
            if ($joined -like 'issue create*') {
                Add-Content -Path $env:TB_TEST_GH_LOG -Value $joined -Encoding UTF8
                return 'https://github.com/canercetinkaya/TenantBrief/issues/99'
            }
            return ''
        }

        try {
            $r1 = & $script:CheckScript -Now ([datetime]'2026-11-20T12:00:00') -StatePath $script:StatePath -ReportDir $script:ReportDir -VersionsPath $script:VersionsJson -SkipSandbox
            $r1.Status | Should -Be 'UpdatesFound'
            $r1.IssueResult | Should -Be 'CREATED'
            @(Get-Content -LiteralPath $ghLogPath).Count | Should -Be 1

            # Second run with fresh state while issue is already open must NOT create a second issue
            $statePath2 = Join-Path $script:TmpDir 'state2.json'
            $env:TB_TEST_OPEN_ISSUE = '1'
            $r2 = & $script:CheckScript -Now ([datetime]'2026-11-20T12:00:00') -StatePath $statePath2 -ReportDir $script:ReportDir -VersionsPath $script:VersionsJson -SkipSandbox
            $r2.IssueResult | Should -Be 'EXISTS'
            @(Get-Content -LiteralPath $ghLogPath).Count | Should -Be 1
        } finally {
            Remove-Item Env:TB_TEST_GH_LOG, Env:TB_TEST_OPEN_ISSUE -ErrorAction SilentlyContinue
        }
    }

    It 'never invokes Install-Module or Remove-Item anywhere in Invoke-TenantBriefUpstreamCheck.ps1 and documents maintenance rules' {
        $tokens = $null; $errors = $null
        $ast = [System.Management.Automation.Language.Parser]::ParseFile($script:CheckScript, [ref]$tokens, [ref]$errors)
        $errors.Count | Should -Be 0
        $cmds = @($ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.CommandAst] }, $true) | ForEach-Object { $_.GetCommandName() })
        $cmds | Should -Not -Contain 'Install-Module'
        $cmds | Should -Not -Contain 'Remove-Item'

        Test-Path -LiteralPath $script:RegisterScript | Should -BeTrue
        $agents = Get-Content -LiteralPath (Join-Path $script:RepoRoot 'AGENTS.md') -Raw -Encoding UTF8
        $agents | Should -Match '`?upstream`? etiketli açık issue'
        $readme = Get-Content -LiteralPath (Join-Path $script:RepoRoot 'README.md') -Raw -Encoding UTF8
        $readme | Should -Match 'Bakım'
    }
}
