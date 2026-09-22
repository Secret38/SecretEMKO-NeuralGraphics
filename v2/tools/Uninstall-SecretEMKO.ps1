[CmdletBinding()]
param(
    [string]$PluginsPath = "$env:LOCALAPPDATA\FiveM\FiveM.app\plugins"
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$PluginsPath = [IO.Path]::GetFullPath([Environment]::ExpandEnvironmentVariables($PluginsPath))
$StateDir = Join-Path $PluginsPath "SecretEMKO"
$StateFile = Join-Path $StateDir "install-state.json"
if (-not (Test-Path -LiteralPath $StateFile)) { throw "SECRET EMKO install-state.json not found: $StateFile" }

$state = Get-Content -LiteralPath $StateFile -Raw | ConvertFrom-Json
$original = $null
if ($state.PSObject.Properties.Name -contains "original_plugins_backup_path") { $original = [string]$state.original_plugins_backup_path }

if ($original -and (Test-Path -LiteralPath $original)) {
    $appRoot = Split-Path -Parent $PluginsPath
    $preservedCurrent = Join-Path $appRoot ("plugins.SecretEMKO-uninstalled-" + (Get-Date -Format "yyyyMMdd-HHmmss"))
    if (Test-Path -LiteralPath $PluginsPath) { Move-Item -LiteralPath $PluginsPath -Destination $preservedCurrent -Force }
    Move-Item -LiteralPath $original -Destination $PluginsPath -Force

    Write-Host "Original pre-SECRET-EMKO plugins folder restored." -ForegroundColor Green
    Write-Host "Restored: $PluginsPath" -ForegroundColor Gray
    Write-Host "The removed SECRET EMKO setup was preserved instead of deleted:" -ForegroundColor Gray
    Write-Host "  $preservedCurrent" -ForegroundColor Gray
    exit 0
}

foreach ($name in @($state.managed_files)) {
    $path = Join-Path $PluginsPath $name
    if (Test-Path -LiteralPath $path) { Remove-Item -LiteralPath $path -Force -Recurse }
}

$backup = $null
if ($state.PSObject.Properties.Name -contains "backup_path") { $backup = [string]$state.backup_path }
if ($backup -and (Test-Path -LiteralPath $backup)) {
    Get-ChildItem -LiteralPath $backup -File -ErrorAction SilentlyContinue | ForEach-Object {
        Copy-Item -LiteralPath $_.FullName -Destination (Join-Path $PluginsPath $_.Name) -Force
    }
}

Write-Host "SECRET EMKO managed files removed." -ForegroundColor Green
Write-Host "No original plugins folder existed before installation, so user-added files were left untouched." -ForegroundColor Gray
