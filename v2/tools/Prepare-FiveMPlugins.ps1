[CmdletBinding()]
param(
    [string]$PluginsPath = "",
    [switch]$DryRun
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

function Get-ShortcutFiveMAppRoots {
    $roots = New-Object System.Collections.Generic.List[string]
    $shortcutRoots = @(
        [Environment]::GetFolderPath("Desktop"),
        [Environment]::GetFolderPath("CommonDesktopDirectory"),
        [Environment]::GetFolderPath("StartMenu"),
        [Environment]::GetFolderPath("CommonStartMenu")
    ) | Where-Object { $_ -and (Test-Path -LiteralPath $_) } | Select-Object -Unique

    try { $shell = New-Object -ComObject WScript.Shell } catch { return @() }

    foreach ($root in $shortcutRoots) {
        Get-ChildItem -LiteralPath $root -Filter "*.lnk" -File -Recurse -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -match 'FiveM' } |
            ForEach-Object {
                try {
                    $target = $shell.CreateShortcut($_.FullName).TargetPath
                    if ($target -and (Test-Path -LiteralPath $target)) {
                        $candidate = Join-Path (Split-Path -Parent $target) "FiveM.app"
                        if (Test-Path -LiteralPath $candidate) { [void]$roots.Add([IO.Path]::GetFullPath($candidate)) }
                    }
                } catch {}
            }
    }

    return @($roots | Select-Object -Unique)
}

function Resolve-PluginsPath([string]$Requested) {
    if ($Requested) {
        return [IO.Path]::GetFullPath([Environment]::ExpandEnvironmentVariables($Requested))
    }

    $candidates = New-Object System.Collections.Generic.List[string]
    if ($env:LOCALAPPDATA) {
        [void]$candidates.Add((Join-Path $env:LOCALAPPDATA "FiveM\FiveM.app"))
    }
    foreach ($root in (Get-ShortcutFiveMAppRoots)) { [void]$candidates.Add($root) }

    foreach ($appRoot in @($candidates | Select-Object -Unique)) {
        if ((Test-Path -LiteralPath $appRoot) -and
            ((Test-Path -LiteralPath (Join-Path $appRoot "CitizenFX.ini")) -or
             (Test-Path -LiteralPath (Join-Path (Split-Path -Parent $appRoot) "FiveM.exe")))) {
            return Join-Path $appRoot "plugins"
        }
    }

    throw "FiveM.app could not be detected. Run with -PluginsPath '<path>\FiveM.app\plugins'."
}

function Get-UniqueSiblingPath([string]$BasePath) {
    if (-not (Test-Path -LiteralPath $BasePath)) { return $BasePath }
    for ($i = 2; $i -lt 1000; $i++) {
        $candidate = "$BasePath-$i"
        if (-not (Test-Path -LiteralPath $candidate)) { return $candidate }
    }
    throw "Could not allocate a unique backup folder next to $BasePath"
}

$resolved = Resolve-PluginsPath $PluginsPath
$appRoot = Split-Path -Parent $resolved

if (-not (Test-Path -LiteralPath $appRoot)) {
    throw "FiveM application folder does not exist: $appRoot"
}

$statePath = Join-Path $resolved "SecretEMKO\install-state.json"
$owned = $false
$existingOriginalBackup = $null

if (Test-Path -LiteralPath $statePath) {
    try {
        $existingState = Get-Content -LiteralPath $statePath -Raw | ConvertFrom-Json
        $owned = $existingState.product -eq "SECRET EMKO Neural Graphics"
        if ($owned -and $existingState.PSObject.Properties.Name -contains "original_plugins_backup_path") {
            $existingOriginalBackup = [string]$existingState.original_plugins_backup_path
        }
    } catch {}
}

$hadPlugins = Test-Path -LiteralPath $resolved
$nonEmpty = $false
if ($hadPlugins) {
    $nonEmpty = $null -ne (Get-ChildItem -LiteralPath $resolved -Force -ErrorAction SilentlyContinue | Select-Object -First 1)
}

$backupPath = $existingOriginalBackup
$isolated = $false
$created = $false

if ($hadPlugins -and $nonEmpty -and -not $owned) {
    $stamp = Get-Date -Format "yyyyMMdd-HHmmss"
    $backupPath = Get-UniqueSiblingPath (Join-Path $appRoot ("plugins.pre-SecretEMKO-" + $stamp))
    if (-not $DryRun) {
        Move-Item -LiteralPath $resolved -Destination $backupPath
        New-Item -ItemType Directory -Path $resolved -Force | Out-Null
    }
    $isolated = $true
    $created = $true
}
elseif (-not $hadPlugins) {
    if (-not $DryRun) { New-Item -ItemType Directory -Path $resolved -Force | Out-Null }
    $created = $true
}

if (-not $DryRun) {
    $probe = Join-Path $resolved (".secretemko-write-test-" + [guid]::NewGuid().ToString("N"))
    try {
        [IO.File]::WriteAllText($probe, "ok")
    }
    finally {
        Remove-Item -LiteralPath $probe -Force -ErrorAction SilentlyContinue
    }
}

[pscustomobject]@{
    plugins_path = $resolved
    fivem_app_root = $appRoot
    existing_secret_emko = $owned
    original_plugins_backup_path = $backupPath
    isolated_existing_plugins = $isolated
    created_plugins_directory = $created
} | ConvertTo-Json -Compress
