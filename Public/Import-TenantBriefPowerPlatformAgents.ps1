function Import-TenantBriefPowerPlatformAgents {
    <#
    .SYNOPSIS
    Read-only parser for Microsoft FastTrack Inventory-PowerPlatformAgents.ps1 JSON or CSV exports.
    Detects Copilot Studio, Agent Builder (Copilot Studio Lite), default-environment sprawl, and stale/unowned agents.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,

        [Parameter()]
        [ValidateSet('tr', 'en')]
        [string]$Language = 'tr'
    )

    if (-not (Test-Path $Path)) { return $null }
    $isTr = ($Language -eq 'tr')
    $rawItems = @()
    try {
        if ($Path -match '\.json$') {
            $parsed = Get-Content -Path $Path -Raw -Encoding UTF8 | ConvertFrom-Json
            if ($parsed -is [System.Array]) { $rawItems = @($parsed) }
            elseif ($parsed.PSObject.Properties['agents']) { $rawItems = @($parsed.agents) }
            elseif ($parsed.PSObject.Properties['Agents']) { $rawItems = @($parsed.Agents) }
            elseif ($parsed.PSObject.Properties['value']) { $rawItems = @($parsed.value) }
            else { $rawItems = @($parsed) }
        } else {
            $rawItems = @(Import-Csv -Path $Path -Encoding UTF8)
        }
    } catch {
        Write-Warning "[TenantBrief] Failed to parse Power Platform Agents inventory '$Path': $($_.Exception.Message)"
        return $null
    }

    $agents = @()
    $cutoff = (Get-Date).AddDays(-90)
    $studioCount = 0
    $builderCount = 0
    $msManagedCount = 0
    $customDefaultEnvCount = 0
    $unownedCount = 0
    $staleCount = 0

    foreach ($a in $rawItems) {
        if ($null -eq $a) { continue }
        $name = [string](Get-TenantBriefPropertyValue -Object $a -Name 'agentName')
        if (-not $name) { $name = [string](Get-TenantBriefPropertyValue -Object $a -Name 'displayName') }
        if (-not $name) { $name = [string](Get-TenantBriefPropertyValue -Object $a -Name 'Name') }
        $id = [string](Get-TenantBriefPropertyValue -Object $a -Name 'agentId')
        if (-not $id) { $id = [string](Get-TenantBriefPropertyValue -Object $a -Name 'id') }
        $createdIn = [string](Get-TenantBriefPropertyValue -Object $a -Name 'createdIn')
        if (-not $createdIn) { $createdIn = 'Copilot Studio' }
        $envName = [string](Get-TenantBriefPropertyValue -Object $a -Name 'environmentName')
        $owner = [string](Get-TenantBriefPropertyValue -Object $a -Name 'ownerUpn')
        if (-not $owner) { $owner = [string](Get-TenantBriefPropertyValue -Object $a -Name 'ownerDisplayName') }
        if (-not $owner) { $owner = [string](Get-TenantBriefPropertyValue -Object $a -Name 'Owner') }
        $msRaw = [string](Get-TenantBriefPropertyValue -Object $a -Name 'isMicrosoftManaged')
        $isMs = ($msRaw -match '^(?i:true|1|yes)$')
        $lastUsedStr = [string](Get-TenantBriefPropertyValue -Object $a -Name 'lastUsedAt')

        $isBuilder = ($createdIn -match '(?i)Lite|Agent Builder')
        if ($isBuilder) { $builderCount++ } else { $studioCount++ }
        if ($isMs) { $msManagedCount++ }
        $isDefaultEnv = ($envName -match '(?i)\(default\)|^default')
        if (-not $isMs -and $isDefaultEnv) { $customDefaultEnvCount++ }
        $ownerMissing = ([string]::IsNullOrWhiteSpace($owner) -or $owner -match '(?i)^(notfound|unknown|n/a)$')
        if (-not $isMs -and $ownerMissing) { $unownedCount++ }
        $isStale = $false
        if ($lastUsedStr) {
            try {
                $dt = [datetime]::Parse($lastUsedStr)
                if ($dt -lt $cutoff) { $isStale = $true; $staleCount++ }
            } catch {}
        }

        $agents += [PSCustomObject]@{
            AgentId            = $id
            AgentName          = if ($name) { $name } else { $id }
            CreatedIn          = if ($isBuilder) { 'Agent Builder (Copilot Studio Lite)' } else { $createdIn }
            EnvironmentName    = if ($envName) { $envName } else { '-' }
            Owner              = if ($ownerMissing) { if ($isTr) { 'Sahipsiz / Çözümlenemedi' } else { 'Unowned / NotFound' } } else { $owner }
            IsMicrosoftManaged = $isMs
            LastUsedAt         = if ($lastUsedStr) { $lastUsedStr } else { '-' }
            IsStale            = $isStale
        }
    }

    $customCount = $agents.Count - $msManagedCount
    $findings = @()
    $findings += [PSCustomObject]@{
        TestId                 = 'FT.AGT.001'
        TestTitle              = if ($isTr) { 'Varsayılan Ortamda (Default) Özel Copilot Studio & Agent Builder Gölge Ajanları' } else { 'Custom Copilot Studio & Agent Builder Sprawl in Default Environment' }
        TestStatus             = if ($customDefaultEnvCount -gt 0) { 'Failed' } elseif ($customCount -gt 0) { 'Investigate' } else { 'Passed' }
        TestRisk               = if ($customDefaultEnvCount -gt 0) { 'High' } else { 'Medium' }
        TestPillar             = 'FastTrack'
        TestDomainPillars      = @('AI')
        TestSource             = 'FastTrack'
        TestCategory           = 'Agent 365 & Power Platform Governance (FastTrack)'
        TestSfiPillar          = 'Protect tenants and isolate production systems'
        TestImplementationCost = 'Medium'
        TestMinimumLicense     = 'AGENT_365'
        TestResult             = if ($isTr) { "Toplam $($agents.Count) ajan (Copilot Studio: $studioCount, Agent Builder: $builderCount, Microsoft Yönetimli: $msManagedCount). Varsayılan ortamda $customDefaultEnvCount özel ajan tespit edildi." } else { "Total $($agents.Count) agents (Copilot Studio: $studioCount, Agent Builder: $builderCount, Microsoft-managed: $msManagedCount). $customDefaultEnvCount custom agents reside in the Default environment." }
        TestDescription        = if ($isTr) { 'Microsoft FastTrack Inventory-PowerPlatformAgents yaklaşımına göre varsayılan ortamda biriken özel ajanlar DLP ve ortam izolasyonu dışına çıkabilir; özel yönetilen ortamlara (Managed Environments) taşınmalıdır.' } else { 'Per Microsoft FastTrack Inventory-PowerPlatformAgents guidance, custom agents accumulating in the Default environment bypass dedicated DLP boundaries and should be migrated to governed Managed Environments.' }
        TestImpact             = if ($isTr) { 'Kontrolsüz gölge AI ajanları, aşırı bağlayıcı izinleri ve kurumsal veri sızıntısı riski.' } else { 'Shadow AI agent sprawl, unvetted connectors, and uncontrolled enterprise data exposure.' }
        SkippedReason          = ''
    }

    $findings += [PSCustomObject]@{
        TestId                 = 'FT.AGT.002'
        TestTitle              = if ($isTr) { 'Sahipsiz veya 90+ Gün Atıl Power Platform / Copilot Ajanları' } else { 'Unowned or 90+ Day Stale Power Platform / Copilot Agents' }
        TestStatus             = if ($unownedCount -gt 0 -or $staleCount -gt 0) { 'Failed' } else { 'Passed' }
        TestRisk               = if ($unownedCount -gt 0) { 'High' } else { 'Medium' }
        TestPillar             = 'FastTrack'
        TestDomainPillars      = @('AI', 'Identity')
        TestSource             = 'FastTrack'
        TestCategory           = 'Agent Lifecycle Hygiene (FastTrack)'
        TestSfiPillar          = 'Protect identities and secrets'
        TestImplementationCost = 'Low'
        TestMinimumLicense     = 'AGENT_365'
        TestResult             = if ($isTr) { "Sahipsiz özel ajan: $unownedCount · 90+ gün kullanılmayan atıl ajan: $staleCount." } else { "Unowned custom agents: $unownedCount · 90+ day stale agents: $staleCount." }
        TestDescription        = if ($isTr) { 'Sahibi ayrılmış veya çözümlenemeyen ajanlar yetim kimlik/bağlayıcı riski taşır; 90+ gün pasif ajanlar gözden geçirilip devre dışı bırakılmalıdır.' } else { 'Orphaned agents without active owners create credential and connector risk; agents inactive for 90+ days should be reviewed and retired.' }
        TestImpact             = if ($isTr) { 'Yetim otomasyon kimlikleri ve gereksiz saldırı yüzeyi.' } else { 'Orphaned automation identities and unnecessary AI attack surface.' }
        SkippedReason          = ''
    }

    return [PSCustomObject]@{
        Summary = [PSCustomObject]@{
            TotalAgents           = $agents.Count
            CopilotStudioCount    = $studioCount
            AgentBuilderCount     = $builderCount
            MicrosoftManagedCount = $msManagedCount
            CustomAgentCount      = $customCount
            CustomDefaultEnvCount = $customDefaultEnvCount
            UnownedCount          = $unownedCount
            Stale90dCount         = $staleCount
            Agents                = @($agents | Select-Object -First 30)
        }
        Findings = @($findings)
    }
}
