function Compare-TenantBriefReports {
    <#
    .SYNOPSIS
    Compares two TenantBrief JSON reports and lists improved and regressed controls.

    .DESCRIPTION
    Matches findings by control Id. A control that moves to Passed is reported as improved;
    a control that leaves Passed is reported as regressed. Use it for drift tracking between
    two assessment runs.

    .EXAMPLE
    Compare-TenantBriefReports -BaselineJsonPath .\old\TenantBriefReport-TR.json `
    -CurrentJsonPath .\new\TenantBriefReport-TR.json
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$BaselineJsonPath,

        [Parameter(Mandatory = $true)]
        [string]$CurrentJsonPath
    )

    if (-not (Test-Path $BaselineJsonPath)) { throw "Baseline JSON not found: $BaselineJsonPath" }
    if (-not (Test-Path $CurrentJsonPath)) { throw "Current JSON not found: $CurrentJsonPath" }

    $base = Get-Content -Path $BaselineJsonPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $curr = Get-Content -Path $CurrentJsonPath -Raw -Encoding UTF8 | ConvertFrom-Json

    $baseMap = @{}
    foreach ($t in @($base.Findings)) { $baseMap[[string]$t.Id] = $t }

    $improved = @()
    $regressed = @()
    $unchanged = 0

    foreach ($t in @($curr.Findings)) {
        $id = [string]$t.Id
        if (-not $id -or -not $baseMap.ContainsKey($id)) { continue }
        $prev = $baseMap[$id]
        if ($prev.Status -ne 'Passed' -and $t.Status -eq 'Passed') {
            $improved += [PSCustomObject]@{ Id = $id; Title = $t.Title; From = $prev.Status; To = $t.Status; Risk = $t.Risk }
        } elseif ($prev.Status -eq 'Passed' -and $t.Status -ne 'Passed') {
            $regressed += [PSCustomObject]@{ Id = $id; Title = $t.Title; From = $prev.Status; To = $t.Status; Risk = $t.Risk }
        } else {
            $unchanged++
        }
    }

    return [PSCustomObject]@{
        BaselineTotal  = $base.Summary.Total
        CurrentTotal   = $curr.Summary.Total
        ImprovedCount  = $improved.Count
        RegressedCount = $regressed.Count
        UnchangedCount = $unchanged
        Improved       = $improved
        Regressed      = $regressed
    }
}
