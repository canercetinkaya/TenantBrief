BeforeAll {
    $script:RepoRoot = Split-Path -Path $PSScriptRoot -Parent
    $script:MeasureScript = Join-Path $script:RepoRoot 'tools\Measure-TenantBriefQuality.ps1'
    $script:SchemaPath = Join-Path $script:RepoRoot 'schemas\tenantbrief-report.schema.json'
    $script:DemoTrJson = Join-Path $script:RepoRoot 'demo\TenantBriefReport-TR.json'
    $script:DemoEnJson = Join-Path $script:RepoRoot 'demo\TenantBriefReport-EN.json'
}

Describe 'tools/Measure-TenantBriefQuality.ps1 (Q01-Q15)' {
    It 'computes Q01-Q15 accurately on a synthetic fixture JSON and HTML' {
        $tmpDir = Join-Path ([System.IO.Path]::GetTempPath()) ("tb-qual-" + [guid]::NewGuid().ToString('N').Substring(0, 8))
        New-Item -ItemType Directory -Path $tmpDir -Force | Out-Null
        $tmpJson = Join-Path $tmpDir 'report.json'
        $tmpHtml = Join-Path $tmpDir 'report.html'
        try {
            [PSCustomObject]@{
                Tenant   = 'fixture.onmicrosoft.com'
                Language = 'tr'
                Frameworks = @(
                    [PSCustomObject]@{ Id = 'ZeroTrust'; SourceTag = 'ZeroTrust'; Score = 50 }
                )
                CopilotReadiness = [PSCustomObject]@{
                    Score         = 50
                    MaturityLevel = 'L2 - Tekrarlanabilir (Repeatable)'
                    Checks        = @(
                        [PSCustomObject]@{ Id = 'COP-LIC-01'; Status = 'Fail' }
                    )
                }
                Findings = @(
                    [PSCustomObject]@{
                        Id = 'F1'; Pillar = 'CISA SCuBA'; DomainPillar = 'Data, AI'; Sources = @('ZeroTrust', 'CISA SCuBA')
                        Status = 'Failed'; Risk = 'High'; Impact = 'Düşük'; ImplementationCost = 'Unknown'; MinimumLicense = ''
                        Title = 'Legacy authentication SHALL be blocked'; RemediationTr = 'Portaldan kapatın... daha fazla öğrenin'
                    },
                    [PSCustomObject]@{
                        Id = 'F2'; Pillar = 'Identity'; DomainPillar = 'Identity'; Sources = @('ZeroTrust')
                        Status = 'Planned'; Risk = 'Medium'; Impact = 'Medium'; ImplementationCost = 'Low'; MinimumLicense = 'P1'
                        Title = 'Kimlik tasdiqi kuralı'; RemediationTr = 'Tam cümle.'
                    },
                    [PSCustomObject]@{
                        Id = 'SCUBA-MS.AAD.1.1v1'; Pillar = 'Identity'; DomainPillar = 'Identity'; Sources = @('CISA SCuBA'); Category = 'AAD'
                        Status = 'Passed'; Risk = 'High'; Impact = 'High'; ImplementationCost = 'Low'; MinimumLicense = 'P1'
                        Title = 'Eski kimlik doğrulama engellenmeli'; RemediationTr = ''
                    }
                )
            } | ConvertTo-Json -Depth 6 | Set-Content -Path $tmpJson -Encoding UTF8

            '<html><body><img src=x onerror=alert(1)></body></html>' | Set-Content -Path $tmpHtml -Encoding UTF8

            $res = & $script:MeasureScript -Path $tmpJson -HtmlPath $tmpHtml
            $byCode = @{}
            foreach ($m in $res.Metrics) { $byCode[$m.Code] = $m }

            $byCode['Q01'].Value | Should -Be 1
            $byCode['Q01'].SampleIds | Should -Contain 'F1'
            $byCode['Q02'].Value | Should -Be 1
            $byCode['Q03'].Value | Should -Be 1
            $byCode['Q04a'].Value | Should -Be 1
            $byCode['Q04b'].Value | Should -Be 0
            $byCode['Q04'].Value | Should -Be 1
            $byCode['Q06'].Value | Should -Be 1
            $byCode['Q07'].Value | Should -Be 1
            $byCode['Q08a'].Value | Should -Be 1
            $byCode['Q08b'].Value | Should -Be 1
            $byCode['Q09'].Value | Should -Be 1
            $byCode['Q10a'].Value | Should -Be 1
            $byCode['Q10b'].Value | Should -Be 1
            $byCode['Q10'].Value | Should -Be 1
            $byCode['Q11'].Value | Should -Be 1
            $byCode['Q12'].Value | Should -Be 1
            $byCode['Q13'].Value | Should -Be 1
            $byCode['Q14'].Value | Should -Be 1
            $byCode['Q15'].Value | Should -BeGreaterThan 0
        } finally {
            Remove-Item -Path $tmpDir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'returns valid machine-readable JSON when -AsJson is passed' {
        $jsonOut = & $script:MeasureScript -Path $script:DemoTrJson -AsJson
        $parsed = $jsonOut | ConvertFrom-Json
        $parsed.TotalFindings | Should -BeGreaterThan 0
        $parsed.Metrics.Count | Should -Be 20
    }

    It 'does not produce false positives on natural Turkish titles for Q08b' {
        $tmpJson = Join-Path ([System.IO.Path]::GetTempPath()) ("tb-q08-" + [guid]::NewGuid().ToString('N').Substring(0, 8) + '.json')
        try {
            [PSCustomObject]@{
                Tenant   = 'turkish.onmicrosoft.com'
                Language = 'tr'
                Findings = @(
                    [PSCustomObject]@{ Id = 'TR1'; Pillar = 'Identity'; DomainPillar = 'Identity'; Sources = @('ZeroTrust'); Status = 'Passed'; Risk = 'High'; Impact = 'High'; ImplementationCost = 'Low'; MinimumLicense = 'P1'; Title = 'Eski kimlik doğrulama protokolleri engellenmelidir'; RemediationTr = '' },
                    [PSCustomObject]@{ Id = 'TR2'; Pillar = 'Data'; DomainPillar = 'Data'; Sources = @('ZeroTrust'); Status = 'Passed'; Risk = 'Medium'; Impact = 'Medium'; ImplementationCost = 'Low'; MinimumLicense = 'P1'; Title = 'Hassasiyet etiketleri ve DLP ilkeleri yapılandırılmalıdır'; RemediationTr = '' },
                    [PSCustomObject]@{ Id = 'EN1'; Pillar = 'SecOps'; DomainPillar = 'SecOps'; Sources = @('MDO / ORCA'); Status = 'Failed'; Risk = 'Medium'; Impact = 'Medium'; ImplementationCost = 'Unknown'; MinimumLicense = ''; Title = 'Zero Hour Autopurge Enabled for Malware'; RemediationTr = '' }
                )
            } | ConvertTo-Json -Depth 5 | Set-Content -Path $tmpJson -Encoding UTF8

            $res = & $script:MeasureScript -Path $tmpJson
            $byCode = @{}
            foreach ($m in $res.Metrics) { $byCode[$m.Code] = $m }
            $byCode['Q08b'].Value | Should -Be 1
            $byCode['Q08b'].SampleIds | Should -Contain 'EN1'
        } finally {
            Remove-Item -Path $tmpJson -Force -ErrorAction SilentlyContinue
        }
    }

    It 'validates demo TR and EN reports against schemas/tenantbrief-report.schema.json' {
        $script:SchemaPath | Should -Exist
        $trRaw = Get-Content -LiteralPath $script:DemoTrJson -Raw -Encoding UTF8
        $enRaw = Get-Content -LiteralPath $script:DemoEnJson -Raw -Encoding UTF8
        (Test-Json -Json $trRaw -SchemaFile $script:SchemaPath) | Should -BeTrue
        (Test-Json -Json $enRaw -SchemaFile $script:SchemaPath) | Should -BeTrue
    }

    It 'counts only canonical ScubaGear 2.0 products (max 7) for Q12 without ZT categories or DEFENDER/SECURITYSUITE double-counting' {
        $tmpDir = Join-Path ([System.IO.Path]::GetTempPath()) ("tb-q12-" + [guid]::NewGuid().ToString('N').Substring(0, 8))
        New-Item -ItemType Directory -Path $tmpDir -Force | Out-Null
        $jPath = Join-Path $tmpDir 'q12.json'
        try {
            [PSCustomObject]@{
                Tenant   = 'contoso.onmicrosoft.com'
                Language = 'tr'
                Findings = @(
                    [PSCustomObject]@{ Id = '21882'; Sources = @('ZeroTrust', 'CISA SCuBA'); CorrelatedIds = @('21882', 'SCUBA-MS.AAD.3.2v1'); Category = 'Access control'; Status = 'Failed'; Risk = 'High'; Title = 'MFA zorunlu kıl' },
                    [PSCustomObject]@{ Id = '21860'; Sources = @('ZeroTrust', 'CISA SCuBA'); CorrelatedIds = @('21860', 'SCUBA-MS.AAD.1.1v1'); Category = 'Privileged access'; Status = 'Passed'; Risk = 'High'; Title = 'Eski kimlik doğrulama' },
                    [PSCustomObject]@{ Id = 'SCUBA-MS.DEFENDER.1.1v1'; Sources = @('CISA SCuBA'); CorrelatedIds = @('SCUBA-MS.DEFENDER.1.1v1'); Category = 'DEFENDER'; Status = 'Failed'; Risk = 'High'; Title = 'Defender check' },
                    [PSCustomObject]@{ Id = 'SCUBA-MS.SECURITYSUITE.1.1v1'; Sources = @('CISA SCuBA'); CorrelatedIds = @('SCUBA-MS.SECURITYSUITE.1.1v1'); Category = 'SECURITYSUITE'; Status = 'Failed'; Risk = 'High'; Title = 'SecuritySuite check' }
                )
            } | ConvertTo-Json -Depth 6 | Set-Content -Path $jPath -Encoding UTF8

            $res = & $script:MeasureScript -Path $jPath
            $q12 = $res.Metrics | Where-Object { $_.Code -eq 'Q12' }
            $q12.Value | Should -Be 2
            $q12.Value | Should -BeLessOrEqual 7
            @($q12.SampleIds) | Should -Contain 'AAD'
            @($q12.SampleIds) | Should -Contain 'SECURITYSUITE'
            @($q12.SampleIds) | Should -Not -Contain 'Access control'
            @($q12.SampleIds) | Should -Not -Contain 'DEFENDER'
        } finally {
            Remove-Item -Path $tmpDir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}
