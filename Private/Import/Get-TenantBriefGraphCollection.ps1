function Get-TenantBriefGraphCollection {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Uri,

        [Parameter(Mandatory = $false)]
        [int]$PageLimit = 200
    )

    $items = New-Object System.Collections.Generic.List[object]
    $nextLink = $Uri
    $page = 0

    while ($nextLink -and $page -lt $PageLimit) {
        $page++
        $response = Invoke-MgGraphRequest -Method GET -Uri $nextLink -ErrorAction Stop
        if ($null -eq $response) { break }

        $values = $null
        if ($response -is [hashtable]) {
            if ($response.ContainsKey('value')) { $values = $response['value'] }
        } elseif ($response.PSObject.Properties['value']) {
            $values = $response.value
        }
        foreach ($v in @($values)) {
            if ($null -ne $v) { $items.Add($v) }
        }

        $nextLink = $null
        if ($response -is [hashtable]) {
            if ($response.ContainsKey('@odata.nextLink')) { $nextLink = [string]$response['@odata.nextLink'] }
        } elseif ($response.PSObject.Properties['@odata.nextLink']) {
            $nextLink = [string]$response.'@odata.nextLink'
        }

        if ($nextLink) {
            Write-Verbose "Graph sayfalamasi devam ediyor (sayfa $page, $($items.Count) kayit): $nextLink"
        }
    }

    if ($nextLink) {
        Write-Warning "Graph sayfalama siniri ($PageLimit sayfa) asildi; sonuc kismi olabilir."
    }

    return $items.ToArray()
}
