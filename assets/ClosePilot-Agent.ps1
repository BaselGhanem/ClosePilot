# ClosePilot agent v1.2.3 | Windows PowerShell 5.1+ | Runs in the current user session.
# Early boot trace: retained even if initialization exits before the main event log.
try {
  $entryRoot = Join-Path $env:LOCALAPPDATA 'ClosePilot'
  New-Item -ItemType Directory -Path $entryRoot -Force | Out-Null
  Add-Content -LiteralPath (Join-Path $entryRoot 'agent-entry.log') -Value ('{0} | Entrypoint reached | PID {1}' -f (Get-Date).ToString('o'), $PID) -Encoding UTF8
} catch { }

# Intentionally observes actual top-level visible windows and only arms an app AFTER
# its visible window has been observed. Does not kill unspecified/background-only apps.
$ErrorActionPreference = 'Stop'
$root = Join-Path $env:LOCALAPPDATA 'ClosePilot'
$configFile = Join-Path $root 'config.json'
$statusFile = Join-Path $root 'status.json'
$logFile = Join-Path $root 'events.jsonl'
$stopFile = Join-Path $root 'stop.request'
New-Item -ItemType Directory -Path $root -Force | Out-Null
$blockedNames = @(
    'system','idle','svchost','wininit','winlogon','csrss','services','lsass',
    'smss','explorer','dwm','sihost','taskhostw','fontdrvhost','registry',
    'spoolsv','conhost','powershell','pwsh','cmd','msmpeng',
    'securityhealthservice','searchhost','shellexperiencehost',
    'startmenuexperiencehost','runtimebroker','audiodg','systemsettings',
    'applicationframehost','taskmgr','closepilot'
)
$mutex = $null
$owned = $false
$metricsWorker = $null
try {
    $mutex = [System.Threading.Mutex]::new($true, 'Local\ClosePilot_Agent_v1', [ref]$owned)
    if (-not $owned) { exit 0 }

    Add-Type -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
public static class ClosePilotWindows {
    private delegate bool EnumWindowCallback(IntPtr hwnd, IntPtr param);
    [DllImport("user32.dll")] private static extern bool EnumWindows(EnumWindowCallback fn, IntPtr param);
    [DllImport("user32.dll")] private static extern bool IsWindowVisible(IntPtr hwnd);
    [DllImport("user32.dll")] private static extern IntPtr GetWindow(IntPtr hwnd, uint command);
    [DllImport("user32.dll")] private static extern int GetWindowTextLength(IntPtr hwnd);
    [DllImport("user32.dll")] private static extern uint GetWindowThreadProcessId(IntPtr hwnd, out uint processId);
    public static HashSet<int> VisibleAppProcessIds() {
        var ids = new HashSet<int>();
        EnumWindows((hwnd, param) => {
            if (!IsWindowVisible(hwnd)) return true;
            if (GetWindow(hwnd, 4) != IntPtr.Zero) return true; // GW_OWNER
            if (GetWindowTextLength(hwnd) == 0) return true; // exclude unnamed helper windows
            uint pid;
            GetWindowThreadProcessId(hwnd, out pid);
            if (pid > 0) ids.Add((int)pid);
            return true;
        }, IntPtr.Zero);
        return ids;
    }
}
'@
    function Write-Event([string]$kind, [string]$app, [string]$message, [int]$pidValue = 0, [double]$observedMb = 0) {
        try {
            $event = [ordered]@{
                at = (Get-Date).ToString('o')
                kind = $kind
                app = $app
                message = $message
                pid = $pidValue
                observedMb = [math]::Round($observedMb, 1)
            }
            Add-Content -LiteralPath $logFile -Value ($event | ConvertTo-Json -Compress -Depth 3) -Encoding UTF8
        } catch { }
    }
    function Write-Status($status) {
        # Write a complete snapshot to a temporary file first.
        # On some Windows configurations File.Replace fails on subsequent updates.
        # An overwrite fallback keeps the heartbeat alive and records the failure.
        $temporary = Join-Path $root ('status-{0}.tmp' -f $PID)
        try {
            $json = $status | ConvertTo-Json -Compress -Depth 7
            $utf8 = New-Object System.Text.UTF8Encoding($false)
            [System.IO.File]::WriteAllText($temporary, $json, $utf8)
            if (Test-Path -LiteralPath $statusFile) {
                try {
                    # PowerShell may coerce a null backup argument into an invalid path.
                    # Use an explicit same-volume backup to preserve atomic replacement.
                    $backup = Join-Path $root 'status.backup'
                    for ($attempt = 0; ; $attempt++) {
                        try {
                            [System.IO.File]::Replace($temporary, $statusFile, $backup)
                            break
                        } catch {
                            $code = $_.Exception.GetBaseException().HResult -band 0xFFFF
                            if ($attempt -ge 4 -or $code -notin @(32,33)) { throw }
                            Start-Sleep -Milliseconds (35 * ($attempt + 1))
                        }
                    }
                } catch {
                    $replaceError = $_.Exception.Message
                    # Avoid leaving status.json stale if atomic replacement is unsupported.
                    [System.IO.File]::Copy($temporary, $statusFile, $true)
                    [System.IO.File]::Delete($temporary)
                    if (-not $script:atomicReplaceWarned) {
                        $script:atomicReplaceWarned = $true
                        Write-Event 'warning' '' ('Atomic heartbeat update unavailable. Overwrite fallback active: {0}' -f $replaceError)
                    }
                }
            } else {
                [System.IO.File]::Move($temporary, $statusFile)
            }
            $script:lastSuccessfulStatus = Get-Date
        } catch {
            $message = ('{0} | STATUS_WRITE_ERROR | PID {1} | {2}' -f (Get-Date).ToString('o'), $PID, $_.Exception.Message)
            try {
                Add-Content -LiteralPath (Join-Path $root 'status-write-errors.log') -Value $message -Encoding UTF8
            } catch { }
        }
    }
    # Query Windows counters off the heartbeat loop so WMI stalls cannot pause cleanup.
    $metricsScript = {
        $sample = @{}
        try {
            $os = Get-CimInstance Win32_OperatingSystem -Property TotalVisibleMemorySize,FreePhysicalMemory -ErrorAction Stop
            $sample.ramTotalMb = [math]::Round($os.TotalVisibleMemorySize / 1024)
            $sample.ramAvailableMb = [math]::Round($os.FreePhysicalMemory / 1024)
        } catch { }
        try {
            $cpu = Get-CimInstance Win32_PerfFormattedData_Counters_ProcessorInformation -Filter "Name='_Total'" -ErrorAction Stop
            if ($null -ne $cpu.PercentProcessorTime) {
                $sample.cpuPercent = [math]::Min(100, [double]$cpu.PercentProcessorTime)
            }
            if ($cpu.ProcessorFrequency -gt 0) {
                $sample.cpuMHz = [double]$cpu.ProcessorFrequency
            }
        } catch { }
        try {
            $disks = Get-CimInstance Win32_PerfFormattedData_PerfDisk_PhysicalDisk -Filter "Name<>'_Total'" -ErrorAction Stop
            $busiest = ($disks | Measure-Object -Property PercentDiskTime -Maximum).Maximum
            if ($null -ne $busiest) { $sample.diskActivePercent = [math]::Min(100, $busiest) }
        } catch { }
        try {
            $interfaces = Get-CimInstance Win32_PerfFormattedData_Tcpip_NetworkInterface -ErrorAction Stop
            $busiest = ($interfaces | Measure-Object -Property BytesTotalPersec -Maximum).Maximum
            if ($null -ne $busiest) { $sample.networkBytesPerSecond = $busiest }
        } catch { }
        try {
            $engines = Get-CimInstance Win32_PerfFormattedData_GPUPerformanceCounters_GPUEngine -ErrorAction Stop
            $loads = $engines | Group-Object -Property { $_.Name -replace '^pid_\d+_', '' } |
                ForEach-Object { ($_.Group | Measure-Object -Property UtilizationPercentage -Sum).Sum }
            $busiest = ($loads | Measure-Object -Maximum).Maximum
            if ($null -ne $busiest) { $sample.gpuPercent = [math]::Min(100, $busiest) }
        } catch { }
        $sample
    }
    try { $metricsWorker = [PowerShell]::Create() } catch { }
    $metricsInvocation = $null
    $performance = @{}
    $sampleAt = [DateTime]::MinValue
    $nextSample = [DateTime]::MinValue
    $iconDirectory = Join-Path $root 'app-icons'
    $iconCache = @{}
    $iconsAvailable = $false
    try {
        Add-Type -AssemblyName System.Drawing
        New-Item -ItemType Directory -Path $iconDirectory -Force | Out-Null
        $iconsAvailable = $true
    } catch { }

    function Save-AppIcon($process) {
        if (-not $iconsAvailable -or -not $process.Path) { return }
        $name = $process.ProcessName.ToLowerInvariant()
        if ($iconCache[$name] -eq $process.Path) { return }
        $iconCache[$name] = $process.Path
        $icon = $null
        $bitmap = $null
        try {
            $icon = [System.Drawing.Icon]::ExtractAssociatedIcon($process.Path)
            if ($null -eq $icon) { return }
            $bitmap = $icon.ToBitmap()
            $target = Join-Path $iconDirectory ($name + '.png')
            $temp = $target + '.tmp'
            $bitmap.Save($temp, [System.Drawing.Imaging.ImageFormat]::Png)
            if ([IO.File]::Exists($target)) {
                [IO.File]::Replace($temp, $target, ($target + '.bak'))
                [IO.File]::Delete($target + '.bak')
            } else {
                [IO.File]::Move($temp, $target)
            }
        } catch { }
        finally {
            if ($null -ne $bitmap) { $bitmap.Dispose() }
            if ($null -ne $icon) { $icon.Dispose() }
        }
    }

    $config = $null
    $tracked = @{}
    $startedAt = (Get-Date).ToString('o')
    Write-Event 'info' '' 'ClosePilot monitor started.'
    while ($true) {
        if (Test-Path -LiteralPath $stopFile) {
            Remove-Item -LiteralPath $stopFile -Force -ErrorAction SilentlyContinue
            Write-Event 'info' '' 'ClosePilot monitor stopped by user.'
            break
        }
        try {
            if (Test-Path -LiteralPath $configFile) {
                $config = Get-Content -LiteralPath $configFile -Raw -Encoding UTF8 | ConvertFrom-Json
            }
        } catch { Write-Event 'warning' '' 'Invalid configuration; retaining previously loaded settings.' }
        if ($null -eq $config) { Start-Sleep -Seconds 2; continue }
        $poll = [int]$config.pollSeconds
        if ($poll -lt 2 -or $poll -gt 15) { $poll = 3 }
        $grace = [int]$config.graceSeconds
        if ($grace -lt 5 -or $grace -gt 120) { $grace = 20 }
        $enabled = ($config.monitorEnabled -eq $true)
        $appStatuses = @{}
        $visiblePids = [ClosePilotWindows]::VisibleAppProcessIds()
        $openApps = @{}
        foreach ($visiblePid in $visiblePids) {
            try {
                $process = Get-Process -Id $visiblePid -ErrorAction Stop
                $name = $process.ProcessName
                if ($name -in $blockedNames -or $openApps.ContainsKey($name)) { continue }
                $label = $process.Description
                if ([string]::IsNullOrWhiteSpace($label)) { $label = $name }
                $openApps[$name] = $label
                Save-AppIcon $process
            } catch { }
        }
        foreach ($app in @($config.apps)) {
            if ($null -eq $app) { continue }
            $id = [string]$app.id
            if ([string]::IsNullOrWhiteSpace($id)) { continue }
            $names = @($app.names | Where-Object { $_ -is [string] -and $_.ToLowerInvariant() -notin $blockedNames -and $_ -match '^[^\\/:*?"<>|,\x00-\x1F]+$' })
            if ($names.Count -eq 0) { continue }
            $running = @(Get-Process -Name $names -ErrorAction SilentlyContinue)
            $running = @($running | Where-Object { $null -ne $_ -and $_.Id -ne $PID })
            $ramMb = 0.0
            foreach ($p in $running) {
                try { $ramMb += ($p.WorkingSet64 / 1MB) } catch { }
            }
            $hasWindow = $false
            foreach ($p in $running) {
                if ($visiblePids.Contains([int]$p.Id)) { $hasWindow = $true; break }
            }
            if (-not $tracked.ContainsKey($id)) {
                $tracked[$id] = @{ armed = $false; closedAt = $null }
            }
            $state = $tracked[$id]
            $secondsRemaining = $null
            $mode = 'not-running'
            if ($running.Count -gt 0) {
                $mode = 'background-only'
                if ($hasWindow) { $mode = 'window-open' }
            }
            if (-not $enabled -or $app.enabled -ne $true) {
                $state.armed = $false
                $state.closedAt = $null
                if ($running.Count -gt 0) { $mode = 'paused' }
            } elseif ($running.Count -eq 0) {
                $state.armed = $false
                $state.closedAt = $null
            } elseif ($hasWindow) {
                $state.armed = $true
                $state.closedAt = $null
            } elseif ($state.armed) {
                if ($null -eq $state.closedAt) { $state.closedAt = Get-Date }
                $elapsed = ((Get-Date) - $state.closedAt).TotalSeconds
                $secondsRemaining = [math]::Max(0, [math]::Ceiling($grace - $elapsed))
                $mode = 'closing'
                if ($elapsed -ge $grace) {
                    # Re-observe windows before terminating: avoids killing an app reopened during grace.
                    $againVisible = [ClosePilotWindows]::VisibleAppProcessIds()
                    $latest = @(Get-Process -Name $names -ErrorAction SilentlyContinue)
                    $reopened = $false
                    foreach ($p in $latest) {
                        if ($againVisible.Contains([int]$p.Id)) { $reopened = $true; break }
                    }
                    if ($reopened) {
                        $state.armed = $true
                        $state.closedAt = $null
                        $mode = 'window-open'
                        $secondsRemaining = $null
                    } else {
                        $autoStopped = 0
                        $autoObservedMb = 0.0
                        foreach ($p in $latest) {
                            try {
                                $targetPid = [int]$p.Id
                                $observed = [math]::Round(($p.WorkingSet64 / 1MB), 1)
                                Stop-Process -Id $targetPid -Force -ErrorAction Stop
                                $autoStopped++
                                $autoObservedMb += $observed
                                Write-Event 'stopped' $id ('Stopped {0} (PID {1}) after its last window closed.' -f $app.label, $targetPid) $targetPid $observed
                            } catch {
                                # A naturally exited process is not an error.
                                $stillExists = Get-Process -Id $targetPid -ErrorAction SilentlyContinue
                                if ($null -ne $stillExists) {
                                    Write-Event 'error' $id ('Could not stop PID {0}: {1}' -f $targetPid, $_.Exception.Message) $targetPid
                                }
                            }
                        }
                        if ($autoStopped -gt 0) {
                            Write-Event 'auto-cleanup' $id (
                                'Automatic cleanup for {0}: {1} leftover processes closed.' -f $app.label, $autoStopped
                            ) 0 $autoObservedMb
                        }
                        $state.armed = $false
                        $state.closedAt = $null
                        $secondsRemaining = $null
                        $mode = 'cleaned'
                    }
                }
            }
            $appStatuses[$id] = [ordered]@{
                count = $running.Count
                memoryMb = [math]::Round($ramMb, 1)
                hasWindow = $hasWindow
                mode = $mode
                remainingSeconds = $secondsRemaining
            }
        }
        $now = [DateTime]::UtcNow
        if ($null -ne $metricsInvocation -and $metricsInvocation.IsCompleted) {
            try {
                $samples = $metricsWorker.EndInvoke($metricsInvocation)
                if ($samples.Count -gt 0) {
                    $performance = $samples[0].PSObject.BaseObject
                    $sampleAt = $now
                }
            } catch {
                if (-not $script:metricsErrorLogged) {
                    $script:metricsErrorLogged = $true
                    Write-Event 'warning' '' ('Unable to read Windows performance counters: {0}' -f $_.Exception.Message)
                }
            }
            $metricsInvocation = $null
            $metricsWorker.Commands.Clear()
            $nextSample = $now.AddSeconds(4)
        }
        if ($null -ne $metricsWorker -and $null -eq $metricsInvocation -and $now -ge $nextSample) {
            try {
                [void]$metricsWorker.AddScript($metricsScript.ToString())
                $metricsInvocation = $metricsWorker.BeginInvoke()
            } catch {
                $metricsWorker.Commands.Clear()
                $nextSample = $now.AddSeconds(10)
            }
        }
        if (($now - $sampleAt).TotalSeconds -gt 20) { $performance = @{} }
        $status = [ordered]@{
            agentPid = $PID
            version = '1.2.3'
            startedAt = $startedAt
            updatedAt = (Get-Date).ToString('o')
            monitorEnabled = $enabled
            apps = $appStatuses
            openApps = $openApps
            performance = $performance
        }
        Write-Status $status
        $wakeAt = [DateTime]::UtcNow.AddSeconds($poll)
        while ([DateTime]::UtcNow -lt $wakeAt -and -not [IO.File]::Exists($stopFile)) {
            Start-Sleep -Milliseconds 100
        }
    }
} catch {
    try {
        $msg = ('{0} | FATAL | {1}' -f (Get-Date).ToString('o'), $_.Exception.Message)
        Add-Content -LiteralPath (Join-Path $root 'agent-fatal.log') -Value $msg -Encoding UTF8
    } catch { }
} finally {
    if ($null -ne $metricsWorker) {
        try { $metricsWorker.BeginStop($null, $null) | Out-Null } catch { }
    }
    if ($owned -and $null -ne $mutex) { $mutex.ReleaseMutex(); $mutex.Dispose() }
}
