param(
  [string]$WorkDir = "$PSScriptRoot\..\work-v2"
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$Root = (Resolve-Path "$PSScriptRoot\..").Path
$RenoRepo = "https://github.com/clshortfuse/renodx.git"
$RenoCommit = "9b212edad4dde9bca2b823b1e045b712b1a8d854"
$BridgeRepo = "https://github.com/NIGos/dlss5-bridge.git"
$BridgeCommit = "d1cc508a7097534c5c0e01a868ebe3b6657b932b"

if (Test-Path $WorkDir) { Remove-Item $WorkDir -Recurse -Force }
New-Item -ItemType Directory -Force -Path $WorkDir | Out-Null

$reno = Join-Path $WorkDir "renodx"
$bridge = Join-Path $WorkDir "dlss5-bridge"

Write-Host "Cloning RenoDX $RenoCommit"
git clone --recursive $RenoRepo $reno
Push-Location $reno
git checkout --detach $RenoCommit
git submodule update --init --recursive
Pop-Location

$target = Join-Path $reno "src\addons\secretemko"
New-Item -ItemType Directory -Force -Path $target | Out-Null
Copy-Item (Join-Path $Root "v2-renodx\src\addon.cpp") (Join-Path $target "addon.cpp") -Force
Copy-Item (Join-Path $Root "v2-renodx\src\metadata.json") (Join-Path $target "metadata.json") -Force

Push-Location $reno
try {
  .\scripts\setup-dev-env.ps1 -Update -Tools dxc,slang,glslang
  cmake --preset vs-x64
  if ($LASTEXITCODE -ne 0) { throw "RenoDX CMake configure failed" }
  cmake --build --preset vs-x64-release --target secretemko --verbose
  if ($LASTEXITCODE -ne 0) { throw "Secret EMKO addon build failed" }
}
finally { Pop-Location }

$addon = Get-ChildItem -Path $reno -Recurse -Filter "renodx-secretemko.addon64" | Select-Object -First 1
if (-not $addon) { throw "renodx-secretemko.addon64 not found" }

Write-Host "Cloning DLSS5 Bridge $BridgeCommit"
git clone --recursive $BridgeRepo $bridge
Push-Location $bridge
git checkout --detach $BridgeCommit
git submodule update --init --recursive
Push-Location "src"
cmd /c build.cmd
if ($LASTEXITCODE -ne 0) { throw "DLSS5 Bridge build failed" }
Pop-Location
Pop-Location

$bridgeAddon = Get-ChildItem -Path $bridge -Recurse -Filter "dlss5-bridge.addon64" | Select-Object -First 1
if (-not $bridgeAddon) { throw "dlss5-bridge.addon64 not found" }

$out = Join-Path $Root "output-v2\SecretEMKO-NeuralGraphics-v2-preview"
if (Test-Path $out) { Remove-Item $out -Recurse -Force }
New-Item -ItemType Directory -Force -Path $out | Out-Null

Copy-Item $addon.FullName (Join-Path $out "SecretEMKO.addon64") -Force
Copy-Item $bridgeAddon.FullName (Join-Path $out "dlss5-bridge.addon64") -Force
Copy-Item (Join-Path $Root "v2-renodx\SecretEMKO-Recommended.ini") (Join-Path $out "SecretEMKO-Recommended.ini") -Force
Copy-Item (Join-Path $Root "v2-renodx\INSTALL_FIVEM.ps1") (Join-Path $out "INSTALL_FIVEM.ps1") -Force
Copy-Item (Join-Path $Root "v2-renodx\INSTALL_FIVEM.cmd") (Join-Path $out "INSTALL_FIVEM.cmd") -Force
Copy-Item (Join-Path $Root "v2-renodx\README.md") (Join-Path $out "README.md") -Force
Copy-Item (Join-Path $Root "v2-renodx\THIRD_PARTY_NOTICES.txt") (Join-Path $out "THIRD_PARTY_NOTICES.txt") -Force

$renoLicense = Join-Path $reno "LICENSE"
if (Test-Path $renoLicense) { Copy-Item $renoLicense (Join-Path $out "LICENSE-RenoDX-MIT.txt") -Force }
$bridgeLicense = Join-Path $bridge "LICENSE"
if (Test-Path $bridgeLicense) { Copy-Item $bridgeLicense (Join-Path $out "LICENSE-DLSS5-Bridge-MIT.txt") -Force }

$manifest = [ordered]@{
  product = "SECRET EMKO Neural Graphics"
  version = "2.0.0-preview"
  architecture = "x64"
  ui = "RenoDX + ReShade Add-on API"
  renodx_commit = $RenoCommit
  bridge_commit = $BridgeCommit
  reshade_baseline = "6.8.0 Full Add-on Support"
  streamline_baseline = "2.14.1"
  notes = @(
    "ReShade binary is intentionally not redistributed; official ReShade terms request linking users to reshade.me.",
    "NVIDIA proprietary runtimes are not redistributed.",
    "This preview builds the Secret EMKO control surface and D3D11 bridge. The open Secret EMKO neural consumer is a separate implementation milestone."
  )
}
$manifest | ConvertTo-Json -Depth 5 | Set-Content (Join-Path $out "build-manifest.json") -Encoding UTF8

$zip = "$out.zip"
if (Test-Path $zip) { Remove-Item $zip -Force }
Compress-Archive -Path (Join-Path $out "*") -DestinationPath $zip -CompressionLevel Optimal

Get-FileHash (Join-Path $out "SecretEMKO.addon64") -Algorithm SHA256
Get-FileHash (Join-Path $out "dlss5-bridge.addon64") -Algorithm SHA256
Write-Host "Package: $zip"
