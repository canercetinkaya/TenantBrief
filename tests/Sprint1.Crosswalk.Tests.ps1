BeforeAll {
    $script:RepoRoot = Split-Path -Path $PSScriptRoot -Parent
    $script:CrosswalkPath = Join-Path $script:RepoRoot 'data\control-crosswalk.json'
    $script:CanonicalPillars = @('Identity', 'Devices', 'Data', 'Network', 'SecOps', 'AI')
}

Describe 'S1.1 - Canonical Control Crosswalk (data/control-crosswalk.json) & Upstream Catalog Verification' {
    It 'exists, is valid JSON, and defines at least 40 canonical controls with upstream sources' {
        Test-Path -LiteralPath $script:CrosswalkPath | Should -BeTrue
        $cw = Get-Content -LiteralPath $script:CrosswalkPath -Raw -Encoding UTF8 | ConvertFrom-Json
        @($cw.controls).Count | Should -BeGreaterOrEqual 40

        $seenCanonical = @{}
        $seenUpstream = @{}
        foreach ($c in $cw.controls) {
            $c.canonicalId | Should -Match '^TB-(ID|DEV|DATA|NET|SECOPS|AI)-[A-Z0-9-]+$'
            $seenCanonical.ContainsKey($c.canonicalId) | Should -BeFalse -Because "Duplicate canonicalId: $($c.canonicalId)"
            $seenCanonical[$c.canonicalId] = $true

            $c.pillar | Should -BeIn $script:CanonicalPillars
            $c.titleEn | Should -Not -BeNullOrEmpty
            $c.titleTr | Should -Not -BeNullOrEmpty
            @($c.ids).Count | Should -BeGreaterOrEqual 2 -Because "$($c.canonicalId) must correlate at least 2 upstream IDs"
            @($c.sources).Count | Should -BeGreaterOrEqual 1 -Because "$($c.canonicalId) must cite at least 1 upstream source URL/path"

            foreach ($uId in $c.ids) {
                $uKey = ([string]$uId).Trim().ToUpperInvariant()
                $seenUpstream.ContainsKey($uKey) | Should -BeFalse -Because "Upstream ID '$uId' mapped to multiple canonical controls"
                $seenUpstream[$uKey] = $c.canonicalId
            }
        }
    }

    It 'verifies ScubaGear 2.0.0 migrations CSV has 71 lines and every upstream ID exists in installed upstream catalogs' {
        Test-Path -LiteralPath $script:CrosswalkPath | Should -BeTrue
        $cw = Get-Content -LiteralPath $script:CrosswalkPath -Raw -Encoding UTF8 | ConvertFrom-Json

        $scubaMod = Get-Module -ListAvailable ScubaGear | Sort-Object Version -Descending | Select-Object -First 1
        $maesterMod = Get-Module -ListAvailable Maester | Sort-Object Version -Descending | Select-Object -First 1
        $orcaMod = Get-Module -ListAvailable ORCA | Sort-Object Version -Descending | Select-Object -First 1
        $ztMod = Get-Module -ListAvailable ZeroTrustAssessment | Sort-Object Version -Descending | Select-Object -First 1

        if (-not ($scubaMod -and $maesterMod -and $orcaMod -and $ztMod)) {
            Set-ItResult -Skipped -Because 'Installed upstream modules (ScubaGear/Maester/ORCA/ZeroTrustAssessment) are not present on this CI runner'
            return
        }

        # 1. Verify ScubaGear migrations CSV line count (71 lines) and collect all valid ScubaGear IDs
        $migCsvPath = Join-Path $scubaMod.ModuleBase 'mappings\scuba-baseline-policy-migrations.csv'
        Test-Path -LiteralPath $migCsvPath | Should -BeTrue
        (Get-Content -LiteralPath $migCsvPath).Count | Should -Be 71

        $scubaValid = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
        foreach ($row in (Import-Csv -LiteralPath $migCsvPath)) {
            if ($row.'Old ID') { $null = $scubaValid.Add("SCUBA-$($row.'Old ID'.Trim())") }
            if ($row.'New ID' -and $row.'New ID' -ne 'None') { $null = $scubaValid.Add("SCUBA-$($row.'New ID'.Trim())") }
        }
        foreach ($md in (Get-ChildItem -Path (Join-Path $scubaMod.ModuleBase 'baselines') -Filter '*.md')) {
            foreach ($m in [regex]::Matches((Get-Content -LiteralPath $md.FullName -Raw), 'MS\.[A-Z]+\.\d+\.\d+v\d+')) {
                $null = $scubaValid.Add("SCUBA-$($m.Value)")
            }
        }

        # 2. Collect all valid Maester (MT.*, CIS.M365.*, EIDSCA.*) IDs from installed Maester module
        $maesterValid = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
        $maesterFiles = Get-ChildItem -Path $maesterMod.ModuleBase -Recurse -Include '*.ps1','*.json','*.md' -File
        foreach ($mf in $maesterFiles) {
            $txt = Get-Content -LiteralPath $mf.FullName -Raw -ErrorAction SilentlyContinue
            if (-not $txt) { continue }
            foreach ($m in [regex]::Matches($txt, '\b(MT\.\d+(?:\.[A-Za-z0-9]+)?|CIS\.M365\.\d+(?:\.\d+)+|EIDSCA\.[A-Z0-9]+)\b')) {
                $null = $maesterValid.Add($m.Value)
            }
        }

        # 3. Collect all valid ORCA IDs from installed ORCA module ($this.Control = "...")
        $orcaValid = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
        $orcaFiles = Get-ChildItem -Path $orcaMod.ModuleBase -Recurse -Include '*.ps1','*.psm1' -File
        foreach ($of in $orcaFiles) {
            $txt = Get-Content -LiteralPath $of.FullName -Raw -ErrorAction SilentlyContinue
            if (-not $txt) { continue }
            foreach ($m in [regex]::Matches($txt, '\$this\.Control\s*=\s*["'']?([A-Za-z0-9_-]+)["'']?')) {
                $val = $m.Groups[1].Value.Trim()
                if ($val -notlike 'ORCA-*') { $val = "ORCA-$val" }
                $null = $orcaValid.Add($val)
            }
        }

        # 4. Collect all valid ZeroTrustAssessment numeric TestIds from installed ZTA module
        $ztValid = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
        $ztFiles = Get-ChildItem -Path $ztMod.ModuleBase -Recurse -Include '*.ps1','*.json' -File
        foreach ($zf in $ztFiles) {
            $txt = Get-Content -LiteralPath $zf.FullName -Raw -ErrorAction SilentlyContinue
            if (-not $txt) { continue }
            foreach ($m in [regex]::Matches($txt, '\b(21\d{3}|22\d{3}|24\d{3}|25\d{3}|35\d{3}|41\d{3}|51\d{3}|61\d{3})\b')) {
                $null = $ztValid.Add($m.Value)
            }
        }

        $missing = New-Object System.Collections.Generic.List[string]
        foreach ($c in $cw.controls) {
            foreach ($uId in $c.ids) {
                $idStr = [string]$uId
                if ($idStr -like 'SCUBA-*') {
                    if (-not $scubaValid.Contains($idStr)) { $missing.Add("$($c.canonicalId)::$idStr (ScubaGear)") }
                } elseif ($idStr -match '^(MT\.|CIS\.M365\.|EIDSCA\.)') {
                    # MT.1024.<SecureScoreControlName> is dynamically expanded by Maester's MT.1024 test
                    $baseMt = if ($idStr -match '^(MT\.1024)\.[A-Za-z0-9]+$') { $Matches[1] } else { $idStr }
                    if (-not ($maesterValid.Contains($idStr) -or $maesterValid.Contains($baseMt))) { $missing.Add("$($c.canonicalId)::$idStr (Maester)") }
                } elseif ($idStr -like 'ORCA-*') {
                    if (-not $orcaValid.Contains($idStr)) { $missing.Add("$($c.canonicalId)::$idStr (ORCA)") }
                } elseif ($idStr -match '^\d{5}$') {
                    if (-not $ztValid.Contains($idStr)) { $missing.Add("$($c.canonicalId)::$idStr (ZeroTrustAssessment)") }
                } else {
                    $missing.Add("$($c.canonicalId)::$idStr (UnknownPrefix)")
                }
            }
        }

        ($missing -join '; ') | Should -BeNullOrEmpty -Because 'Every upstream ID in control-crosswalk.json must exist in its real upstream catalog'
    }
}
