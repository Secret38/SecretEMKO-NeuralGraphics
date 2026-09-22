# SECRET EMKO v2 RC2 — Compatibility

## Supported target

SECRET EMKO v2 RC2 targets **FiveM GTA V Legacy on 64-bit Windows**. It is not an Enhanced build.

The installer supports the normal `%LOCALAPPDATA%\FiveM\FiveM.app` layout and custom FiveM Legacy locations. It resolves an explicit path first, then the standard install, then FiveM shortcuts, and finally offers a FiveM.exe picker when running interactively.

## Existing plugins folder

The default mode is **Isolate**.

If `FiveM.app\plugins` already contains files, the installer renames that complete folder to:

```text
plugins.before-secret-emko.YYYYMMDD-HHMMSS
```

It then creates a clean new `plugins` folder for SECRET EMKO.

To preserve useful user content without reintroducing arbitrary injectors, the installer migrates:

- a compatible ReShade Full Add-on `dxgi.dll`, when present;
- the existing `reshade-shaders` library.

Other DLLs, ASI files and ReShade add-ons remain in the archived old folder and are not automatically re-enabled. This is deliberate: blindly mixing unknown hooks is one of the main causes of FiveM startup instability.

If installation fails during a first isolated install, the installer attempts to move the failed SECRET EMKO folder aside and restore the original `plugins` folder automatically.

The uninstaller does the inverse: it snapshots the current SECRET EMKO plugins folder and restores the original pre-install plugins folder when one exists.

## Hardware modes

| Hardware | RC2 behavior |
| --- | --- |
| GeForce RTX 50 Series | Full Neural mode: SECRET EMKO + ReShade + RenoDX DLSS 5 + DLSS 5 Bridge + NVIDIA NR/SR runtime |
| GeForce RTX 20/30/40 | Visual-compatibility mode by default; no claim that DLSS 5 Neural Rendering works |
| AMD / Intel GPU | Visual-compatibility mode: ReShade presets and SECRET EMKO UI |
| Unknown GPU | Visual-compatibility mode unless explicitly forced |

`-ForceNeuralStack` is an expert override. It does not turn unsupported hardware into a supported configuration.

## FiveM for GTAV Enhanced

Not supported by RC2. If only the Enhanced client is detected, the installer stops instead of writing files into the wrong client.

## RP servers / multiplayer

FiveM officially allows a plugins folder, but servers can disallow client plugins. ReShade Full Add-on Support also carries its own multiplayer warning. SECRET EMKO does not bypass server plugin policy, Pure Mode, anti-cheat, network/depth restrictions or other protections.

Therefore **no installer can guarantee that SECRET EMKO will be usable on every RP server**. Compatibility depends on the server allowing the relevant client-side plugin/add-on stack.

## QuantV and other external effects

SECRET EMKO does not download proprietary graphics packages from unofficial mirrors. Existing `reshade-shaders` content is migrated from an isolated previous plugins folder. If the shipped Main preset still references an external effect that is not available, RC2 removes that unavailable technique from the installed copy so the remaining public effect stack starts cleanly instead of presenting a broken default preset.

## ReShade core

If no compatible Full Add-on `dxgi.dll` exists, RC2 downloads the current official Full Add-on installer from reshade.me and attempts a headless DXGI installation into the clean FiveM plugins directory. The finished installation is verified by checking for the ReShade add-on API export.

## Scope limits

RC2 does not claim FiveM Frame Generation is operational. The UI keeps FG gated until a validated motion/depth/HUD-less-colour/swapchain/pacing path exists. The current RenoDX DLSS 5 consumer path is treated as one real neural pass rather than exposing cosmetic multi-pass controls.
