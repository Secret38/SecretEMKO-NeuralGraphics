param(
  [string]$FiveMPlugins = "$env:LOCALAPPDATA\FiveM\FiveM.app\plugins",
  [switch]$AcceptNvidiaLicenses,
  [switch]$InstallStreamline
)

$ErrorActionPreference = "Stop"
$Source = Split-Path -Parent $MyInvocation.MyCommand.Path
$Stamp = Get-Date -Format "yyyyMMdd-HHmmss"
$Backup = Join-Path $FiveMPlugins "SecretEMKO-Backup-$Stamp"

Write-Host ""
Write-Host "SECRET EMKO Neural Graphics v2 installer"
Write-Host "Target: $FiveMPlugins"
Write-Host ""

if (-not (Test-Path $FiveMPlugins)) {
  New-Item -ItemType Directory -Path $FiveMPlugins -Force | Out-Null
}

$reshade = Join-Path $FiveMPlugins "dxgi.dll"
if (-not (Test-Path $reshade)) {
  Write-Warning "ReShade dxgi.dll was not found. Install ReShade 6.8.0 WITH FULL ADD-ON SUPPORT from https://reshade.me/ first."
  Write-Warning "Secret EMKO will still be copied, but .addon64 files will not load without an add-on capable ReShade host."
} else {
  try {
    $v = (Get-Item $reshade).VersionInfo.FileVersion
    Write-Host "Detected ReShade/DXGI file version: $v"
  } catch {
    Write-Host "Detected existing dxgi.dll (version could not be read)."
  }
}

$toBackup = @("SecretEMKO.addon64","dlss5-bridge.addon64","SecretEMKO-Recommended.ini")
$existing = $toBackup | ForEach-Object { Join-Path $FiveMPlugins $_ } | Where-Object { Test-Path $_ }
if ($existing) {
  New-Item -ItemType Directory -Path $Backup -Force | Out-Null
  foreach ($f in $existing) { Copy-Item $f $Backup -Force }
  Write-Host "Backup: $Backup"
}

Copy-Item (Join-Path $Source "SecretEMKO.addon64") (Join-Path $FiveMPlugins "SecretEMKO.addon64") -Force
Copy-Item (Join-Path $Source "dlss5-bridge.addon64") (Join-Path $FiveMPlugins "dlss5-bridge.addon64") -Force
Copy-Item (Join-Path $Source "SecretEMKO-Recommended.ini") (Join-Path $FiveMPlugins "SecretEMKO-Recommended.ini") -Force
Copy-Item (Join-Path $Source "README.md") (Join-Path $FiveMPlugins "SecretEMKO-README.md") -Force
Copy-Item (Join-Path $Source "THIRD_PARTY_NOTICES.txt") (Join-Path $FiveMPlugins "SecretEMKO-THIRD_PARTY_NOTICES.txt") -Force

if ($InstallStreamline) {
  if (-not $AcceptNvidiaLicenses) {
    throw "Streamline download requested without -AcceptNvidiaLicenses. Read NVIDIA's SDK licences first, then rerun with both switches."
  }

  $uri = "https://github.com/NVIDIA-RTX/Streamline/releases/download/v2.14.1/streamline-sdk-v2.14.1.zip"
  $expected = "92C4D954631A1710DA86CA3FA8D5034F2B9503838C95FC4AE977AE149319781B"
  $cache = Join-Path $env:TEMP "SecretEMKO-streamline-2.14.1.zip"
  $extract = Join-Path $env:TEMP "SecretEMKO-streamline-2.14.1"
  Write-Host "Downloading official NVIDIA Streamline 2.14.1..."
  Invoke-WebRequest -Uri $uri -OutFile $cache
  $actual = (Get-FileHash $cache -Algorithm SHA256).Hash
  if ($actual -ne $expected) { throw "Streamline archive hash mismatch. Expected $expected, got $actual" }
  if (Test-Path $extract) { Remove-Item $extract -Recurse -Force }
  Expand-Archive $cache -DestinationPath $extract -Force

  $bin = Get-ChildItem $extract -Directory -Recurse | Where-Object { $_.FullName -match 'bin\\x64$' } | Select-Object -First 1
  if (-not $bin) { throw "Could not locate Streamline bin\x64 in official archive." }

  $sl = Join-Path $FiveMPlugins "SecretEMKO\streamline"
  New-Item -ItemType Directory -Path $sl -Force | Out-Null
  foreach ($n in @("sl.interposer.dll","sl.common.dll","sl.dlss_g.dll","sl.reflex.dll","sl.pcl.dll","nvngx_dlssg.dll")) {
    $src = Join-Path $bin.FullName $n
    if (-not (Test-Path $src)) { throw "Official Streamline file missing: $n" }
    Copy-Item $src (Join-Path $sl $n) -Force
  }
  Write-Host "Installed official Streamline 2.14.1 runtime files to $sl"
}

Write-Host ""
Write-Host "Installed:"
Write-Host "  SecretEMKO.addon64"
Write-Host "  dlss5-bridge.addon64"
Write-Host ""
Write-Host "Not redistributed by this package:"
Write-Host "  ReShade full add-on build (keep your existing dxgi.dll)"
Write-Host "  nvngx_dlssnr.dll (NVIDIA Neural Rendering runtime)"
Write-Host "  nvngx_dlss.dll (DLSS SR runtime where required)"
Write-Host ""
Write-Host "Open ReShade with Home and select the 'SECRET EMKO // Neural Graphics' tab."
