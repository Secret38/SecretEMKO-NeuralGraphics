[CmdletBinding()]
param(
    [string]$PluginsPath = "",
    [string]$FiveMPath = "",
    [ValidateSet("Isolate","Merge")]
    [string]$ExistingPluginsMode = "Isolate",
    [ValidateSet("Auto","RPVisual","FullNeural")]
    [string]$Mode = "Auto",
    [switch]$SkipStreamline,
    [switch]$ForceNeuralStack,
    [switch]$NonInteractive
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest
$ProgressPreference = "SilentlyContinue"

$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
if ((Split-Path -Leaf $Root) -ieq "tools") { $Root = Split-Path -Parent $Root }

$Product = "SECRET EMKO Neural Graphics"
$Version = "2.0.0-rc2"
$Cache = Join-Path $env:LOCALAPPDATA "SecretEMKO\cache"
$GlobalStateRoot = Join-Path $env:LOCALAPPDATA "SecretEMKO\state"
$Stamp = Get-Date -Format "yyyyMMdd-HHmmss"

$Urls = @{
    RenoDX = "https://github.com/RankFTW/rhi-repo/releases/download/renodx-dlss5-4.70/renodx-dlss5_4.70.zip"
    DlssNr = "https://github.com/RankFTW/rhi-repo/releases/download/dlssnr-310.8.0/nvngx_dlssnr_310.8.0.zip"
    DlssSr = "https://github.com/RankFTW/rhi-repo/releases/download/dlss-310.9.1/nvngx_dlss_310.9.1.zip"
    Streamline = "https://github.com/NVIDIA-RTX/Streamline/releases/download/v2.14.1/streamline-sdk-v2.14.1.zip"
}
$Hashes = @{
    RenoDX = "D6E356D01B429AF6288F488A4926C44F1D779A7D4586EE8C79D04D3A09A536E6"
    DlssNr = "388C0A7912E15EC911B9C9E11A692142B11FE387DDF2B637D8C358138FFFB3AC"
    DlssSr = "AABA83B288BD145C3808E8D7A0BA03CC8C8676D18AD984B1BFA6563046A3BA37"
    Streamline = "92C4D954631A1710DA86CA3FA8D5034F2B9503838C95FC4AE977AE149319781B"
}
$Rtx50NrDllHash = "E16BCF15E16E13F527491CDF7845B2FE6521A738D8F7C9C721866A8496E1FC8E"

function Banner {
    Write-Host ""
    Write-Host "================================================================" -ForegroundColor DarkGray
    Write-Host " SECRET EMKO  //  NEURAL GRAPHICS v2 RC2" -ForegroundColor Cyan
    Write-Host " Universal FiveM Legacy installer  |  isolated + reversible" -ForegroundColor Gray
    Write-Host "================================================================" -ForegroundColor DarkGray
    Write-Host ""
}

function Step([string]$Text) {
    Write-Host ""
    Write-Host ">> $Text" -ForegroundColor Cyan
}

function Ok([string]$Text) {
    Write-Host "   [OK] $Text" -ForegroundColor Green
}

function Warn([string]$Text) {
    Write-Host "   [!]  $Text" -ForegroundColor Yellow
}

function Ensure-Folder([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path)) {
        New-Item -ItemType Directory -Path $Path -Force | Out-Null
    }
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
        if ($item.Name -ieq "CitizenFX.ini") {
            $candidate = $item.DirectoryName
        }
        elseif ($item.Name -ieq "FiveM.exe") {
            $base = $item.DirectoryName
            if (Test-FiveMAppPath (Join-Path $base "FiveM.app")) { return (Join-Path $base "FiveM.app") }
            $candidate = $base
        }
        else {
            $candidate = $item.DirectoryName
        }
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

function Get-ShortcutFiveMCandidates {
    $roots = @(
        (Join-Path $env:APPDATA "Microsoft\Windows\Start Menu\Programs"),
        (Join-Path $env:ProgramData "Microsoft\Windows\Start Menu\Programs"),
        ([Environment]::GetFolderPath("Desktop"))
    ) | Where-Object { $_ -and (Test-Path -LiteralPath $_) }

    $shell = New-Object -ComObject WScript.Shell
    foreach ($root in $roots) {
        Get-ChildItem -LiteralPath $root -Filter "*FiveM*.lnk" -File -Recurse -ErrorAction SilentlyContinue | ForEach-Object {
            try {
                $shortcut = $shell.CreateShortcut($_.FullName)
                if ($shortcut.TargetPath) {
                    $resolved = Normalize-FiveMAppPath $shortcut.TargetPath
                    if ($resolved) { $resolved }
                }
            } catch {}
        }
    }
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
    } catch {
        Warn "Interactive FiveM picker could not be opened: $($_.Exception.Message)"
    }
    return $null
}

function Resolve-FiveMAppPath {
    if ($PluginsPath) {
        $fromPlugins = Normalize-FiveMAppPath $PluginsPath
        if ($fromPlugins) { return $fromPlugins }

        $pluginsParent = Split-Path -Parent ([IO.Path]::GetFullPath($PluginsPath))
        if (Test-FiveMAppPath $pluginsParent) { return $pluginsParent }

        throw "-PluginsPath does not point to a valid FiveM Legacy application-data plugins path: $PluginsPath"
    }

    if ($FiveMPath) {
        $explicit = Normalize-FiveMAppPath $FiveMPath
        if ($explicit) { return $explicit }
        throw "-FiveMPath does not resolve to a FiveM Legacy installation: $FiveMPath"
    }

    $candidates = New-Object System.Collections.Generic.List[string]
    $default = Join-Path $env:LOCALAPPDATA "FiveM\FiveM.app"
    if (Test-FiveMAppPath $default) { [void]$candidates.Add([IO.Path]::GetFullPath($default)) }

    foreach ($p in @(Get-ShortcutFiveMCandidates)) {
        if ($p -and -not $candidates.Contains($p)) { [void]$candidates.Add($p) }
    }

    if ($candidates.Count -eq 1) { return $candidates[0] }
    if ($candidates.Count -gt 1) {
        $ordered = $candidates | Sort-Object {
            $citizen = Join-Path $_ "CitizenFX.ini"
            if (Test-Path -LiteralPath $citizen) { (Get-Item -LiteralPath $citizen).LastWriteTimeUtc } else { [datetime]::MinValue }
        } -Descending
        Warn "Multiple FiveM Legacy installs were discovered; selecting the candidate with the most recently modified CitizenFX.ini."
        Write-Host ("   Selected: " + $ordered[0])
        Write-Host "   Use -FiveMPath if another installation should be targeted."
        return $ordered[0]
    }

    $picked = Select-FiveMInteractively
    if ($picked) { return $picked }

    $enhancedConfig = Join-Path $env:APPDATA "FiveM for GTAV Enhanced\config.toml"
    if (Test-Path -LiteralPath $enhancedConfig) {
        throw "Only FiveM for GTAV Enhanced was detected. SECRET EMKO v2 RC2 currently targets FiveM GTA V Legacy and will not install into Enhanced."
    }

    throw "FiveM Legacy was not found. Start FiveM Legacy once, or run the installer with -FiveMPath <path-to-FiveM.exe>."
}

function Download-Verified([string]$Url, [string]$Path, [string]$ExpectedHash) {
    Ensure-Folder (Split-Path -Parent $Path)
    $need = $true
    if (Test-Path -LiteralPath $Path) {
        $hash = (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash
        if ($hash -ieq $ExpectedHash) { $need = $false }
        else { Remove-Item -LiteralPath $Path -Force }
    }
    if ($need) {
        Write-Host "   Downloading $(Split-Path -Leaf $Path)..."
        Invoke-WebRequest -UseBasicParsing -Uri $Url -OutFile $Path -Headers @{ "User-Agent" = "SecretEMKO-v2" }
    }
    $actual = (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash
    if ($actual -ine $ExpectedHash) {
        throw "SHA256 mismatch for $(Split-Path -Leaf $Path). Expected $ExpectedHash, got $actual"
    }
    Ok "$(Split-Path -Leaf $Path) verified"
}

function Expand-Fresh([string]$Zip, [string]$Dest) {
    if (Test-Path -LiteralPath $Dest) { Remove-Item -LiteralPath $Dest -Recurse -Force }
    Ensure-Folder $Dest
    Expand-Archive -LiteralPath $Zip -DestinationPath $Dest -Force
}

function Find-RequiredFile([string]$RootPath, [string]$Name, [string]$Hash = "") {
    $all = @(Get-ChildItem -LiteralPath $RootPath -Recurse -File -Filter $Name -ErrorAction SilentlyContinue)
    if ($Hash) {
        foreach ($f in $all) {
            if ((Get-FileHash -LiteralPath $f.FullName -Algorithm SHA256).Hash -ieq $Hash) { return $f.FullName }
        }
        throw "$Name with required SHA256 $Hash was not found in the verified package."
    }
    if ($all.Count -eq 0) { throw "$Name was not found in $RootPath" }
    return $all[0].FullName
}

function Get-ReShadeMode([string]$Directory) {
    $dll = Join-Path $Directory "dxgi.dll"
    if (-not (Test-Path -LiteralPath $dll)) { return "missing" }

    try {
        $info = [Diagnostics.FileVersionInfo]::GetVersionInfo($dll)
        if ($info.ProductName -notlike "ReShade*") { return "foreign" }

        $bytes = [IO.File]::ReadAllBytes($dll)
        $ascii = [Text.Encoding]::ASCII.GetString($bytes)
        if ($ascii.Contains("only limited add-on functionality")) { return "standard" }
        return "full-addon"
    }
    catch {
        return "foreign"
    }
}

function Test-ReShadeFullAddon([string]$Directory) {
    return (Get-ReShadeMode $Directory) -eq "full-addon"
}

function Get-LatestReShadeSetup([bool]$FullAddon) {
    $landingPage = Invoke-WebRequest -UseBasicParsing -Uri "https://reshade.me/" -Headers @{ "User-Agent" = "SecretEMKO-v2" }
    if ($landingPage.Content -notmatch 'Version\s+([0-9]+\.[0-9]+\.[0-9]+)') {
        throw "Could not resolve the current ReShade version from reshade.me."
    }
    $version = $Matches[1]
    $suffix = if ($FullAddon) { "_Addon" } else { "" }
    return [pscustomobject]@{
        Version = $version
        FullAddon = $FullAddon
        Url = ("https://reshade.me/downloads/ReShade_Setup_" + $version + $suffix + ".exe")
        FileName = ("ReShade_Setup_" + $version + $suffix + ".exe")
    }
}

function Install-ReShadeHeadless([string]$Directory, [bool]$FullAddon) {
    $expected = if ($FullAddon) { "full-addon" } else { "standard" }
    $existing = Get-ReShadeMode $Directory
    if ($existing -eq $expected) {
        Ok ("ReShade " + $expected + " build detected")
        return
    }
    if ($existing -eq "foreign") {
        throw "A foreign dxgi.dll already exists in the active plugins folder. Use the default Isolate mode instead of mixing graphics proxies."
    }

    $setupInfo = Get-LatestReShadeSetup $FullAddon
    Ensure-Folder $Cache
    $setup = Join-Path $Cache $setupInfo.FileName
    if (-not (Test-Path -LiteralPath $setup)) {
        $label = if ($FullAddon) { "Full Add-on Support" } else { "standard signed build" }
        Step ("Downloading official ReShade " + $setupInfo.Version + " " + $label)
        Invoke-WebRequest -UseBasicParsing -Uri $setupInfo.Url -OutFile $setup -Headers @{ "User-Agent" = "SecretEMKO-v2" }
    }

    $hostSource = Join-Path $env:WINDIR "System32\notepad.exe"
    if (-not (Test-Path -LiteralPath $hostSource)) { throw "Could not locate a 64-bit Windows host executable for ReShade setup." }
    $host = Join-Path $Directory "_SecretEMKO_ReShadeHost.exe"
    Copy-Item -LiteralPath $hostSource -Destination $host -Force

    try {
        $label = if ($FullAddon) { "Full Add-on Support" } else { "standard signed build" }
        Step ("Installing ReShade " + $label + " automatically")
        $args = New-Object System.Collections.Generic.List[string]
        [void]$args.Add("--headless")
        if ($existing -eq "standard" -or $existing -eq "full-addon") {
            [void]$args.Add("--state")
            [void]$args.Add("update")
        }
        [void]$args.Add("--api")
        [void]$args.Add("dxgi")
        [void]$args.Add($host)

        $proc = Start-Process -FilePath $setup -ArgumentList @($args) -Wait -PassThru
        if ($proc.ExitCode -ne 0) {
            throw "ReShade setup returned exit code $($proc.ExitCode)."
        }
    }
    finally {
        Remove-Item -LiteralPath $host -Force -ErrorAction SilentlyContinue
    }

    $actual = Get-ReShadeMode $Directory
    if ($actual -ne $expected) {
        throw "ReShade verification failed. Expected '$expected', detected '$actual'."
    }
    Ok ("ReShade " + $expected + " build installed")
}

function Backup-IfExists([string]$Path, [string]$BackupRoot) {
    if (-not (Test-Path -LiteralPath $Path)) { return }
    Ensure-Folder $BackupRoot
    $dest = Join-Path $BackupRoot (Split-Path -Leaf $Path)
    Copy-Item -LiteralPath $Path -Destination $dest -Recurse -Force
}

function Copy-Managed([string]$Source, [string]$Name, [string]$Target, [string]$BackupRoot) {
    $dest = Join-Path $Target $Name
    Backup-IfExists $dest $BackupRoot
    Copy-Item -LiteralPath $Source -Destination $dest -Force
    Ok "$Name"
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
        if ($lines[$i] -match ("^\s*" + [regex]::Escape($Key) + "\s*=")) {
            $lines[$i]="$Key=$Value"
            Set-Content -LiteralPath $Path -Value $lines -Encoding UTF8
            return
        }
    }

    $lines.Insert($start+1,"$Key=$Value")
    Set-Content -LiteralPath $Path -Value $lines -Encoding UTF8
}

function Copy-OptionalStreamlineFile([string]$Extracted, [string]$Name, [string]$Target, [string]$BackupRoot) {
    $candidates = @(Get-ChildItem -LiteralPath $Extracted -Recurse -File -Filter $Name -ErrorAction SilentlyContinue |
        Where-Object { $_.FullName -match '[\\/]bin[\\/]x64[\\/]' -and $_.FullName -notmatch '[\\/]development[\\/]' })
    if ($candidates.Count -eq 0) {
        Warn "$Name was not present in the production x64 set"
        return $false
    }
    Copy-Managed $candidates[0].FullName $Name $Target $BackupRoot
    return $true
}

function Get-GpuSummary {
    $rows = @()
    try {
        $rows = @(Get-CimInstance Win32_VideoController -ErrorAction Stop | ForEach-Object {
            [pscustomobject]@{
                Name = [string]$_.Name
                DriverVersion = [string]$_.DriverVersion
            }
        })
    } catch {}
    return $rows
}

function Test-Rtx50([object[]]$Gpus) {
    foreach ($gpu in $Gpus) {
        if ($gpu.Name -match '(?i)NVIDIA.*RTX\s*50[0-9]{2}') { return $true }
    }
    return $false
}

function Restore-UpdateBackup([string]$BackupRoot, [string]$Target) {
    if (-not (Test-Path -LiteralPath $BackupRoot)) { return }
    Get-ChildItem -LiteralPath $BackupRoot -Force | ForEach-Object {
        Copy-Item -LiteralPath $_.FullName -Destination (Join-Path $Target $_.Name) -Recurse -Force
    }
}

Banner

if (-not [Environment]::Is64BitOperatingSystem) {
    throw "SECRET EMKO v2 requires 64-bit Windows."
}

if (Get-Process -ErrorAction SilentlyContinue | Where-Object { $_.ProcessName -like "FiveM*" -or $_.ProcessName -like "GTAProcess*" }) {
    throw "Close FiveM before installing SECRET EMKO."
}

$FiveMApp = Resolve-FiveMAppPath
if (-not $PluginsPath) { $PluginsPath = Join-Path $FiveMApp "plugins" }
$PluginsPath = [IO.Path]::GetFullPath($PluginsPath)

Step "Resolved FiveM Legacy installation"
Write-Host "   FiveM.app : $FiveMApp"
Write-Host "   plugins   : $PluginsPath"

$pathId = Get-PathId $PluginsPath
Ensure-Folder $GlobalStateRoot
$GlobalStateFile = Join-Path $GlobalStateRoot ("install-state-" + $pathId + ".json")

$priorState = $null
$localMarker = Join-Path $PluginsPath "SecretEMKO\install-state.json"
if (Test-Path -LiteralPath $localMarker) {
    try { $priorState = Get-Content -LiteralPath $localMarker -Raw | ConvertFrom-Json } catch {}
}
if (-not $priorState -and (Test-Path -LiteralPath $GlobalStateFile)) {
    try { $priorState = Get-Content -LiteralPath $GlobalStateFile -Raw | ConvertFrom-Json } catch {}
}

$managedExisting = $false
if ($priorState -and $priorState.product -eq $Product -and $priorState.plugins_path -eq $PluginsPath -and (Test-Path -LiteralPath $PluginsPath)) {
    $managedExisting = $true
}

$gpus = @(Get-GpuSummary)
$rtx50 = Test-Rtx50 $gpus
$resolvedMode = $Mode

if ($Mode -eq "Auto") {
    if ($managedExisting -and $priorState.install_mode) {
        if ([string]$priorState.install_mode -eq "full-neural") { $resolvedMode = "FullNeural" }
        else { $resolvedMode = "RPVisual" }
    }
    elseif ($ForceNeuralStack) {
        $resolvedMode = "FullNeural"
    }
    elseif ($rtx50 -and -not $NonInteractive) {
        Write-Host ""
        Write-Host "RTX 50-series detected." -ForegroundColor Cyan
        Write-Host "Choose installation mode:"
        Write-Host "  [1] RP Visual (recommended for multiplayer / unknown server policy)"
        Write-Host "      Signed standard ReShade + Main/Stream presets. No external ReShade add-ons."
        Write-Host "  [2] Full Neural"
        Write-Host "      ReShade Full Add-on + SECRET EMKO/RenoDX/DLSS 5. Use only where the server explicitly permits this stack."
        $choice = Read-Host "Mode [1]"
        $resolvedMode = if ($choice -eq "2") { "FullNeural" } else { "RPVisual" }
    }
    else {
        $resolvedMode = "RPVisual"
    }
}

if ($resolvedMode -eq "FullNeural" -and -not $rtx50 -and -not $ForceNeuralStack) {
    throw "Full Neural mode requires a detected GeForce RTX 50-series GPU. Use RPVisual on this system."
}

$neuralMode = $resolvedMode -eq "FullNeural"
$installMode = if ($neuralMode) { "full-neural" } else { "rp-visual" }

Step "Hardware / multiplayer mode"
if ($gpus.Count -gt 0) {
    foreach ($gpu in $gpus) {
        Write-Host ("   GPU: " + $gpu.Name + "  |  driver: " + $gpu.DriverVersion)
    }
} else {
    Warn "GPU could not be identified through Win32_VideoController."
}

if ($neuralMode) {
    if ($rtx50) { Ok "Full Neural mode selected on RTX 50-series hardware" }
    else { Warn "Full Neural was forced on unsupported/unverified hardware." }
    Warn "This mode requires ReShade Full Add-on Support. ReShade documents that build as singleplayer-oriented and warns it may cause bans in multiplayer."
    Warn "Use Full Neural only on servers/environments where this client add-on stack is explicitly permitted."
} else {
    Ok "RP Visual mode selected"
    Write-Host "   Uses the signed standard ReShade build and post-processing presets only."
    if (-not $rtx50) {
        Write-Host "   DLSS 5 3D-Guided Neural Rendering is not enabled on this GPU."
    }
}
Warn "FiveM servers can disallow client plugins. SECRET EMKO does not bypass server plugin policy, Pure Mode, anti-cheat or ReShade restrictions."

$originalPluginsBackup = $null
$createdFreshPlugins = $false
$rollbackOriginal = $false

if (-not $managedExisting) {
    $hasExistingContent = $false
    if (Test-Path -LiteralPath $PluginsPath) {
        $hasExistingContent = $null -ne (Get-ChildItem -LiteralPath $PluginsPath -Force -ErrorAction SilentlyContinue | Select-Object -First 1)
    }

    if ($hasExistingContent -and $ExistingPluginsMode -eq "Isolate") {
        $originalPluginsBackup = Join-Path $FiveMApp ("plugins.before-secret-emko." + $Stamp)
        Step "Isolating existing FiveM plugins"
        Move-Item -LiteralPath $PluginsPath -Destination $originalPluginsBackup
        Ensure-Folder $PluginsPath
        $createdFreshPlugins = $true
        $rollbackOriginal = $true
        Ok "Existing plugins preserved at: $originalPluginsBackup"

        $oldShaderRoot = Join-Path $originalPluginsBackup "reshade-shaders"
        if (Test-Path -LiteralPath $oldShaderRoot) {
            Copy-Item -LiteralPath $oldShaderRoot -Destination (Join-Path $PluginsPath "reshade-shaders") -Recurse -Force
            Ok "Existing ReShade shader library migrated; old add-ons and proxy DLLs remain isolated"
        }
    }
    elseif (-not (Test-Path -LiteralPath $PluginsPath)) {
        Ensure-Folder $PluginsPath
        $createdFreshPlugins = $true
        Ok "Created missing FiveM plugins folder"
    }
    elseif ($hasExistingContent) {
        Warn "Merge mode selected: existing plugins stay active. Conflicting injectors/add-ons remain the user's responsibility."
    }
}
else {
    Ok "Existing SECRET EMKO installation detected; updating in place"
    if ($priorState.original_plugins_backup) { $originalPluginsBackup = [string]$priorState.original_plugins_backup }
}

$StateDir = Join-Path $PluginsPath "SecretEMKO"
$Backup = Join-Path $StateDir "backups\$Stamp"
$LicenseDir = Join-Path $StateDir "licenses"
Ensure-Folder $StateDir
Ensure-Folder $LicenseDir
Ensure-Folder $Cache

try {
    Step "Checking/installing ReShade"
    Install-ReShadeHeadless $PluginsPath $neuralMode

    Step "Backing up active managed configuration"
    $reshadeIni = Join-Path $PluginsPath "ReShade.ini"
    $bridgeCfg = Join-Path $PluginsPath "dlss5-bridge.cfg"
    foreach ($name in @(
        "ReShade.ini",
        "dlss5-bridge.cfg",
        "SecretEMKO.addon64",
        "dlss5-bridge.addon64",
        "renodx-dlss5.addon64",
        "nvngx_dlssnr.dll",
        "nvngx_dlss.dll",
        "swapchain_override.addon64",
        "Secret_Emko_Main.ini",
        "Secret_Emko_Stream.ini"
    )) {
        Backup-IfExists (Join-Path $PluginsPath $name) $Backup
    }
    Ok "Update backup root: $Backup"

    Step "Installing SECRET EMKO package metadata"
    Copy-Item -LiteralPath (Join-Path $Root "THIRD_PARTY_NOTICES.md") -Destination (Join-Path $LicenseDir "THIRD_PARTY_NOTICES.md") -Force
    Copy-Item -LiteralPath (Join-Path $Root "LICENSE") -Destination (Join-Path $LicenseDir "SECRET_EMKO_LICENSE.txt") -Force
    if (Test-Path (Join-Path $Root "licenses")) {
        Copy-Item (Join-Path $Root "licenses\*") -Destination $LicenseDir -Recurse -Force
    }

    $managed = New-Object System.Collections.Generic.List[string]

    if ($neuralMode) {
        Step "Installing SECRET EMKO neural add-on stack"
        Copy-Managed (Join-Path $Root "SecretEMKO.addon64") "SecretEMKO.addon64" $PluginsPath $Backup
        [void]$managed.Add("SecretEMKO.addon64")
        Step "Installing neural runtime bridge"
        Copy-Managed (Join-Path $Root "dlss5-bridge.addon64") "dlss5-bridge.addon64" $PluginsPath $Backup
        [void]$managed.Add("dlss5-bridge.addon64")

        Step "Downloading RenoDX DLSS 5 v4.70"
        $renodxZip = Join-Path $Cache "renodx-dlss5_4.70.zip"
        Download-Verified $Urls.RenoDX $renodxZip $Hashes.RenoDX
        $renodxExtract = Join-Path $Cache "renodx-dlss5_4.70"
        Expand-Fresh $renodxZip $renodxExtract
        $consumer = Find-RequiredFile $renodxExtract "renodx-dlss5*.addon64"
        Copy-Managed $consumer "renodx-dlss5.addon64" $PluginsPath $Backup
        [void]$managed.Add("renodx-dlss5.addon64")

        Step "Downloading NVIDIA DLSS Neural Rendering 310.8.0"
        $nrZip = Join-Path $Cache "nvngx_dlssnr_310.8.0.zip"
        Download-Verified $Urls.DlssNr $nrZip $Hashes.DlssNr
        $nrExtract = Join-Path $Cache "nvngx_dlssnr_310.8.0"
        Expand-Fresh $nrZip $nrExtract
        $nrDll = Find-RequiredFile $nrExtract "nvngx_dlssnr.dll" $Rtx50NrDllHash
        Copy-Managed $nrDll "nvngx_dlssnr.dll" $PluginsPath $Backup
        [void]$managed.Add("nvngx_dlssnr.dll")

        Step "Downloading NVIDIA DLSS Super Resolution 310.9.1"
        $srZip = Join-Path $Cache "nvngx_dlss_310.9.1.zip"
        Download-Verified $Urls.DlssSr $srZip $Hashes.DlssSr
        $srExtract = Join-Path $Cache "nvngx_dlss_310.9.1"
        Expand-Fresh $srZip $srExtract
        $srDll = Find-RequiredFile $srExtract "nvngx_dlss.dll"
        Copy-Managed $srDll "nvngx_dlss.dll" $PluginsPath $Backup
        [void]$managed.Add("nvngx_dlss.dll")

        if (-not $SkipStreamline) {
            Step "Downloading NVIDIA Streamline 2.14.1"
            $slZip = Join-Path $Cache "streamline-sdk-v2.14.1.zip"
            Download-Verified $Urls.Streamline $slZip $Hashes.Streamline
            $slExtract = Join-Path $Cache "streamline-sdk-v2.14.1"
            Expand-Fresh $slZip $slExtract

            foreach ($name in @(
                "sl.interposer.dll",
                "sl.common.dll",
                "sl.dlss.dll",
                "sl.dlss_g.dll",
                "sl.dlss_nr.dll",
                "sl.reflex.dll",
                "sl.pcl.dll",
                "sl.nis.dll",
                "nvngx_dlssg.dll"
            )) {
                if (Copy-OptionalStreamlineFile $slExtract $name $PluginsPath $Backup) {
                    [void]$managed.Add($name)
                }
            }

            foreach ($notice in @("license.txt","3rd-party-licenses.md")) {
                $found = @(Get-ChildItem -LiteralPath $slExtract -Recurse -File -Filter $notice -ErrorAction SilentlyContinue | Select-Object -First 1)
                if ($found.Count -gt 0) {
                    Copy-Item -LiteralPath $found[0].FullName -Destination (Join-Path $LicenseDir ("NVIDIA-Streamline-" + $notice)) -Force
                }
            }
        }

        Step "Writing FiveM / RenoDX quality defaults"
        Set-IniValue $reshadeIni "ADDON" "AddonPath" "."
        Set-IniValue $reshadeIni "RenoDX.DLSS5" "EnableHooks" "2"
        Set-IniValue $reshadeIni "RenoDX.DLSS5" "NeuralUplift" "1"
        Set-IniValue $reshadeIni "RenoDX.DLSS5" "NREnableUpscaling" "0"
        Set-IniValue $reshadeIni "RenoDX.DLSS5" "NRPreset" "0"
        Set-IniValue $reshadeIni "RenoDX.DLSS5" "NRStyle" "1"
        Set-IniValue $reshadeIni "RenoDX.DLSS5" "NRIntensity" "1.20"
        Set-IniValue $reshadeIni "RenoDX.DLSS5" "NRGlobalTone" "1.05"
        Set-IniValue $reshadeIni "RenoDX.DLSS5" "NRLocalTone" "1.05"
        Set-IniValue $reshadeIni "RenoDX.DLSS5" "NRLocalStructure" "1.35"
        Set-IniValue $reshadeIni "RenoDX.DLSS5" "NRSkinStructure" "1.00"
        Set-IniValue $reshadeIni "RenoDX.DLSS5" "NRAutoMask" "1"
        Set-IniValue $reshadeIni "RenoDX.DLSS5" "NRUICorrection" "1"
        Set-IniValue $reshadeIni "RenoDX.DLSS5" "NRDiffuseWhiteNits" "203"
        Set-IniValue $reshadeIni "RenoDX.DLSS5" "NRPaperWhiteScale" "1.0"
        Set-IniValue $reshadeIni "RenoDX.DLSS5" "NRTransferStrength" "1.0"
        Set-IniValue $reshadeIni "RenoDX.DLSS5" "NRColorStrength" "0.95"
        Set-IniValue $reshadeIni "RenoDX.DLSS5" "NRDepthMode" "0"
        Set-IniValue $reshadeIni "RenoDX.DLSS5" "NRMVecScaleX" "1.0"
        Set-IniValue $reshadeIni "RenoDX.DLSS5" "NRMVecScaleY" "1.0"
        Set-IniValue $reshadeIni "RenoDX.DLSS5" "NRToggleKey" "0"
        Set-IniValue $reshadeIni "RenoDX.DLSS5" "NRScreenshotKey" "0"
        Set-IniValue $reshadeIni "SecretEMKO" "Profile" "3"
        Set-IniValue $reshadeIni "SecretEMKO" "FrameGenerationPolicy" "0"
        Set-IniValue $reshadeIni "SecretEMKO" "InstallMode" "full-neural"

        Copy-Item -LiteralPath (Join-Path $Root "config\dlss5-bridge.cfg") -Destination $bridgeCfg -Force
        [void]$managed.Add("dlss5-bridge.cfg")
        Ok "Enhanced profile + synthetic D3D11 bridge configured"
    }
    else {
        Step "Configuring RP Visual mode"
        Set-IniValue $reshadeIni "SecretEMKO" "InstallMode" "rp-visual"
        Ok "Standard ReShade visual stack selected; external add-ons and Neural Rendering remain inactive"
    }

    Step "Installing/updating integrated ReShade presets, shaders and official add-ons"
    $reshadeContentTool = Join-Path $Root "tools\Update-ReShadeContent.ps1"
    if (-not (Test-Path -LiteralPath $reshadeContentTool)) {
        throw "Missing integrated ReShade updater: $reshadeContentTool"
    }
    if ($neuralMode) {
        & $reshadeContentTool -TargetDirectory $PluginsPath -Architecture 64
        if (-not $managed.Contains("swapchain_override.addon64")) { [void]$managed.Add("swapchain_override.addon64") }
    }
    else {
        & $reshadeContentTool -TargetDirectory $PluginsPath -Architecture 64 -SkipAddon -SkipCoreCheck
    }
    Ok "ReShade Main/Stream content updated"

    foreach ($name in @("Secret_Emko_Main.ini","Secret_Emko_Stream.ini")) {
        if (-not $managed.Contains($name)) { [void]$managed.Add($name) }
    }

    Step "Writing install state"
    $state = [ordered]@{
        product = $Product
        version = $Version
        installed_at = (Get-Date).ToUniversalTime().ToString("o")
        fivem_app_path = $FiveMApp
        plugins_path = $PluginsPath
        install_mode = $installMode
        gpu = @($gpus)
        original_plugins_backup = $originalPluginsBackup
        existing_plugins_mode = $ExistingPluginsMode
        created_fresh_plugins = $createdFreshPlugins
        update_backup_path = $Backup
        managed_files = @($managed)
        reshade_mode = (Get-ReShadeMode $PluginsPath)
    }
    $json = $state | ConvertTo-Json -Depth 6
    $json | Set-Content -LiteralPath $GlobalStateFile -Encoding UTF8
    $json | Set-Content -LiteralPath (Join-Path $StateDir "install-state.json") -Encoding UTF8
    $rollbackOriginal = $false

    Step "Verification"
    $required = New-Object System.Collections.Generic.List[string]
    foreach ($name in @(
        "dxgi.dll",
        "ReShade.ini",
        "Secret_Emko_Main.ini",
        "Secret_Emko_Stream.ini"
    )) { [void]$required.Add($name) }

    if ($neuralMode) {
        foreach ($name in @(
            "SecretEMKO.addon64",
            "swapchain_override.addon64",
            "dlss5-bridge.addon64",
            "renodx-dlss5.addon64",
            "nvngx_dlssnr.dll",
            "nvngx_dlss.dll",
            "dlss5-bridge.cfg"
        )) { [void]$required.Add($name) }
    }

    $missing = @()
    foreach ($name in $required) {
        $p = Join-Path $PluginsPath $name
        if (Test-Path -LiteralPath $p) {
            $size = (Get-Item -LiteralPath $p).Length
            Write-Host ("   [OK] {0,-28} {1,12:N0} bytes" -f $name,$size) -ForegroundColor Green
        } else {
            $missing += $name
            Write-Host "   [MISSING] $name" -ForegroundColor Red
        }
    }
    if ($missing.Count -gt 0) { throw "Installation incomplete: $($missing -join ', ')" }

    Write-Host ""
    Write-Host "================================================================" -ForegroundColor DarkGray
    Write-Host " SECRET EMKO installation complete." -ForegroundColor Green
    Write-Host (" Mode: " + $installMode) -ForegroundColor White
    Write-Host (" Active plugins: " + $PluginsPath) -ForegroundColor White
    if ($originalPluginsBackup) {
        Write-Host (" Previous plugins preserved: " + $originalPluginsBackup) -ForegroundColor Gray
    }
    if ($neuralMode) {
        Write-Host " Full Neural uses ReShade Full Add-on Support: use only where the server explicitly permits it." -ForegroundColor Yellow
        Write-Host " Frame Generation remains gated until the FiveM FG signal/pacing path is validated." -ForegroundColor Yellow
    } else {
        Write-Host " RP Visual uses standard ReShade only; individual server plugin policy can still block it." -ForegroundColor Yellow
    }
    Write-Host "================================================================" -ForegroundColor DarkGray
}
catch {
    $message = $_.Exception.Message
    Warn "Installation failed: $message"

    if ($rollbackOriginal -and $originalPluginsBackup -and (Test-Path -LiteralPath $originalPluginsBackup)) {
        try {
            $failedSnapshot = Join-Path $FiveMApp ("plugins.secret-emko-failed." + $Stamp)
            if (Test-Path -LiteralPath $PluginsPath) {
                Move-Item -LiteralPath $PluginsPath -Destination $failedSnapshot
                Warn "Failed SECRET EMKO attempt preserved at: $failedSnapshot"
            }
            Move-Item -LiteralPath $originalPluginsBackup -Destination $PluginsPath
            Ok "Original plugins folder restored automatically"
        }
        catch {
            Warn "Automatic rollback also failed. Original backup remains at: $originalPluginsBackup"
        }
    }
    elseif ($managedExisting) {
        try {
            Restore-UpdateBackup $Backup $PluginsPath
            Warn "Managed files from the pre-update backup were restored where possible."
        } catch {}
    }

    throw
}
