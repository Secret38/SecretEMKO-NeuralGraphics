[CmdletBinding()]
param(
    [string]$TargetDirectory = "$env:LOCALAPPDATA\FiveM\FiveM.app\plugins",
    [ValidateSet("64","32")]
    [string]$Architecture = "64",
    [ValidateSet("Addon","Standard")]
    [string]$CoreVariant = "Addon",
    [string]$LegacyContentRoot = "",
    [switch]$SkipShaders,
    [switch]$SkipAddon,
    [switch]$SkipPresets,
    [switch]$SkipCoreCheck,
    [switch]$DryRun,
    [switch]$RequireAllEffects
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest
$ProgressPreference = "SilentlyContinue"
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$ToolRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$PackageRoot = Split-Path -Parent $ToolRoot
$PresetRoot = Join-Path $PackageRoot "presets"
$ConfigRoot = Join-Path $PackageRoot "config"
$MainPreset = Join-Path $PresetRoot "Secret_Emko_Main.ini"
$StreamPreset = Join-Path $PresetRoot "Secret_Emko_Stream.ini"
$TemplateIni = Join-Path $ConfigRoot "ReShade.SecretEMKO.ini"
$EffectCatalogUrl = "https://raw.githubusercontent.com/crosire/reshade-shaders/list/EffectPackages.ini"
$AddonCatalogUrl = "https://raw.githubusercontent.com/crosire/reshade-shaders/list/Addons.ini"

function Step([string]$Text) { Write-Host "   [ReShade] $Text" -ForegroundColor Cyan }
function Ok([string]$Text) { Write-Host "   [OK] $Text" -ForegroundColor Green }
function Warn([string]$Text) { Write-Host "   [!] $Text" -ForegroundColor Yellow }
function Ensure-Folder([string]$Path) { if (-not (Test-Path -LiteralPath $Path)) { New-Item -ItemType Directory -Path $Path -Force | Out-Null } }

function Invoke-Download([string]$Url, [string]$OutFile) {
    Ensure-Folder (Split-Path -Parent $OutFile)
    $temp = $OutFile + ".partial"
    for ($attempt = 1; $attempt -le 3; $attempt++) {
        try {
            Remove-Item -LiteralPath $temp -Force -ErrorAction SilentlyContinue
            Invoke-WebRequest -UseBasicParsing -Uri $Url -OutFile $temp -Headers @{ "User-Agent" = "SecretEMKO-v2" }
            Move-Item -LiteralPath $temp -Destination $OutFile -Force
            return
        } catch {
            if ($attempt -eq 3) { throw }
            Start-Sleep -Seconds (2 * $attempt)
        }
    }
}

function Parse-Catalog([string]$Text) {
    $items = @(); $current = $null
    foreach ($raw in ($Text -split "\r?\n")) {
        $line = $raw.Trim()
        if (-not $line -or $line.StartsWith(";") -or $line.StartsWith("#")) { continue }
        if ($line -match '^\[(.+)\]$') {
            if ($null -ne $current) { $items += [pscustomobject]$current }
            $current = [ordered]@{ Section = $Matches[1] }
            continue
        }
        if ($null -ne $current -and $line -match '^([^=]+)=(.*)$') { $current[$Matches[1].Trim()] = $Matches[2].Trim() }
    }
    if ($null -ne $current) { $items += [pscustomobject]$current }
    return $items
}

function Get-PresetEffects([string[]]$PresetPaths) {
    $effects = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($preset in $PresetPaths) {
        if (-not (Test-Path -LiteralPath $preset)) { throw "Preset missing: $preset" }
        $tech = Get-Content -LiteralPath $preset | Where-Object { $_ -like "Techniques=*" } | Select-Object -First 1
        if (-not $tech) { continue }
        foreach ($entry in ($tech.Substring($tech.IndexOf("=") + 1) -split ",")) {
            if ($entry -match '@(.+\.fx)$') { [void]$effects.Add($Matches[1]) }
        }
    }
    return @($effects)
}

function Get-LatestReShadeSetup([string]$Variant) {
    $home = Invoke-WebRequest -UseBasicParsing -Uri "https://reshade.me/" -Headers @{ "User-Agent" = "SecretEMKO-v2" }
    if ($home.Content -notmatch 'Version\s+([0-9]+\.[0-9]+\.[0-9]+)') { throw "Could not resolve the current ReShade version from reshade.me." }
    $version = $Matches[1]
    $suffix = if ($Variant -eq "Addon") { "_Addon" } else { "" }
    [pscustomobject]@{ Version = $version; Url = ("https://reshade.me/downloads/ReShade_Setup_" + $version + $suffix + ".exe") }
}

function Test-ReShadeModule([string]$Directory, [string]$Variant) {
    $dll = Join-Path $Directory "dxgi.dll"
    if (-not (Test-Path -LiteralPath $dll)) { return $false }
    try {
        $info = (Get-Item -LiteralPath $dll).VersionInfo
        if ($info.ProductName -notmatch "ReShade") { return $false }
        $ascii = [Text.Encoding]::ASCII.GetString([IO.File]::ReadAllBytes($dll))
        $addon = $ascii.Contains("ReShadeRegisterAddon")
        if ($Variant -eq "Addon") { return $addon }
        return -not $addon
    } catch { return $false }
}

function Extract-ReShade64FromSetup([string]$SetupPath, [string]$OutDll) {
    Add-Type -AssemblyName System.IO.Compression
    $bytes = [IO.File]::ReadAllBytes($SetupPath)
    $offset = -1
    for ($i = 0; $i -le $bytes.Length - 30; $i += 512) {
        if ($bytes[$i] -eq 0x50 -and $bytes[$i+1] -eq 0x4B -and $bytes[$i+2] -eq 0x03 -and $bytes[$i+3] -eq 0x04) {
            $nonZero = $false
            for ($j = $i + 4; $j -lt $i + 30; $j++) { if ($bytes[$j] -ne 0) { $nonZero = $true; break } }
            if ($nonZero) { $offset = $i; break }
        }
    }
    if ($offset -lt 0) { throw "Could not locate the embedded ReShade archive in the official setup executable." }

    $ms = [IO.MemoryStream]::new()
    try {
        $ms.Write($bytes, $offset, $bytes.Length - $offset)
        $ms.Position = 0
        $zip = [IO.Compression.ZipArchive]::new($ms, [IO.Compression.ZipArchiveMode]::Read, $true)
        try {
            $entry = $zip.Entries | Where-Object { $_.FullName -match '(^|[\\/])ReShade64\.dll$' } | Select-Object -First 1
            if (-not $entry) { throw "ReShade64.dll was not found in the official setup archive." }
            Ensure-Folder (Split-Path -Parent $OutDll)
            $source = $entry.Open()
            try {
                $dest = [IO.File]::Open($OutDll, [IO.FileMode]::Create, [IO.FileAccess]::Write, [IO.FileShare]::None)
                try { $source.CopyTo($dest) } finally { $dest.Dispose() }
            } finally { $source.Dispose() }
        } finally { $zip.Dispose() }
    } finally { $ms.Dispose() }
}

function Ensure-ReShadeCore([string]$Directory, [string]$Variant) {
    if (Test-ReShadeModule $Directory $Variant) { Ok ("ReShade " + $Variant + " module detected"); return }
    if ($DryRun) { Warn ("ReShade " + $Variant + " module would be installed automatically"); return }

    $setupInfo = Get-LatestReShadeSetup $Variant
    $cache = Join-Path $env:LOCALAPPDATA "SecretEMKO\cache"
    Ensure-Folder $cache
    $suffix = if ($Variant -eq "Addon") { "_Addon" } else { "" }
    $setup = Join-Path $cache ("ReShade_Setup_" + $setupInfo.Version + $suffix + ".exe")
    Step ("Downloading official ReShade " + $setupInfo.Version + " (" + $Variant + ")")
    Invoke-Download $setupInfo.Url $setup

    $dll = Join-Path $Directory "dxgi.dll"
    if (Test-Path -LiteralPath $dll) {
        $old = Join-Path $Directory ("dxgi.pre-SecretEMKO-" + (Get-Date -Format "yyyyMMdd-HHmmss") + ".dll")
        Move-Item -LiteralPath $dll -Destination $old -Force
        Warn ("Preserved incompatible dxgi.dll as " + (Split-Path -Leaf $old))
    }
    Extract-ReShade64FromSetup $setup $dll
    if (-not (Test-ReShadeModule $Directory $Variant)) { throw "Extracted ReShade module failed validation." }
    Ok ("Installed official ReShade " + $setupInfo.Version + " " + $Variant + " module")
}

function Copy-TreeContents([string]$Source, [string]$Destination) {
    if (-not (Test-Path -LiteralPath $Source)) { return }
    Ensure-Folder $Destination
    Get-ChildItem -LiteralPath $Source -Force | ForEach-Object { Copy-Item -LiteralPath $_.FullName -Destination $Destination -Recurse -Force }
}

function To-TargetPath([string]$Root, [string]$Relative) {
    $r = $Relative.Trim() -replace '^[.]\\', ''
    $r = $r -replace '/', '\'
    return Join-Path $Root $r
}

function Install-EffectPackage([object]$Package, [string]$Target, [string]$Work) {
    if (-not ($Package.PSObject.Properties.Name -contains "DownloadUrl")) { return }
    $name = if ($Package.PSObject.Properties.Name -contains "PackageName") { $Package.PackageName } else { $Package.Section }
    Step ("Installing shader package: " + $name)
    $zip = Join-Path $Work ("effects-" + $Package.Section + ".zip")
    $extract = Join-Path $Work ("effects-" + $Package.Section)
    Invoke-Download $Package.DownloadUrl $zip
    if (Test-Path -LiteralPath $extract) { Remove-Item -LiteralPath $extract -Recurse -Force }
    Expand-Archive -LiteralPath $zip -DestinationPath $extract -Force
    $shaderSource = Get-ChildItem -LiteralPath $extract -Directory -Recurse -ErrorAction SilentlyContinue | Where-Object { $_.Name -eq "Shaders" } | Sort-Object { $_.FullName.Length } | Select-Object -First 1
    $textureSource = Get-ChildItem -LiteralPath $extract -Directory -Recurse -ErrorAction SilentlyContinue | Where-Object { $_.Name -eq "Textures" } | Sort-Object { $_.FullName.Length } | Select-Object -First 1
    if ($shaderSource -and ($Package.PSObject.Properties.Name -contains "InstallPath")) { Copy-TreeContents $shaderSource.FullName (To-TargetPath $Target $Package.InstallPath) }
    if ($textureSource -and ($Package.PSObject.Properties.Name -contains "TextureInstallPath")) { Copy-TreeContents $textureSource.FullName (To-TargetPath $Target $Package.TextureInstallPath) }
    if (-not $shaderSource) { throw "Package '$name' did not contain a Shaders directory." }
}

function Find-SelectedPackages([object[]]$Packages, [string[]]$Effects) {
    $selected = [System.Collections.Generic.Dictionary[string,object]]::new([System.StringComparer]::OrdinalIgnoreCase)
    $unresolved = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    $standard = $Packages | Where-Object { $_.Section -eq "00" } | Select-Object -First 1
    if ($standard) { $selected[$standard.Section] = $standard }
    foreach ($effect in $Effects) {
        $pkg = $Packages | Where-Object {
            $_.PSObject.Properties.Name -contains "EffectFiles" -and
            (($_.EffectFiles -split ",") | ForEach-Object { $_.Trim() }) -contains $effect
        } | Select-Object -First 1
        if ($pkg) { $selected[$pkg.Section] = $pkg } else { [void]$unresolved.Add($effect) }
    }
    [pscustomobject]@{ Packages = @($selected.Values | Sort-Object { [int]$_.Section }); Unresolved = @($unresolved) }
}

function Get-IniLines([string]$Path) {
    $lines = New-Object System.Collections.Generic.List[string]
    if (Test-Path -LiteralPath $Path) { foreach ($line in Get-Content -LiteralPath $Path) { [void]$lines.Add($line) } }
    return $lines
}
function Set-IniValue([string]$Path, [string]$Section, [string]$Key, [string]$Value) {
    $lines = Get-IniLines $Path; $sectionHeader = "[$Section]"; $start = -1
    for ($i = 0; $i -lt $lines.Count; $i++) { if ($lines[$i].Trim() -ieq $sectionHeader) { $start = $i; break } }
    if ($start -lt 0) {
        if ($lines.Count -gt 0 -and $lines[$lines.Count - 1].Trim()) { [void]$lines.Add("") }
        [void]$lines.Add($sectionHeader); [void]$lines.Add("$Key=$Value"); Set-Content -LiteralPath $Path -Value $lines -Encoding UTF8; return
    }
    $end = $lines.Count
    for ($i = $start + 1; $i -lt $lines.Count; $i++) { if ($lines[$i].Trim() -match '^\[.+\]$') { $end = $i; break } }
    for ($i = $start + 1; $i -lt $end; $i++) {
        if ($lines[$i] -match ("^\s*" + [regex]::Escape($Key) + "\s*=")) { $lines[$i] = "$Key=$Value"; Set-Content -LiteralPath $Path -Value $lines -Encoding UTF8; return }
    }
    $lines.Insert($start + 1, "$Key=$Value"); Set-Content -LiteralPath $Path -Value $lines -Encoding UTF8
}
function Get-IniValue([string]$Path, [string]$Section, [string]$Key) {
    if (-not (Test-Path -LiteralPath $Path)) { return $null }
    $inside = $false
    foreach ($line in Get-Content -LiteralPath $Path) {
        $trim = $line.Trim()
        if ($trim -match '^\[(.+)\]$') { $inside = $Matches[1] -ieq $Section; continue }
        if ($inside -and $line -match ("^\s*" + [regex]::Escape($Key) + "\s*=(.*)$")) { return $Matches[1].Trim() }
    }
    return $null
}
function Merge-IniListValue([string]$Path, [string]$Section, [string]$Key, [string]$RequiredValue) {
    $current = Get-IniValue $Path $Section $Key
    if (-not $current) { Set-IniValue $Path $Section $Key $RequiredValue; return }
    $parts = @($current -split "," | ForEach-Object { $_.Trim() } | Where-Object { $_ })
    if ($parts -notcontains $RequiredValue) { $parts += $RequiredValue }
    Set-IniValue $Path $Section $Key ($parts -join ",")
}
function Ensure-IniValue([string]$Path, [string]$Section, [string]$Key, [string]$DefaultValue) { if ($null -eq (Get-IniValue $Path $Section $Key)) { Set-IniValue $Path $Section $Key $DefaultValue } }

function Install-PresetsAndConfig([string]$Target) {
    Copy-Item -LiteralPath $MainPreset -Destination (Join-Path $Target "Secret_Emko_Main.ini") -Force
    Copy-Item -LiteralPath $StreamPreset -Destination (Join-Path $Target "Secret_Emko_Stream.ini") -Force
    $ini = Join-Path $Target "ReShade.ini"
    if (-not (Test-Path -LiteralPath $ini) -and (Test-Path -LiteralPath $TemplateIni)) { Copy-Item -LiteralPath $TemplateIni -Destination $ini -Force }
    Merge-IniListValue $ini "GENERAL" "EffectSearchPaths" ".\reshade-shaders\Shaders\**"
    Merge-IniListValue $ini "GENERAL" "TextureSearchPaths" ".\reshade-shaders\Textures\**"

    if ($LegacyContentRoot -and (Test-Path -LiteralPath $LegacyContentRoot)) {
        $legacyShaders = Join-Path $LegacyContentRoot "reshade-shaders\Shaders"
        $legacyTextures = Join-Path $LegacyContentRoot "reshade-shaders\Textures"
        if (Test-Path -LiteralPath $legacyShaders) { Merge-IniListValue $ini "GENERAL" "EffectSearchPaths" ((Resolve-Path $legacyShaders).Path + "\**") }
        if (Test-Path -LiteralPath $legacyTextures) { Merge-IniListValue $ini "GENERAL" "TextureSearchPaths" ((Resolve-Path $legacyTextures).Path + "\**") }
    }

    Set-IniValue $ini "GENERAL" "IntermediateCachePath" ".\reshade-cache"
    Set-IniValue $ini "GENERAL" "PresetPath" ".\Secret_Emko_Main.ini"
    Set-IniValue $ini "GENERAL" "SkipLoadingDisabledEffects" "1"
    if ($CoreVariant -eq "Addon") { Merge-IniListValue $ini "ADDON" "AddonPath" "." }
    Set-IniValue $ini "SCREENSHOT" "SavePath" ".\Screenshots"
    foreach ($pair in @(
        @("Force10BitFormat","0"), @("ForceDefaultRefreshRate","0"), @("ForceFullscreen","0"),
        @("ForceResolution","0,0"), @("ForceVsync","0"), @("ForceWindowed","0")
    )) { Ensure-IniValue $ini "APP" $pair[0] $pair[1] }
    Ensure-Folder (Join-Path $Target "reshade-cache"); Ensure-Folder (Join-Path $Target "Screenshots")
    Ok "Main/Stream presets and portable ReShade paths installed"
}

function Install-SwapchainOverride([string]$Target, [string]$Arch) {
    $catalogText = (Invoke-WebRequest -UseBasicParsing -Uri $AddonCatalogUrl -Headers @{ "User-Agent" = "SecretEMKO-v2" }).Content
    $addons = Parse-Catalog $catalogText
    $swap = $addons | Where-Object {
        ($_.PSObject.Properties.Name -contains "RepositoryUrl" -and $_.RepositoryUrl -match '16-swapchain_override') -or
        ($_.PSObject.Properties.Name -contains "PackageName" -and $_.PackageName -like "Swap chain override*")
    } | Select-Object -First 1
    if (-not $swap) { throw "Swap chain override was not found in ReShade's official Addons.ini." }
    $field = if ($Arch -eq "64") { "DownloadUrl64" } else { "DownloadUrl32" }
    $url = $swap.$field
    $name = if ($Arch -eq "64") { "swapchain_override.addon64" } else { "swapchain_override.addon32" }
    if ($DryRun) { Step ("Would install official add-on: " + $url); return $url }
    Invoke-Download $url (Join-Path $Target $name); Ok ($name + " updated from ReShade's official add-on catalog"); return $url
}

$TargetDirectory = [IO.Path]::GetFullPath($TargetDirectory)
Ensure-Folder $TargetDirectory
if (-not $SkipCoreCheck) { Ensure-ReShadeCore $TargetDirectory $CoreVariant }

$effects = Get-PresetEffects @($MainPreset, $StreamPreset)
$catalog = (Invoke-WebRequest -UseBasicParsing -Uri $EffectCatalogUrl -Headers @{ "User-Agent" = "SecretEMKO-v2" }).Content
$packages = Parse-Catalog $catalog
$selection = Find-SelectedPackages $packages $effects

Step ("Preset effect files: " + $effects.Count)
foreach ($pkg in $selection.Packages) { Write-Host ("      - " + $pkg.PackageName) }
$unresolved = @($selection.Unresolved)
if ($unresolved.Count -gt 0) {
    foreach ($effect in $unresolved) { Warn ("External/proprietary effect not in official catalog: " + $effect) }
    if ($RequireAllEffects) { throw "One or more preset effects are not available through ReShade's official effect catalog." }
}

if ($DryRun) {
    if (-not $SkipAddon -and $CoreVariant -eq "Addon") { [void](Install-SwapchainOverride $TargetDirectory $Architecture) }
    Write-Host "ReShade content dry-run completed." -ForegroundColor Green
    exit 0
}

$work = Join-Path ([IO.Path]::GetTempPath()) ("SecretEMKO-ReShade-" + [guid]::NewGuid().ToString("N"))
Ensure-Folder $work
try {
    if (-not $SkipShaders) { foreach ($pkg in $selection.Packages) { Install-EffectPackage $pkg $TargetDirectory $work } }
    if (-not $SkipPresets) { Install-PresetsAndConfig $TargetDirectory }

    $addonUrl = $null
    if (-not $SkipAddon -and $CoreVariant -eq "Addon") { $addonUrl = Install-SwapchainOverride $TargetDirectory $Architecture }

    $missingLocal = @()
    $searchRoots = @((Join-Path $TargetDirectory "reshade-shaders\Shaders"))
    if ($LegacyContentRoot) { $searchRoots += (Join-Path $LegacyContentRoot "reshade-shaders\Shaders") }
    foreach ($effect in $unresolved) {
        $found = $false
        foreach ($root in $searchRoots) {
            if ((Test-Path -LiteralPath $root) -and (Get-ChildItem -LiteralPath $root -Recurse -File -Filter $effect -ErrorAction SilentlyContinue | Select-Object -First 1)) { $found = $true; break }
        }
        if (-not $found) { $missingLocal += $effect }
    }
    if ($missingLocal.Count -gt 0) { Warn ("External effects still missing: " + ($missingLocal -join ", ")) }

    $stateDir = Join-Path $TargetDirectory "SecretEMKO"; Ensure-Folder $stateDir
    [ordered]@{
        updated_at = (Get-Date).ToUniversalTime().ToString("o")
        core_variant = $CoreVariant
        effect_catalog = $EffectCatalogUrl
        addon_catalog = $AddonCatalogUrl
        installed_packages = @($selection.Packages | ForEach-Object { $_.PackageName })
        unresolved_effects = $unresolved
        missing_external_effects = $missingLocal
        legacy_content_root = $LegacyContentRoot
        default_preset = "Secret_Emko_Main.ini"
        stream_preset = "Secret_Emko_Stream.ini"
        swapchain_override_source = $addonUrl
    } | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $stateDir "reshade-content-state.json") -Encoding UTF8
    Write-Host ""; Write-Host "ReShade content integration complete." -ForegroundColor Green
}
finally { if (Test-Path -LiteralPath $work) { Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue } }
