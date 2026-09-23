# SECRET EMKO v2 RC3 — Compatibility

## Target

RC3 targets **FiveM GTA V Legacy on 64-bit Windows**. FiveM for GTAV Enhanced is not silently treated as Legacy; if Legacy cannot be resolved, installation stops.

FiveM's documented default application-data location is under `%LOCALAPPDATA%\FiveM\FiveM.app`, while custom application locations are possible. RC3 accepts explicit paths, detects the standard location, inspects FiveM shortcuts and can fall back to an interactive FiveM.exe picker.

## One-click modes

### INSTALL_SECRET_EMKO.bat — RP Visual

This is the default distribution path for ordinary RP players.

It installs the current official **standard signed ReShade build**, public shader packages, and `Secret_Emko_Main.ini` / `Secret_Emko_Stream.ini`. It does **not** activate external ReShade add-ons, RenoDX DLSS 5, DLSS 5 Bridge, Neural Rendering or swapchain_override.

This has the broadest compatibility profile, but it still cannot override a FiveM server that disallows client plugins.

### INSTALL_SECRET_EMKO_FULL_NEURAL.bat — Full Neural

This is an explicit advanced mode for **GeForce RTX 50 Series** systems and only for environments where the server/user policy permits the Full Add-on stack.

It installs ReShade Full Add-on Support, `SecretEMKO.addon64`, RenoDX DLSS 5, DLSS 5 Bridge, the pinned NVIDIA neural runtimes and the official swapchain override add-on.

ReShade itself documents Full Add-on Support as unsuitable as a general multiplayer default, so RC3 never silently upgrades an RP Visual installation to Full Neural.

## Existing plugins folder

Default behavior is **Isolate**. If `FiveM.app\plugins` already contains files, RC3 renames the complete directory to:

```text
plugins.before-secret-emko.YYYYMMDD-HHMMSS
```

It then creates a clean new active `plugins` directory. The old `reshade-shaders` library is copied into the clean environment so owned custom effects can remain available. Existing DLL, ASI and ReShade add-on binaries are **not** automatically reactivated; they remain intact in the archived old folder.

If a first isolated installation fails, RC3 attempts to move the failed environment aside and restore the original plugins folder automatically. Uninstall performs the inverse: it preserves the current SECRET EMKO folder as a snapshot and restores the original pre-install folder when present.

## Hardware matrix

| Setup | Supported RC3 path |
| --- | --- |
| RTX 50 Series | RP Visual; or explicit Full Neural |
| RTX 20/30/40 | RP Visual |
| AMD / Intel | RP Visual |
| Unknown GPU | RP Visual |
| FiveM GTAV Enhanced | Not supported by RC3 |

`-ForceNeuralStack` exists only for expert validation; it is not a hardware support claim.

## RP server limits

FiveM supports a plugins directory, but server owners can disallow client plugins. Pure Mode can also block modified client files. RC3 does not bypass these restrictions or anti-cheat.

Therefore "installs correctly" and "is permitted/usable on every RP server" are separate questions. The installer can make the local setup deterministic and reversible; it cannot force a server to accept a prohibited client modification.

## QuantV / external effects

RC3 never downloads proprietary graphics packages from unofficial mirrors. Existing `reshade-shaders` content is migrated from the archived plugins folder. If the shipped Main preset references an effect that is still unavailable, that technique is removed from the **installed copy** of the preset so the remaining public stack starts cleanly.

## ReShade installation

Both ReShade modes are installed from the current official setup obtained from reshade.me. RC3 uses ReShade's supported headless setup arguments and verifies the installed build type before continuing.

## Current deliberate limits

FiveM Frame Generation is still gated; DLL presence is not counted as a functional FG provider. A correct implementation still requires validated motion/depth/HUD-less-colour, swapchain ownership and pacing.

The current RenoDX DLSS 5 provider is treated as one real neural pass. RC3 does not invent cosmetic 2/3-pass controls.


## RC3 managed backend lifecycle

Full Neural keeps `renodx-dlss5.addon64` and `dlss5-bridge.addon64` installed because GTA V Legacy's D3D11 neural path requires both backends. They are not treated as separate user products.

When Neural Rendering is disabled in SECRET EMKO, the active bridge is switched to `source=off` / `synth=0` and the verified RenoDX v4.70 provider is switched off through its own settings callback when that adapter is available. The DLLs are deliberately not unloaded from a live process. ReShade's `DisabledAddons` list is updated so both backend add-ons are skipped entirely on the next game start.

When Neural Rendering is enabled again while the backends are still loaded, supported values apply live. If they were skipped at process start, SECRET EMKO removes the disable markers and asks for one restart so ReShade can load them normally.

The RenoDX live-control adapter is restricted to the exact v4.70 consumer, SHA-256 `D5ADF82EB44B065F4C590AC91FE824BAB07AFEA0EB9F994BDE936710C8593952`, and validates code fingerprints before use. Different builds fall back to persistent configuration/restart behavior rather than unsafe guessed offsets.


### UI fail-safe

SECRET EMKO hides the RenoDX settings page only after the exact pinned provider has passed hash/fingerprint checks and one hidden discovery invocation has exposed the expected controls. If live control cannot be proven, the RenoDX page remains available rather than leaving the user with no backend controls.

### Why backends are not unloaded mid-session

RC3 deliberately separates **soft-disable now** from **do not load next start**. RenoDX and DLSS 5 Bridge install native hooks/callbacks and own runtime state; force-unloading them from an active FiveM/ReShade process would create more crash risk than benefit. SECRET EMKO therefore idles the pipeline immediately and uses ReShade's official `DisabledAddons` mechanism so the modules are skipped on the next launch.
