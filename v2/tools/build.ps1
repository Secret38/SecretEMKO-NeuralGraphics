[CmdletBinding()]
param(
    [string]$WorkDir = "$PSScriptRoot\..\work-v2"
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest
$ProgressPreference = "SilentlyContinue"

$RepoRoot = (Resolve-Path "$PSScriptRoot\..").Path
$Upstream = "https://github.com/clshortfuse/renodx.git"
$Commit = "9b212edad4dde9bca2b823b1e045b712b1a8d854"
$BridgeUrl = "https://github.com/NIGos/dlss5-bridge/releases/download/v1.4.12/dlss5-bridge.addon64"
$BridgeHash = "4F2ACECC1026AE89AC0B92767BE66CEEA2662AD0EF88710B89C7DA7840D548D4"

if (Test-Path -LiteralPath $WorkDir) { Remove-Item -LiteralPath $WorkDir -Recurse -Force }
New-Item -ItemType Directory -Path $WorkDir -Force | Out-Null

$src = Join-Path $WorkDir "renodx"
& git clone --recursive $Upstream $src
if ($LASTEXITCODE -ne 0) { throw "RenoDX clone failed" }

Push-Location $src
try {
    & git checkout --detach $Commit
    if ($LASTEXITCODE -ne 0) { throw "RenoDX checkout failed" }
    & git submodule update --init --recursive
    if ($LASTEXITCODE -ne 0) { throw "RenoDX submodule update failed" }
}
finally { Pop-Location }

$addonDir = Join-Path $src "src\addons\secretemko"
New-Item -ItemType Directory -Path $addonDir -Force | Out-Null
Copy-Item (Join-Path $RepoRoot "src\addon.cpp") (Join-Path $addonDir "addon.cpp") -Force
Copy-Item (Join-Path $RepoRoot "src\metadata.json") (Join-Path $addonDir "metadata.json") -Force

$buildDir = Join-Path $WorkDir "build"
& cmake -S $src -B $buildDir -A x64 -DRENODX_BUILD_TESTS=OFF
if ($LASTEXITCODE -ne 0) { throw "CMake configure failed" }

& cmake --build $buildDir --config Release --target secretemko --parallel 2
if ($LASTEXITCODE -ne 0) { throw "Secret EMKO add-on build failed" }

$built = Get-ChildItem -LiteralPath $buildDir -Recurse -File -Filter "renodx-secretemko.addon64" | Select-Object -First 1
if (-not $built) { throw "renodx-secretemko.addon64 not found after build" }

$distRoot = Join-Path $RepoRoot "dist"
$stage = Join-Path $distRoot "SecretEMKO-NeuralGraphics-v2.0.0-preview1"
$zip = "$stage.zip"
if (Test-Path $stage) { Remove-Item $stage -Recurse -Force }
if (Test-Path $zip) { Remove-Item $zip -Force }
New-Item -ItemType Directory -Path $stage -Force | Out-Null
New-Item -ItemType Directory -Path (Join-Path $stage "tools") -Force | Out-Null
New-Item -ItemType Directory -Path (Join-Path $stage "config") -Force | Out-Null
New-Item -ItemType Directory -Path (Join-Path $stage "licenses") -Force | Out-Null

Copy-Item $built.FullName (Join-Path $stage "SecretEMKO.addon64") -Force

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
Copy-Item (Join-Path $RepoRoot "tools\Uninstall-SecretEMKO.ps1") (Join-Path $stage "tools\Uninstall-SecretEMKO.ps1") -Force
Copy-Item (Join-Path $RepoRoot "INSTALL_SECRET_EMKO.bat") (Join-Path $stage "INSTALL_SECRET_EMKO.bat") -Force
Copy-Item (Join-Path $RepoRoot "UNINSTALL_SECRET_EMKO.bat") (Join-Path $stage "UNINSTALL_SECRET_EMKO.bat") -Force

Copy-Item (Join-Path $src "LICENSE") (Join-Path $stage "licenses\RenoDX-LICENSE.txt") -Force

$bridgeLicense = Join-Path $WorkDir "DLSS5-Bridge-LICENSE.txt"
Invoke-WebRequest -UseBasicParsing -Uri "https://raw.githubusercontent.com/NIGos/dlss5-bridge/d1cc508a7097534c5c0e01a868ebe3b6657b932b/LICENSE" -OutFile $bridgeLicense
Copy-Item $bridgeLicense (Join-Path $stage "licenses\DLSS5-Bridge-LICENSE.txt") -Force

$reshadeLicense = Join-Path $WorkDir "ReShade-LICENSE.md"
Invoke-WebRequest -UseBasicParsing -Uri "https://raw.githubusercontent.com/crosire/reshade/3645e3025d1d98a90e318278858931f034d5d1f6/LICENSE.md" -OutFile $reshadeLicense
Copy-Item $reshadeLicense (Join-Path $stage "licenses\ReShade-LICENSE.md") -Force

$manifest = [ordered]@{
    product = "SECRET EMKO Neural Graphics"
    version = "2.0.0-preview1"
    built = (Get-Date).ToUniversalTime().ToString("o")
    renodx_commit = $Commit
    bridge_version = "1.4.12"
    bridge_sha256 = $BridgeHash
    addon_sha256 = (Get-FileHash -LiteralPath (Join-Path $stage "SecretEMKO.addon64") -Algorithm SHA256).Hash
}
$manifest | ConvertTo-Json -Depth 3 | Set-Content -LiteralPath (Join-Path $stage "BUILD-MANIFEST.json") -Encoding UTF8

Compress-Archive -Path (Join-Path $stage "*") -DestinationPath $zip -CompressionLevel Optimal
Write-Host "PACKAGE=$zip"
Write-Host "ADDON=$(Join-Path $stage 'SecretEMKO.addon64')"
