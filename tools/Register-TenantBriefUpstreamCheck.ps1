<#
.SYNOPSIS
Registers or unregisters the monthly TenantBrief upstream check Windows Scheduled Task (S8.1).

.DESCRIPTION
Creates a user-level (RunLevel Limited, no admin required) Scheduled Task that triggers
10 minutes after the current user logs on, runs only when network is available, allows battery
operation, caps execution at 1 hour, and invokes tools/Invoke-TenantBriefUpstreamCheck.ps1
hidden in PowerShell 7. Pass -Unregister to remove the task.

.EXAMPLE
pwsh -NoProfile -File .\tools\Register-TenantBriefUpstreamCheck.ps1

.EXAMPLE
pwsh -NoProfile -File .\tools\Register-TenantBriefUpstreamCheck.ps1 -Unregister
#>
[CmdletBinding()]
param(
    [Parameter()]
    [switch]$Unregister,

    [Parameter()]
    [string]$TaskName = 'TenantBrief-UpstreamCheck',

    [Parameter()]
    [string]$ScriptPath = (Join-Path $PSScriptRoot 'Invoke-TenantBriefUpstreamCheck.ps1')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ($Unregister) {
    $existing = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
    if ($existing) {
        Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false
        Write-Output "Unregistered scheduled task '$TaskName'."
    } else {
        Write-Output "Scheduled task '$TaskName' was not registered."
    }
    return
}

if (-not (Test-Path -LiteralPath $ScriptPath)) {
    throw "Upstream check script not found: $ScriptPath"
}
$resolvedScript = (Resolve-Path -LiteralPath $ScriptPath).Path
$pwshExe = (Get-Command pwsh -ErrorAction SilentlyContinue).Source
if (-not $pwshExe) { $pwshExe = 'pwsh.exe' }

$trigger = New-ScheduledTaskTrigger -AtLogOn -User $env:USERNAME
$trigger.Delay = 'PT10M'

$settings = New-ScheduledTaskSettingsSet `
    -StartWhenAvailable `
    -RunOnlyIfNetworkAvailable `
    -ExecutionTimeLimit (New-TimeSpan -Hours 1) `
    -AllowStartIfOnBatteries `
    -DontStopIfGoingOnBatteries

$principal = New-ScheduledTaskPrincipal -UserId $env:USERNAME -LogonType Interactive -RunLevel Limited
$action = New-ScheduledTaskAction -Execute $pwshExe -Argument "-NoProfile -WindowStyle Hidden -File `"$resolvedScript`""

$null = Register-ScheduledTask `
    -TaskName $TaskName `
    -Action $action `
    -Trigger $trigger `
    -Settings $settings `
    -Principal $principal `
    -Description 'TenantBrief monthly read-only upstream dependency check (S8.1).' `
    -Force

Get-ScheduledTask -TaskName $TaskName
