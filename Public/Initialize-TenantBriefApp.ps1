function Initialize-TenantBriefApp {
    <#
    .SYNOPSIS
    Automates one-time setup (or cleanup via -Remove) of a read-only Entra ID App Registration and local X.509 certificate for zero-popup TenantBrief runs.

    .DESCRIPTION
    Creates a non-exportable local X.509 certificate in Cert:\CurrentUser\My, registers a strictly
    read-only Entra ID application, uploads only the public key, grants least-privilege read-only
    Microsoft Graph and Exchange.ManageAsApp application permissions, assigns the Global Reader
    directory role to the Service Principal, and saves non-secret profile metadata locally for
    zero-popup runs via Connect-TenantBrief -UseAppAuth.

    Supports -WhatIf and -Remove for full rollback.

    .EXAMPLE
    Initialize-TenantBriefApp

    .EXAMPLE
    Initialize-TenantBriefApp -Remove
    #>
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
    [OutputType([PSCustomObject])]
    param(
        [Parameter()]
        [string]$AppDisplayName = 'TenantBrief-ReadOnly-Audit',

        [Parameter()]
        [ValidateRange(1, 24)]
        [int]$CertValidityMonths = 12,

        [Parameter()]
        [string]$TenantId,

        [Parameter()]
        [string]$ProfilePath,

        [Parameter()]
        [switch]$Remove
    )

    $resolvedProfilePath = Get-TenantBriefAppProfilePath -ProfilePath $ProfilePath

    if ($Remove) {
        $existing = Get-TenantBriefAppProfile -ProfilePath $resolvedProfilePath
        if (-not $existing) {
            Write-Warning "[TenantBrief] No local app profile found at '$resolvedProfilePath'."
            return $null
        }
        if ($PSCmdlet.ShouldProcess("$($existing.AppDisplayName) ($($existing.AppId))", 'Remove Entra ID App Registration, local certificate, and profile')) {
            $mg = Get-MgContext -ErrorAction SilentlyContinue
            if (-not $mg) {
                Connect-MgGraph -Scopes 'Application.ReadWrite.All' -NoWelcome | Out-Null
            }
            if ($existing.AppObjectId) {
                try {
                    Invoke-MgGraphRequest -Method DELETE -Uri "https://graph.microsoft.com/v1.0/applications/$($existing.AppObjectId)" -ErrorAction Stop | Out-Null
                    Write-Information -MessageData "[TenantBrief] Deleted Entra ID App Registration ($($existing.AppId))." -InformationAction Continue
                } catch {
                    Write-Warning "[TenantBrief] Could not delete Entra ID app ($($existing.AppObjectId)): $($_.Exception.Message)"
                }
            }
            if ($existing.CertificateThumbprint) {
                $certItem = Get-Item -Path "Cert:\CurrentUser\My\$($existing.CertificateThumbprint)" -ErrorAction SilentlyContinue
                if ($certItem) {
                    Remove-Item -LiteralPath $certItem.PSPath -Force -ErrorAction SilentlyContinue
                    Write-Information -MessageData "[TenantBrief] Removed local certificate ($($existing.CertificateThumbprint))." -InformationAction Continue
                }
            }
            if (Test-Path -LiteralPath $resolvedProfilePath) {
                Remove-Item -LiteralPath $resolvedProfilePath -Force -ErrorAction SilentlyContinue
                Write-Information -MessageData "[TenantBrief] Removed local app profile '$resolvedProfilePath'." -InformationAction Continue
            }
        }
        return [PSCustomObject]@{ Action = 'Removed'; AppId = $existing.AppId; ProfilePath = $resolvedProfilePath }
    }

    $setupScopes = @('Application.ReadWrite.All', 'AppRoleAssignment.ReadWrite.All', 'RoleManagement.ReadWrite.Directory', 'Organization.Read.All')
    if (-not $PSCmdlet.ShouldProcess($AppDisplayName, 'Create local X.509 certificate, read-only Entra ID App Registration, and grant least-privilege read-only permissions')) {
        return [PSCustomObject]@{
            Action         = 'WhatIf'
            AppDisplayName = $AppDisplayName
            ProfilePath    = $resolvedProfilePath
            ValidityMonths = $CertValidityMonths
        }
    }

    Write-Information -MessageData '[TenantBrief] Connecting once with admin setup scopes to provision read-only App Registration...' -InformationAction Continue
    $connectArgs = @{ Scopes = $setupScopes; NoWelcome = $true }
    if (-not [string]::IsNullOrWhiteSpace($TenantId)) { $connectArgs['TenantId'] = $TenantId }
    Connect-MgGraph @connectArgs | Out-Null

    $mgCtx = Get-MgContext -ErrorAction Stop
    $orgResp = Invoke-MgGraphRequest -Method GET -Uri 'https://graph.microsoft.com/v1.0/organization?$select=id,verifiedDomains' -ErrorAction Stop
    $resolvedTenantId = [string]$orgResp.value[0].id
    $onMsDomain = @($orgResp.value[0].verifiedDomains | Where-Object { $_.name -like '*.onmicrosoft.com' -and $_.name -notlike '*.mail.onmicrosoft.com' } | Select-Object -First 1)
    $orgDomain = if ($onMsDomain -and $onMsDomain.name) { [string]$onMsDomain.name } else { [string]$orgResp.value[0].verifiedDomains[0].name }

    # 1. Create non-exportable local X.509 certificate
    $notAfter = (Get-Date).AddMonths($CertValidityMonths)
    $cert = New-SelfSignedCertificate `
        -Subject "CN=$AppDisplayName-$orgDomain" `
        -CertStoreLocation 'Cert:\CurrentUser\My' `
        -KeyExportPolicy NonExportable `
        -KeySpec Signature `
        -KeyLength 2048 `
        -HashAlgorithm SHA256 `
        -NotAfter $notAfter `
        -ErrorAction Stop

    $rawCertB64 = [Convert]::ToBase64String($cert.GetRawCertData())
    $thumbprint = [string]$cert.Thumbprint

    # 2. Resolve Microsoft Graph & Exchange Online service principals and exact least-privilege read-only appRole IDs
    $graphSpResp = Invoke-MgGraphRequest -Method GET -Uri "https://graph.microsoft.com/v1.0/servicePrincipals?`$filter=appId eq '00000003-0000-0000-c000-000000000000'&`$select=id,appId,appRoles" -ErrorAction Stop
    $graphSp = $graphSpResp.value[0]

    $exoSpResp = Invoke-MgGraphRequest -Method GET -Uri "https://graph.microsoft.com/v1.0/servicePrincipals?`$filter=appId eq '00000002-0000-0ff1-ce00-000000000000'&`$select=id,appId,appRoles" -ErrorAction Stop
    $exoSp = if ($exoSpResp.value -and $exoSpResp.value.Count -gt 0) { $exoSpResp.value[0] } else { $null }

    $desiredGraphRoles = @(
        'AuditLog.Read.All',
        'DeviceManagementConfiguration.Read.All',
        'DeviceManagementManagedDevices.Read.All',
        'Directory.Read.All',
        'IdentityRiskyUser.Read.All',
        'Organization.Read.All',
        'Policy.Read.All',
        'Policy.Read.ConditionalAccess',
        'Reports.Read.All',
        'RoleManagement.Read.All',
        'SecurityEvents.Read.All',
        'SharePointTenantSettings.Read.All',
        'Sites.Read.All',
        'UserAuthenticationMethod.Read.All'
    )

    $graphRoleIds = [System.Collections.Generic.List[string]]::new()
    foreach ($rName in $desiredGraphRoles) {
        $match = @($graphSp.appRoles | Where-Object { $_.value -eq $rName -and $_.isEnabled -eq $true } | Select-Object -First 1)
        if ($match -and $match.id) { $graphRoleIds.Add([string]$match.id) }
    }

    $exoRoleId = $null
    if ($exoSp) {
        $exoMatch = @($exoSp.appRoles | Where-Object { $_.value -eq 'Exchange.ManageAsApp' -and $_.isEnabled -eq $true } | Select-Object -First 1)
        if ($exoMatch -and $exoMatch.id) { $exoRoleId = [string]$exoMatch.id }
    }

    $reqAccess = [System.Collections.Generic.List[object]]::new()
    $reqAccess.Add(@{
        resourceAppId  = '00000003-0000-0000-c000-000000000000'
        resourceAccess = @($graphRoleIds | ForEach-Object { @{ id = $_; type = 'Role' } })
    })
    if ($exoRoleId) {
        $reqAccess.Add(@{
            resourceAppId  = '00000002-0000-0ff1-ce00-000000000000'
            resourceAccess = @(@{ id = $exoRoleId; type = 'Role' })
        })
    }

    # 3. Create Entra ID Application with public key credential attached
    $appBody = @{
        displayName            = $AppDisplayName
        signInAudience         = 'AzureADMyOrg'
        requiredResourceAccess = $reqAccess.ToArray()
        keyCredentials         = @(
            @{
                type        = 'AsymmetricX509Cert'
                usage       = 'Verify'
                displayName = "TenantBrief-$($thumbprint.Substring(0,8))"
                key         = $rawCertB64
            }
        )
    } | ConvertTo-Json -Depth 10

    $appObj = Invoke-MgGraphRequest -Method POST -Uri 'https://graph.microsoft.com/v1.0/applications' -Body $appBody -ContentType 'application/json' -ErrorAction Stop
    $appId = [string]$appObj.appId
    $appObjectId = [string]$appObj.id

    # 4. Create Service Principal
    $spBody = @{ appId = $appId } | ConvertTo-Json
    $spObj = Invoke-MgGraphRequest -Method POST -Uri 'https://graph.microsoft.com/v1.0/servicePrincipals' -Body $spBody -ContentType 'application/json' -ErrorAction Stop
    $spId = [string]$spObj.id

    # 5. Grant admin consent via appRoleAssignments
    foreach ($rid in $graphRoleIds) {
        $assignBody = @{ principalId = $spId; resourceId = [string]$graphSp.id; appRoleId = $rid } | ConvertTo-Json
        try {
            Invoke-MgGraphRequest -Method POST -Uri "https://graph.microsoft.com/v1.0/servicePrincipals/$spId/appRoleAssignments" -Body $assignBody -ContentType 'application/json' -ErrorAction Stop | Out-Null
        } catch {
            Write-Verbose ("Graph appRoleAssignment note ($rid): " + $_.Exception.Message)
        }
    }
    if ($exoSp -and $exoRoleId) {
        $exoAssignBody = @{ principalId = $spId; resourceId = [string]$exoSp.id; appRoleId = $exoRoleId } | ConvertTo-Json
        try {
            Invoke-MgGraphRequest -Method POST -Uri "https://graph.microsoft.com/v1.0/servicePrincipals/$spId/appRoleAssignments" -Body $exoAssignBody -ContentType 'application/json' -ErrorAction Stop | Out-Null
        } catch {
            Write-Verbose ("EXO appRoleAssignment note: " + $_.Exception.Message)
        }
    }

    # 6. Assign Global Reader directory role to Service Principal (required for read-only EXO/Teams/Defender)
    try {
        $roleDefResp = Invoke-MgGraphRequest -Method GET -Uri "https://graph.microsoft.com/v1.0/roleManagement/directory/roleDefinitions?`$filter=displayName eq 'Global Reader'&`$select=id,displayName" -ErrorAction Stop
        if ($roleDefResp.value -and $roleDefResp.value.Count -gt 0) {
            $globalReaderDefId = [string]$roleDefResp.value[0].id
            $roleAssignBody = @{
                '@odata.type'    = '#microsoft.graph.unifiedRoleAssignment'
                principalId      = $spId
                roleDefinitionId = $globalReaderDefId
                directoryScopeId = '/'
            } | ConvertTo-Json
            Invoke-MgGraphRequest -Method POST -Uri 'https://graph.microsoft.com/v1.0/roleManagement/directory/roleAssignments' -Body $roleAssignBody -ContentType 'application/json' -ErrorAction Stop | Out-Null
        }
    } catch {
        Write-Warning "[TenantBrief] Could not auto-assign Global Reader role (assign manually in Entra ID -> Roles -> Global Reader): $($_.Exception.Message)"
    }

    # 7. Save non-secret local profile JSON
    $profileDir = Split-Path -Path $resolvedProfilePath -Parent
    if ($profileDir -and -not (Test-Path -LiteralPath $profileDir)) {
        New-Item -ItemType Directory -Path $profileDir -Force | Out-Null
    }
    $profileObj = [PSCustomObject]@{
        AppDisplayName        = $AppDisplayName
        TenantId              = $resolvedTenantId
        Organization          = $orgDomain
        AppId                 = $appId
        AppObjectId           = $appObjectId
        ServicePrincipalId    = $spId
        CertificateThumbprint = $thumbprint
        CertExpiresAt         = $notAfter.ToString('o')
        CreatedBy             = [string]$mgCtx.Account
        CreatedAt             = (Get-Date).ToString('o')
        GraphPermissionsCount = $graphRoleIds.Count
        ExchangeManageAsApp   = [bool]$exoRoleId
    }
    $profileObj | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $resolvedProfilePath -Encoding UTF8

    Write-Information -MessageData "[TenantBrief] Setup complete! Profile saved to '$resolvedProfilePath'." -InformationAction Continue
    Write-Information -MessageData "[TenantBrief] Next: Connect-TenantBrief -UseAppAuth ; Invoke-TenantBriefAssessment -OutputPath `"`$HOME\TenantBriefReport`" -Language tr -Framework All" -InformationAction Continue
    return $profileObj
}
