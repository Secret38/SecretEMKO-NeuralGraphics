# SECRET EMKO Neural Graphics v2 — RenoDX / ReShade architecture

This is the clean v2 line for **FiveM GTA V Legacy x64**. It replaces the invasive v1 ASI architecture with a native **ReShade add-on control surface**, the public RenoDX framework and NIGos DLSS 5 Bridge.

## Design goals

- Leave FiveM's normal D3D11 device creation untouched.
- Reuse the ReShade Full Add-on Support instance already known to work in `FiveM.app\plugins\dxgi.dll`.
- Present one coherent, modern **SECRET EMKO Neural Graphics** panel in ReShade.
- Keep dependency provenance visible instead of renaming third-party binaries.
- Use version-pinned downloads, hashes, backups and reversible installation.
- Default to quality and temporal stability instead of maximum effect strength.

## Current v2 preview2 stack

- **RenoDX public framework:** pinned to `9b212edad4dde9bca2b823b1e045b712b1a8d854`.
- **ReShade:** 6.8.0 Full Add-on Support baseline. Existing `dxgi.dll` is preserved; ReShade itself is not bundled.
- **DLSS 5 Bridge:** 1.4.13-pre8, the latest immutable prerelease used by preview2. It contains the newer MinHook/lifecycle work; it is still a prerelease.
- **RenoDX DLSS5 neural consumer:** external binary, not part of the public RenoDX source tree. Installer offers:
  - `Latest`: 6.5.3.
  - `Compatibility`: 4.55.
  - `Auto` (default): chooses the compatibility channel on NVIDIA driver 616.64+ because current community reports document faults with newer consumer builds on that driver branch.
- **DLSS Super Resolution:** 310.9.1.
- **DLSS Neural Rendering runtime:** 310.8.0 original RTX 50 runtime, exact hash checked and NVIDIA signature verified.
- **NVIDIA Streamline:** 2.14.1 from NVIDIA's official release, hash checked.

See `VERSIONS.json` for the exact package hashes and provenance.

## One-click installation flow

Extract the GitHub Actions artifact and run:

```bat
INSTALL_SECRET_EMKO.bat
```

The installer targets:

```text
%LOCALAPPDATA%\FiveM\FiveM.app\plugins
```

It preserves the existing ReShade `dxgi.dll`, checks that it exposes the ReShade add-on API, backs up the files/configuration it manages, installs the Secret EMKO and Bridge add-ons, selects a RenoDX DLSS5 compatibility channel, verifies hashes/signatures, writes GTA/FiveM bridge defaults, and records install state for rollback.

The external RenoDX DLSS5 consumer and the RTX 50 neural runtime are **not bundled as Secret EMKO files**. The installer identifies them as external and requires confirmation before downloading them for local use.

If ReShade Full Add-on Support is missing, the installer opens the official ReShade 6.8.0 Add-on installer. It does not silently replace an existing `dxgi.dll`.

## Modern ReShade UI

Start FiveM, press **Home**, then open **Add-ons → SECRET EMKO Neural Graphics**.

The panel is organized into:
- **Overview** — readiness meter, loaded/on-disk dependency status and architecture summary.
- **Styles** — Natural, Clean, Detail, Enhanced, Cinematic and Ultra Detail with purpose and artifact warnings.
- **Neural** — model style, preset, Intensity, Global Tone, Local Tone, Structure, Character/Skin Structure, automatic mask and UI correction.
- **Quality** — Transfer Strength, Colour Strength, model resolution and motion/depth guidance.
- **Bridge** — synthetic GTA V Legacy contract, optical-flow grid/effort and safe defaults.
- **Frame Generation** — dependency/readiness status and the 2x/3x product policy.
- **Diagnostics** — file/load state plus the exact logs required for troubleshooting.
- **About** — attribution and third-party ownership.

Every non-obvious control has an inline explanation.

## Quality-first style profiles

**Enhanced** is the default:
- Natural NVIDIA model style for current stability.
- Intensity 1.20.
- Global Tone 1.05.
- Local Tone 1.05.
- Structure 1.35.
- Character/Skin Structure 1.00.
- Transfer Strength 1.00.
- Colour Strength 0.95.
- Optical-flow grid 2 / medium effort.
- Native neural model resolution on 6.x.

For a 3440×1440 RTX 50 system, start here. Evaluate moving footage, thin fences, foliage, hair, distant text, emissive edges and translucent UI before increasing structure.

**Natural** is the safest visual baseline. **Clean** is deliberately restrained. **Detail** increases fine structure without going to the maximum. **Cinematic** changes tone more than structure but deliberately uses the Natural model style for now. **Ultra Detail** is the stress profile and should be validated in motion.

## 0.00–2.00 expert range

Secret EMKO exposes the requested 0.00–2.00 UI range for Intensity/Tone/Structure/Skin and colour-transfer controls. A third-party consumer may internally clamp values that exceed what that particular build supports. The UI calls this out rather than pretending every external binary accepts every range identically.

## Model resolution

RenoDX DLSS5 6.x replaced the old `NREnableUpscaling` key with:
- `NRFollowInputRes=0`
- `NRResolutionScale=1`

Preview2 uses the new 6.x contract and exposes **0.25×–1.00×** model scale (25–100%). At 3440×1440 on RTX 50, **1.00×** is the quality-first default. The 4.x compatibility channel retains its older 1:1/no-upscale behavior.

## Pass count

The external RenoDX DLSS5 path is treated as **one real temporal pass**. Secret EMKO does not display fake 2/3-pass buttons. The product design ceiling remains 1–3, but extra passes will only be enabled when a current backend exposes a safe, independently historied multipass route that can be validated in FiveM.

## Frame Generation

Streamline/DLSSG runtimes can be staged, but **FiveM Frame Generation is not armed in preview2**. Presence of `nvngx_dlssg.dll` is not proof of a valid FG integration. GTA V Legacy still needs a validated source for motion/depth/HUD-less colour plus swapchain ownership and pacing.

When that provider is validated, Secret EMKO will expose only **2x or 3x total**, never 4x+.

## Multiplayer / depth

ReShade can restrict depth access during network play. SECRET EMKO does not bypass that protection. The GTA/FiveM synthetic route therefore prioritizes the bridge's hardware optical-flow path rather than depending on protected depth access.

## Test procedure

1. Start with **Enhanced**, FG off.
2. Use borderless display mode and a fixed native output resolution.
3. Drive/walk through a repeatable scene for several minutes.
4. Check motion stability before raising structure or lowering model resolution.
5. Close FiveM and keep:
   - `ReShade.log`
   - `dlss5-bridge.log`
   - any FiveM crash dump

A higher FPS counter by itself is not proof that Neural Rendering or generated frames are correct.
