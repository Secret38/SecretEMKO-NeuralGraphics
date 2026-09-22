# SECRET EMKO Neural Graphics

FiveM GTA V Legacy neural-graphics project.

## v2 — current development line

The recommended architecture is now **RenoDX + ReShade Full Add-on Support + DLSS 5 Bridge** rather than an invasive game-level ASI hook.

The v2 package provides:

- `SecretEMKO.addon64` — the ReShade-native SECRET EMKO control surface
- native ReShade Add-ons UI with Overview, Styles, Neural, Quality, Bridge, Frame Generation, Diagnostics and About pages
- Natural, Clean, Detail, Enhanced, Cinematic and Ultra Detail quality profiles
- Neural controls with explicit explanations and safe defaults
- GTA V Legacy synthetic DLSS contract configuration
- central v2 main-system policy with current official ReShade shader/add-on catalogs
- `Secret_Emko_Main.ini` and `Secret_Emko_Stream.ini` post-processing presets
- portable ReShade configuration without per-user absolute paths
- pinned/verified binary-sensitive runtime versions and SHA-256 verification
- clean-room one-run installer that auto-detects/creates the FiveM plugins directory and preserves an existing plugins folder
- backups and an uninstaller
- runtime diagnostics instead of silently assuming that a DLL loaded
- no PureDark proprietary source, authentication or paid-mod assets

Source and documentation live under [v2/](v2/README.md).

### Current v2 stack

- RenoDX public framework: current upstream main is resolved at build time and the exact commit is recorded in the build manifest
- ReShade Standard or Full Add-on Support 6.8.0+ selected automatically by compatibility mode
- DLSS 5 Bridge 1.4.12 stable
- RenoDX DLSS 5 consumer 4.70
- NVIDIA DLSS SR 310.9.1
- NVIDIA DLSS Neural Rendering 310.8.0 for RTX 50
- NVIDIA Streamline 2.14.1 staged as optional runtime support

Public ReShade shader packages and, in FullNeural mode, the official swapchain override add-on are resolved from ReShade's current official catalogs at install/update time. Auto mode uses FullNeural on validated RTX 50-class hardware and VisualOnly on other GPUs. Binary-sensitive DLSS/NR/Bridge runtime packages remain pinned and verified rather than being blindly advanced to incompatible "latest" combinations. Third-party/proprietary runtime packages are not committed to this repository.

## v1 — legacy ASI prototype

The original OptiScaler-based `SecretEMKO.asi` work remains in the repository for reference. It is no longer the preferred architecture after FiveM-specific D3D11 startup compatibility testing showed that keeping graphics-device creation outside the ASI is substantially cleaner.

## Important implementation status

Neural Rendering is the v2 focus. The current RenoDX DLSS 5 v4.7 consumer is single-pass, so v2 does **not** fake a 2/3-pass control.

Frame Generation remains subject to the SECRET EMKO product ceiling of 2x/3x total, but the v2 preview does not arm a FiveM FG provider until the required motion/depth/HUD-less-colour/swapchain/pacing path is validated.

See `v2/VERSIONS.json` and `v2/THIRD_PARTY_NOTICES.md` for exact provenance and licensing notes.


## Installer compatibility model

v2.0.0-rc2 uses a clean-room `plugins` strategy. Existing non-SECRET-EMKO plugin folders are renamed and preserved before a fresh active `plugins` directory is created. First-install failures restore the original directory automatically; uninstall restores it later while preserving the removed SECRET EMKO setup as a separate folder. This protects existing FiveM RP mod setups instead of modifying them in place.

Server policy still applies: FiveM servers may disallow client plugins, so FullNeural cannot be guaranteed on every RP server.
