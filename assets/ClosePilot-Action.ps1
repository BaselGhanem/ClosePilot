param(
    [Parameter(Mandatory=$true)][ValidateSet('close-all')][string]$Action,
    [Parameter(Mandatory=$true)][string]$IdsBase64
)
$ErrorActionPreference = 'Stop'
$root = Join-Path $env:LOCALAPPDATA 'ClosePilot'
$configFile = Join-Path $root 'config.json'
$logFile = Join-Path $root 'events.jsonl'
if (-not (Test-Path -LiteralPath $configFile)) { throw 'ClosePilot configuration is missing.' }
$configuration = Get-Content -LiteralPath $configFile -Raw -Encoding UTF8 | ConvertFrom-Json
try {
    $rawIds = [System.Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($IdsBase64))
    $parsedIds = ConvertFrom-Json -InputObject $rawIds
    $requestedIds = @()
    foreach ($candidate in $parsedIds) {
        if ($candidate -is [string] -and -not [string]::IsNullOrWhiteSpace($candidate)) {
            $requestedIds += [string]$candidate
        }
    }
} catch { throw 'Invalid Close All selection.' }
if ($requestedIds.Count -eq 0) { throw 'No application selected.' }
$blockedNames = @(
    'system','idle','svchost','wininit','winlogon','csrss','services','lsass',
    'smss','explorer','dwm','sihost','taskhostw','fontdrvhost','registry',
    'spoolsv','conhost','powershell','pwsh','cmd','msmpeng',
    'securityhealthservice','searchhost','shellexperiencehost',
    'startmenuexperiencehost','runtimebroker','audiodg','systemsettings',
    'applicationframehost','taskmgr','closepilot'
)
$closedApps = 0
$closedProcesses = 0
$failedProcesses = 0
$observedMb = 0.0
$selectedApps = 0
foreach ($app in @($configuration.apps)) {
    if ($null -eq $app) { continue }
    if (-not ($requestedIds -ccontains [string]$app.id)) { continue }
    $selectedApps++
    $names = @($app.names | Where-Object {
        $_ -is [string] -and
        $_ -match '^[a-zA-Z0-9_-]+$' -and
        $_.ToLowerInvariant() -notin $blockedNames
    })
    if ($names.Count -eq 0) { continue }
    $processes = @(Get-Process -Name $names -ErrorAction SilentlyContinue |
        Where-Object { $null -ne $_ -and $_.Id -ne $PID } |
        Sort-Object -Property Id -Unique)
    $appStopped = 0
    $appMb = 0.0
    foreach ($process in $processes) {
        $targetPid = [int]$process.Id
        try {
            $mb = [math]::Round(([double]$process.WorkingSet64 / 1MB), 2)
            Stop-Process -Id $targetPid -Force -ErrorAction Stop
            $appStopped++
            $closedProcesses++
            $appMb += $mb
        } catch {
            if (Get-Process -Id $targetPid -ErrorAction SilentlyContinue) {
                $failedProcesses++
                $entry = [ordered]@{
                    at=(Get-Date).ToString('o'); kind='error'; app=[string]$app.id
                    message=('Manual close failed for PID {0}: {1}' -f $targetPid,$_.Exception.Message)
                    pid=$targetPid; observedMb=0
                }
                Add-Content -LiteralPath $logFile -Value ($entry | ConvertTo-Json -Compress -Depth 3) -Encoding UTF8
            }
        }
    }
    if ($appStopped -gt 0) {
        $closedApps++
        $observedMb += $appMb
        $event = [ordered]@{
            at=(Get-Date).ToString('o'); kind='manual-close-all'; app=[string]$app.id
            message=('Close All: closed {0} processes for {1}.' -f $appStopped,[string]$app.label)
            pid=0; observedMb=[math]::Round($appMb,1)
        }
        Add-Content -LiteralPath $logFile -Value ($event | ConvertTo-Json -Compress -Depth 3) -Encoding UTF8
    }
}
$summary = [ordered]@{
    selectedApps = $selectedApps
    closedApps = $closedApps
    closedProcesses = $closedProcesses
    failedProcesses = $failedProcesses
    observedMb = [math]::Round($observedMb,1)
}
$summary | ConvertTo-Json -Compress -Depth 3
