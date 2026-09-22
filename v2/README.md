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

- RenoDX public framework is built from the current upstream `origin/main`; the exact commit is recorded in each `BUILD-MANIFEST.json`.
- ReShade Full Add-on Support 6.8.0+; when installation is required, the installer resolves the current official version from reshade.me.
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

It preserves an existing compatible ReShade `dxgi.dll`, backs up managed configuration, installs the Secret EMKO/Bridge add-ons, downloads the pinned neural consumer and NVIDIA runtimes, writes GTA/FiveM bridge defaults, and verifies hashes.

The same installer then runs the integrated ReShade content manager. That manager reads ReShade's live official `EffectPackages.ini` and `Addons.ini`, installs the current shader packages needed by the shipped presets, installs the current official `swapchain_override` add-on, and merges portable relative paths into `ReShade.ini` instead of embedding a Windows username.

After installation, start FiveM and open ReShade. In **Add-ons**, choose **SECRET EMKO Neural Graphics** and start with **Enhanced** for the neural profile.

For post-processing, `Secret_Emko_Main.ini` is the default preset and `Secret_Emko_Stream.ini` is the lighter stream preset. Main retains the supplied QuantV configuration, but QuantV itself is not redistributed or downloaded from unofficial mirrors; if it is absent, the installer reports the missing external effect while still installing all official/public dependencies.

## Quality profiles

**Enhanced** is the default quality-first profile. Natural is the compatibility baseline. Ultra Detail increases optical-flow effort and neural structure strength and should be validated in motion.

The raw NVIDIA/RenoDX **Cinematic** model style is deliberately not used by production profiles because recent v4.x reports include a startup fault on at least one reference system with `NRStyle=2`. It remains available as an explicitly experimental raw control.

## Pass count

The current RenoDX DLSS 5 v4.7 core is single-pass. v2 therefore exposes **one real pass**, not cosmetic 2/3-pass buttons. The product still reserves 1–3 as its design ceiling; extra passes will only be enabled when the current core exposes a safe, testable independent-history path.

## Frame Generation

Streamline/DLSSG runtime files can be staged by the installer, but **FiveM Frame Generation is still gated in rc1**. A usable FG integration needs valid motion/depth/HUD-less colour, swapchain ownership and pacing. The UI shows readiness but intentionally does not claim FG is working from DLL presence alone. Product policy remains 2x/3x total maximum when a validated provider is added.

## Multiplayer / depth

ReShade can restrict depth access during network play. SECRET EMKO does not bypass that protection. The FiveM synthetic route therefore uses DLSS 5 Bridge's hardware optical-flow path as the primary motion source.

## Troubleshooting

Keep these files after each test:

- `ReShade.log`
- `dlss5-bridge.log`
- any FiveM crash dump

The Secret EMKO Diagnostics tab shows which files are present and loaded.


## Main-system update policy

`MAIN-SYSTEM.json` is the machine-readable policy for the v2 main system. Public ReShade content follows the current official upstream catalogs. The public RenoDX framework follows upstream main at build time. Binary-sensitive DLSS/NR/Bridge runtime packages remain pinned and SHA-256 verified until a newer combination has been validated together. This prevents an automatic "latest" update from silently breaking the FiveM rendering chain.
