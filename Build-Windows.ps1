# Run on Windows 10/11 after Flutter + Visual Studio C++ desktop workload are installed.
# Creates native Windows runner, builds the release and packages the *whole* runnable bundle.
$ErrorActionPreference = 'Stop'
Set-Location -LiteralPath $PSScriptRoot
if (-not (Get-Command flutter -ErrorAction SilentlyContinue)) {
    throw 'Flutter CLI not found. Install Flutter SDK, add flutter\bin to PATH, then rerun.'
}
Write-Host '[1/5] Generating Windows desktop runner...' -ForegroundColor Cyan
flutter create --platforms=windows --project-name close_pilot .
if ($LASTEXITCODE -ne 0) { throw 'flutter create failed.' }
# The generated Flutter counter-app test may reference MyApp instead of ClosePilot.
$sampleTest = Join-Path $PSScriptRoot 'test\widget_test.dart'
if (Test-Path -LiteralPath $sampleTest) {
    $sampleContent = Get-Content -LiteralPath $sampleTest -Raw
    if ($sampleContent -match 'MyApp|Counter increments smoke test') {
        Remove-Item -LiteralPath $sampleTest -Force
    }
}
$cmakePath = Join-Path $PSScriptRoot 'windows\CMakeLists.txt'
$cmake = Get-Content -LiteralPath $cmakePath -Raw
$cmake = [regex]::Replace($cmake, 'set\(BINARY_NAME\s+"[^"]+"\)', 'set(BINARY_NAME "ClosePilot")')
Set-Content -LiteralPath $cmakePath -Value $cmake -Encoding UTF8
$runnerPath = Join-Path $PSScriptRoot 'windows\runner\main.cpp'
if (Test-Path -LiteralPath $runnerPath) {
    $runner = Get-Content -LiteralPath $runnerPath -Raw
    $marker = '  // Join the existing ClosePilot session.'
    if (-not $runner.Contains($marker)) {
        $entry = 'int APIENTRY wWinMain\([^)]*\)\s*\{'
        $match = [regex]::Match($runner, $entry)
        if (-not $match.Success) { throw 'Windows runner entry point not found.' }
        $guard = @'
  // Join the existing ClosePilot session.
  HANDLE instance = ::CreateMutexW(nullptr, FALSE, L"Local\\ClosePilot_Desktop_Instance");
  if (instance == nullptr) {
    return EXIT_FAILURE;
  }
  if (::GetLastError() == ERROR_ALREADY_EXISTS) {
    for (int attempt = 0; attempt < 40; ++attempt) {
      HWND existing = ::FindWindowW(L"FLUTTER_RUNNER_WIN32_WINDOW", L"ClosePilot | Basel Edition");
      if (existing == nullptr) {
        existing = ::FindWindowW(L"FLUTTER_RUNNER_WIN32_WINDOW", L"ClosePilot");
      }
      if (existing != nullptr) {
        ::ShowWindowAsync(existing, ::IsIconic(existing) ? SW_RESTORE : SW_SHOW);
        ::SetForegroundWindow(existing);
        break;
      }
      ::Sleep(50);
    }
    ::CloseHandle(instance);
    return EXIT_SUCCESS;
  }
'@
        $runner = $runner.Insert($match.Index + $match.Length, [Environment]::NewLine + $guard + [Environment]::NewLine)
    }
    $runner = $runner -replace 'L"close_pilot"', 'L"ClosePilot"'
    Set-Content -LiteralPath $runnerPath -Value $runner -Encoding UTF8
}
$icon = Join-Path $PSScriptRoot 'assets\closepilot.ico'
$runnerIcon = Join-Path $PSScriptRoot 'windows\runner\resources\app_icon.ico'
if ((Test-Path -LiteralPath $icon) -and (Test-Path -LiteralPath $runnerIcon)) {
    Copy-Item -LiteralPath $icon -Destination $runnerIcon -Force
}
Write-Host '[2/5] Installing packages...' -ForegroundColor Cyan
flutter pub get
if ($LASTEXITCODE -ne 0) { throw 'flutter pub get failed.' }
Write-Host '[3/5] Running tests...' -ForegroundColor Cyan
flutter test
if ($LASTEXITCODE -ne 0) { throw 'flutter test failed.' }
Write-Host '[4/5] Building release executable...' -ForegroundColor Cyan
flutter build windows --release
if ($LASTEXITCODE -ne 0) { throw 'flutter build windows failed.' }
$exe = Get-ChildItem -Path (Join-Path $PSScriptRoot 'build\windows') -Filter 'ClosePilot.exe' -File -Recurse |
    Where-Object { $_.DirectoryName -match 'Release$' } | Select-Object -First 1
if (-not $exe) { throw 'Built ClosePilot.exe not found in the Flutter release directory.' }
Write-Host '[5/5] Packing complete runtime...' -ForegroundColor Cyan
$dist = Join-Path $PSScriptRoot 'ClosePilot-Windows-Release.zip'
if (Test-Path -LiteralPath $dist) { Remove-Item -LiteralPath $dist -Force }
Compress-Archive -Path (Join-Path $exe.DirectoryName '*') -DestinationPath $dist -CompressionLevel Optimal
Write-Host ''
Write-Host "DONE: $dist" -ForegroundColor Green
Write-Host 'Extract the zip completely. Run ClosePilot.exe beside its DLL files and data folder.'
