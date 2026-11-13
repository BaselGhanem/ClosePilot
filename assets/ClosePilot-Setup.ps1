param(
    [Parameter(Mandatory=$true)]
    [ValidateSet('enable-startup','disable-startup','migrate-legacy','start-agent','stop-agent','start-updater')]
    [string]$Action
)
$ErrorActionPreference = 'Stop'
$root = Join-Path $env:LOCALAPPDATA 'ClosePilot'
$agent = Join-Path $root 'ClosePilot-Agent.ps1'
$startup = [Environment]::GetFolderPath('Startup')
$link = Join-Path $startup 'ClosePilot Monitor.lnk'
if ($Action -eq 'enable-startup') {
    if (-not (Test-Path -LiteralPath $agent)) { throw 'Agent file missing.' }
    $shell = New-Object -ComObject WScript.Shell
    $shortcut = $shell.CreateShortcut($link)
    $shortcut.TargetPath = Join-Path $PSHOME 'powershell.exe'
    $shortcut.Arguments = ('-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File "{0}"' -f $agent)
    $shortcut.WorkingDirectory = $root
    $shortcut.Description = 'ClosePilot automatic background monitor'
    $shortcut.WindowStyle = 7
    $shortcut.Save()
    Write-Output 'Startup enabled.'
}
if ($Action -eq 'disable-startup') {
    Remove-Item -LiteralPath $link -Force -ErrorAction SilentlyContinue
    Write-Output 'Startup disabled.'
}

if ($Action -eq 'start-updater') {
    $updaterScript = Join-Path $root 'ClosePilot-Updater.ps1'
    $requestFile = Join-Path $root 'update-request.json'
    if (-not (Test-Path -LiteralPath $updaterScript -PathType Leaf)) {
        throw 'Update script not installed.'
    }
    if (-not (Test-Path -LiteralPath $requestFile -PathType Leaf)) {
        throw 'Update request missing.'
    }
    $powershell = Join-Path $PSHOME 'powershell.exe'
    $arguments = '-NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "{0}"' -f $updaterScript
    $updateProcess = Start-Process -FilePath $powershell -ArgumentList $arguments -WorkingDirectory $root -WindowStyle Hidden -PassThru -ErrorAction Stop
    Write-Output ('Update process launched, PID {0}' -f $updateProcess.Id)
}

if ($Action -eq 'start-agent') {
    if (-not (Test-Path -LiteralPath $agent)) { throw 'Agent file missing.' }
    $statusFile = Join-Path $root 'status.json'
    $processes = @(Get-CimInstance Win32_Process -Filter "Name = 'powershell.exe'" -ErrorAction Stop | Where-Object {
        $_.CommandLine -and
        $_.CommandLine.IndexOf($agent, [System.StringComparison]::OrdinalIgnoreCase) -ge 0
    })
    $healthy = $false
    if ($processes.Count -eq 1 -and (Test-Path -LiteralPath $statusFile)) {
        try {
            $status = Get-Content -LiteralPath $statusFile -Raw -Encoding UTF8 | ConvertFrom-Json
            $updated = [DateTimeOffset]::Parse([string]$status.updatedAt)
            $ageSeconds = ([DateTimeOffset]::Now - $updated).TotalSeconds
            $healthy = (($status.version -eq '1.2.2') -and
                        ([int]$status.agentPid -eq [int]$processes[0].ProcessId) -and
                        ($ageSeconds -gt -5) -and ($ageSeconds -lt 12))
        } catch { $healthy = $false }
    }
    if ($healthy) {
        Write-Output ('Healthy ClosePilot agent already running, PID {0}' -f $processes[0].ProcessId)
    } else {
        # A stale legacy process may still own the named mutex. Terminate only agents
        # whose PowerShell command line points to this exact ClosePilot agent path.
        foreach ($process in $processes) {
            Stop-Process -Id ([int]$process.ProcessId) -Force -ErrorAction Stop
            Write-Output ('Retired stale ClosePilot agent PID {0}' -f $process.ProcessId)
        }
        Remove-Item -LiteralPath (Join-Path $root 'stop.request') -Force -ErrorAction SilentlyContinue
        if ($processes.Count -gt 0) { Start-Sleep -Milliseconds 750 }
        $powershell = Join-Path $PSHOME 'powershell.exe'
        $args = '-NoProfile -NonInteractive -ExecutionPolicy Bypass -File "{0}"' -f $agent
        $newProcess = Start-Process -FilePath $powershell -ArgumentList $args -WorkingDirectory $root -WindowStyle Hidden -PassThru -ErrorAction Stop
        Write-Output ('Agent launch requested, PID {0}' -f $newProcess.Id)
    }
}

if ($Action -eq 'stop-agent') {
    $processes = @(Get-CimInstance Win32_Process -Filter "Name = 'powershell.exe'" -ErrorAction Stop |
        Where-Object {
            $_.CommandLine -and
            $_.CommandLine.IndexOf($agent, [System.StringComparison]::OrdinalIgnoreCase) -ge 0
        })
    if ($processes.Count -gt 0) {
        Set-Content -LiteralPath (Join-Path $root 'stop.request') -Value 'stop'
        foreach ($process in $processes) {
            $running = Get-Process -Id $process.ProcessId -ErrorAction SilentlyContinue
            if ($null -ne $running -and -not $running.WaitForExit(4000)) {
                $running.Kill()
                if (-not $running.WaitForExit(4000)) { throw 'Monitor did not exit.' }
            }
        }
    }
    Remove-Item -LiteralPath (Join-Path $root 'status.json'),(Join-Path $root 'stop.request') -Force -ErrorAction SilentlyContinue
}

if ($Action -eq 'migrate-legacy') {
    # Only the known previous script is retired, not other PowerShell processes.
    $legacy = Join-Path $env:LOCALAPPDATA 'AutoCloseCleaner\AutoCloseCleaner.ps1'
    $legacyLink = Join-Path $startup 'AutoCloseCleaner.lnk'
    Remove-Item -LiteralPath $legacyLink -Force -ErrorAction SilentlyContinue
    Get-CimInstance Win32_Process -Filter "Name = 'powershell.exe'" -ErrorAction SilentlyContinue | ForEach-Object {
        if ($_.CommandLine -and $_.CommandLine.IndexOf($legacy, [System.StringComparison]::OrdinalIgnoreCase) -ge 0) {
            Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue
        }
    }
    Write-Output 'Previous monitor retired. Its files and logs were preserved.'
}
