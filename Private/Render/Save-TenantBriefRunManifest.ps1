function Save-TenantBriefRunManifest {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [object]$Manifest,

        [Parameter(Mandatory = $true)]
        [string]$Path,

        [Parameter(Mandatory = $false)]
        [string]$Status,

        [Parameter(Mandatory = $false)]
        [AllowEmptyCollection()]
        [System.Collections.Generic.List[object]]$Diagnostics
    )

    if ($Status) { $Manifest.Status = $Status }
    $Manifest.UpdatedAt = (Get-Date).ToString('o')
    if ($null -ne $Diagnostics) { $Manifest.Diagnostics = @($Diagnostics) }
    try {
        # Written after every stage transition so an interrupted run still leaves a trace on disk.
        $Manifest | ConvertTo-Json -Depth 6 | Set-Content -Path $Path -Encoding UTF8 -ErrorAction Stop
    } catch {
        Write-Verbose "[TenantBrief] run manifest could not be written: $($_.Exception.Message)"
    }
}
