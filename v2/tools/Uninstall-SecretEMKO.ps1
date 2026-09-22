[CmdletBinding()]
param(
    [string]$PluginsPath = "$env:LOCALAPPDATA\FiveM\FiveM.app\plugins"
)

$ErrorActionPreference = "Stop"
$StateDir = Join-Path $PluginsPath "SecretEMKO"
$StateFile = Join-Path $StateDir "install-state.json"

if (-not (Test-Path -LiteralPath $StateFile)) {
    throw "SECRET EMKO install-state.json not found: $StateFile"
}

$state = Get-Content -LiteralPath $StateFile -Raw | ConvertFrom-Json
$backup = $state.backup_path

foreach ($name in $state.managed_files) {
    $path = Join-Path $PluginsPath $name
    if (Test-Path -LiteralPath $path) { Remove-Item -LiteralPath $path -Force }
}

if ($backup -and (Test-Path -LiteralPath $backup)) {
    Get-ChildItem -LiteralPath $backup -File | ForEach-Object {
        Copy-Item -LiteralPath $_.FullName -Destination (Join-Path $PluginsPath $_.Name) -Force
    }
}

if ($state.reshade_ini_backed_up -and (Test-Path (Join-Path $backup "ReShade.ini"))) {
    Copy-Item -LiteralPath (Join-Path $backup "ReShade.ini") -Destination (Join-Path $PluginsPath "ReShade.ini") -Force
}

Write-Host "SECRET EMKO removed. Existing files backed up by the installer were restored." -ForegroundColor Green
Write-Host "ReShade dxgi.dll was not removed." -ForegroundColor Gray
