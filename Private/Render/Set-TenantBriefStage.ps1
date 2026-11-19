function Set-TenantBriefStage {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [object]$Manifest,

        [Parameter(Mandatory = $true)]
        [int]$Stage,

        [Parameter(Mandatory = $true)]
        [string]$Name,

        [Parameter(Mandatory = $true)]
        [ValidateSet('started', 'completed', 'failed', 'skipped')]
        [string]$Status,

        [Parameter(Mandatory = $false)]
        [string]$Message
    )

    $now = (Get-Date).ToString('o')
    $entry = $null
    foreach ($s in @($Manifest.Stages)) {
        if ($s.Stage -eq $Stage) { $entry = $s; break }
    }
    if (-not $entry) {
        $entry = [PSCustomObject]@{
            Stage     = $Stage
            Name      = $Name
            Status    = $Status
            StartedAt = $now
            EndedAt   = $null
            Message   = ''
        }
        $Manifest.Stages = @($Manifest.Stages) + $entry
    }
    if (-not $entry.StartedAt) { $entry.StartedAt = $now }
    $entry.Status = $Status
    if ($Status -eq 'started') { $entry.EndedAt = $null } else { $entry.EndedAt = $now }
    if ($Message) { $entry.Message = $Message }
}
