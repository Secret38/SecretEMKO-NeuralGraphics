# SECRET EMKO Neural Graphics v2 RC2 — RenoDX / ReShade architecture

SECRET EMKO v2 RC2 is the hardened FiveM **GTA V Legacy x64** line. It uses a ReShade-native control surface, public RenoDX infrastructure and DLSS 5 Bridge, with an installer designed for ordinary RP players rather than a single developer machine.

## What the installer now does

Run:

```bat
INSTALL_SECRET_EMKO.bat
```

RC2 automatically resolves the FiveM Legacy installation. It supports the standard LocalAppData layout and custom installations discoverable from FiveM shortcuts; if necessary it opens a FiveM.exe picker.

If no `plugins` folder exists, it creates one. If a non-SECRET-EMKO `plugins` folder already contains files, the default **Isolate** mode renames the entire existing folder to `plugins.before-secret-emko.<timestamp>`, creates a clean new `plugins` folder, migrates only a compatible ReShade loader and the old `reshade-shaders` library, and leaves arbitrary DLL/ASI/add-on hooks safely archived.

A failed first isolated install attempts an automatic rollback to the original plugins folder. Uninstall snapshots the SECRET EMKO environment and restores the original folder when one existed.

See `COMPATIBILITY.md` for the detailed behavior and limits.

## Hardware modes

**Full Neural mode** is automatically selected only when an NVIDIA GeForce RTX 50 Series GPU is detected. NVIDIA currently documents DLSS 5 3D-Guided Neural Rendering for RTX 50 Series hardware.

Other NVIDIA, AMD and Intel GPUs receive **visual-compatibility mode**: SECRET EMKO UI, ReShade, Main/Stream presets and public shader/add-on content still install, but the installer does not pretend that DLSS 5 Neural Rendering is supported.

An expert `-ForceNeuralStack` switch exists for controlled testing; it is not a compatibility guarantee.

## ReShade and presets

The installer uses the current official ReShade Full Add-on setup when needed and verifies that the installed `dxgi.dll` exposes the ReShade add-on API.

The ReShade content manager reads the live official `EffectPackages.ini` and `Addons.ini`, installs the public shader packages required by the shipped presets, installs the official `swapchain_override` add-on, and writes portable relative paths.

`Secret_Emko_Main.ini` remains the default preset and `Secret_Emko_Stream.ini` is the lighter stream preset. Existing `reshade-shaders` content is carried into an isolated install so user-owned effects such as an existing QuantV setup can remain available. SECRET EMKO does not obtain proprietary packages from unofficial mirrors. If an external effect is absent, that unavailable technique is disabled in the installed preset rather than leaving the default in a broken state.

## Runtime policy

- RenoDX framework: current upstream `origin/main` at build time; exact SHA recorded in `BUILD-MANIFEST.json`.
- ReShade core/effect/add-on catalogs: current official upstream at install time.
- DLSS 5 Bridge 1.4.12, RenoDX DLSS 5 consumer 4.70, DLSS SR 310.9.1, DLSS NR 310.8.0 and Streamline 2.14.1 remain pinned/verified where binary compatibility matters.

This deliberately separates "safe to track latest" content from binary-sensitive runtime combinations.

## Multiplayer / RP servers

FiveM supports a plugins folder, but server owners can disallow client plugins. ReShade Full Add-on Support also warns about multiplayer use. SECRET EMKO does **not** bypass plugin policy, Pure Mode, anti-cheat, ReShade network/depth restrictions or server rules.

That means RC2 can make installation portable and reversible, but it cannot make the stack work on a server that intentionally blocks it.

## FiveM Enhanced

RC2 is **Legacy-only**. FiveM for GTAV Enhanced is a separate client line in 2026; the installer fails closed if it detects only Enhanced instead of guessing a path.

## Frame Generation and pass count

FiveM Frame Generation remains gated. Runtime DLL presence is not treated as proof of a working FG integration; valid motion/depth/HUD-less colour, swapchain ownership and pacing are still required.

The current RenoDX DLSS 5 consumer path is treated as one real pass. SECRET EMKO does not expose fake 2/3-pass buttons.

## Diagnostics

Keep after testing:

- `ReShade.log`
- `dlss5-bridge.log` in Full Neural mode
- any FiveM crash dump
- `%LOCALAPPDATA%\SecretEMKO\state\install-state-*.json`

The install state records the resolved FiveM path, detected GPUs, chosen hardware mode, archived original plugins folder and managed files.
