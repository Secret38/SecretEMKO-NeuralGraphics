[CmdletBinding()]
param(
    [string]$TargetDirectory = "$env:LOCALAPPDATA\FiveM\FiveM.app\plugins",
    [ValidateSet("64","32")]
    [string]$Architecture = "64",
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

$ToolRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$PackageRoot = Split-Path -Parent $ToolRoot
$PresetRoot = Join-Path $PackageRoot "presets"
$ConfigRoot = Join-Path $PackageRoot "config"
$MainPreset = Join-Path $PresetRoot "Secret_Emko_Main.ini"
$StreamPreset = Join-Path $PresetRoot "Secret_Emko_Stream.ini"
$TemplateIni = Join-Path $ConfigRoot "ReShade.SecretEMKO.ini"

$EffectCatalogUrl = "https://raw.githubusercontent.com/crosire/reshade-shaders/list/EffectPackages.ini"
$AddonCatalogUrl = "https://raw.githubusercontent.com/crosire/reshade-shaders/list/Addons.ini"

function Step([string]$Text) {
    Write-Host "   [ReShade] $Text" -ForegroundColor Cyan
}

function Ok([string]$Text) {
    Write-Host "   [OK] $Text" -ForegroundColor Green
}

function Warn([string]$Text) {
    Write-Host "   [!] $Text" -ForegroundColor Yellow
}

function Ensure-Folder([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path)) {
        New-Item -ItemType Directory -Path $Path -Force | Out-Null
    }
}

function Invoke-Download([string]$Url, [string]$OutFile) {
    Ensure-Folder (Split-Path -Parent $OutFile)
    Invoke-WebRequest -UseBasicParsing -Uri $Url -OutFile $OutFile -Headers @{ "User-Agent" = "SecretEMKO-v2" }
}

function Parse-Catalog([string]$Text) {
    $items = @()
    $current = $null
    foreach ($raw in ($Text -split "\r?\n")) {
        $line = $raw.Trim()
        if (-not $line -or $line.StartsWith(";") -or $line.StartsWith("#")) { continue }
        if ($line -match '^\[(.+)\]$') {
            if ($null -ne $current) { $items += [pscustomobject]$current }
            $current = [ordered]@{ Section = $Matches[1] }
            continue
        }
        if ($null -ne $current -and $line -match '^([^=]+)=(.*)$') {
            $current[$Matches[1].Trim()] = $Matches[2].Trim()
        }
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

function Get-LatestReShadeAddonSetup {
    $home = Invoke-WebRequest -UseBasicParsing -Uri "https://reshade.me/" -Headers @{ "User-Agent" = "SecretEMKO-v2" }
    if ($home.Content -notmatch 'Version\s+([0-9]+\.[0-9]+\.[0-9]+)') {
        throw "Could not resolve the current ReShade version from reshade.me."
    }
    $version = $Matches[1]
    [pscustomobject]@{
        Version = $version
        Url = ("https://reshade.me/downloads/ReShade_Setup_" + $version + "_Addon.exe")
    }
}

function Test-ReShadeFullAddon([string]$Directory) {
    $dll = Join-Path $Directory "dxgi.dll"
    if (-not (Test-Path -LiteralPath $dll)) { return $false }
    try {
        $bytes = [IO.File]::ReadAllBytes($dll)
        $ascii = [Text.Encoding]::ASCII.GetString($bytes)
        return $ascii.Contains("ReShadeRegisterAddon")
    }
    catch { return $false }
}

function Ensure-ReShadeFullAddon([string]$Directory) {
    if (Test-ReShadeFullAddon $Directory) {
        Ok "ReShade Full Add-on Support detected"
        return
    }

    if ($DryRun) {
        Warn "ReShade Full Add-on Support is not currently detected"
        return
    }

    $setupInfo = Get-LatestReShadeAddonSetup
    $cache = Join-Path $env:LOCALAPPDATA "SecretEMKO\cache"
    Ensure-Folder $cache
    $setup = Join-Path $cache ("ReShade_Setup_" + $setupInfo.Version + "_Addon.exe")
    Step ("Downloading official ReShade " + $setupInfo.Version + " Full Add-on installer")
    Invoke-Download $setupInfo.Url $setup
    Warn "ReShade Full Add-on Support must be installed for FiveM before SECRET EMKO can continue."
    Write-Host "   The current official installer will open now. Install it for FiveM, then run INSTALL_SECRET_EMKO.bat again."
    Start-Process -FilePath $setup
    exit 20
}

function Copy-TreeContents([string]$Source, [string]$Destination) {
    if (-not (Test-Path -LiteralPath $Source)) { return }
    Ensure-Folder $Destination
    Get-ChildItem -LiteralPath $Source -Force | ForEach-Object {
        Copy-Item -LiteralPath $_.FullName -Destination $Destination -Recurse -Force
    }
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

    $shaderSource = Get-ChildItem -LiteralPath $extract -Directory -Recurse -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -eq "Shaders" } | Sort-Object { $_.FullName.Length } | Select-Object -First 1
    $textureSource = Get-ChildItem -LiteralPath $extract -Directory -Recurse -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -eq "Textures" } | Sort-Object { $_.FullName.Length } | Select-Object -First 1

    if ($shaderSource -and ($Package.PSObject.Properties.Name -contains "InstallPath")) {
        Copy-TreeContents $shaderSource.FullName (To-TargetPath $Target $Package.InstallPath)
    }
    if ($textureSource -and ($Package.PSObject.Properties.Name -contains "TextureInstallPath")) {
        Copy-TreeContents $textureSource.FullName (To-TargetPath $Target $Package.TextureInstallPath)
    }

    if (-not $shaderSource) {
        throw "Package '$name' did not contain a Shaders directory in the expected ReShade package layout."
    }
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

        if ($pkg) { $selected[$pkg.Section] = $pkg }
        else { [void]$unresolved.Add($effect) }
    }

    [pscustomobject]@{
        Packages = @($selected.Values | Sort-Object { [int]$_.Section })
        Unresolved = @($unresolved)
    }
}

function Get-IniLines([string]$Path) {
    $lines = New-Object System.Collections.Generic.List[string]
    if (Test-Path -LiteralPath $Path) {
        foreach ($line in Get-Content -LiteralPath $Path) { [void]$lines.Add($line) }
    }
    return $lines
}

function Set-IniValue([string]$Path, [string]$Section, [string]$Key, [string]$Value) {
    $lines = Get-IniLines $Path
    $sectionHeader = "[$Section]"
    $start = -1
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($lines[$i].Trim() -ieq $sectionHeader) { $start = $i; break }
    }

    if ($start -lt 0) {
        if ($lines.Count -gt 0 -and $lines[$lines.Count - 1].Trim()) { [void]$lines.Add("") }
        [void]$lines.Add($sectionHeader)
        [void]$lines.Add("$Key=$Value")
        Set-Content -LiteralPath $Path -Value $lines -Encoding UTF8
        return
    }

    $end = $lines.Count
    for ($i = $start + 1; $i -lt $lines.Count; $i++) {
        if ($lines[$i].Trim() -match '^\[.+\]$') { $end = $i; break }
    }

    for ($i = $start + 1; $i -lt $end; $i++) {
        if ($lines[$i] -match ("^\s*" + [regex]::Escape($Key) + "\s*=")) {
            $lines[$i] = "$Key=$Value"
            Set-Content -LiteralPath $Path -Value $lines -Encoding UTF8
            return
        }
    }

    $lines.Insert($start + 1, "$Key=$Value")
    Set-Content -LiteralPath $Path -Value $lines -Encoding UTF8
}

function Get-IniValue([string]$Path, [string]$Section, [string]$Key) {
    if (-not (Test-Path -LiteralPath $Path)) { return $null }
    $inside = $false
    foreach ($line in Get-Content -LiteralPath $Path) {
        $trim = $line.Trim()
        if ($trim -match '^\[(.+)\]$') {
            $inside = $Matches[1] -ieq $Section
            continue
        }
        if ($inside -and $line -match ("^\s*" + [regex]::Escape($Key) + "\s*=(.*)$")) {
            return $Matches[1].Trim()
        }
    }
    return $null
}

function Merge-IniListValue([string]$Path, [string]$Section, [string]$Key, [string]$RequiredValue) {
    $current = Get-IniValue $Path $Section $Key
    if (-not $current) {
        Set-IniValue $Path $Section $Key $RequiredValue
        return
    }

    $parts = @($current -split "," | ForEach-Object { $_.Trim() } | Where-Object { $_ })
    if ($parts -notcontains $RequiredValue) { $parts += $RequiredValue }
    Set-IniValue $Path $Section $Key ($parts -join ",")
}

function Ensure-IniValue([string]$Path, [string]$Section, [string]$Key, [string]$DefaultValue) {
    if ($null -eq (Get-IniValue $Path $Section $Key)) {
        Set-IniValue $Path $Section $Key $DefaultValue
    }
}

function Install-PresetsAndConfig([string]$Target) {
    if (-not (Test-Path -LiteralPath $MainPreset)) { throw "Missing preset: $MainPreset" }
    if (-not (Test-Path -LiteralPath $StreamPreset)) { throw "Missing preset: $StreamPreset" }

    Copy-Item -LiteralPath $MainPreset -Destination (Join-Path $Target "Secret_Emko_Main.ini") -Force
    Copy-Item -LiteralPath $StreamPreset -Destination (Join-Path $Target "Secret_Emko_Stream.ini") -Force

    $ini = Join-Path $Target "ReShade.ini"
    if (-not (Test-Path -LiteralPath $ini) -and (Test-Path -LiteralPath $TemplateIni)) {
        Copy-Item -LiteralPath $TemplateIni -Destination $ini -Force
    }

    Merge-IniListValue $ini "GENERAL" "EffectSearchPaths" ".\reshade-shaders\Shaders\**"
    Merge-IniListValue $ini "GENERAL" "TextureSearchPaths" ".\reshade-shaders\Textures\**"
    Set-IniValue $ini "GENERAL" "IntermediateCachePath" ".\reshade-cache"
    Set-IniValue $ini "GENERAL" "PresetPath" ".\Secret_Emko_Main.ini"
    Set-IniValue $ini "GENERAL" "SkipLoadingDisabledEffects" "1"
    Merge-IniListValue $ini "ADDON" "AddonPath" "."
    Set-IniValue $ini "SCREENSHOT" "SavePath" ".\Screenshots"

    Ensure-IniValue $ini "APP" "Force10BitFormat" "0"
    Ensure-IniValue $ini "APP" "ForceDefaultRefreshRate" "0"
    Ensure-IniValue $ini "APP" "ForceFullscreen" "0"
    Ensure-IniValue $ini "APP" "ForceResolution" "0,0"
    Ensure-IniValue $ini "APP" "ForceVsync" "0"
    Ensure-IniValue $ini "APP" "ForceWindowed" "0"

    Ensure-Folder (Join-Path $Target "reshade-cache")
    Ensure-Folder (Join-Path $Target "Screenshots")
    Ok "Main/Stream presets and portable ReShade paths installed"
}

function Disable-MissingPresetTechniques([string]$Path, [string[]]$MissingEffects) {
    if (-not (Test-Path -LiteralPath $Path) -or $MissingEffects.Count -eq 0) { return }

    $missing = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($effect in $MissingEffects) { [void]$missing.Add($effect) }

    $lines = @(Get-Content -LiteralPath $Path)
    $changed = $false
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -notmatch '^(Techniques|TechniqueSorting)=(.*)$') { continue }

        $key = $Matches[1]
        $entries = @($Matches[2] -split "," | Where-Object { $_ })
        $kept = New-Object System.Collections.Generic.List[string]

        foreach ($entry in $entries) {
            $drop = $false
            if ($entry -match '@(.+\.fx)$') {
                $drop = $missing.Contains($Matches[1])
            }
            if (-not $drop) { [void]$kept.Add($entry) }
            else { $changed = $true }
        }

        $lines[$i] = $key + "=" + ($kept -join ",")
    }

    if ($changed) {
        Set-Content -LiteralPath $Path -Value $lines -Encoding UTF8
        Warn ("Disabled unavailable external techniques in " + (Split-Path -Leaf $Path))
    }
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
    if (-not ($swap.PSObject.Properties.Name -contains $field)) { throw "Swap chain override does not publish $field." }
    $url = $swap.$field
    $name = if ($Arch -eq "64") { "swapchain_override.addon64" } else { "swapchain_override.addon32" }

    if ($DryRun) {
        Step ("Would install official add-on: " + $url)
        return $url
    }

    Invoke-Download $url (Join-Path $Target $name)
    Ok ($name + " updated from ReShade's official add-on catalog")
    return $url
}

$TargetDirectory = [IO.Path]::GetFullPath($TargetDirectory)
Ensure-Folder $TargetDirectory

if (-not $SkipCoreCheck) {
    Ensure-ReShadeFullAddon $TargetDirectory
}

$effects = Get-PresetEffects @($MainPreset, $StreamPreset)
$catalog = (Invoke-WebRequest -UseBasicParsing -Uri $EffectCatalogUrl -Headers @{ "User-Agent" = "SecretEMKO-v2" }).Content
$packages = Parse-Catalog $catalog
$selection = Find-SelectedPackages $packages $effects

Step ("Preset effect files: " + $effects.Count)
foreach ($pkg in $selection.Packages) {
    $name = if ($pkg.PSObject.Properties.Name -contains "PackageName") { $pkg.PackageName } else { $pkg.Section }
    Write-Host ("      - " + $name)
}

$unresolved = @($selection.Unresolved)
if ($unresolved.Count -gt 0) {
    foreach ($effect in $unresolved) { Warn ("External/proprietary effect not in official catalog: " + $effect) }
    if ($RequireAllEffects) { throw "One or more preset effects are not available through ReShade's official effect catalog." }
}

if ($DryRun) {
    if (-not $SkipAddon) { [void](Install-SwapchainOverride $TargetDirectory $Architecture) }
    Write-Host "ReShade content dry-run completed." -ForegroundColor Green
    exit 0
}

$work = Join-Path ([IO.Path]::GetTempPath()) ("SecretEMKO-ReShade-" + [guid]::NewGuid().ToString("N"))
Ensure-Folder $work
try {
    if (-not $SkipShaders) {
        foreach ($pkg in $selection.Packages) { Install-EffectPackage $pkg $TargetDirectory $work }
    }

    if (-not $SkipPresets) { Install-PresetsAndConfig $TargetDirectory }

    $addonUrl = $null
    if (-not $SkipAddon) { $addonUrl = Install-SwapchainOverride $TargetDirectory $Architecture }

    $missingLocal = @()
    $shaderRoot = Join-Path $TargetDirectory "reshade-shaders\Shaders"
    foreach ($effect in $unresolved) {
        $found = $false
        if (Test-Path -LiteralPath $shaderRoot) {
            $found = $null -ne (Get-ChildItem -LiteralPath $shaderRoot -Recurse -File -Filter $effect -ErrorAction SilentlyContinue | Select-Object -First 1)
        }
        if (-not $found) { $missingLocal += $effect }
    }

    if ($missingLocal.Count -gt 0) {
        Warn ("Preset references external/proprietary files that were not found locally: " + ($missingLocal -join ", "))
        Warn "SECRET EMKO does not fetch proprietary graphics packages from unofficial mirrors."
        Disable-MissingPresetTechniques (Join-Path $TargetDirectory "Secret_Emko_Main.ini") $missingLocal
        Disable-MissingPresetTechniques (Join-Path $TargetDirectory "Secret_Emko_Stream.ini") $missingLocal
    }

    $stateDir = Join-Path $TargetDirectory "SecretEMKO"
    Ensure-Folder $stateDir
    $state = [ordered]@{
        updated_at = (Get-Date).ToUniversalTime().ToString("o")
        effect_catalog = $EffectCatalogUrl
        addon_catalog = $AddonCatalogUrl
        installed_packages = @($selection.Packages | ForEach-Object { $_.PackageName })
        unresolved_effects = $unresolved
        missing_external_effects = $missingLocal
        default_preset = "Secret_Emko_Main.ini"
        stream_preset = "Secret_Emko_Stream.ini"
        swapchain_override_source = $addonUrl
    }
    $state | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $stateDir "reshade-content-state.json") -Encoding UTF8

    Write-Host ""
    Write-Host "ReShade content integration complete." -ForegroundColor Green
}
finally {
    if (Test-Path -LiteralPath $work) { Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue }
}
) { continue }

        $key = $Matches[1]
        $entries = @($Matches[2] -split "," | Where-Object { $_ })
        $kept = New-Object System.Collections.Generic.List[string]

        foreach ($entry in $entries) {
            $drop = $false
            if ($entry -match '@(.+\.fx)
function Install-SwapchainOverride([string]$Target, [string]$Arch) {
    $catalogText = (Invoke-WebRequest -UseBasicParsing -Uri $AddonCatalogUrl -Headers @{ "User-Agent" = "SecretEMKO-v2" }).Content
    $addons = Parse-Catalog $catalogText
    $swap = $addons | Where-Object {
        ($_.PSObject.Properties.Name -contains "RepositoryUrl" -and $_.RepositoryUrl -match '16-swapchain_override') -or
        ($_.PSObject.Properties.Name -contains "PackageName" -and $_.PackageName -like "Swap chain override*")
    } | Select-Object -First 1
    if (-not $swap) { throw "Swap chain override was not found in ReShade's official Addons.ini." }

    $field = if ($Arch -eq "64") { "DownloadUrl64" } else { "DownloadUrl32" }
    if (-not ($swap.PSObject.Properties.Name -contains $field)) { throw "Swap chain override does not publish $field." }
    $url = $swap.$field
    $name = if ($Arch -eq "64") { "swapchain_override.addon64" } else { "swapchain_override.addon32" }

    if ($DryRun) {
        Step ("Would install official add-on: " + $url)
        return $url
    }

    Invoke-Download $url (Join-Path $Target $name)
    Ok ($name + " updated from ReShade's official add-on catalog")
    return $url
}

$TargetDirectory = [IO.Path]::GetFullPath($TargetDirectory)
Ensure-Folder $TargetDirectory

if (-not $SkipCoreCheck) {
    Ensure-ReShadeFullAddon $TargetDirectory
}

$effects = Get-PresetEffects @($MainPreset, $StreamPreset)
$catalog = (Invoke-WebRequest -UseBasicParsing -Uri $EffectCatalogUrl -Headers @{ "User-Agent" = "SecretEMKO-v2" }).Content
$packages = Parse-Catalog $catalog
$selection = Find-SelectedPackages $packages $effects

Step ("Preset effect files: " + $effects.Count)
foreach ($pkg in $selection.Packages) {
    $name = if ($pkg.PSObject.Properties.Name -contains "PackageName") { $pkg.PackageName } else { $pkg.Section }
    Write-Host ("      - " + $name)
}

$unresolved = @($selection.Unresolved)
if ($unresolved.Count -gt 0) {
    foreach ($effect in $unresolved) { Warn ("External/proprietary effect not in official catalog: " + $effect) }
    if ($RequireAllEffects) { throw "One or more preset effects are not available through ReShade's official effect catalog." }
}

if ($DryRun) {
    if (-not $SkipAddon) { [void](Install-SwapchainOverride $TargetDirectory $Architecture) }
    Write-Host "ReShade content dry-run completed." -ForegroundColor Green
    exit 0
}

$work = Join-Path ([IO.Path]::GetTempPath()) ("SecretEMKO-ReShade-" + [guid]::NewGuid().ToString("N"))
Ensure-Folder $work
try {
    if (-not $SkipShaders) {
        foreach ($pkg in $selection.Packages) { Install-EffectPackage $pkg $TargetDirectory $work }
    }

    if (-not $SkipPresets) { Install-PresetsAndConfig $TargetDirectory }

    $addonUrl = $null
    if (-not $SkipAddon) { $addonUrl = Install-SwapchainOverride $TargetDirectory $Architecture }

    $missingLocal = @()
    $shaderRoot = Join-Path $TargetDirectory "reshade-shaders\Shaders"
    foreach ($effect in $unresolved) {
        $found = $false
        if (Test-Path -LiteralPath $shaderRoot) {
            $found = $null -ne (Get-ChildItem -LiteralPath $shaderRoot -Recurse -File -Filter $effect -ErrorAction SilentlyContinue | Select-Object -First 1)
        }
        if (-not $found) { $missingLocal += $effect }
    }

    if ($missingLocal.Count -gt 0) {
        Warn ("Main preset needs externally supplied files that were not found locally: " + ($missingLocal -join ", "))
        Warn "SECRET EMKO does not fetch proprietary graphics packages from unofficial mirrors."
    }

    $stateDir = Join-Path $TargetDirectory "SecretEMKO"
    Ensure-Folder $stateDir
    $state = [ordered]@{
        updated_at = (Get-Date).ToUniversalTime().ToString("o")
        effect_catalog = $EffectCatalogUrl
        addon_catalog = $AddonCatalogUrl
        installed_packages = @($selection.Packages | ForEach-Object { $_.PackageName })
        unresolved_effects = $unresolved
        missing_external_effects = $missingLocal
        default_preset = "Secret_Emko_Main.ini"
        stream_preset = "Secret_Emko_Stream.ini"
        swapchain_override_source = $addonUrl
    }
    $state | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $stateDir "reshade-content-state.json") -Encoding UTF8

    Write-Host ""
    Write-Host "ReShade content integration complete." -ForegroundColor Green
}
finally {
    if (Test-Path -LiteralPath $work) { Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue }
}
) {
                $drop = $missing.Contains($Matches[1])
            }
            if (-not $drop) { [void]$kept.Add($entry) }
            else { $changed = $true }
        }

        $lines[$i] = $key + "=" + ($kept -join ",")
    }

    if ($changed) {
        Set-Content -LiteralPath $Path -Value $lines -Encoding UTF8
        Warn ("Disabled unavailable external techniques in " + (Split-Path -Leaf $Path))
    }
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
    if (-not ($swap.PSObject.Properties.Name -contains $field)) { throw "Swap chain override does not publish $field." }
    $url = $swap.$field
    $name = if ($Arch -eq "64") { "swapchain_override.addon64" } else { "swapchain_override.addon32" }

    if ($DryRun) {
        Step ("Would install official add-on: " + $url)
        return $url
    }

    Invoke-Download $url (Join-Path $Target $name)
    Ok ($name + " updated from ReShade's official add-on catalog")
    return $url
}

$TargetDirectory = [IO.Path]::GetFullPath($TargetDirectory)
Ensure-Folder $TargetDirectory

if (-not $SkipCoreCheck) {
    Ensure-ReShadeFullAddon $TargetDirectory
}

$effects = Get-PresetEffects @($MainPreset, $StreamPreset)
$catalog = (Invoke-WebRequest -UseBasicParsing -Uri $EffectCatalogUrl -Headers @{ "User-Agent" = "SecretEMKO-v2" }).Content
$packages = Parse-Catalog $catalog
$selection = Find-SelectedPackages $packages $effects

Step ("Preset effect files: " + $effects.Count)
foreach ($pkg in $selection.Packages) {
    $name = if ($pkg.PSObject.Properties.Name -contains "PackageName") { $pkg.PackageName } else { $pkg.Section }
    Write-Host ("      - " + $name)
}

$unresolved = @($selection.Unresolved)
if ($unresolved.Count -gt 0) {
    foreach ($effect in $unresolved) { Warn ("External/proprietary effect not in official catalog: " + $effect) }
    if ($RequireAllEffects) { throw "One or more preset effects are not available through ReShade's official effect catalog." }
}

if ($DryRun) {
    if (-not $SkipAddon) { [void](Install-SwapchainOverride $TargetDirectory $Architecture) }
    Write-Host "ReShade content dry-run completed." -ForegroundColor Green
    exit 0
}

$work = Join-Path ([IO.Path]::GetTempPath()) ("SecretEMKO-ReShade-" + [guid]::NewGuid().ToString("N"))
Ensure-Folder $work
try {
    if (-not $SkipShaders) {
        foreach ($pkg in $selection.Packages) { Install-EffectPackage $pkg $TargetDirectory $work }
    }

    if (-not $SkipPresets) { Install-PresetsAndConfig $TargetDirectory }

    $addonUrl = $null
    if (-not $SkipAddon) { $addonUrl = Install-SwapchainOverride $TargetDirectory $Architecture }

    $missingLocal = @()
    $shaderRoot = Join-Path $TargetDirectory "reshade-shaders\Shaders"
    foreach ($effect in $unresolved) {
        $found = $false
        if (Test-Path -LiteralPath $shaderRoot) {
            $found = $null -ne (Get-ChildItem -LiteralPath $shaderRoot -Recurse -File -Filter $effect -ErrorAction SilentlyContinue | Select-Object -First 1)
        }
        if (-not $found) { $missingLocal += $effect }
    }

    if ($missingLocal.Count -gt 0) {
        Warn ("Main preset needs externally supplied files that were not found locally: " + ($missingLocal -join ", "))
        Warn "SECRET EMKO does not fetch proprietary graphics packages from unofficial mirrors."
    }

    $stateDir = Join-Path $TargetDirectory "SecretEMKO"
    Ensure-Folder $stateDir
    $state = [ordered]@{
        updated_at = (Get-Date).ToUniversalTime().ToString("o")
        effect_catalog = $EffectCatalogUrl
        addon_catalog = $AddonCatalogUrl
        installed_packages = @($selection.Packages | ForEach-Object { $_.PackageName })
        unresolved_effects = $unresolved
        missing_external_effects = $missingLocal
        default_preset = "Secret_Emko_Main.ini"
        stream_preset = "Secret_Emko_Stream.ini"
        swapchain_override_source = $addonUrl
    }
    $state | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $stateDir "reshade-content-state.json") -Encoding UTF8

    Write-Host ""
    Write-Host "ReShade content integration complete." -ForegroundColor Green
}
finally {
    if (Test-Path -LiteralPath $work) { Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue }
}
