function Add-TenantBriefDiagnostic {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [System.Collections.Generic.List[object]]$Diagnostics,

        [Parameter(Mandatory = $true)]
        [int]$Stage,

        [Parameter(Mandatory = $true)]
        [string]$Component,

        [Parameter(Mandatory = $true)]
        [string]$Message,

        [Parameter(Mandatory = $false)]
        [ValidateSet('Info', 'Warning', 'Error')]
        [string]$Severity = 'Warning',

        [Parameter(Mandatory = $false)]
        [string]$Remedy = ''
    )

    if ($null -eq $Diagnostics) { return }
    $Diagnostics.Add([PSCustomObject]@{
        Stage     = $Stage
        Component = $Component
        Severity  = $Severity
        Message   = $Message
        Remedy    = $Remedy
        Timestamp = (Get-Date).ToString('o')
    })
    Write-Verbose "[TenantBrief] Stage $Stage / ${Component}: $Message"
}
