# SECRET EMKO Neural Graphics v2 Preview

A FiveM / GTA V Legacy focused graphics control layer built as a **ReShade add-on on top of RenoDX**, with the D3D11-to-D3D12 **DLSS 5 Bridge** built from source as a companion.

## Why v2 exists

The v1 ASI path had to intercept GTA/FiveM D3D device creation and caused a real `ERR_GFX_D3D_NOFEATURELEVEL_1` startup failure during testing. v2 moves the user-facing integration to ReShade's add-on system and RenoDX utilities instead of using executable-build offsets or owning GTA's D3D11 device setup.

## UI

Open ReShade with **Home** and select:

`SECRET EMKO // Neural Graphics`

The interface is intentionally quality-first and exposes:
- live dependency/status card
- Natural / Clean / Detail / Cinematic / Enhanced / Ultra Detail / Custom profiles
- 1-3 NR passes only
- 25-100% model resolution
- real Standard / Natural / Cinematic NR style selection
- Intensity, Local Tone, Local Structure and Skin Structure at 0.00-2.00
- transfer/colour controls
- Native Look policy
- texture/detail and MIP-bias policy
- Frame Generation Off / 2x / 3x total only
- target-output-FPS planning and HUD-safe policy
- per-control explanations/tooltips

### Quality-first baseline for 3440x1440

Start with **Enhanced**, **1 pass**, **100% model resolution**, `Intensity 1.20`, `Local Tone 1.00`, `Local Structure 1.35`, `Skin Structure 1.20`, transfer and colour strength `1.00`. Validate motion before trying 2 or 3 passes.

For Frame Generation, first establish stable base rendering with FG off. Then try 2x total. A 120 FPS output target corresponds to roughly 60 base FPS at 2x or 40 base FPS at 3x, but latency/frametime quality matters more than the arithmetic.

## Installation

1. Keep/install **ReShade 6.8.0 with full add-on support** as `FiveM.app\plugins\dxgi.dll`.
2. Run `INSTALL_FIVEM.cmd`.
3. Keep only one neural consumer/provider active.
4. Supply a trusted `nvngx_dlssnr.dll` separately when the neural backend requires it.
5. Start FiveM, press **Home**, and open the Secret EMKO tab.

The package intentionally does not redistribute the ReShade binary because ReShade's official download page asks projects to link users to the official site rather than redistribute its binaries.

## Important preview boundary

This branch builds the **new Secret EMKO RenoDX UI/control plane** and the current open-source D3D11 bridge. It is not yet the final independent Secret EMKO feature-18 neural consumer. The closed `renodx-dlss5.addon64` is not copied, modified, renamed or redistributed because its source/licence is not published in the RenoDX repository.

The final v2 architecture is therefore being built in two clean layers:
1. the already-source-built RenoDX/ReShade UI + bridge;
2. an open-source Secret EMKO neural consumer that owns DLSSNR feature 18 without relying on a closed RenoDX binary.

This avoids repeating the PureDark-style binary-patching approach.

## Pinned upstream state

- RenoDX: `9b212edad4dde9bca2b823b1e045b712b1a8d854` (2026-09-22 current main when v2 was started)
- DLSS5 Bridge: `d1cc508a7097534c5c0e01a868ebe3b6657b932b`
- ReShade baseline: 6.8.0 full add-on support
- NVIDIA Streamline baseline: 2.14.1
