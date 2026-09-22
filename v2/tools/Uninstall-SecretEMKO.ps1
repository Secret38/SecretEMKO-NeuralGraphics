[CmdletBinding()]
param(
    [string]$PluginsPath = "",
    [string]$FiveMPath = "",
    [switch]$NonInteractive
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$Product = "SECRET EMKO Neural Graphics"
$GlobalStateRoot = Join-Path $env:LOCALAPPDATA "SecretEMKO\state"
$Stamp = Get-Date -Format "yyyyMMdd-HHmmss"

function Warn([string]$Text) {
    Write-Host "   [!]  $Text" -ForegroundColor Yellow
}

function Ok([string]$Text) {
    Write-Host "   [OK] $Text" -ForegroundColor Green
}

function Get-PathId([string]$Path) {
    $normalized = [IO.Path]::GetFullPath($Path).TrimEnd('\').ToLowerInvariant()
    $bytes = [Text.Encoding]::UTF8.GetBytes($normalized)
    $sha = [Security.Cryptography.SHA256]::Create()
    try { $hash = $sha.ComputeHash($bytes) } finally { $sha.Dispose() }
    return ([BitConverter]::ToString($hash).Replace("-", "").Substring(0, 12))
}

function Test-FiveMAppPath([string]$Path) {
    if (-not $Path) { return $false }
    try { $full = [IO.Path]::GetFullPath($Path) } catch { return $false }
    return (Test-Path -LiteralPath (Join-Path $full "CitizenFX.ini"))
}

function Normalize-FiveMAppPath([string]$Path) {
    if (-not $Path) { return $null }
    $candidate = $Path.Trim('"')
    if (-not (Test-Path -LiteralPath $candidate)) { return $null }

    $item = Get-Item -LiteralPath $candidate
    if (-not $item.PSIsContainer) {
        if ($item.Name -ieq "CitizenFX.ini") { $candidate = $item.DirectoryName }
        elseif ($item.Name -ieq "FiveM.exe") {
            $base = $item.DirectoryName
            if (Test-FiveMAppPath (Join-Path $base "FiveM.app")) { return (Join-Path $base "FiveM.app") }
            $candidate = $base
        }
        else { $candidate = $item.DirectoryName }
    }

    $candidate = [IO.Path]::GetFullPath($candidate)
    if (Test-FiveMAppPath $candidate) { return $candidate }
    $nested = Join-Path $candidate "FiveM.app"
    if (Test-FiveMAppPath $nested) { return [IO.Path]::GetFullPath($nested) }
    if ((Split-Path -Leaf $candidate) -ieq "plugins") {
        $parent = Split-Path -Parent $candidate
        if (Test-FiveMAppPath $parent) { return [IO.Path]::GetFullPath($parent) }
    }
    return $null
}

function Select-FiveMInteractively {
    if ($NonInteractive) { return $null }
    try {
        Add-Type -AssemblyName System.Windows.Forms
        $dialog = New-Object System.Windows.Forms.OpenFileDialog
        $dialog.Title = "Select FiveM.exe (Legacy)"
        $dialog.Filter = "FiveM executable (FiveM.exe)|FiveM.exe|All files (*.*)|*.*"
        $dialog.CheckFileExists = $true
        if ($dialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
            return (Normalize-FiveMAppPath $dialog.FileName)
        }
    } catch {}
    return $null
}

function Resolve-PluginsPath {
    if ($PluginsPath) { return [IO.Path]::GetFullPath($PluginsPath) }

    if ($FiveMPath) {
        $app = Normalize-FiveMAppPath $FiveMPath
        if (-not $app) { throw "Could not resolve FiveM Legacy from -FiveMPath: $FiveMPath" }
        return (Join-Path $app "plugins")
    }

    if (Test-Path -LiteralPath $GlobalStateRoot) {
        $states = @(Get-ChildItem -LiteralPath $GlobalStateRoot -Filter "install-state-*.json" -File -ErrorAction SilentlyContinue |
            Sort-Object LastWriteTimeUtc -Descending)
        foreach ($file in $states) {
            try {
                $state = Get-Content -LiteralPath $file.FullName -Raw | ConvertFrom-Json
                if ($state.product -eq $Product -and $state.plugins_path) {
                    return [string]$state.plugins_path
                }
            } catch {}
        }
    }

    $default = Join-Path $env:LOCALAPPDATA "FiveM\FiveM.app"
    if (Test-FiveMAppPath $default) {
        return (Join-Path $default "plugins")
    }

    $picked = Select-FiveMInteractively
    if ($picked) { return (Join-Path $picked "plugins") }

    throw "Could not determine the SECRET EMKO FiveM plugins path."
}

if (Get-Process -ErrorAction SilentlyContinue | Where-Object { $_.ProcessName -like "FiveM*" -or $_.ProcessName -like "GTAProcess*" }) {
    throw "Close FiveM before uninstalling SECRET EMKO."
}

$PluginsPath = Resolve-PluginsPath
$PluginsPath = [IO.Path]::GetFullPath($PluginsPath)
$pathId = Get-PathId $PluginsPath
$GlobalStateFile = Join-Path $GlobalStateRoot ("install-state-" + $pathId + ".json")
$LocalStateFile = Join-Path $PluginsPath "SecretEMKO\install-state.json"

$state = $null
if (Test-Path -LiteralPath $LocalStateFile) {
    try { $state = Get-Content -LiteralPath $LocalStateFile -Raw | ConvertFrom-Json } catch {}
}
if (-not $state -and (Test-Path -LiteralPath $GlobalStateFile)) {
    try { $state = Get-Content -LiteralPath $GlobalStateFile -Raw | ConvertFrom-Json } catch {}
}
if (-not $state) {
    throw "SECRET EMKO install state was not found for: $PluginsPath"
}
if ($state.product -ne $Product) {
    throw "The discovered state file does not belong to SECRET EMKO."
}

$FiveMApp = if ($state.fivem_app_path) { [string]$state.fivem_app_path } else { Split-Path -Parent $PluginsPath }
$original = if ($state.original_plugins_backup) { [string]$state.original_plugins_backup } else { $null }

Write-Host ""
Write-Host "SECRET EMKO uninstall / restore" -ForegroundColor Cyan
Write-Host "Active plugins: $PluginsPath"

$removedSnapshot = $null
if (Test-Path -LiteralPath $PluginsPath) {
    $removedSnapshot = Join-Path $FiveMApp ("plugins.secret-emko-removed." + $Stamp)
    Move-Item -LiteralPath $PluginsPath -Destination $removedSnapshot
    Ok "Current SECRET EMKO plugins snapshot preserved at: $removedSnapshot"
}

if ($original -and (Test-Path -LiteralPath $original)) {
    Move-Item -LiteralPath $original -Destination $PluginsPath
    Ok "Original pre-SECRET-EMKO plugins folder restored"
}
else {
    Write-Host "No pre-existing plugins folder was recorded. FiveM is left without an active plugins folder." -ForegroundColor Gray
}

if (Test-Path -LiteralPath $GlobalStateFile) {
    Remove-Item -LiteralPath $GlobalStateFile -Force -ErrorAction SilentlyContinue
}

Write-Host ""
Write-Host "SECRET EMKO removed." -ForegroundColor Green
if ($removedSnapshot) {
    Write-Host "The removed SECRET EMKO environment was preserved rather than deleted:" -ForegroundColor Gray
    Write-Host "  $removedSnapshot" -ForegroundColor Gray
}
Write-Host "No server/anti-cheat restrictions were bypassed or modified." -ForegroundColor Gray
