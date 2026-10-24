# Collects uztranslit.exe, the Qt libraries and plugins (windeployqt) and the MSVC runtime DLLs into one folder,
# which the Inno Setup script (packaging/installer/uztranslit.iss) turns into the installer.
#   pwsh platforms/qt-desktop/packaging/windows/deploy.ps1 [-Build <build dir>] [-Out <folder>]
# Run it from a Visual Studio developer shell (VCToolsRedistDir must be set) with Qt's bin folder on PATH.
param(
    [string]$Build = (Join-Path $PSScriptRoot '..\..\build'),
    [string]$Out = ''
)
$ErrorActionPreference = 'Stop'
$Build = (Resolve-Path $Build).Path
if (-not $Out) { $Out = Join-Path $Build 'deploy' }
if (Test-Path $Out) { Remove-Item -Recurse -Force $Out }
New-Item -ItemType Directory -Force $Out | Out-Null

Copy-Item (Join-Path $Build 'uztranslit.exe') $Out
$windeployqt = Get-Command windeployqt, windeployqt6 -ErrorAction SilentlyContinue | Select-Object -First 1
if (-not $windeployqt) { throw 'windeployqt not found: put Qt''s bin folder on PATH' }
# Qt's own translations: Russian only (Qt ships none for Uzbek; the app's .ts files cover the Qt strings it shows)
& $windeployqt.Source --release --no-compiler-runtime --no-system-d3d-compiler --no-opengl-sw --translations ru `
    (Join-Path $Out 'uztranslit.exe')
if ($LASTEXITCODE -ne 0) { throw "windeployqt failed with exit code $LASTEXITCODE" }

# The MSVC runtime next to the executable (app-local), so that no separate VC++ redistributable is needed.
if (-not $env:VCToolsRedistDir) { throw 'VCToolsRedistDir is not set: run from a Visual Studio developer shell' }
$crt = Get-ChildItem (Join-Path $env:VCToolsRedistDir 'x64') -Directory -Filter 'Microsoft.VC*.CRT' | Select-Object -First 1
if (-not $crt) { throw "no Microsoft.VC*.CRT folder under $env:VCToolsRedistDir\x64" }
Copy-Item (Join-Path $crt.FullName '*.dll') $Out
Copy-Item (Join-Path $PSScriptRoot '..\..\..\..\LICENSE') (Join-Path $Out 'LICENSE.txt')
Write-Host "deployed to $Out"
