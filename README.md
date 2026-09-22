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
- pinned/current component versions and SHA-256 verification
- one-run installer for the FiveM plugins directory
- backups and an uninstaller
- runtime diagnostics instead of silently assuming that a DLL loaded
- no PureDark proprietary source, authentication or paid-mod assets

Source and documentation live under [v2/](v2/README.md).

### Current v2 stack

- RenoDX public framework: pinned current main revision used by the build
- ReShade Full Add-on Support 6.8.0+
- DLSS 5 Bridge 1.4.12 stable
- RenoDX DLSS 5 consumer 4.70
- NVIDIA DLSS SR 310.9.1
- NVIDIA DLSS Neural Rendering 310.8.0 for RTX 50
- NVIDIA Streamline 2.14.1 staged as optional runtime support

Third-party/proprietary runtime packages are downloaded and verified by the installer instead of being committed to this repository.

## v1 — legacy ASI prototype

The original OptiScaler-based `SecretEMKO.asi` work remains in the repository for reference. It is no longer the preferred architecture after FiveM-specific D3D11 startup compatibility testing showed that keeping graphics-device creation outside the ASI is substantially cleaner.

## Important implementation status

Neural Rendering is the v2 focus. The current RenoDX DLSS 5 v4.7 consumer is single-pass, so v2 does **not** fake a 2/3-pass control.

Frame Generation remains subject to the SECRET EMKO product ceiling of 2x/3x total, but the v2 preview does not arm a FiveM FG provider until the required motion/depth/HUD-less-colour/swapchain/pacing path is validated.

See `v2/VERSIONS.json` and `v2/THIRD_PARTY_NOTICES.md` for exact provenance and licensing notes.
