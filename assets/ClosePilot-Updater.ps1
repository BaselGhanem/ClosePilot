# ClosePilot desktop updater. Runs outside the installed application directory.
# The UI asks for consent before this script is launched.
$ErrorActionPreference = 'Stop'
$root = Join-Path $env:LOCALAPPDATA 'ClosePilot'
$requestFile = Join-Path $root 'update-request.json'
$logFile = Join-Path $root 'update.log'
$updateMutex = $null
$ownsMutex = $false
function Write-UpdateLog([string]$message) {
    try {
        Add-Content -LiteralPath $logFile -Encoding UTF8 -Value (
            '{0} | {1}' -f (Get-Date).ToString('o'), $message
        )
    } catch { }
}
try {
    $updateMutex = [Threading.Mutex]::new($true, 'Local\ClosePilot_Updater_v1', [ref]$ownsMutex)
    if (-not $ownsMutex) { exit 0 }
    if (-not (Test-Path -LiteralPath $requestFile)) {
        throw 'No update request found.'
    }
    $req = Get-Content -LiteralPath $requestFile -Raw -Encoding UTF8 | ConvertFrom-Json
    if ([string]$req.version -notmatch '^\d+\.\d+\.\d+$') {
        throw 'Unsupported release version.'
    }
    $pidToWait = [int]$req.pid
    $installDir = [IO.Path]::GetFullPath([string]$req.installDir).TrimEnd('\')
    $archive = [IO.Path]::GetFullPath([string]$req.archive)
    $expectedRoot = [IO.Path]::GetFullPath((Join-Path $root 'updates')) + '\'
    if (-not $archive.StartsWith($expectedRoot, [StringComparison]::OrdinalIgnoreCase)) {
        throw 'Update archive path is outside ClosePilot updates folder.'
    }
    if (-not (Test-Path -LiteralPath $archive -PathType Leaf)) { throw 'Archive is missing.' }
    if (-not (Test-Path -LiteralPath (Join-Path $installDir 'ClosePilot.exe'))) {
        throw 'Target directory is not a ClosePilot installation.'
    }
    $parent = Split-Path -Path $installDir -Parent
    $base = Split-Path -Path $installDir -Leaf
    if ([string]::IsNullOrWhiteSpace($base) -or $installDir -eq [IO.Path]::GetPathRoot($installDir)) {
        throw 'Unsafe installation directory.'
    }
    $id = [guid]::NewGuid().ToString('N')
    $unpack = Join-Path $root ('updates\unpacked-' + $id)
    $prepared = Join-Path $parent ('.ClosePilot-prepared-' + $id)
    $backupName = $base + '.ClosePilotBackup-' + (Get-Date -Format 'yyyyMMdd-HHmmss')
    $backup = Join-Path $parent $backupName
    Write-UpdateLog ('Preparing update v{0} for {1} from PID {2}' -f $req.version,$installDir,$pidToWait)

    # Validate ZIP layout before touching the installed application.
    Add-Type -AssemblyName System.IO.Compression
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $zip = [IO.Compression.ZipFile]::OpenRead($archive)
    try {
        $names = @($zip.Entries | ForEach-Object { $_.FullName.Replace('\','/') })
        foreach ($entry in $names) {
            if ($entry.StartsWith('/') -or $entry.Contains('..') -or $entry.Contains(':')) {
                throw ('Unsafe archive entry: ' + $entry)
            }
        }
        foreach ($required in @('ClosePilot.exe','flutter_windows.dll','data/icudtl.dat')) {
            if ($names -cnotcontains $required) {
                throw ('Release archive lacks required file: ' + $required)
            }
        }
    } finally { $zip.Dispose() }

    New-Item -ItemType Directory -Path $unpack -Force | Out-Null
    Expand-Archive -LiteralPath $archive -DestinationPath $unpack -Force
    if (-not (Test-Path -LiteralPath (Join-Path $unpack 'ClosePilot.exe'))) {
        throw 'Extracted ClosePilot.exe missing.'
    }
    New-Item -ItemType Directory -Path $prepared -Force | Out-Null
    Get-ChildItem -LiteralPath $unpack -Force |
        Copy-Item -Destination $prepared -Recurse -Force -ErrorAction Stop
    if (-not (Test-Path -LiteralPath (Join-Path $prepared 'data\flutter_assets'))) {
        throw 'Staged Flutter assets are incomplete.'
    }

    # The GUI closes itself after the updater starts. Never force terminate user apps.
    $deadline = (Get-Date).AddSeconds(60)
    while ((Get-Process -Id $pidToWait -ErrorAction SilentlyContinue) -and
           (Get-Date) -lt $deadline) {
        Start-Sleep -Milliseconds 400
    }
    if (Get-Process -Id $pidToWait -ErrorAction SilentlyContinue) {
        throw 'Old ClosePilot process is still running. Update was not applied.'
    }
    $movedOld = $false
    $movedNew = $false
    try {
        Rename-Item -LiteralPath $installDir -NewName $backupName -ErrorAction Stop
        $movedOld = $true
        Rename-Item -LiteralPath $prepared -NewName $base -ErrorAction Stop
        $movedNew = $true
        Write-UpdateLog ('Installed v{0}. Previous version retained in {1}' -f $req.version,$backup)
    } catch {
        Write-UpdateLog ('Swap failed: {0}. Attempting rollback.' -f $_.Exception.Message)
        if ($movedOld -and -not $movedNew) {
            if (Test-Path -LiteralPath $installDir) {
                Remove-Item -LiteralPath $installDir -Recurse -Force -ErrorAction SilentlyContinue
            }
            Rename-Item -LiteralPath $backup -NewName $base -ErrorAction Stop
        }
        throw
    }
    Remove-Item -LiteralPath $requestFile -Force -ErrorAction SilentlyContinue
    $newExe = Join-Path $installDir 'ClosePilot.exe'
    try {
        Start-Process -FilePath $newExe -WorkingDirectory $installDir -ErrorAction Stop
        Write-UpdateLog ('Restarted ClosePilot v{0}' -f $req.version)
    } catch {
        Write-UpdateLog ('Updated executable failed to launch. Rolling back: {0}' -f $_.Exception.Message)
        $failedPath = Join-Path $parent ('.ClosePilot-failed-' + $id)
        Rename-Item -LiteralPath $installDir -NewName (Split-Path $failedPath -Leaf) -ErrorAction Stop
        Rename-Item -LiteralPath $backup -NewName $base -ErrorAction Stop
        try {
            Start-Process -FilePath (Join-Path $installDir 'ClosePilot.exe') -WorkingDirectory $installDir -ErrorAction Stop
            Write-UpdateLog 'Previous version restored and restarted.'
        } catch {
            Write-UpdateLog ('Restore launch failed: {0}' -f $_.Exception.Message)
        }
        throw 'New version failed to start; previous version was restored.'
    }
} catch {
    Write-UpdateLog ('UPDATE FAILED: {0}' -f $_.Exception.Message)
} finally {
    if ($ownsMutex -and $null -ne $updateMutex) {
        $updateMutex.ReleaseMutex()
        $updateMutex.Dispose()
    }
    if ($null -ne $unpack -and (Test-Path -LiteralPath $unpack)) {
        Remove-Item -LiteralPath $unpack -Force -Recurse -ErrorAction SilentlyContinue
    }
}
