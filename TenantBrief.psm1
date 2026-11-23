Set-StrictMode -Version Latest

$script:ModuleRoot = $PSScriptRoot
$script:FrameworkMapPath = Join-Path $script:ModuleRoot 'data/framework-mappings.json'
$script:CrosswalkPath = Join-Path $script:ModuleRoot 'data/control-crosswalk.json'
$script:CrosswalkMapCache = $null
$script:ScoringConfigPath = Join-Path $script:ModuleRoot 'data/scoring.json'
$script:ScoringConfigCache = $null
$script:I18nCache = @{}
$script:GlossaryTrCache = $null
$script:ReportTemplatePath = Join-Path $script:ModuleRoot 'assets/report-template.html'
$script:TenantBriefAppAuth = $null

foreach ($folder in @('Private/Render', 'Private/Scoring', 'Private/Correlation', 'Private/Import', 'Public')) {
    $dirPath = Join-Path $script:ModuleRoot $folder
    if (Test-Path -LiteralPath $dirPath) {
        $files = Get-ChildItem -LiteralPath $dirPath -Filter '*.ps1' -File | Sort-Object Name
        foreach ($file in $files) {
            . $file.FullName
        }
    }
}
