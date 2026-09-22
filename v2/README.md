# SECRET EMKO Neural Graphics v2 — RenoDX / ReShade architecture

This is the clean v2 line for **FiveM GTA V Legacy x64**. It replaces the invasive v1 ASI architecture with a native **ReShade add-on control surface** plus the public RenoDX ecosystem and NIGos DLSS 5 Bridge.

## Goals

- Keep FiveM's normal D3D11 device creation intact.
- Use the ReShade instance already known to work in `FiveM.app\plugins\dxgi.dll`.
- Present one coherent, modern `SECRET EMKO Neural Graphics` page inside ReShade's **Add-ons** tab.
- Use current/pinned components and reproducible hashes.
- Make quality profiles explicit and reversible.
- Never pretend a dependency or feature is active when it is merely present on disk.

## Current stack

- RenoDX framework main pinned to `9b212edad4dde9bca2b823b1e045b712b1a8d854`.
- ReShade Full Add-on Support 6.8.0 or newer.
- NIGos DLSS 5 Bridge 1.4.12 stable.
- RenoDX DLSS 5 consumer 4.70.
- NVIDIA DLSS SR 310.9.1.
- NVIDIA DLSS Neural Rendering 310.8.0 (RTX 50 original runtime).
- NVIDIA Streamline 2.14.1 staged as optional modern runtime support.

See `VERSIONS.json` for hashes and provenance.

## Install

Extract the release and run:

```bat
INSTALL_SECRET_EMKO.bat
```

The installer targets:

```text
%LOCALAPPDATA%\FiveM\FiveM.app\plugins
```

It preserves the existing ReShade `dxgi.dll`, backs up files it manages, installs the Secret EMKO/Bridge add-ons, downloads the pinned neural consumer and NVIDIA runtimes, writes GTA/FiveM bridge defaults, installs the SECRET EMKO ReShade presets, updates their required public shader packages from ReShade's official package index, and verifies the managed runtime files.

The release also includes `swapchain_override.addon64`, compiled during the build from the official `crosire/reshade` source matching the latest official ReShade release tag.

After installation, start FiveM and open ReShade. In **Add-ons**, choose **SECRET EMKO Neural Graphics** and start with **Enhanced**. The default ReShade preset is `Secret_Emko_Main.ini`; `Secret_Emko_Stream.ini` is the lighter streaming preset.

## Quality profiles

**Enhanced** is the default quality-first profile. Natural is the compatibility baseline. Ultra Detail increases optical-flow effort and neural structure strength and should be validated in motion.

The raw NVIDIA/RenoDX **Cinematic** model style is deliberately not used by production profiles because recent v4.x reports include a startup fault on at least one reference system with `NRStyle=2`. It remains available as an explicitly experimental raw control.

## Pass count

The current RenoDX DLSS 5 v4.7 core is single-pass. v2 therefore exposes **one real pass**, not cosmetic 2/3-pass buttons. The product still reserves 1–3 as its design ceiling; extra passes will only be enabled when the current core exposes a safe, testable independent-history path.

## Frame Generation

Streamline/DLSSG runtime files can be staged by the installer, but **FiveM Frame Generation is not armed in preview1**. A usable FG integration needs valid motion/depth/HUD-less colour, swapchain ownership and pacing. The UI shows readiness but intentionally does not claim FG is working from DLL presence alone. Product policy remains 2x/3x total maximum when a validated provider is added.

## Multiplayer / depth

ReShade can restrict depth access during network play. SECRET EMKO does not bypass that protection. The FiveM synthetic route therefore uses DLSS 5 Bridge's hardware optical-flow path as the primary motion source.

## Troubleshooting

Keep these files after each test:

- `ReShade.log`
- `dlss5-bridge.log`
- any FiveM crash dump

The Secret EMKO Diagnostics tab shows which files are present and loaded.


## ReShade preset / shader policy

- `Secret_Emko_Main.ini` is the main visual preset.
- `Secret_Emko_Stream.ini` is the streaming-oriented preset with the supplied SMAA/sharpen chain.
- ReShade search paths, cache and screenshots use relative paths so the package is not tied to one Windows username.
- Public shader dependencies are resolved on install from ReShade's current official `EffectPackages.ini` index and downloaded from the upstream URLs defined there.
- Proprietary packages such as QuantV/NVE are never fetched from third-party mirrors. If a preset references one and it is not already installed legitimately, the installer reports it instead of silently downloading an untrusted copy.
- ReShade itself follows the current official Full Add-on Support installer at install time. The neural runtime stack remains pinned and hash-verified until a newer combination has been validated against the SECRET EMKO bridge/API contract.
