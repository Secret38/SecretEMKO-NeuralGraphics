# SECRET EMKO RC5 — Native Frame Generation Architecture

RC5 deliberately separates the simple user-facing controls from the native GTA V Legacy input provider.

## Product goal

The normal player should only see:

- Frame Generation: Off / 2x / 3x
- Base FPS: Automatic or manual
- HUD Protection: Automatic / Strict / Off
- Automatic pause during menus, loading screens and display-mode changes

The implementation must fail closed. The UI must not report Frame Generation as available merely because `sl.dlss_g.dll` or `nvngx_dlssg.dll` exists.

## Native input provider contract

A future `SecretEMKO-FG.addon64` must provide frame-aligned GTA V Legacy data:

1. Geometry-derived dense motion vectors, including camera motion and dynamic objects.
2. The corresponding depth buffer and depth convention.
3. HUD-less scene color captured after normal scene post-processing but before GTA/FiveM UI.
4. UI alpha or UI color+alpha captured separately.
5. Camera matrices, jitter and frame index aligned to the presented frame.
6. Swap-chain ownership and deterministic present-thread control.
7. Menu/loading/resolution-change detection so FG can be suspended safely.
8. Frame pacing / Reflex integration and a stable base-frame limiter.
9. Recovery from D3D12 interop/device-loss conditions without freezing the presented image.

## Motion policy

Optical Flow is not accepted as the production Frame Generation input path.

The current DLSS 5 Bridge optical-flow route remains a compatibility fallback for the separate synthetic Neural Rendering path only. The production FG provider must use geometry-derived GTA motion data.

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
