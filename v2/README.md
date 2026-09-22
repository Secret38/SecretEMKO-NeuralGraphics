# SECRET EMKO Neural Graphics v2 RC2

RC2 is the hardened **FiveM GTA V Legacy x64** distribution. The key change is that "portable for RP players" is no longer treated as the same thing as "force the Full Add-on neural stack everywhere."

## Install

> **Do not use GitHub `Code -> Download ZIP` for Full Neural.** The source archive does not contain the compiled `SecretEMKO.addon64` or packaged bridge. Download the successful GitHub Actions artifact `SecretEMKO-NeuralGraphics-v2.0.0-rc2`, extract it completely, and run the installer from that extracted package.

For normal FiveM RP use, double-click:

```bat
INSTALL_SECRET_EMKO.bat
```

This installs **RP Visual**: the current official standard signed ReShade build plus the Secret Emko Main/Stream presets and their public shader dependencies.

For an RTX 50 Series system where the relevant server/environment explicitly permits ReShade Full Add-on client add-ons, use:

```bat
INSTALL_SECRET_EMKO_FULL_NEURAL.bat
```

That enables the Full Neural stack: ReShade Full Add-on Support, SECRET EMKO UI/add-on, RenoDX DLSS 5, DLSS 5 Bridge and the pinned NVIDIA neural runtimes.

## FiveM path and existing plugins

RC2 resolves standard and custom Legacy installs. It uses an explicit path when supplied, otherwise the standard LocalAppData install and discovered FiveM shortcuts; multiple discovered installations are resolved using the most recently modified `CitizenFX.ini`.

If no `plugins` directory exists, RC2 creates it.

If an unrelated `plugins` directory already contains files, RC2 defaults to **Isolate**: it renames the entire old folder to `plugins.before-secret-emko.<timestamp>`, creates a clean active `plugins` folder, and carries forward only the old `reshade-shaders` library. DLL/ASI/add-on hooks are kept intact in the archived old folder rather than being blindly mixed into the new graphics chain.

Failed first installs automatically attempt rollback. Uninstall snapshots the SECRET EMKO environment and restores the original plugins folder.

## Presets and external shaders

`Secret_Emko_Main.ini` is the default visual preset; `Secret_Emko_Stream.ini` is the lighter alternative. Public effects are resolved against ReShade's live official package catalog.

User-owned shader libraries are carried forward. Proprietary packages such as QuantV are not fetched from unofficial mirrors. If an external effect is missing, RC2 removes that unavailable technique from the installed preset copy instead of leaving the default preset in an error state.

## Compatibility boundary

FiveM documents that plugins can live in its application-data `plugins` directory and that servers may disallow them. ReShade also distinguishes the standard multiplayer-oriented build from Full Add-on Support. RC2 therefore uses the standard build for the default RP Visual path and requires explicit selection for Full Neural.

DLSS 5 3D-Guided Neural Rendering is only treated as supported on GeForce RTX 50 Series hardware. Other GPUs use RP Visual.

FiveM for GTAV Enhanced is not supported by this Legacy RC2 line.

## Runtime/update policy

RenoDX is built from current upstream main and its exact SHA is written to `BUILD-MANIFEST.json`. Public ReShade effect/add-on metadata follows current official catalogs. Binary-sensitive DLSS/NR/Bridge versions remain pinned and SHA-256 verified until a newer combination is validated together.

## Not claimed as complete yet

Frame Generation remains gated until a real FiveM motion/depth/HUD-less-colour/swapchain/pacing integration is validated. The current RenoDX DLSS 5 path remains one real pass.

See `COMPATIBILITY.md` for the detailed matrix and recovery behavior.
