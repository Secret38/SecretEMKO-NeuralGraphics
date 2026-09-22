[CmdletBinding()]
param(
    [string]$PluginsPath = "$env:LOCALAPPDATA\FiveM\FiveM.app\plugins",
    [ValidateSet("Auto","Latest","Compatibility")]
    [string]$ConsumerChannel = "Auto",
    [switch]$InstallStreamlinePreview,
    [switch]$Force
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest
$ProgressPreference = "SilentlyContinue"

$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
if ((Split-Path -Leaf $Root) -ieq "tools") { $Root = Split-Path -Parent $Root }

$Cache = Join-Path $env:LOCALAPPDATA "SecretEMKO\cache"
$Stamp = Get-Date -Format "yyyyMMdd-HHmmss"
$StateDir = Join-Path $PluginsPath "SecretEMKO"
$Backup = Join-Path $StateDir "backups\$Stamp"
$LicenseDir = Join-Path $StateDir "licenses"

$Urls = @{
    RenoDXLatest = "https://github.com/RankFTW/rhi-repo/releases/download/renodx-dlss5-6.5.3/renodx-dlss5_6.5.3.zip"
    RenoDXCompatibility = "https://github.com/RankFTW/rhi-repo/releases/download/renodx-dlss5-4.55/renodx-dlss5_4.55.zip"
    DlssNr = "https://github.com/RankFTW/rhi-repo/releases/download/dlssnr-310.8.0/nvngx_dlssnr_310.8.0.zip"
    DlssSr = "https://github.com/RankFTW/rhi-repo/releases/download/dlss-310.9.1/nvngx_dlss_310.9.1.zip"
    Streamline = "https://github.com/NVIDIA-RTX/Streamline/releases/download/v2.14.1/streamline-sdk-v2.14.1.zip"
    ReShade = "https://reshade.me/downloads/ReShade_Setup_6.8.0_Addon.exe"
}
$Hashes = @{
    RenoDXLatest = "553B1619B9E5DDFBCB4EBC7F2F3BFFFF9256A48A25B988F4817F5C63F4CAA1DE"
    RenoDXCompatibility = "15481C492DB76682E9A88917E7F78897351ECF088BFAE9BCA74A0C5B74DDD033"
    DlssNr = "388C0A7912E15EC911B9C9E11A692142B11FE387DDF2B637D8C358138FFFB3AC"
    DlssSr = "AABA83B288BD145C3808E8D7A0BA03CC8C8676D18AD984B1BFA6563046A3BA37"
    Streamline = "92C4D954631A1710DA86CA3FA8D5034F2B9503838C95FC4AE977AE149319781B"
}
$Rtx50NrDllHash = "E16BCF15E16E13F527491CDF7845B2FE6521A738D8F7C9C721866A8496E1FC8E"

function Banner {
    Write-Host ""
    Write-Host "===============================================================" -ForegroundColor DarkGray
    Write-Host " SECRET EMKO  //  NEURAL GRAPHICS v2" -ForegroundColor Cyan
    Write-Host " FiveM GTA V Legacy  |  RenoDX + ReShade architecture" -ForegroundColor Gray
    Write-Host "===============================================================" -ForegroundColor DarkGray
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
        Invoke-WebRequest -UseBasicParsing -Uri $Url -OutFile $Path
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

function Backup-IfExists([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path)) { return }
    Ensure-Folder $Backup
    $dest = Join-Path $Backup (Split-Path -Leaf $Path)
    Copy-Item -LiteralPath $Path -Destination $dest -Force
}

function Copy-Managed([string]$Source, [string]$Name) {
    $dest = Join-Path $PluginsPath $Name
    Backup-IfExists $dest
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
        if ($lines[$i] -match "^\s*$([regex]::Escape($Key))\s*=") {
            $lines[$i]="$Key=$Value"
            Set-Content -LiteralPath $Path -Value $lines -Encoding UTF8
            return
        }
    }

    $lines.Insert($start+1,"$Key=$Value")
    Set-Content -LiteralPath $Path -Value $lines -Encoding UTF8
}

function Remove-IniKey([string]$Path,[string]$Section,[string]$Key) {
    if (-not (Test-Path -LiteralPath $Path)) { return }
    $lines = New-Object System.Collections.Generic.List[string]
    foreach ($line in Get-Content -LiteralPath $Path) { [void]$lines.Add($line) }

    $start = -1
    for ($i=0; $i -lt $lines.Count; $i++) {
        if ($lines[$i].Trim() -ieq "[$Section]") { $start=$i; break }
    }
    if ($start -lt 0) { return }

    $end=$lines.Count
    for ($i=$start+1; $i -lt $lines.Count; $i++) {
        if ($lines[$i].Trim() -match '^\[.+\]
function Copy-OptionalStreamlineFile([string]$Extracted, [string]$Name) {
    $candidates = @(Get-ChildItem -LiteralPath $Extracted -Recurse -File -Filter $Name -ErrorAction SilentlyContinue |
        Where-Object { $_.FullName -match '[\\/]bin[\\/]x64[\\/]' -and $_.FullName -notmatch '[\\/]development[\\/]' })
    if ($candidates.Count -eq 0) {
        Warn "$Name was not present in the production x64 set"
        return
    }
    Copy-Managed $candidates[0].FullName $Name
}

Banner

if (Get-Process -ErrorAction SilentlyContinue | Where-Object { $_.ProcessName -like "FiveM*" -or $_.ProcessName -like "GTAProcess*" }) {
    throw "Close FiveM before installing SECRET EMKO."
}

Ensure-Folder $PluginsPath
Ensure-Folder $Cache
Ensure-Folder $StateDir
Ensure-Folder $LicenseDir

Step "Checking ReShade"
$reshade = Join-Path $PluginsPath "dxgi.dll"
if (-not (Test-Path -LiteralPath $reshade)) {
    $setup = Join-Path $Cache "ReShade_Setup_6.8.0_Addon.exe"
    Warn "No plugins\dxgi.dll was found. SECRET EMKO requires ReShade 6.8+ Full Add-on Support."
    Write-Host "   The official installer will be downloaded and opened. Install ReShade Full Add-on Support for FiveM, then run this installer again."
    Invoke-WebRequest -UseBasicParsing -Uri $Urls.ReShade -OutFile $setup
    Start-Process -FilePath $setup
    exit 2
}
$reshadeBytes = [IO.File]::ReadAllBytes($reshade)
$reshadeAscii = [Text.Encoding]::ASCII.GetString($reshadeBytes)
if (-not $reshadeAscii.Contains("ReShadeRegisterAddon")) {
    $setup = Join-Path $Cache "ReShade_Setup_6.8.0_Addon.exe"
    Warn "The existing dxgi.dll does not expose ReShadeRegisterAddon and appears to be the standard build."
    Write-Host "   SECRET EMKO requires ReShade Full Add-on Support. The official installer will be opened; install the Add-on build and then run SECRET EMKO again."
    Invoke-WebRequest -UseBasicParsing -Uri $Urls.ReShade -OutFile $setup
    Start-Process -FilePath $setup
    exit 3
}
Ok "Existing ReShade Full Add-on Support dxgi.dll preserved"

Step "Backing up managed configuration"
$reshadeIni = Join-Path $PluginsPath "ReShade.ini"
$bridgeCfg = Join-Path $PluginsPath "dlss5-bridge.cfg"
Backup-IfExists $reshadeIni
Backup-IfExists $bridgeCfg
Ok "Backup root: $Backup"

Step "Installing SECRET EMKO and DLSS 5 Bridge"
Copy-Managed (Join-Path $Root "SecretEMKO.addon64") "SecretEMKO.addon64"
Copy-Managed (Join-Path $Root "dlss5-bridge.addon64") "dlss5-bridge.addon64"
Copy-Item -LiteralPath (Join-Path $Root "THIRD_PARTY_NOTICES.md") -Destination (Join-Path $LicenseDir "THIRD_PARTY_NOTICES.md") -Force
Copy-Item -LiteralPath (Join-Path $Root "LICENSE") -Destination (Join-Path $LicenseDir "SECRET_EMKO_LICENSE.txt") -Force
if (Test-Path (Join-Path $Root "licenses")) {
    Copy-Item (Join-Path $Root "licenses\*") -Destination $LicenseDir -Recurse -Force
}

Step "Selecting RenoDX DLSS 5 consumer"
$driverVersion = Get-NvidiaDriverVersion
$selectedConsumer = $ConsumerChannel
if ($selectedConsumer -eq "Auto") {
    if (Test-DriverNeedsCompatibility $driverVersion) {
        $selectedConsumer = "Compatibility"
    } else {
        $selectedConsumer = "Latest"
    }
}

if ($driverVersion) {
    Write-Host "   NVIDIA Windows driver version: $driverVersion"
}

if ($selectedConsumer -eq "Compatibility") {
    $consumerVersion = "4.55"
    $consumerMajor = 4
    $consumerUrl = $Urls.RenoDXCompatibility
    $consumerHash = $Hashes.RenoDXCompatibility
    Warn "Compatibility channel selected: RenoDX DLSS5 4.55."
    Warn "Current community testing reports faults with newer consumers on NVIDIA 616.64+ in a number of ReShade bridge routes."
} else {
    $consumerVersion = "6.5.3"
    $consumerMajor = 6
    $consumerUrl = $Urls.RenoDXLatest
    $consumerHash = $Hashes.RenoDXLatest
    Ok "Latest channel selected: RenoDX DLSS5 6.5.3"
}

Write-Host "   The RenoDX DLSS5 neural consumer is an external binary distributed separately from the public RenoDX source tree."
Write-Host "   SECRET EMKO does not rebrand or redistribute it in this package."
if (-not $Force) {
    $answer = Read-Host "   Type YES to download this external consumer and the pinned RTX 50 neural runtime for local use"
    if ($answer -cne "YES") { throw "External runtime download was not accepted." }
}

Step "Downloading RenoDX DLSS 5 $consumerVersion"
$renodxZip = Join-Path $Cache ("renodx-dlss5_" + $consumerVersion + ".zip")
Download-Verified $consumerUrl $renodxZip $consumerHash
$renodxExtract = Join-Path $Cache ("renodx-dlss5_" + $consumerVersion)
Expand-Fresh $renodxZip $renodxExtract
$consumer = Find-RequiredFile $renodxExtract "renodx-dlss5*.addon64"
Copy-Managed $consumer "renodx-dlss5.addon64"

Step "Downloading NVIDIA DLSS Neural Rendering 310.8.0"
$nrZip = Join-Path $Cache "nvngx_dlssnr_310.8.0.zip"
Download-Verified $Urls.DlssNr $nrZip $Hashes.DlssNr
$nrExtract = Join-Path $Cache "nvngx_dlssnr_310.8.0"
Expand-Fresh $nrZip $nrExtract
$nrDll = Find-RequiredFile $nrExtract "nvngx_dlssnr.dll" $Rtx50NrDllHash
Assert-NvidiaSignature $nrDll
Copy-Managed $nrDll "nvngx_dlssnr.dll"

Step "Downloading NVIDIA DLSS Super Resolution 310.9.1"
$srZip = Join-Path $Cache "nvngx_dlss_310.9.1.zip"
Download-Verified $Urls.DlssSr $srZip $Hashes.DlssSr
$srExtract = Join-Path $Cache "nvngx_dlss_310.9.1"
Expand-Fresh $srZip $srExtract
$srDll = Find-RequiredFile $srExtract "nvngx_dlss.dll"
Assert-NvidiaSignature $srDll
Copy-Managed $srDll "nvngx_dlss.dll"

if ($InstallStreamlinePreview) {
    Step "Downloading optional NVIDIA Streamline 2.14.1"
    Warn "FiveM Frame Generation is not armed in preview2. Streamline is optional and is being staged only because -InstallStreamlinePreview was requested."
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
        Copy-OptionalStreamlineFile $slExtract $name
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
if ($consumerMajor -ge 6) {
    Remove-IniKey $reshadeIni "RenoDX.DLSS5" "NREnableUpscaling"
    Set-IniValue $reshadeIni "RenoDX.DLSS5" "NRFollowInputRes" "0"
    Set-IniValue $reshadeIni "RenoDX.DLSS5" "NRResolutionScale" "1"
} else {
    Set-IniValue $reshadeIni "RenoDX.DLSS5" "NREnableUpscaling" "0"
}
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
Set-IniValue $reshadeIni "SecretEMKO" "ConsumerMajor" "$consumerMajor"
Set-IniValue $reshadeIni "SecretEMKO" "ConsumerVersion" "$consumerVersion"
Set-IniValue $reshadeIni "SecretEMKO" "ConsumerChannel" "$selectedConsumer"
Set-IniValue $reshadeIni "SecretEMKO" "FrameGenerationPolicy" "0"

Copy-Item -LiteralPath (Join-Path $Root "config\dlss5-bridge.cfg") -Destination $bridgeCfg -Force
Ok "Enhanced profile + synthetic D3D11 bridge configured"

Step "Writing install state"
$managed = @(
    "SecretEMKO.addon64",
    "dlss5-bridge.addon64",
    "renodx-dlss5.addon64",
    "nvngx_dlssnr.dll",
    "nvngx_dlss.dll",
    "dlss5-bridge.cfg"
)
if ($InstallStreamlinePreview) {
    $managed += @(
        "sl.interposer.dll",
        "sl.common.dll",
        "sl.dlss.dll",
        "sl.dlss_g.dll",
        "sl.dlss_nr.dll",
        "sl.reflex.dll",
        "sl.pcl.dll",
        "sl.nis.dll",
        "nvngx_dlssg.dll"
    )
}
$state = [ordered]@{
    product = "SECRET EMKO Neural Graphics"
    version = "2.0.0-preview2"
    installed_at = (Get-Date).ToString("o")
    plugins_path = $PluginsPath
    backup_path = $Backup
    consumer_channel = $selectedConsumer
    consumer_version = $consumerVersion
    consumer_major = $consumerMajor
    nvidia_driver = if ($driverVersion) { $driverVersion.ToString() } else { "unknown" }
    managed_files = $managed
    reshade_ini_backed_up = (Test-Path (Join-Path $Backup "ReShade.ini"))
}
$state | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $StateDir "install-state.json") -Encoding UTF8

Step "Verification"
$required = @(
    "dxgi.dll",
    "SecretEMKO.addon64",
    "dlss5-bridge.addon64",
    "renodx-dlss5.addon64",
    "nvngx_dlssnr.dll",
    "nvngx_dlss.dll",
    "ReShade.ini",
    "dlss5-bridge.cfg"
)
$missing = @()
foreach ($name in $required) {
    $p = Join-Path $PluginsPath $name
    if (Test-Path -LiteralPath $p) {
        $size = (Get-Item -LiteralPath $p).Length
        Write-Host ("   [OK] {0,-26} {1,12:N0} bytes" -f $name,$size) -ForegroundColor Green
    } else {
        $missing += $name
        Write-Host "   [MISSING] $name" -ForegroundColor Red
    }
}
if ($missing.Count -gt 0) { throw "Installation incomplete: $($missing -join ', ')" }

Write-Host ""
Write-Host "===============================================================" -ForegroundColor DarkGray
Write-Host " SECRET EMKO installation complete." -ForegroundColor Green
Write-Host " RenoDX DLSS5 channel: $selectedConsumer ($consumerVersion)" -ForegroundColor White
Write-Host " Start FiveM, open ReShade, then Add-ons -> SECRET EMKO Neural Graphics." -ForegroundColor White
Write-Host " Recommended first profile: Enhanced." -ForegroundColor White
Write-Host ""
Write-Host " Keep ReShade.log and dlss5-bridge.log after the first test." -ForegroundColor Gray
Write-Host " Frame Generation is intentionally not armed in preview2." -ForegroundColor Yellow
if (-not $InstallStreamlinePreview) {
    Write-Host " Streamline was intentionally NOT installed because FG is not active." -ForegroundColor Gray
}
Write-Host "===============================================================" -ForegroundColor DarkGray
) { $end=$i; break }
    }
    for ($i=$end-1; $i -gt $start; $i--) {
        if ($lines[$i] -match "^\s*$([regex]::Escape($Key))\s*=") { $lines.RemoveAt($i) }
    }
    Set-Content -LiteralPath $Path -Value $lines -Encoding UTF8
}

function Get-NvidiaDriverVersion {
    try {
        $gpu = Get-CimInstance Win32_VideoController -ErrorAction Stop |
            Where-Object { $_.Name -match 'NVIDIA' } |
            Select-Object -First 1
        if ($gpu -and $gpu.DriverVersion) { return [version]$gpu.DriverVersion }
    } catch {}
    return $null
}

function Test-DriverNeedsCompatibility([version]$Version) {
    if (-not $Version) { return $false }
    # NVIDIA 616.64 maps to Windows driver version 32.0.16.1664.
    if ($Version.Major -gt 32) { return $true }
    if ($Version.Major -eq 32 -and $Version.Minor -gt 0) { return $true }
    if ($Version.Major -eq 32 -and $Version.Minor -eq 0 -and $Version.Build -gt 16) { return $true }
    if ($Version.Major -eq 32 -and $Version.Minor -eq 0 -and $Version.Build -eq 16 -and $Version.Revision -ge 1664) { return $true }
    return $false
}

function Assert-NvidiaSignature([string]$Path) {
    $sig = Get-AuthenticodeSignature -LiteralPath $Path
    if ($sig.Status -ne "Valid") {
        throw "NVIDIA runtime signature is not valid: $Path ($($sig.Status))"
    }
    if (-not $sig.SignerCertificate -or $sig.SignerCertificate.Subject -notmatch "NVIDIA") {
        throw "Unexpected signer for NVIDIA runtime: $Path"
    }
}

function Copy-OptionalStreamlineFile([string]$Extracted, [string]$Name) {
    $candidates = @(Get-ChildItem -LiteralPath $Extracted -Recurse -File -Filter $Name -ErrorAction SilentlyContinue |
        Where-Object { $_.FullName -match '[\\/]bin[\\/]x64[\\/]' -and $_.FullName -notmatch '[\\/]development[\\/]' })
    if ($candidates.Count -eq 0) {
        Warn "$Name was not present in the production x64 set"
        return
    }
    Copy-Managed $candidates[0].FullName $Name
}

Banner

if (Get-Process -ErrorAction SilentlyContinue | Where-Object { $_.ProcessName -like "FiveM*" -or $_.ProcessName -like "GTAProcess*" }) {
    throw "Close FiveM before installing SECRET EMKO."
}

Ensure-Folder $PluginsPath
Ensure-Folder $Cache
Ensure-Folder $StateDir
Ensure-Folder $LicenseDir

Step "Checking ReShade"
$reshade = Join-Path $PluginsPath "dxgi.dll"
if (-not (Test-Path -LiteralPath $reshade)) {
    $setup = Join-Path $Cache "ReShade_Setup_6.8.0_Addon.exe"
    Warn "No plugins\dxgi.dll was found. SECRET EMKO requires ReShade 6.8+ Full Add-on Support."
    Write-Host "   The official installer will be downloaded and opened. Install ReShade Full Add-on Support for FiveM, then run this installer again."
    Invoke-WebRequest -UseBasicParsing -Uri $Urls.ReShade -OutFile $setup
    Start-Process -FilePath $setup
    exit 2
}
$reshadeBytes = [IO.File]::ReadAllBytes($reshade)
$reshadeAscii = [Text.Encoding]::ASCII.GetString($reshadeBytes)
if (-not $reshadeAscii.Contains("ReShadeRegisterAddon")) {
    $setup = Join-Path $Cache "ReShade_Setup_6.8.0_Addon.exe"
    Warn "The existing dxgi.dll does not expose ReShadeRegisterAddon and appears to be the standard build."
    Write-Host "   SECRET EMKO requires ReShade Full Add-on Support. The official installer will be opened; install the Add-on build and then run SECRET EMKO again."
    Invoke-WebRequest -UseBasicParsing -Uri $Urls.ReShade -OutFile $setup
    Start-Process -FilePath $setup
    exit 3
}
Ok "Existing ReShade Full Add-on Support dxgi.dll preserved"

Step "Backing up managed configuration"
$reshadeIni = Join-Path $PluginsPath "ReShade.ini"
$bridgeCfg = Join-Path $PluginsPath "dlss5-bridge.cfg"
Backup-IfExists $reshadeIni
Backup-IfExists $bridgeCfg
Ok "Backup root: $Backup"

Step "Installing SECRET EMKO and DLSS 5 Bridge"
Copy-Managed (Join-Path $Root "SecretEMKO.addon64") "SecretEMKO.addon64"
Copy-Managed (Join-Path $Root "dlss5-bridge.addon64") "dlss5-bridge.addon64"
Copy-Item -LiteralPath (Join-Path $Root "THIRD_PARTY_NOTICES.md") -Destination (Join-Path $LicenseDir "THIRD_PARTY_NOTICES.md") -Force
Copy-Item -LiteralPath (Join-Path $Root "LICENSE") -Destination (Join-Path $LicenseDir "SECRET_EMKO_LICENSE.txt") -Force
if (Test-Path (Join-Path $Root "licenses")) {
    Copy-Item (Join-Path $Root "licenses\*") -Destination $LicenseDir -Recurse -Force
}

Step "Downloading RenoDX DLSS 5 v4.70"
$renodxZip = Join-Path $Cache "renodx-dlss5_4.70.zip"
Download-Verified $Urls.RenoDX $renodxZip $Hashes.RenoDX
$renodxExtract = Join-Path $Cache "renodx-dlss5_4.70"
Expand-Fresh $renodxZip $renodxExtract
$consumer = Find-RequiredFile $renodxExtract "renodx-dlss5*.addon64"
Copy-Managed $consumer "renodx-dlss5.addon64"

Step "Downloading NVIDIA DLSS Neural Rendering 310.8.0"
$nrZip = Join-Path $Cache "nvngx_dlssnr_310.8.0.zip"
Download-Verified $Urls.DlssNr $nrZip $Hashes.DlssNr
$nrExtract = Join-Path $Cache "nvngx_dlssnr_310.8.0"
Expand-Fresh $nrZip $nrExtract
$nrDll = Find-RequiredFile $nrExtract "nvngx_dlssnr.dll" $Rtx50NrDllHash
Copy-Managed $nrDll "nvngx_dlssnr.dll"

Step "Downloading NVIDIA DLSS Super Resolution 310.9.1"
$srZip = Join-Path $Cache "nvngx_dlss_310.9.1.zip"
Download-Verified $Urls.DlssSr $srZip $Hashes.DlssSr
$srExtract = Join-Path $Cache "nvngx_dlss_310.9.1"
Expand-Fresh $srZip $srExtract
$srDll = Find-RequiredFile $srExtract "nvngx_dlss.dll"
Copy-Managed $srDll "nvngx_dlss.dll"

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
        Copy-OptionalStreamlineFile $slExtract $name
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

Copy-Item -LiteralPath (Join-Path $Root "config\dlss5-bridge.cfg") -Destination $bridgeCfg -Force
Ok "Enhanced profile + synthetic D3D11 bridge configured"

Step "Writing install state"
$managed = @(
    "SecretEMKO.addon64",
    "dlss5-bridge.addon64",
    "renodx-dlss5.addon64",
    "nvngx_dlssnr.dll",
    "nvngx_dlss.dll",
    "sl.interposer.dll",
    "sl.common.dll",
    "sl.dlss.dll",
    "sl.dlss_g.dll",
    "sl.dlss_nr.dll",
    "sl.reflex.dll",
    "sl.pcl.dll",
    "sl.nis.dll",
    "nvngx_dlssg.dll",
    "dlss5-bridge.cfg"
)
$state = [ordered]@{
    product = "SECRET EMKO Neural Graphics"
    version = "2.0.0-preview1"
    installed_at = (Get-Date).ToString("o")
    plugins_path = $PluginsPath
    backup_path = $Backup
    managed_files = $managed
    reshade_ini_backed_up = (Test-Path (Join-Path $Backup "ReShade.ini"))
}
$state | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $StateDir "install-state.json") -Encoding UTF8

Step "Verification"
$required = @(
    "dxgi.dll",
    "SecretEMKO.addon64",
    "dlss5-bridge.addon64",
    "renodx-dlss5.addon64",
    "nvngx_dlssnr.dll",
    "nvngx_dlss.dll",
    "ReShade.ini",
    "dlss5-bridge.cfg"
)
$missing = @()
foreach ($name in $required) {
    $p = Join-Path $PluginsPath $name
    if (Test-Path -LiteralPath $p) {
        $size = (Get-Item -LiteralPath $p).Length
        Write-Host ("   [OK] {0,-26} {1,12:N0} bytes" -f $name,$size) -ForegroundColor Green
    } else {
        $missing += $name
        Write-Host "   [MISSING] $name" -ForegroundColor Red
    }
}
if ($missing.Count -gt 0) { throw "Installation incomplete: $($missing -join ', ')" }

Write-Host ""
Write-Host "===============================================================" -ForegroundColor DarkGray
Write-Host " SECRET EMKO installation complete." -ForegroundColor Green
Write-Host " Start FiveM, open ReShade, then Add-ons -> SECRET EMKO Neural Graphics." -ForegroundColor White
Write-Host " Recommended first profile: Enhanced." -ForegroundColor White
Write-Host ""
Write-Host " Keep ReShade.log and dlss5-bridge.log after the first test." -ForegroundColor Gray
Write-Host " Frame Generation is intentionally not armed in preview1." -ForegroundColor Yellow
Write-Host "===============================================================" -ForegroundColor DarkGray
