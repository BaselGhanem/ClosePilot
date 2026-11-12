param(
    [Parameter(Mandatory=$true)]
    [ValidateSet('enable-startup','disable-startup','migrate-legacy')]
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
