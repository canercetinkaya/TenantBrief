BeforeAll {
    $script:RepoRoot = Split-Path -Path $PSScriptRoot -Parent
    Import-Module (Join-Path $script:RepoRoot 'TenantBrief.psd1') -Force
}

Describe 'S2.3 - AutoFixDependencies Safety Guard (Zero Unrequested Local Machine Mutations)' {
    It 'exposes -AutoFixDependencies on Connect-TenantBrief and never calls Install-Module or Remove-Item on default path' {
        (Get-Command Connect-TenantBrief).Parameters.ContainsKey('AutoFixDependencies') | Should -BeTrue

        $tmpDir = Join-Path ([System.IO.Path]::GetTempPath()) ("tb-s23-" + [guid]::NewGuid().ToString('N').Substring(0, 8))
        New-Item -ItemType Directory -Path $tmpDir -Force | Out-Null
        try {
            InModuleScope TenantBrief -Parameters @{ OutDir = $tmpDir } {
                (Get-Command Invoke-TenantBriefBaselineCollections).Parameters.ContainsKey('AutoFixDependencies') | Should -BeTrue

                Mock Get-Module { return $null }
                Mock Remove-Item { throw 'Remove-Item must not be called without -AutoFixDependencies' }
                $script:__installCalled = 0
                Mock Invoke-Command { }
                # If Install-Module were invoked without -AutoFixDependencies, it would try to call PSGallery or throw
                $diag = New-Object System.Collections.Generic.List[object]
                $state = @{ Stage = 2 }
                $null = Invoke-TenantBriefBaselineCollections -OutputPath $OutDir -Log { param($m) $null = $m } -State $state -Diagnostics $diag -SkipMaester

                Should -Invoke Remove-Item -Times 0 -Exactly
                @($diag | Where-Object { $_.Component -eq 'ScubaGear' -and $_.Message -match 'AutoFixDependencies|Install-Module' }).Count | Should -BeGreaterOrEqual 1
                @($diag | Where-Object { $_.Component -eq 'ORCA' -and $_.Message -match 'AutoFixDependencies|Install-Module' }).Count | Should -BeGreaterOrEqual 1
            }
        } finally {
            Remove-Item -Path $tmpDir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'documents local machine changes and -AutoFixDependencies in README.md' {
        $readme = Get-Content -LiteralPath (Join-Path $script:RepoRoot 'README.md') -Raw -Encoding UTF8
        $readme | Should -Match 'AutoFixDependencies'
    }
}
