#Requires -Version 7.0
param(
    [Parameter(Mandatory = $true)]
    [string]$OutDir,

    [Parameter(Mandatory = $false)]
    [string]$ModulePath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -Parent
$psd1 = if ($ModulePath) { $ModulePath } else { Join-Path $repoRoot 'TenantBrief.psd1' }
Import-Module $psd1 -Force

New-Item -ItemType Directory -Path $OutDir -Force | Out-Null
$rawZt = Join-Path $OutDir 'ZeroTrustAssessmentReport.json'

$lsChar = [string][char]0x2028
$psChar = [string][char]0x2029
$xssTitle = "</script><script>window.__xssTriggered=true;alert(1)</script><img src=x onerror='window.__xssTriggered=true;alert(1)'> LineSep${lsChar}ParaSep${psChar}"
$xssCat   = '<svg onload="window.__xssTriggered=true;alert(2)">EvilCategory'
$xssDom   = '<img src=x onerror="window.__xssTriggered=true;alert(3)">contoso.onmicrosoft.com'

[PSCustomObject]@{
    TenantId   = '00000000-0000-0000-0000-000000000001'
    TenantName = $xssDom
    Domain     = $xssDom
    TenantInfo = [PSCustomObject]@{
        TenantOverview                     = [PSCustomObject]@{ UserCount = 5; GuestCount = 0; GroupCount = 1; ApplicationCount = 1; DeviceCount = 1; ManagedDeviceCount = 1 }
        OverviewCaMfaAllUsers              = [PSCustomObject]@{ description = '<img src=x onerror="window.__xssTriggered=true;alert(7)">MFA' }
        DeviceOverview                     = [PSCustomObject]@{ DeviceCompliance = $null }
        AgentOverview                      = $null
        OverviewAuthMethodsPrivilegedUsers = $null
    }
    Tests = @(
        [PSCustomObject]@{
            TestId                 = '99901'
            TestTitle              = $xssTitle
            TestStatus             = 'Failed'
            TestRisk               = 'High'
            TestPillar             = 'Identity'
            TestCategory           = $xssCat
            TestSfiPillar          = 'Protect identities and secrets'
            TestImplementationCost = 'Low'
            TestMinimumLicense     = 'P1" onmouseover="window.__xssTriggered=true;alert(6)'
            TestImpact             = 'Low'
            TestResult             = '<img src=x onerror="window.__xssTriggered=true;alert(4)">'
            TestDescription        = '**Remediation action** Fix <script>window.__xssTriggered=true;alert(5)</script> now.'
            SkippedReason          = ''
        },
        [PSCustomObject]@{
            TestId                 = '99902'
            TestTitle              = 'Skipped XSS <img src=x onerror="window.__xssTriggered=true;alert(8)">'
            TestStatus             = 'Skipped'
            TestRisk               = 'Medium'
            TestPillar             = 'Identity'
            TestCategory           = 'SkippedCat'
            TestSfiPillar          = 'Protect identities and secrets'
            TestImplementationCost = 'Low'
            TestMinimumLicense     = 'P2'
            TestImpact             = 'Low'
            TestResult             = ''
            TestDescription        = 'Skipped control description'
            SkippedReason          = 'Missing license <img src=x onerror="window.__xssTriggered=true;alert(9)">'
        }
    )
} | ConvertTo-Json -Depth 10 | Set-Content -Path $rawZt -Encoding UTF8

$res = Invoke-TenantBriefAssessment -InputReportJson $rawZt -OutputPath $OutDir -Language tr -Framework All -NoBrowser
[PSCustomObject]@{
    HtmlPath             = $res.HtmlPath
    ExecutiveSummaryPath = $res.ExecutiveSummaryPath
    JsonPath             = $res.JsonPath
} | ConvertTo-Json -Compress
