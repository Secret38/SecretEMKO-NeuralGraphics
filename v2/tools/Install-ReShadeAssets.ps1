[CmdletBinding()]
param(
    [string]$PluginsPath = "$env:LOCALAPPDATA\FiveM\FiveM.app\plugins",
    [string]$Root = ""
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest
$ProgressPreference = "SilentlyContinue"

if (-not $Root) {
    $Root = Split-Path -Parent $MyInvocation.MyCommand.Path
    if ((Split-Path -Leaf $Root) -ieq "tools") { $Root = Split-Path -Parent $Root }
}

function Ensure-Folder([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path)) {
        New-Item -ItemType Directory -Path $Path -Force | Out-Null
    }
}

function Copy-DirectoryContents([string]$Source, [string]$Destination) {
    if (-not (Test-Path -LiteralPath $Source)) { return }
    Ensure-Folder $Destination
    Get-ChildItem -LiteralPath $Source -Force | ForEach-Object {
        Copy-Item -LiteralPath $_.FullName -Destination $Destination -Recurse -Force
    }
}

function Convert-ToTargetPath([string]$Base, [string]$Relative) {
    $r = $Relative.Trim()
    $r = $r -replace '^[.]\\', ''
    $r = $r -replace '/', '\\'
    return Join-Path $Base $r
}

function Parse-EffectPackageIndex([string]$Text) {
    $result = @()
    $current = $null
    foreach ($rawLine in ($Text -split "`r?`n")) {
        $line = $rawLine.Trim()
        if ($line.Length -eq 0 -or $line.StartsWith(';')) { continue }
        if ($line -match '^\[(.+)\]$') {
            if ($null -ne $current) { $result += [pscustomobject]$current }
            $current = [ordered]@{ Section = $Matches[1] }
            continue
        }
        if ($null -ne $current -and $line -match '^([^=]+)=(.*)$') {
            $current[$Matches[1].Trim()] = $Matches[2].Trim()
        }
    }
    if ($null -ne $current) { $result += [pscustomobject]$current }
    return $result
}

function Get-ActiveEffectFiles([string[]]$PresetPaths) {
    $files = New-Object System.Collections.Generic.HashSet[string] ([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($preset in $PresetPaths) {
        if (-not (Test-Path -LiteralPath $preset)) { continue }
        $line = Get-Content -LiteralPath $preset | Where-Object { $_ -like 'Techniques=*' } | Select-Object -First 1
        if (-not $line) { continue }
        $value = $line.Substring($line.IndexOf('=') + 1)
        foreach ($entry in ($value -split ',')) {
            if ($entry -match '@(.+\.fx)$') { [void]$files.Add($Matches[1]) }
        }
    }
    return @($files)
}

function Set-IniValue([string]$Path,[string]$Section,[string]$Key,[string]$Value) {
    $lines = New-Object System.Collections.Generic.List[string]
    if (Test-Path -LiteralPath $Path) {
        foreach ($line in Get-Content -LiteralPath $Path) { [void]$lines.Add($line) }
    }

    $sectionLine = "[$Section]"
    $start = -1
    for ($i=0; $i -lt $lines.Count; $i++) {
        if ($lines[$i].Trim() -ieq $sectionLine) { $start = $i; break }
    }

    if ($start -lt 0) {
        if ($lines.Count -gt 0 -and $lines[$lines.Count-1].Trim() -ne "") { [void]$lines.Add("") }
        [void]$lines.Add($sectionLine)
        [void]$lines.Add("$Key=$Value")
        Set-Content -LiteralPath $Path -Value $lines -Encoding UTF8
        return
    }

    $end = $lines.Count
    for ($i=$start+1; $i -lt $lines.Count; $i++) {
        if ($lines[$i].Trim() -match '^\[.+\]$') { $end=$i; break }
    }

    for ($i=$start+1; $i -lt $end; $i++) {
        if ($lines[$i] -match "^\s*$([regex]::Escape($Key))\s*=") {
            $lines[$i]="$Key=$Value"
            Set-Content -LiteralPath $Path -Value $lines -Encoding UTF8
            return
        }
    }

    $lines.Insert($start+1,"$Key=$Value")
    Set-Content -LiteralPath $Path -Value $lines -Encoding UTF8
}

Ensure-Folder $PluginsPath
$cache = Join-Path $env:LOCALAPPDATA "SecretEMKO\cache\reshade-effects"
Ensure-Folder $cache

$mainPresetSource = Join-Path $Root "presets\Secret_Emko_Main.ini"
$streamPresetSource = Join-Path $Root "presets\Secret_Emko_Stream.ini"
$portableConfigSource = Join-Path $Root "config\ReShade.ini"
foreach ($p in @($mainPresetSource,$streamPresetSource,$portableConfigSource)) {
    if (-not (Test-Path -LiteralPath $p)) { throw "Required ReShade package file missing: $p" }
}

$mainPreset = Join-Path $PluginsPath "Secret_Emko_Main.ini"
$streamPreset = Join-Path $PluginsPath "Secret_Emko_Stream.ini"
Copy-Item -LiteralPath $mainPresetSource -Destination $mainPreset -Force
Copy-Item -LiteralPath $streamPresetSource -Destination $streamPreset -Force

$reshadeIni = Join-Path $PluginsPath "ReShade.ini"
if (-not (Test-Path -LiteralPath $reshadeIni)) {
    Copy-Item -LiteralPath $portableConfigSource -Destination $reshadeIni -Force
}

Ensure-Folder (Join-Path $PluginsPath "reshade-cache")
Ensure-Folder (Join-Path $PluginsPath "Screenshots")
Ensure-Folder (Join-Path $PluginsPath "reshade-shaders\Shaders")
Ensure-Folder (Join-Path $PluginsPath "reshade-shaders\Textures")

Set-IniValue $reshadeIni "GENERAL" "EffectSearchPaths" ".\reshade-shaders\Shaders\**"
Set-IniValue $reshadeIni "GENERAL" "TextureSearchPaths" ".\reshade-shaders\Textures\**"
Set-IniValue $reshadeIni "GENERAL" "IntermediateCachePath" ".\reshade-cache"
Set-IniValue $reshadeIni "GENERAL" "PresetPath" ".\Secret_Emko_Main.ini"
Set-IniValue $reshadeIni "GENERAL" "SkipLoadingDisabledEffects" "1"
Set-IniValue $reshadeIni "SCREENSHOT" "SavePath" ".\Screenshots"

$indexUrl = "https://raw.githubusercontent.com/crosire/reshade-shaders/list/EffectPackages.ini"
Write-Host "   Updating ReShade effects from official package index..."
$index = (Invoke-WebRequest -UseBasicParsing -Uri $indexUrl -Headers @{"User-Agent"="SecretEMKO-v2"}).Content
$packages = Parse-EffectPackageIndex $index
$requiredEffects = Get-ActiveEffectFiles @($mainPreset,$streamPreset)

$selected = New-Object System.Collections.Generic.Dictionary[string,object] ([System.StringComparer]::OrdinalIgnoreCase)
$standard = $packages | Where-Object { $_.Section -eq '00' } | Select-Object -First 1
if ($standard) { $selected[$standard.Section] = $standard }

$unresolved = New-Object System.Collections.Generic.HashSet[string] ([System.StringComparer]::OrdinalIgnoreCase)
foreach ($effect in $requiredEffects) {
    $pkg = $packages | Where-Object {
        $_.PSObject.Properties.Name -contains 'EffectFiles' -and
        (($_.EffectFiles -split ',') | ForEach-Object { $_.Trim() }) -contains $effect
    } | Select-Object -First 1
    if ($pkg) { $selected[$pkg.Section] = $pkg }
    else { [void]$unresolved.Add($effect) }
}

foreach ($pkg in ($selected.Values | Sort-Object { [int]$_.Section })) {
    if (-not ($pkg.PSObject.Properties.Name -contains 'DownloadUrl')) { continue }
    $name = if ($pkg.PSObject.Properties.Name -contains 'PackageName') { $pkg.PackageName } else { "Package $($pkg.Section)" }
    Write-Host "      $name"
    $zip = Join-Path $cache ("effectpkg-" + $pkg.Section + ".zip")
    $extract = Join-Path $cache ("effectpkg-" + $pkg.Section)
    Invoke-WebRequest -UseBasicParsing -Uri $pkg.DownloadUrl -OutFile $zip -Headers @{"User-Agent"="SecretEMKO-v2"}
    if (Test-Path -LiteralPath $extract) { Remove-Item -LiteralPath $extract -Recurse -Force }
    Expand-Archive -LiteralPath $zip -DestinationPath $extract -Force

    $shaderSource = Get-ChildItem -LiteralPath $extract -Directory -Recurse | Where-Object { $_.Name -eq 'Shaders' } | Sort-Object { $_.FullName.Length } | Select-Object -First 1
    $textureSource = Get-ChildItem -LiteralPath $extract -Directory -Recurse | Where-Object { $_.Name -eq 'Textures' } | Sort-Object { $_.FullName.Length } | Select-Object -First 1

    if ($shaderSource -and ($pkg.PSObject.Properties.Name -contains 'InstallPath')) {
        Copy-DirectoryContents $shaderSource.FullName (Convert-ToTargetPath $PluginsPath $pkg.InstallPath)
    }
    if ($textureSource -and ($pkg.PSObject.Properties.Name -contains 'TextureInstallPath')) {
        Copy-DirectoryContents $textureSource.FullName (Convert-ToTargetPath $PluginsPath $pkg.TextureInstallPath)
    }
}

if ($unresolved.Count -gt 0) {
    $shaderRoot = Join-Path $PluginsPath "reshade-shaders\Shaders"
    foreach ($effect in $unresolved) {
        $found = $null -ne (Get-ChildItem -LiteralPath $shaderRoot -File -Recurse -Filter $effect -ErrorAction SilentlyContinue | Select-Object -First 1)
        if (-not $found) {
            Write-Warning "Effect '$effect' is not in the official ReShade package index and is not installed locally. Proprietary packages such as QuantV/NVE are not downloaded from mirrors."
        }
    }
}

Write-Host "   ReShade presets/effects ready: Secret_Emko_Main.ini + Secret_Emko_Stream.ini" -ForegroundColor Green
