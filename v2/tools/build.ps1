[CmdletBinding()]
param(
    [string]$WorkDir = "$PSScriptRoot\..\work-v2",
    [string]$RenoDXRef = "origin/main"
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest
$ProgressPreference = "SilentlyContinue"

$RepoRoot = (Resolve-Path "$PSScriptRoot\..").Path
$Upstream = "https://github.com/clshortfuse/renodx.git"
$BridgeUrl = "https://github.com/NIGos/dlss5-bridge/releases/download/v1.4.12/dlss5-bridge.addon64"
$BridgeHash = "4F2ACECC1026AE89AC0B92767BE66CEEA2662AD0EF88710B89C7DA7840D548D4"

if (Test-Path -LiteralPath $WorkDir) { Remove-Item -LiteralPath $WorkDir -Recurse -Force }
New-Item -ItemType Directory -Path $WorkDir -Force | Out-Null

$src = Join-Path $WorkDir "renodx"
& git clone --recursive $Upstream $src
if ($LASTEXITCODE -ne 0) { throw "RenoDX clone failed" }

Push-Location $src
try {
    & git checkout --detach $RenoDXRef
    if ($LASTEXITCODE -ne 0) { throw "RenoDX checkout failed: $RenoDXRef" }
    $Commit = (& git rev-parse HEAD).Trim()
    if (-not $Commit) { throw "Could not resolve RenoDX commit" }
    & git submodule update --init --recursive
    if ($LASTEXITCODE -ne 0) { throw "RenoDX submodule update failed" }
}
finally { Pop-Location }

$addonDir = Join-Path $src "src\addons\secretemko"
New-Item -ItemType Directory -Path $addonDir -Force | Out-Null
Copy-Item (Join-Path $RepoRoot "src\addon.cpp") (Join-Path $addonDir "addon.cpp") -Force
Copy-Item (Join-Path $RepoRoot "src\renodx_live_adapter.hpp") (Join-Path $addonDir "renodx_live_adapter.hpp") -Force
Copy-Item (Join-Path $RepoRoot "src\metadata.json") (Join-Path $addonDir "metadata.json") -Force

Write-Host "Preparing RenoDX shader toolchain..."
Push-Location $src
try {
    & ".\scripts\setup-dev-env.ps1" -Update -Tools @("dxc", "slang", "glslang")
    if ($LASTEXITCODE -ne 0) { throw "RenoDX dev tool setup failed" }
}
finally { Pop-Location }

$buildDir = Join-Path $WorkDir "build"
& cmake -S $src -B $buildDir -A x64 -DRENODX_BUILD_TESTS=OFF
if ($LASTEXITCODE -ne 0) { throw "CMake configure failed" }

& cmake --build $buildDir --config Release --target secretemko --parallel 2
if ($LASTEXITCODE -ne 0) { throw "Secret EMKO add-on build failed" }

$built = Get-ChildItem -LiteralPath $buildDir -Recurse -File -Filter "renodx-secretemko.addon64" | Select-Object -First 1
if (-not $built) { throw "renodx-secretemko.addon64 not found after build" }

$distRoot = Join-Path $RepoRoot "dist"
$stage = Join-Path $distRoot "SecretEMKO-NeuralGraphics-v2.0.0-rc3"
$zip = "$stage.zip"
if (Test-Path $stage) { Remove-Item $stage -Recurse -Force }
if (Test-Path $zip) { Remove-Item $zip -Force }
New-Item -ItemType Directory -Path $stage -Force | Out-Null
New-Item -ItemType Directory -Path (Join-Path $stage "tools") -Force | Out-Null
New-Item -ItemType Directory -Path (Join-Path $stage "config") -Force | Out-Null
New-Item -ItemType Directory -Path (Join-Path $stage "licenses") -Force | Out-Null
New-Item -ItemType Directory -Path (Join-Path $stage "presets") -Force | Out-Null

Copy-Item $built.FullName (Join-Path $stage "SecretEMKO.addon64") -Force

# Verify the ReShade AddonInit/AddOnUninit lifecycle markers are present in the
# compiled PE before packaging. __declspec(dllexport) causes these names to be
# emitted into the export directory; this catches accidental regression back to
# DllMain-only initialization without depending on Visual Studio PATH state.
$addonPath = Join-Path $stage "SecretEMKO.addon64"
$addonAscii = [Text.Encoding]::ASCII.GetString([IO.File]::ReadAllBytes($addonPath))
foreach ($symbol in @("AddonInit","AddonUninit","NAME","DESCRIPTION")) {
    if (-not $addonAscii.Contains($symbol)) {
        throw "Compiled SECRET EMKO add-on is missing lifecycle/export marker: $symbol"
    }
}
Write-Host "SECRET EMKO AddonInit lifecycle markers verified"

$bridge = Join-Path $WorkDir "dlss5-bridge.addon64"
Invoke-WebRequest -UseBasicParsing -Uri $BridgeUrl -OutFile $bridge
$actualBridge = (Get-FileHash -LiteralPath $bridge -Algorithm SHA256).Hash
if ($actualBridge -ine $BridgeHash) {
    throw "DLSS 5 Bridge hash mismatch: $actualBridge"
}
Copy-Item $bridge (Join-Path $stage "dlss5-bridge.addon64") -Force

Copy-Item (Join-Path $RepoRoot "README.md") (Join-Path $stage "README.md") -Force
Copy-Item (Join-Path $RepoRoot "VERSIONS.json") (Join-Path $stage "VERSIONS.json") -Force
Copy-Item (Join-Path $RepoRoot "LICENSE") (Join-Path $stage "LICENSE") -Force
Copy-Item (Join-Path $RepoRoot "THIRD_PARTY_NOTICES.md") (Join-Path $stage "THIRD_PARTY_NOTICES.md") -Force
Copy-Item (Join-Path $RepoRoot "config\dlss5-bridge.cfg") (Join-Path $stage "config\dlss5-bridge.cfg") -Force
Copy-Item (Join-Path $RepoRoot "tools\Install-SecretEMKO.ps1") (Join-Path $stage "tools\Install-SecretEMKO.ps1") -Force
Copy-Item (Join-Path $RepoRoot "tools\Update-ReShadeContent.ps1") (Join-Path $stage "tools\Update-ReShadeContent.ps1") -Force
Copy-Item (Join-Path $RepoRoot "config\ReShade.SecretEMKO.ini") (Join-Path $stage "config\ReShade.SecretEMKO.ini") -Force
Copy-Item (Join-Path $RepoRoot "presets\Secret_Emko_Main.ini") (Join-Path $stage "presets\Secret_Emko_Main.ini") -Force
Copy-Item (Join-Path $RepoRoot "presets\Secret_Emko_Stream.ini") (Join-Path $stage "presets\Secret_Emko_Stream.ini") -Force
Copy-Item (Join-Path $RepoRoot "MAIN-SYSTEM.json") (Join-Path $stage "MAIN-SYSTEM.json") -Force
Copy-Item (Join-Path $RepoRoot "COMPATIBILITY.md") (Join-Path $stage "COMPATIBILITY.md") -Force
Copy-Item (Join-Path $RepoRoot "tools\Uninstall-SecretEMKO.ps1") (Join-Path $stage "tools\Uninstall-SecretEMKO.ps1") -Force
Copy-Item (Join-Path $RepoRoot "INSTALL_SECRET_EMKO.bat") (Join-Path $stage "INSTALL_SECRET_EMKO.bat") -Force
Copy-Item (Join-Path $RepoRoot "INSTALL_SECRET_EMKO_FULL_NEURAL.bat") (Join-Path $stage "INSTALL_SECRET_EMKO_FULL_NEURAL.bat") -Force
Copy-Item (Join-Path $RepoRoot "UNINSTALL_SECRET_EMKO.bat") (Join-Path $stage "UNINSTALL_SECRET_EMKO.bat") -Force

Copy-Item (Join-Path $src "LICENSE") (Join-Path $stage "licenses\RenoDX-LICENSE.txt") -Force

$bridgeLicense = Join-Path $WorkDir "DLSS5-Bridge-LICENSE.txt"
Invoke-WebRequest -UseBasicParsing -Uri "https://raw.githubusercontent.com/NIGos/dlss5-bridge/d1cc508a7097534c5c0e01a868ebe3b6657b932b/LICENSE" -OutFile $bridgeLicense
Copy-Item $bridgeLicense (Join-Path $stage "licenses\DLSS5-Bridge-LICENSE.txt") -Force

$reshadeLicense = Join-Path $WorkDir "ReShade-LICENSE.md"
Invoke-WebRequest -UseBasicParsing -Uri "https://raw.githubusercontent.com/crosire/reshade/3645e3025d1d98a90e318278858931f034d5d1f6/LICENSE.md" -OutFile $reshadeLicense
Copy-Item $reshadeLicense (Join-Path $stage "licenses\ReShade-LICENSE.md") -Force

$swapperLicense = Join-Path $WorkDir "DLSS5-Swapper-LICENSE.txt"
Invoke-WebRequest -UseBasicParsing -Uri "https://raw.githubusercontent.com/rakanki911/DLSS5-Swapper/24bd2aca7a7451ce94e564366381e33cac9dcdba/LICENSE" -OutFile $swapperLicense
Copy-Item $swapperLicense (Join-Path $stage "licenses\DLSS5-Swapper-LICENSE.txt") -Force

$manifest = [ordered]@{
    product = "SECRET EMKO Neural Graphics"
    version = "2.0.0-rc3"
    built = (Get-Date).ToUniversalTime().ToString("o")
    renodx_commit = $Commit
    bridge_version = "1.4.12"
    bridge_sha256 = $BridgeHash
    renodx_dlss5_live_compatible_sha256 = "D5ADF82EB44B065F4C590AC91FE824BAB07AFEA0EB9F994BDE936710C8593952"
    live_adapter_provenance = "Derived from MIT DLSS5-Swapper v4.7 UI bridge, commit 24bd2aca7a7451ce94e564366381e33cac9dcdba"
    addon_sha256 = (Get-FileHash -LiteralPath (Join-Path $stage "SecretEMKO.addon64") -Algorithm SHA256).Hash
}
$manifest | ConvertTo-Json -Depth 3 | Set-Content -LiteralPath (Join-Path $stage "BUILD-MANIFEST.json") -Encoding UTF8

Compress-Archive -Path (Join-Path $stage "*") -DestinationPath $zip -CompressionLevel Optimal
Write-Host "PACKAGE=$zip"
Write-Host "ADDON=$(Join-Path $stage 'SecretEMKO.addon64')"
