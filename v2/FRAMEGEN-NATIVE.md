# SECRET EMKO RC5 — Native Frame Generation Architecture

RC5 deliberately separates the simple user-facing controls from the native GTA V Legacy input provider.

## Product goal

The normal player should only see:

- Frame Generation: Off / 2x / 3x
- Base FPS: Automatic or manual
- HUD Protection: Automatic / Strict / Off
- Automatic pause during menus, loading screens and display-mode changes

The implementation must fail closed. The UI must not report Frame Generation as available merely because `sl.dlss_g.dll` or `nvngx_dlssg.dll` exists.

## Verified GTA V constraint

Public GTAV Upscaler notes from PureDark state that GTA V does **not** expose engine motion vectors and that the mod patches large numbers of GTA shaders to inject them. Later changelogs describe additional fixes for QuantV/NVE-related shader paths where vehicles or roads stopped producing correct motion vectors.

That changes the SECRET EMKO implementation target: do not waste time searching for a complete pre-existing GTA motion-vector buffer. The production provider must build **shader-injected, geometry-derived motion vectors** from GTA's render pipeline.

## Native input provider contract

`SecretEMKO-FG.addon64` must provide frame-aligned GTA V Legacy data:

1. Shader-injected, geometry-derived dense motion vectors, including camera motion and dynamic objects.
2. The corresponding depth buffer and depth convention.
3. HUD-less scene color captured after normal scene post-processing but before GTA/FiveM UI.
4. UI alpha or UI color+alpha captured separately.
5. Camera matrices, jitter and frame index aligned to the presented frame.
6. Swap-chain ownership and deterministic present-thread control.
7. Menu/loading/resolution-change detection so FG can be suspended safely.
8. Frame pacing / Reflex integration and a stable base-frame limiter.
9. Recovery from D3D12 interop/device-loss conditions without freezing the presented image.

## Motion / Frame Generation coexistence policy

The important distinction is **not "motion versus Frame Generation"**. Frame Generation requires motion data.

Two different temporal paths exist:

- **Compatibility Motion**: DLSS 5 Bridge synthetic Neural Rendering uses NVIDIA Optical Flow because GTA has no native DLSS contract. This path is NR-only in SECRET EMKO and forces Frame Generation off.
- **GTA Shader Motion**: SECRET EMKO injects geometry motion into GTA shader paths. This is the production route for Frame Generation and can be shared with Neural Rendering once the provider explicitly reports a frame-aligned shared NR contract.

Public GTAV Upscaler AIO notes state that DLSS Neural Rendering and DLSS Frame Generation can run together. Therefore RC5 does **not** make NR and FG inherently mutually exclusive. It makes the **Optical-Flow compatibility path and native/shader-motion FG path mutually exclusive**.

Optical Flow is not accepted as the production Frame Generation input path. When 2x/3x FG is enabled, the synthetic Optical Flow bridge is disabled and the GTA shader-motion provider owns motion/depth/HUD/pacing input.

## HUD policy

Automatic HUD protection is the default:

- capture scene color before HUD/UI;
- capture UI alpha (preferred) or UI color+alpha;
- tag both for Frame Generation;
- recompose UI after generated-frame processing where the backend supports it;
- suspend FG for full-screen menus or UI-dominant transitions.

A Strict mode may additionally exclude problematic screen regions when a GTA effect cannot be separated cleanly.

## Multiplier policy

- Off: no generated frames and no FG interop overhead.
- 2x: generate one frame per engine-rendered frame.
- 3x: generate two frames per engine-rendered frame.
- No 4x+ mode in the normal SECRET EMKO interface.

## Base FPS policy

Automatic mode derives the base-frame target from display timing, selected multiplier, current GPU headroom and stability.

Manual mode exposes one slider only. It controls the engine-rendered/base FPS target, not the displayed/generated FPS.

## UI rule

The simple UI and the provider are separate layers. Advanced implementation details stay under Status/Advanced. Normal players should never need to configure motion-vector scale, Streamline tags, swap-chain flags or raw provider parameters.

## External technical basis checked for RC5

- NVIDIA Streamline DLSS-G Programming Guide 2.14.1: Frame Generation requires depth and dense motion vectors; best UI quality additionally uses HUD-less color plus UI alpha or UI color+alpha. The same guide recommends invalidating tags / disabling FG when inputs are invalid, such as menus/loading/video transitions.
- NVIDIA states the same depth and motion-vector inputs used by DLSS-SR can be used by DLSS-G.
- PureDark public GTAV Upscaler notes (2023) state GTA V has no engine motion-vector output and describe shader patching to inject motion vectors.
- PureDark public GTAV Upscaler notes (2026 AIO Build 08) state DLSS Neural Rendering works with DLSS Frame Generation.

SECRET EMKO uses these public facts only as architectural reference. It does not include PureDark source code, binaries, authentication, paid assets or proprietary shader patches.
