# SECRET EMKO v2 RC2 — Compatibility

## Target

RC2 targets **FiveM GTA V Legacy on 64-bit Windows**. FiveM for GTAV Enhanced is not silently treated as Legacy; if Legacy cannot be resolved, installation stops.

FiveM's documented default application-data location is under `%LOCALAPPDATA%\FiveM\FiveM.app`, while custom application locations are possible. RC2 accepts explicit paths, detects the standard location, inspects FiveM shortcuts and can fall back to an interactive FiveM.exe picker.

## One-click modes

### INSTALL_SECRET_EMKO.bat — RP Visual

This is the default distribution path for ordinary RP players.

It installs the current official **standard signed ReShade build**, public shader packages, and `Secret_Emko_Main.ini` / `Secret_Emko_Stream.ini`. It does **not** activate external ReShade add-ons, RenoDX DLSS 5, DLSS 5 Bridge, Neural Rendering or swapchain_override.

This has the broadest compatibility profile, but it still cannot override a FiveM server that disallows client plugins.

### INSTALL_SECRET_EMKO_FULL_NEURAL.bat — Full Neural

This is an explicit advanced mode for **GeForce RTX 50 Series** systems and only for environments where the server/user policy permits the Full Add-on stack.

It installs ReShade Full Add-on Support, `SecretEMKO.addon64`, RenoDX DLSS 5, DLSS 5 Bridge, the pinned NVIDIA neural runtimes and the official swapchain override add-on.

ReShade itself documents Full Add-on Support as unsuitable as a general multiplayer default, so RC2 never silently upgrades an RP Visual installation to Full Neural.

## Existing plugins folder

Default behavior is **Isolate**. If `FiveM.app\plugins` already contains files, RC2 renames the complete directory to:

```text
plugins.before-secret-emko.YYYYMMDD-HHMMSS
```

It then creates a clean new active `plugins` directory. The old `reshade-shaders` library is copied into the clean environment so owned custom effects can remain available. Existing DLL, ASI and ReShade add-on binaries are **not** automatically reactivated; they remain intact in the archived old folder.

If a first isolated installation fails, RC2 attempts to move the failed environment aside and restore the original plugins folder automatically. Uninstall performs the inverse: it preserves the current SECRET EMKO folder as a snapshot and restores the original pre-install folder when present.

## Hardware matrix

| Setup | Supported RC2 path |
| --- | --- |
| RTX 50 Series | RP Visual; or explicit Full Neural |
| RTX 20/30/40 | RP Visual |
| AMD / Intel | RP Visual |
| Unknown GPU | RP Visual |
| FiveM GTAV Enhanced | Not supported by RC2 |

`-ForceNeuralStack` exists only for expert validation; it is not a hardware support claim.

## RP server limits

FiveM supports a plugins directory, but server owners can disallow client plugins. Pure Mode can also block modified client files. RC2 does not bypass these restrictions or anti-cheat.

Therefore "installs correctly" and "is permitted/usable on every RP server" are separate questions. The installer can make the local setup deterministic and reversible; it cannot force a server to accept a prohibited client modification.

## QuantV / external effects

RC2 never downloads proprietary graphics packages from unofficial mirrors. Existing `reshade-shaders` content is migrated from the archived plugins folder. If the shipped Main preset references an effect that is still unavailable, that technique is removed from the **installed copy** of the preset so the remaining public stack starts cleanly.

## ReShade installation

Both ReShade modes are installed from the current official setup obtained from reshade.me. RC2 uses ReShade's supported headless setup arguments and verifies the installed build type before continuing.

## Current deliberate limits

FiveM Frame Generation is still gated; DLL presence is not counted as a functional FG provider. A correct implementation still requires validated motion/depth/HUD-less-colour, swapchain ownership and pacing.

The current RenoDX DLSS 5 provider is treated as one real neural pass. RC2 does not invent cosmetic 2/3-pass controls.
