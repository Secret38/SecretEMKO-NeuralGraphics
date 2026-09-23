# SECRET EMKO Neural Graphics v2 RC4

RC4 is the hardened **FiveM GTA V Legacy x64** distribution. The key change is that "portable for RP players" is no longer treated as the same thing as "force the Full Add-on neural stack everywhere."

## Install

> **Do not use GitHub `Code -> Download ZIP` for Full Neural.** The source archive does not contain the compiled `SecretEMKO.addon64` or packaged bridge. Download the successful GitHub Actions artifact `SecretEMKO-NeuralGraphics-v2.0.0-rc4`, extract it completely, and run the installer from that extracted package.

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

### RC4 control model

SECRET EMKO is the intended single control surface. The verified RenoDX v4.70 settings page is removed from the ReShade settings UI only after SECRET EMKO has successfully discovered and validated the live-control surface in the current session; if that proof fails, the original RenoDX page remains visible as a recovery fallback. DLSS 5 Bridge already has no separate ImGui settings page. The backend modules may still appear in ReShade's technical loaded-add-on inventory because they are genuinely loaded components.

Supported RenoDX controls are applied live through the exact v4.70 provider's own settings callback and immediately read back for confirmation. This adapter is fail-closed: the v4.70 file size, SHA-256, code fingerprints and ImGui dispatch identity must all match. A newer/different RenoDX build is not guessed or memory-patched.

Bridge controls are persisted to `dlss5-bridge.cfg`; upstream Bridge re-reads that file while the game is running, normally within about one second.

### RC4 synthetic FiveM path

FiveM GTA V Legacy does not expose a native DLSS contract. RC4 therefore pins the official upstream DLSS 5 Bridge `v1.4.13-pre8` build and uses its synthetic route. With `ofa_grid=1`, `2` or `4`, motion guidance comes from the bridge's internal NVIDIA Optical Flow path; a separate ReShade motion-vector shader is not required. `ofa_grid=0` remains the explicit external-provider mode.

The DLSS SR runtime remains managed in `FiveM.app\\plugins`. At Full Neural startup SECRET EMKO loads that exact `nvngx_dlss.dll` by full path and, only when the current host is FiveM's disposable `data\\cache\\subprocess` GTA process, creates an executable-local hardlink (copy fallback). This satisfies NGX's SuperSampling snippet lookup without asking users to edit dynamic cache folders manually.

The header progress bar is installation readiness only. Runtime diagnostics separately report **WAITING**, **ARMED**, **BLOCKED** or **ACTIVE**. ACTIVE is only shown after current-session bridge telemetry confirms delivered frames.

Turning Neural Rendering off does not call `FreeLibrary` on third-party add-ons. Runtime unloading is intentionally avoided because both backends install hooks/callback state that is safer to retire at process shutdown. Instead SECRET EMKO soft-disables the active pipeline and writes ReShade's official `DisabledAddons` configuration so `renodx-dlss5.addon64` and `dlss5-bridge.addon64` are not loaded at the next start. Turning Neural back on in a session where those backends were skipped schedules them for the next start and requires one restart.

## FiveM path and existing plugins

RC4 resolves standard and custom Legacy installs. It uses an explicit path when supplied, otherwise the standard LocalAppData install and discovered FiveM shortcuts; multiple discovered installations are resolved using the most recently modified `CitizenFX.ini`.

If no `plugins` directory exists, RC4 creates it.

If an unrelated `plugins` directory already contains files, RC4 defaults to **Isolate**: it renames the entire old folder to `plugins.before-secret-emko.<timestamp>`, creates a clean active `plugins` folder, and carries forward only the old `reshade-shaders` library. DLL/ASI/add-on hooks are kept intact in the archived old folder rather than being blindly mixed into the new graphics chain.

Failed first installs automatically attempt rollback. Uninstall snapshots the SECRET EMKO environment and restores the original plugins folder.

## Presets and external shaders

`Secret_Emko_Main.ini` is the default visual preset; `Secret_Emko_Stream.ini` is the lighter alternative. Public effects are resolved against ReShade's live official package catalog.

User-owned shader libraries are carried forward. Proprietary packages such as QuantV are not fetched from unofficial mirrors. If an external effect is missing, RC4 removes that unavailable technique from the installed preset copy instead of leaving the default preset in an error state.

## Compatibility boundary

FiveM documents that plugins can live in its application-data `plugins` directory and that servers may disallow them. ReShade also distinguishes the standard multiplayer-oriented build from Full Add-on Support. RC4 therefore uses the standard build for the default RP Visual path and requires explicit selection for Full Neural.

DLSS 5 3D-Guided Neural Rendering is only treated as supported on GeForce RTX 50 Series hardware. Other GPUs use RP Visual.

FiveM for GTAV Enhanced is not supported by this Legacy RC4 line.

## Persistence

SECRET EMKO writes the desired Neural state to `ReShade.ini`, Bridge state to `dlss5-bridge.cfg`, and backend load policy to `[ADDON] DisabledAddons` plus `[SecretEMKO] BackendsNextStart`. Re-running the installer preserves existing user-tuned values and only supplies defaults for missing keys.

Not every legacy/provider field is exposed by the verified RenoDX v4.70 callback. `NRPaperWhiteScale`, `NRTransferStrength` and `NRColorStrength` remain persisted but are not falsely labelled live; changing one keeps a restart-required indication.

## Runtime/update policy

RenoDX is built from current upstream main and its exact SHA is written to `BUILD-MANIFEST.json`. Public ReShade effect/add-on metadata follows current official catalogs. Binary-sensitive DLSS/NR/Bridge versions remain pinned and SHA-256 verified until a newer combination is validated together.

## Not claimed as complete yet

Frame Generation remains gated until a real FiveM motion/depth/HUD-less-colour/swapchain/pacing integration is validated. The current RenoDX DLSS 5 path remains one real pass.

See `COMPATIBILITY.md` for the detailed matrix and recovery behavior.
