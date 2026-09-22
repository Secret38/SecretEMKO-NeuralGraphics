param([string]$WorkDir = "$PSScriptRoot\..\work")

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$RepoRoot = (Resolve-Path "$PSScriptRoot\..").Path
$UpstreamRepo = "https://github.com/wilsjo2/OptiScaler-DLSSNR-PreSR-Multipass.git"
$UpstreamCommit = "e237f895623742b761f9e5f00067cb3dc62619f4"

function Get-MSBuild {
    $pf86 = [Environment]::GetFolderPath("ProgramFilesX86")
    $vswhere = Join-Path $pf86 "Microsoft Visual Studio\Installer\vswhere.exe"
    if (Test-Path $vswhere) {
        $path = & $vswhere -latest -products * -requires Microsoft.Component.MSBuild -find MSBuild\**\Bin\MSBuild.exe | Select-Object -First 1
        if ($path) { return $path }
    }

    $cmd = Get-Command MSBuild.exe -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }

    throw "MSBuild.exe not found"
}

if (Test-Path $WorkDir) { Remove-Item $WorkDir -Recurse -Force }
New-Item -ItemType Directory -Path $WorkDir -Force | Out-Null

$src = Join-Path $WorkDir "upstream"
& git clone --recursive $UpstreamRepo $src
if ($LASTEXITCODE -ne 0) { throw "git clone failed" }

Push-Location $src
try {
    & git checkout --detach $UpstreamCommit
    if ($LASTEXITCODE -ne 0) { throw "git checkout failed" }

    & git submodule update --init --recursive
    if ($LASTEXITCODE -ne 0) { throw "git submodule update failed" }
}
finally {
    Pop-Location
}

& python (Join-Path $RepoRoot "tools\patch_upstream.py") $src
if ($LASTEXITCODE -ne 0) { throw "patch_upstream.py failed" }

$msbuild = Get-MSBuild

$forwarderProj = Join-Path $src "OptiScaler\dlssnr\forwarder\dlssnr_forwarder.vcxproj"
& $msbuild $forwarderProj /p:Configuration=Release /p:Platform=x64 /v:minimal /m
if ($LASTEXITCODE -ne 0) { throw "DLSS-NR forwarder build failed" }

& $msbuild (Join-Path $src "OptiScaler.sln") /p:Configuration=Release /p:Platform=x64 /v:minimal /m
if ($LASTEXITCODE -ne 0) { throw "Main x64 build failed" }

$buildOut = Join-Path $src "x64\Release\a"
$mainDll = Join-Path $buildOut "OptiScaler.dll"
if (-not (Test-Path $mainDll)) { throw "Missing build output: $mainDll" }

$outRoot = Join-Path $RepoRoot "output"
$stage = Join-Path $outRoot "SecretEMKO-NeuralGraphics-v1.1.0-FiveM-Legacy"
$zip = "$stage.zip"

if (Test-Path $stage) { Remove-Item $stage -Recurse -Force }
if (Test-Path $zip) { Remove-Item $zip -Force }
New-Item -ItemType Directory -Path $stage -Force | Out-Null
New-Item -ItemType Directory -Path (Join-Path $stage "SecretEMKO") -Force | Out-Null

Copy-Item $mainDll (Join-Path $stage "SecretEMKO.asi") -Force
Copy-Item (Join-Path $src "OptiScaler.ini") (Join-Path $stage "SecretEMKO.ini") -Force

$backend = Join-Path $buildOut "OptiScaler"
if (Test-Path $backend) {
    Copy-Item (Join-Path $backend "*") (Join-Path $stage "SecretEMKO") -Recurse -Force
}

$forwarderCandidates = @(
    (Join-Path $src "OptiScaler\dlssnr\forwarder\x64\Release\a\nvngx.dll_dlssnr.dll"),
    (Join-Path $buildOut "nvngx.dll_dlssnr.dll")
)
$forwarder = $forwarderCandidates | Where-Object { Test-Path $_ } | Select-Object -First 1
if (-not $forwarder) { throw "nvngx.dll_dlssnr.dll not produced" }
Copy-Item $forwarder (Join-Path $stage "nvngx.dll_dlssnr.dll") -Force

if (Test-Path (Join-Path $buildOut "Licenses")) {
    Copy-Item (Join-Path $buildOut "Licenses") (Join-Path $stage "Licenses") -Recurse -Force
}
Copy-Item (Join-Path $RepoRoot "LICENSE") (Join-Path $stage "LICENSE") -Force
Copy-Item (Join-Path $RepoRoot "THIRD_PARTY_NOTICES.txt") (Join-Path $stage "THIRD_PARTY_NOTICES.txt") -Force
Copy-Item (Join-Path $RepoRoot "docs\RUNTIME_POLICY.md") (Join-Path $stage "RUNTIME_FILES_REQUIRED.md") -Force
Copy-Item (Join-Path $RepoRoot "project-manifest.json") (Join-Path $stage "build-manifest.json") -Force

$installer = @'
@echo off
setlocal
set "PLUGINS=%LOCALAPPDATA%\FiveM\FiveM.app\plugins"
if not exist "%PLUGINS%" mkdir "%PLUGINS%"
copy /Y "SecretEMKO.asi" "%PLUGINS%\SecretEMKO.asi" >nul
copy /Y "SecretEMKO.ini" "%PLUGINS%\SecretEMKO.ini" >nul
copy /Y "nvngx.dll_dlssnr.dll" "%PLUGINS%\nvngx.dll_dlssnr.dll" >nul
if exist "SecretEMKO" xcopy /E /I /Y "SecretEMKO" "%PLUGINS%\SecretEMKO" >nul
if exist "Licenses" xcopy /E /I /Y "Licenses" "%PLUGINS%\Licenses\SecretEMKO" >nul
echo.
echo SECRET EMKO installed to %PLUGINS%
echo Read RUNTIME_FILES_REQUIRED.md for NVIDIA runtime requirements.
pause
'@
Set-Content (Join-Path $stage "INSTALL_FIVEM.bat") $installer -Encoding ASCII

Compress-Archive -Path (Join-Path $stage "*") -DestinationPath $zip -CompressionLevel Optimal

Write-Host "Built: $stage\SecretEMKO.asi"
Write-Host "Package: $zip"
