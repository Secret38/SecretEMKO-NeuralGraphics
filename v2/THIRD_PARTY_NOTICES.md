# THIRD-PARTY NOTICES — SECRET EMKO Neural Graphics v2

SECRET EMKO Neural Graphics is the product/integration branding for this project. It does not imply authorship of third-party components.

## RenoDX
Public framework source: clshortfuse/renodx  
Copyright (c) 2025 Carlos Lopez Jr. and contributors  
License: MIT.

The build resolves RenoDX `origin/main` at build time and records the exact commit SHA in `BUILD-MANIFEST.json`. RenoDX's original notices remain applicable.

## ReShade
ReShade and its add-on API are Copyright (C) Patrick Mours / crosire and contributors.  
License: BSD 3-Clause for the source/API components used by the build.

The ReShade binary is **not redistributed** by SECRET EMKO. The installer resolves the current official ReShade setup from reshade.me and installs the Standard or Full Add-on build required by the selected mode.

## DLSS 5 Bridge
NIGos/dlss5-bridge  
Copyright (c) 2026 NIGos and contributors  
License: MIT.

RC5 pins the official upstream prerelease `v1.4.13-pre8` (commit `ecd1b00674020a1e8c76a9cb653a1a21d11676a0`, asset SHA-256 `C4C8B5BC4B26B2B3F3BF2767CDB708546D62F7D0BBB63D24E940C736DA9EFE26`). This build is used specifically for its internal NVIDIA Optical Flow synthetic-input path and its MinHook/lifecycle fixes. It remains an upstream prerelease rather than being represented as a stable release.

The pinned bridge binary is obtained from its official GitHub prerelease during the release build, SHA-256 verified, and may be included with this package under its MIT license.

## RenoDX DLSS 5 neural consumer
The separately distributed `renodx-dlss5.addon64` is not source code from the public RenoDX main repository. SECRET EMKO does not claim ownership of it and does not repackage it in Git. The installer fetches the pinned public release package used by current DLSS5-Feeder tooling.

## NVIDIA
DLSS, DLSS Neural Rendering, DLSS Frame Generation, NGX and Streamline are NVIDIA technologies. Their proprietary runtime binaries are not relicensed as SECRET EMKO code. The installer downloads pinned runtime packages separately and preserves applicable NVIDIA notices.

## No PureDark code
SECRET EMKO v2 contains no PureDark proprietary source, authentication bypass, Patreon bypass, license bypass or paid-mod assets.


## DLSS5-Swapper live-control adapter provenance
The RC5 RenoDX live-control adapter is derived from the MIT-licensed, hash-pinned RenoDX v4.7 UI bridge in `rakanki911/DLSS5-Swapper` (commit `24bd2aca7a7451ce94e564366381e33cac9dcdba`).  
Copyright (c) 2026 Rakan Alkhaldi  
License: MIT.

SECRET EMKO uses that technique only for the exact verified `renodx-dlss5.addon64` v4.70 binary (SHA-256 `D5ADF82EB44B065F4C590AC91FE824BAB07AFEA0EB9F994BDE936710C8593952`) and additionally checks code fingerprints before enabling live control. Unknown or changed RenoDX builds are refused rather than patched heuristically. The adapter calls RenoDX's own settings callback synchronously and confirms supported values by readback; it does not retain private setting pointers or patch the RenoDX file on disk.
