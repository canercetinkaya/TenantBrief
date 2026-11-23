BeforeAll {
    $script:RepoRoot = Split-Path -Path $PSScriptRoot -Parent
    Import-Module (Join-Path $script:RepoRoot 'TenantBrief.psd1') -Force
}

Describe 'S3.5 - Sentence-Boundary Remediation, Zero Ellipsis/Learn Artifacts & Language-Aware Field (Q10=0)' {
    It 'cuts remediation on sentence boundary without ellipsis, strips Learn/öğrenin artifacts, and emits language-aware Remediation + RemediationTr' {
        InModuleScope TenantBrief {
            $longDesc = @"
**Remediation action**
Configure a Conditional Access policy blocking legacy authentication for all users. Verify sign-in logs for seven days before switching from report-only to enforce mode. Additional lengthy guidance continues well beyond one hundred and sixty characters to ensure mid-word ellipsis truncation never occurs.
Daha fazla bilgi edinin ve bu politikayı nasıl yapılandıracağınızı öğrenin.
Learn more about Conditional Access.
Related links: https://learn.microsoft.com/entra
"@
            $t = [PSCustomObject]@{
                TestId = '21796'; TestTitle = 'Block legacy auth'; TestStatus = 'Failed'
                TestRisk = 'High'; TestPillar = 'Identity'; TestCategory = 'CA'
                TestDescription = $longDesc
            }
            $fTr = @(New-TenantBriefFindings -Tests @($t) -Language tr)[0]
            $fTr.PSObject.Properties['Remediation'] | Should -Not -BeNullOrEmpty
            $fTr.Remediation | Should -Be $fTr.RemediationTr
            $fTr.RemediationTr | Should -Not -Match '\.\.\.'
            $fTr.RemediationTr | Should -Not -Match '(?i)öğrenin|Daha fazla bilgi|Learn more|Related links'

            $fEn = @(New-TenantBriefFindings -Tests @($t) -Language en)[0]
            $fEn.Remediation | Should -Not -BeNullOrEmpty
            $fEn.Remediation | Should -Not -Match '\.\.\.'
            $fEn.Remediation | Should -Not -Match 'Denetim \(Report-only\) kipinde'
        }
    }
}
