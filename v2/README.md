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

The installer first detects FiveM's application-data location. The normal target is:

```text
%LOCALAPPDATA%\FiveM\FiveM.app\plugins
```

If FiveM is installed elsewhere, the installer also checks FiveM shortcuts; `-PluginsPath` remains available as an explicit override.

### Clean-room plugins behavior

If no `plugins` directory exists, it is created automatically. If a non-empty existing `plugins` directory exists and is not already owned by SECRET EMKO, the entire directory is renamed to a timestamped sibling such as `plugins.pre-SecretEMKO-20260923-010000`. A new clean `plugins` directory is then created for SECRET EMKO. Nothing in the previous directory is deleted.

The old shader directory is retained as a fallback search location after the current official shader packages. This lets proprietary/external effects such as an already-installed QuantV remain discoverable without copying or overwriting the original setup. A matching existing ReShade module may be reused; otherwise the current official ReShade module is extracted automatically from the official setup package.

If the first installation fails after isolation, the incomplete new directory is renamed to `plugins.SecretEMKO-failed-...` and the original `plugins` directory is automatically restored. Re-running an existing SECRET EMKO installation updates it in place instead of creating endless nested backups.

### Install modes

- **Auto**: RTX 50-class NVIDIA hardware selects FullNeural. Other GPUs select VisualOnly.
- **FullNeural**: ReShade Full Add-on Support + SECRET EMKO native add-on + RenoDX/DLSS stack. This is the validated neural path for RTX 50-class hardware in rc2.
- **VisualOnly**: standard ReShade + Main/Stream presets and public shader packages. No RenoDX/DLSS native add-on chain is injected, making this the broad-compatibility option for AMD, Intel, older RTX, laptops and unknown GPU configurations.

FullNeural is not presented as universally multiplayer-safe. FiveM servers can disallow plugins, and ReShade's Full Add-on build carries its own multiplayer warning. The installer therefore requires explicit confirmation before a FullNeural install unless an unattended deployment explicitly passes the acknowledgement flag.

The same installer then runs the integrated ReShade content manager. That manager reads ReShade's live official `EffectPackages.ini` and `Addons.ini`, installs the current shader packages needed by the shipped presets, installs the current official `swapchain_override` add-on, and merges portable relative paths into `ReShade.ini` instead of embedding a Windows username.

After installation, start FiveM and open ReShade. In **Add-ons**, choose **SECRET EMKO Neural Graphics** and start with **Enhanced** for the neural profile.

For post-processing, `Secret_Emko_Main.ini` is the default preset and `Secret_Emko_Stream.ini` is the lighter stream preset. Main retains the supplied QuantV configuration, but QuantV itself is not redistributed or downloaded from unofficial mirrors; if it is absent, the installer reports the missing external effect while still installing all official/public dependencies.

## Quality profiles

**Enhanced** is the default quality-first profile. Natural is the compatibility baseline. Ultra Detail increases optical-flow effort and neural structure strength and should be validated in motion.

The raw NVIDIA/RenoDX **Cinematic** model style is deliberately not used by production profiles because recent v4.x reports include a startup fault on at least one reference system with `NRStyle=2`. It remains available as an explicitly experimental raw control.

## Pass count

The current RenoDX DLSS 5 v4.7 core is single-pass. v2 therefore exposes **one real pass**, not cosmetic 2/3-pass buttons. The product still reserves 1–3 as its design ceiling; extra passes will only be enabled when the current core exposes a safe, testable independent-history path.

## Frame Generation

Streamline/DLSSG runtime files can be staged by the installer, but **FiveM Frame Generation is still gated in rc2**. A usable FG integration needs valid motion/depth/HUD-less colour, swapchain ownership and pacing. The UI shows readiness but intentionally does not claim FG is working from DLL presence alone. Product policy remains 2x/3x total maximum when a validated provider is added.

## Multiplayer / server compatibility

FiveM supports a `plugins` directory, but individual servers can disallow plugins. SECRET EMKO cannot override a server's policy and does not attempt to bypass it. VisualOnly is the lower-risk compatibility mode because it does not use the native Full Add-on/RenoDX chain. FullNeural requires ReShade Full Add-on Support and therefore must be treated as server-dependent.

ReShade can also restrict depth access during network play. SECRET EMKO does not bypass that protection. The FullNeural FiveM route therefore uses DLSS 5 Bridge's hardware optical-flow path as the primary motion source.

## Troubleshooting

Keep these files after each test:

- `ReShade.log`
- `dlss5-bridge.log`
- any FiveM crash dump

The Secret EMKO Diagnostics tab shows which files are present and loaded.


## Main-system update policy

`MAIN-SYSTEM.json` is the machine-readable policy for the v2 main system. Public ReShade content follows the current official upstream catalogs. The public RenoDX framework follows upstream main at build time. Binary-sensitive DLSS/NR/Bridge runtime packages remain pinned and SHA-256 verified until a newer combination has been validated together. This prevents an automatic "latest" update from silently breaking the FiveM rendering chain.
