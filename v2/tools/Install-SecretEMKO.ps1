[CmdletBinding()]
param(
    [string]$PluginsPath = "",
    [ValidateSet("Auto","FullNeural","VisualOnly")]
    [string]$Mode = "Auto",
    [switch]$SkipStreamline,
    [switch]$Force,
    [switch]$AcceptMultiplayerAddonRisk
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest
$ProgressPreference = "SilentlyContinue"
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
if ((Split-Path -Leaf $Root) -ieq "tools") { $Root = Split-Path -Parent $Root }
$ToolRoot = Join-Path $Root "tools"
$Cache = Join-Path $env:LOCALAPPDATA "SecretEMKO\cache"
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
    Write-Host "===============================================================" -ForegroundColor DarkGray
    Write-Host " SECRET EMKO  //  NEURAL GRAPHICS v2" -ForegroundColor Cyan
    Write-Host " Universal FiveM clean-room installer" -ForegroundColor Gray
    Write-Host "===============================================================" -ForegroundColor DarkGray
}
function Step([string]$Text) { Write-Host ""; Write-Host ">> $Text" -ForegroundColor Cyan }
function Ok([string]$Text) { Write-Host "   [OK] $Text" -ForegroundColor Green }
function Warn([string]$Text) { Write-Host "   [!]  $Text" -ForegroundColor Yellow }
function Ensure-Folder([string]$Path) { if (-not (Test-Path -LiteralPath $Path)) { New-Item -ItemType Directory -Path $Path -Force | Out-Null } }

function Download-Verified([string]$Url, [string]$Path, [string]$ExpectedHash) {
    Ensure-Folder (Split-Path -Parent $Path)
    if (Test-Path -LiteralPath $Path) {
        if ((Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash -ieq $ExpectedHash) { Ok "$(Split-Path -Leaf $Path) cached + verified"; return }
        Remove-Item -LiteralPath $Path -Force
    }
    $partial = $Path + ".partial"
    for ($attempt = 1; $attempt -le 3; $attempt++) {
        try {
            Remove-Item -LiteralPath $partial -Force -ErrorAction SilentlyContinue
            Write-Host "   Downloading $(Split-Path -Leaf $Path) (attempt $attempt/3)..."
            Invoke-WebRequest -UseBasicParsing -Uri $Url -OutFile $partial -Headers @{ "User-Agent" = "SecretEMKO-v2" }
            $actual = (Get-FileHash -LiteralPath $partial -Algorithm SHA256).Hash
            if ($actual -ine $ExpectedHash) { throw "SHA256 mismatch. Expected $ExpectedHash, got $actual" }
            Move-Item -LiteralPath $partial -Destination $Path -Force
            Ok "$(Split-Path -Leaf $Path) verified"
            return
        } catch {
            Remove-Item -LiteralPath $partial -Force -ErrorAction SilentlyContinue
            if ($attempt -eq 3) { throw }
            Start-Sleep -Seconds (2 * $attempt)
        }
    }
}
function Expand-Fresh([string]$Zip, [string]$Dest) {
    if (Test-Path -LiteralPath $Dest) { Remove-Item -LiteralPath $Dest -Recurse -Force }
    Ensure-Folder $Dest
    Expand-Archive -LiteralPath $Zip -DestinationPath $Dest -Force
}
function Find-RequiredFile([string]$RootPath, [string]$Name, [string]$Hash = "") {
    $all = @(Get-ChildItem -LiteralPath $RootPath -Recurse -File -Filter $Name -ErrorAction SilentlyContinue)
    if ($Hash) {
        foreach ($f in $all) { if ((Get-FileHash -LiteralPath $f.FullName -Algorithm SHA256).Hash -ieq $Hash) { return $f.FullName } }
        throw "$Name with required SHA256 $Hash was not found."
    }
    if ($all.Count -eq 0) { throw "$Name was not found in $RootPath" }
    return $all[0].FullName
}
function Backup-IfExists([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path)) { return }
    Ensure-Folder $Backup
    Copy-Item -LiteralPath $Path -Destination (Join-Path $Backup (Split-Path -Leaf $Path)) -Force
}
function Copy-Managed([string]$Source, [string]$Name) {
    $dest = Join-Path $script:PluginsPath $Name
    Backup-IfExists $dest
    Copy-Item -LiteralPath $Source -Destination $dest -Force
    Ok $Name
}
function Copy-OptionalStreamlineFile([string]$Extracted, [string]$Name) {
    $candidate = Get-ChildItem -LiteralPath $Extracted -Recurse -File -Filter $Name -ErrorAction SilentlyContinue |
        Where-Object { $_.FullName -match '[\\/]bin[\\/]x64[\\/]' -and $_.FullName -notmatch '[\\/]development[\\/]' } |
        Select-Object -First 1
    if ($candidate) { Copy-Managed $candidate.FullName $Name } else { Warn "$Name was not present in the production x64 set" }
}
function Set-IniValue([string]$Path,[string]$Section,[string]$Key,[string]$Value) {
    $lines = New-Object System.Collections.Generic.List[string]
    if (Test-Path -LiteralPath $Path) { foreach ($line in Get-Content -LiteralPath $Path) { [void]$lines.Add($line) } }
    $header = "[$Section]"; $start = -1
    for ($i=0; $i -lt $lines.Count; $i++) { if ($lines[$i].Trim() -ieq $header) { $start=$i; break } }
    if ($start -lt 0) {
        if ($lines.Count -gt 0 -and $lines[$lines.Count-1].Trim()) { [void]$lines.Add("") }
        [void]$lines.Add($header); [void]$lines.Add("$Key=$Value"); Set-Content -LiteralPath $Path -Value $lines -Encoding UTF8; return
    }
    $end=$lines.Count
    for ($i=$start+1; $i -lt $lines.Count; $i++) { if ($lines[$i].Trim() -match '^\[.+\]$') { $end=$i; break } }
    for ($i=$start+1; $i -lt $end; $i++) {
        if ($lines[$i] -match ("^\s*" + [regex]::Escape($Key) + "\s*=")) { $lines[$i]="$Key=$Value"; Set-Content -LiteralPath $Path -Value $lines -Encoding UTF8; return }
    }
    $lines.Insert($start+1,"$Key=$Value"); Set-Content -LiteralPath $Path -Value $lines -Encoding UTF8
}
function Test-ReShadeVariant([string]$DllPath,[string]$Variant) {
    if (-not (Test-Path -LiteralPath $DllPath)) { return $false }
    try {
        if ((Get-Item -LiteralPath $DllPath).VersionInfo.ProductName -notmatch "ReShade") { return $false }
        $addon = [Text.Encoding]::ASCII.GetString([IO.File]::ReadAllBytes($DllPath)).Contains("ReShadeRegisterAddon")
        if ($Variant -eq "Addon") { return $addon }
        return -not $addon
    } catch { return $false }
}
function Get-GpuProfile {
    $names = @()
    try { $names = @(Get-CimInstance Win32_VideoController -ErrorAction Stop | ForEach-Object { $_.Name } | Where-Object { $_ }) } catch {}
    $joined = $names -join " | "
    [pscustomobject]@{
        Names = $names
        Description = $(if ($joined) { $joined } else { "Unknown GPU" })
        Nvidia = $joined -match '(?i)NVIDIA|GeForce'
        Rtx50 = $joined -match '(?i)RTX\s*50[0-9]{2}'
    }
}
function Confirm-FullAddonRisk {
    if ($AcceptMultiplayerAddonRisk) { return }
    Write-Host ""
    Write-Host "MULTIPLAYER NOTICE" -ForegroundColor Yellow
    Write-Host "Full Neural mode requires ReShade Full Add-on Support and native add-ons." -ForegroundColor Yellow
    Write-Host "FiveM servers can disallow plugins, and ReShade labels its Full Add-on build as intended for single-player use." -ForegroundColor Yellow
    Write-Host "SECRET EMKO cannot guarantee acceptance on every RP server." -ForegroundColor Yellow
    if (-not [Environment]::UserInteractive) { throw "Use -AcceptMultiplayerAddonRisk for unattended FullNeural installation." }
    $answer = Read-Host "Continue with Full Neural mode? [y/N]"
    if ($answer -notmatch '^(?i)y(es)?$|^(?i)j(a)?$') { throw "Installation cancelled before enabling Full Add-on Support." }
}
function Test-FreeSpace([string]$Path,[long]$MinimumBytes) {
    $root = [IO.Path]::GetPathRoot([IO.Path]::GetFullPath($Path))
    $drive = New-Object IO.DriveInfo($root)
    if ($drive.AvailableFreeSpace -lt $MinimumBytes) { throw "At least $([math]::Round($MinimumBytes/1GB,1)) GB free space is required on $root." }
}

Banner

$running = @(Get-Process -ErrorAction SilentlyContinue | Where-Object { $_.ProcessName -like "FiveM*" -or $_.ProcessName -like "GTAProcess*" })
if ($running.Count -gt 0) { throw "Close FiveM/GTA before installing SECRET EMKO." }

$gpu = Get-GpuProfile
Step "Hardware profile"
Write-Host "   GPU: $($gpu.Description)"
$ResolvedMode = $Mode
if ($Mode -eq "Auto") { $ResolvedMode = if ($gpu.Rtx50) { "FullNeural" } else { "VisualOnly" } }
if ($ResolvedMode -eq "FullNeural" -and -not $gpu.Rtx50 -and -not $Force) {
    throw "FullNeural is validated for RTX 50-class hardware in this release. Use -Mode VisualOnly, or -Force only for deliberate testing."
}
if ($ResolvedMode -eq "FullNeural") { Confirm-FullAddonRisk }
Ok "Install mode: $ResolvedMode"
$CoreVariant = if ($ResolvedMode -eq "FullNeural") { "Addon" } else { "Standard" }

$prepareTool = Join-Path $ToolRoot "Prepare-FiveMPlugins.ps1"
if (-not (Test-Path -LiteralPath $prepareTool)) { throw "Missing installer component: $prepareTool" }

Step "Detecting FiveM and preparing an isolated plugins directory"
$layoutJson = if ($PluginsPath) { & $prepareTool -PluginsPath $PluginsPath } else { & $prepareTool }
$layout = $layoutJson | ConvertFrom-Json
$script:PluginsPath = [string]$layout.plugins_path
$FiveMAppRoot = [string]$layout.fivem_app_root
$OriginalPluginsBackup = [string]$layout.original_plugins_backup_path

function Restore-CleanRoomOnFailure {
    if ($layout.isolated_existing_plugins -and $OriginalPluginsBackup -and (Test-Path -LiteralPath $OriginalPluginsBackup)) {
        $failed = Join-Path $FiveMAppRoot ("plugins.SecretEMKO-failed-" + (Get-Date -Format "yyyyMMdd-HHmmss"))
        if (Test-Path -LiteralPath $script:PluginsPath) { Move-Item -LiteralPath $script:PluginsPath -Destination $failed -Force }
        Move-Item -LiteralPath $OriginalPluginsBackup -Destination $script:PluginsPath -Force
        Warn "Installation failed; original plugins were automatically restored."
        Warn "Incomplete SECRET EMKO files were preserved at: $failed"
    }
}

try {
    if ($layout.isolated_existing_plugins) {
        Ok "Existing plugins preserved without modification"
        Write-Host "      $OriginalPluginsBackup"
    }
    elseif ($layout.existing_secret_emko) { Ok "Existing SECRET EMKO installation detected; updating in place" }
    else { Ok "Clean plugins directory ready: $script:PluginsPath" }

    Test-FreeSpace $script:PluginsPath 2GB
    Ensure-Folder $Cache

    $StateDir = Join-Path $script:PluginsPath "SecretEMKO"
    $Backup = Join-Path $StateDir "backups\$Stamp"
    $LicenseDir = Join-Path $StateDir "licenses"
    Ensure-Folder $StateDir
    Ensure-Folder $LicenseDir

    # If an old plugins directory was isolated, reuse only a matching official ReShade module.
    if ($OriginalPluginsBackup -and (Test-Path -LiteralPath $OriginalPluginsBackup)) {
        $legacyDxgi = Join-Path $OriginalPluginsBackup "dxgi.dll"
        if (Test-ReShadeVariant $legacyDxgi $CoreVariant) {
            Copy-Item -LiteralPath $legacyDxgi -Destination (Join-Path $script:PluginsPath "dxgi.dll") -Force
            Ok "Reused compatible ReShade $CoreVariant module from preserved plugins"
        }
    }

    $reshadeTool = Join-Path $ToolRoot "Update-ReShadeContent.ps1"
    Step "Installing ReShade core, presets and shader content"
    $reshadeArgs = @{
        TargetDirectory = $script:PluginsPath
        Architecture = "64"
        CoreVariant = $CoreVariant
    }
    if ($OriginalPluginsBackup) { $reshadeArgs.LegacyContentRoot = $OriginalPluginsBackup }
    if ($ResolvedMode -eq "VisualOnly") { $reshadeArgs.SkipAddon = $true }
    & $reshadeTool @reshadeArgs

    if ($ResolvedMode -eq "FullNeural") {
        Step "Installing SECRET EMKO neural add-ons"
        Copy-Managed (Join-Path $Root "SecretEMKO.addon64") "SecretEMKO.addon64"
        Copy-Managed (Join-Path $Root "dlss5-bridge.addon64") "dlss5-bridge.addon64"

        Copy-Item -LiteralPath (Join-Path $Root "THIRD_PARTY_NOTICES.md") -Destination (Join-Path $LicenseDir "THIRD_PARTY_NOTICES.md") -Force
        Copy-Item -LiteralPath (Join-Path $Root "LICENSE") -Destination (Join-Path $LicenseDir "SECRET_EMKO_LICENSE.txt") -Force
        if (Test-Path (Join-Path $Root "licenses")) { Copy-Item (Join-Path $Root "licenses\*") -Destination $LicenseDir -Recurse -Force }

        Step "Downloading verified neural runtimes"
        $renodxZip = Join-Path $Cache "renodx-dlss5_4.70.zip"
        Download-Verified $Urls.RenoDX $renodxZip $Hashes.RenoDX
        $renodxExtract = Join-Path $Cache "renodx-dlss5_4.70"
        Expand-Fresh $renodxZip $renodxExtract
        Copy-Managed (Find-RequiredFile $renodxExtract "renodx-dlss5*.addon64") "renodx-dlss5.addon64"

        $nrZip = Join-Path $Cache "nvngx_dlssnr_310.8.0.zip"
        Download-Verified $Urls.DlssNr $nrZip $Hashes.DlssNr
        $nrExtract = Join-Path $Cache "nvngx_dlssnr_310.8.0"
        Expand-Fresh $nrZip $nrExtract
        Copy-Managed (Find-RequiredFile $nrExtract "nvngx_dlssnr.dll" $Rtx50NrDllHash) "nvngx_dlssnr.dll"

        $srZip = Join-Path $Cache "nvngx_dlss_310.9.1.zip"
        Download-Verified $Urls.DlssSr $srZip $Hashes.DlssSr
        $srExtract = Join-Path $Cache "nvngx_dlss_310.9.1"
        Expand-Fresh $srZip $srExtract
        Copy-Managed (Find-RequiredFile $srExtract "nvngx_dlss.dll") "nvngx_dlss.dll"

        if (-not $SkipStreamline) {
            $slZip = Join-Path $Cache "streamline-sdk-v2.14.1.zip"
            Download-Verified $Urls.Streamline $slZip $Hashes.Streamline
            $slExtract = Join-Path $Cache "streamline-sdk-v2.14.1"
            Expand-Fresh $slZip $slExtract
            foreach ($name in @("sl.interposer.dll","sl.common.dll","sl.dlss.dll","sl.dlss_g.dll","sl.dlss_nr.dll","sl.reflex.dll","sl.pcl.dll","sl.nis.dll","nvngx_dlssg.dll")) {
                Copy-OptionalStreamlineFile $slExtract $name
            }
        }

        Step "Writing neural defaults"
        $reshadeIni = Join-Path $script:PluginsPath "ReShade.ini"
        foreach ($kv in @(
            @("EnableHooks","2"), @("NeuralUplift","1"), @("NREnableUpscaling","0"), @("NRPreset","0"),
            @("NRStyle","1"), @("NRIntensity","1.20"), @("NRGlobalTone","1.05"), @("NRLocalTone","1.05"),
            @("NRLocalStructure","1.35"), @("NRSkinStructure","1.00"), @("NRAutoMask","1"), @("NRUICorrection","1"),
            @("NRDiffuseWhiteNits","203"), @("NRPaperWhiteScale","1.0"), @("NRTransferStrength","1.0"),
            @("NRColorStrength","0.95"), @("NRDepthMode","0"), @("NRMVecScaleX","1.0"), @("NRMVecScaleY","1.0")
        )) { Set-IniValue $reshadeIni "RenoDX.DLSS5" $kv[0] $kv[1] }

        Set-IniValue $reshadeIni "SecretEMKO" "Profile" "3"
        Set-IniValue $reshadeIni "SecretEMKO" "FrameGenerationPolicy" "0"
        Copy-Item -LiteralPath (Join-Path $Root "config\dlss5-bridge.cfg") -Destination (Join-Path $script:PluginsPath "dlss5-bridge.cfg") -Force
    }

    $managed = New-Object System.Collections.Generic.List[string]
    foreach ($n in @("dxgi.dll","ReShade.ini","Secret_Emko_Main.ini","Secret_Emko_Stream.ini")) { [void]$managed.Add($n) }
    if ($ResolvedMode -eq "FullNeural") {
        foreach ($n in @(
            "SecretEMKO.addon64","dlss5-bridge.addon64","renodx-dlss5.addon64","nvngx_dlssnr.dll","nvngx_dlss.dll",
            "sl.interposer.dll","sl.common.dll","sl.dlss.dll","sl.dlss_g.dll","sl.dlss_nr.dll","sl.reflex.dll","sl.pcl.dll","sl.nis.dll",
            "nvngx_dlssg.dll","dlss5-bridge.cfg","swapchain_override.addon64"
        )) { [void]$managed.Add($n) }
    }

    Step "Writing install state"
    [ordered]@{
        product = "SECRET EMKO Neural Graphics"
        version = "2.0.0-rc2"
        installed_at = (Get-Date).ToString("o")
        install_mode = $ResolvedMode
        requested_mode = $Mode
        gpu = $gpu.Description
        plugins_path = $script:PluginsPath
        fivem_app_root = $FiveMAppRoot
        original_plugins_backup_path = $OriginalPluginsBackup
        clean_room_install = [bool]$layout.isolated_existing_plugins
        managed_files = @($managed)
        reshade_variant = $CoreVariant
        legacy_shader_fallback = $OriginalPluginsBackup
        backup_path = $Backup
    } | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $StateDir "install-state.json") -Encoding UTF8

    Step "Verification"
    $required = @("dxgi.dll","ReShade.ini","Secret_Emko_Main.ini","Secret_Emko_Stream.ini")
    if ($ResolvedMode -eq "FullNeural") {
        $required += @("SecretEMKO.addon64","dlss5-bridge.addon64","renodx-dlss5.addon64","nvngx_dlssnr.dll","nvngx_dlss.dll","swapchain_override.addon64")
    }
    $missing = @()
    foreach ($name in $required) {
        $p = Join-Path $script:PluginsPath $name
        if (Test-Path -LiteralPath $p) { Write-Host ("   [OK] {0}" -f $name) -ForegroundColor Green }
        else { $missing += $name; Write-Host "   [MISSING] $name" -ForegroundColor Red }
    }
    if ($missing.Count -gt 0) { throw "Installation incomplete: $($missing -join ', ')" }
}
catch {
    Restore-CleanRoomOnFailure
    throw
}

Write-Host ""
Write-Host "===============================================================" -ForegroundColor DarkGray
Write-Host " SECRET EMKO installation complete." -ForegroundColor Green
Write-Host " Mode: $ResolvedMode" -ForegroundColor White
Write-Host " Plugins: $script:PluginsPath" -ForegroundColor White
if ($OriginalPluginsBackup) { Write-Host " Previous plugins preserved: $OriginalPluginsBackup" -ForegroundColor Gray }
if ($ResolvedMode -eq "VisualOnly") {
    Write-Host " VisualOnly avoids neural/add-on injection and is the broad compatibility mode." -ForegroundColor Gray
} else {
    Write-Host " FullNeural uses native add-ons; server plugin policy can still prevent use." -ForegroundColor Yellow
}
Write-Host "===============================================================" -ForegroundColor DarkGray
