# SECRET EMKO Neural Graphics

**Modern visual and neural-rendering control system for FiveM GTA V Legacy x64.**  
Created and maintained by **Secret EMKO** · GitHub owner: **@Secret38**

Current release candidate: **v2.0.0-rc4**

> One product. One installer. One control surface.  
> ReShade, RenoDX, DLSS 5 Bridge and NVIDIA runtimes are treated as backend technologies where required — the user-facing product is **SECRET EMKO Neural Graphics**.

## Who this is for

### RP Visual
For normal FiveM RP players who want a clean, reversible graphics setup with:

- SECRET EMKO Main and Stream presets
- current public ReShade shader dependencies
- automatic FiveM Legacy path detection
- safe isolation of an existing `plugins` folder
- rollback and uninstall restore
- no neural/native add-on stack

Use:

```text
INSTALL_SECRET_EMKO.bat
```

### Full Neural
For **GeForce RTX 50 Series** systems where the server/environment permits ReShade Full Add-on client add-ons.

Adds:

- SECRET EMKO Neural Graphics control surface
- verified RenoDX DLSS 5 neural backend
- DLSS 5 Bridge backend for FiveM GTA V Legacy D3D11
- pinned and verified NVIDIA DLSS Neural Rendering / DLSS SR runtimes
- internal NVIDIA Optical Flow motion guidance on the synthetic path (no separate motion-vector shader required by default)
- automatic DLSS SR runtime preparation for FiveM's dynamic GTA subprocess; no manual cache-folder DLL copy
- live neural parameter control where the verified backend exposes it
- persistent backend load policy between launches

Use:

```text
INSTALL_SECRET_EMKO_FULL_NEURAL.bat
```

## End users: download the built package

**Do not use GitHub `Code -> Download ZIP` as the Full Neural installer.**

The source archive intentionally does not contain the compiled native add-ons.

Download the latest successful GitHub Actions artifact named:

```text
SecretEMKO-NeuralGraphics-v2.0.0-rc4
```

Then:

1. Extract the ZIP completely.
2. Close FiveM and GTA V.
3. Run the installer for the desired mode.
4. Start FiveM.
5. Open ReShade with **Home / Pos1**.
6. Use **SECRET EMKO Neural Graphics** as the primary settings surface.

## Clean-room FiveM installation

SECRET EMKO is designed to avoid destroying an existing FiveM setup.

If `FiveM.app\plugins` does not exist, it is created automatically.

If an unrelated non-empty `plugins` folder already exists, the default behavior is:

```text
plugins
  -> plugins.before-secret-emko.<timestamp>

new clean plugins
  -> SECRET EMKO environment
```

Existing DLL/ASI/add-on hooks remain in the archived folder instead of being mixed blindly into the new graphics chain.

If the first isolated installation fails, SECRET EMKO attempts to restore the original `plugins` folder automatically.

Uninstall preserves the removed SECRET EMKO environment and restores the original pre-SECRET-EMKO plugins folder when one existed.

## SECRET EMKO as the main system

In Full Neural mode, the intended control model is:

```text
SECRET EMKO Neural Graphics
        |
        +-- Profiles
        +-- Neural Rendering
        +-- Quality
        +-- Bridge
        +-- Diagnostics
        |
        +-- RenoDX backend
        +-- DLSS 5 Bridge backend
        +-- NVIDIA DLSS runtimes
```

The verified RenoDX v4.70 settings page is hidden only after SECRET EMKO proves that live control works in the current session. If verification fails, the original RenoDX page remains visible as a recovery fallback.

DLSS 5 Bridge has no separate ImGui settings page and remains backend-only.

## Live control and persistence

Supported RenoDX settings are applied through the verified provider's own settings callback and read back immediately for confirmation.

Bridge settings are written to `dlss5-bridge.cfg`; the bridge re-reads its configuration while the game is running.

RC4 pins DLSS 5 Bridge `v1.4.13-pre8` because its synthetic path can generate motion guidance with NVIDIA Optical Flow (`ofa_grid=1/2/4`). SECRET EMKO preloads the pinned `nvngx_dlss.dll` from the managed plugins directory and relays it only into FiveM's disposable `data\\cache\\subprocess` host when NGX requires an executable-local SR snippet. The UI now distinguishes **installed**, **armed**, **blocked** and **active**; file presence alone is not reported as proof of Neural Rendering.

Persistent state is stored in:

```text
ReShade.ini
dlss5-bridge.cfg
[SecretEMKO] BackendsNextStart
[ADDON] DisabledAddons
```

If Neural Rendering is disabled:

- the active pipeline is soft-disabled immediately;
- RenoDX and DLSS 5 Bridge are marked not to load on the next start;
- the backend files remain installed so re-enabling does not require another download.

Native third-party add-ons are intentionally **not force-unloaded with FreeLibrary mid-session**.

## Compatibility boundaries

Current RC4 target:

```text
FiveM
GTA V Legacy
Windows x64
```

Full Neural is validated for:

```text
GeForce RTX 50 Series
```

Not claimed:

- FiveM GTA V Enhanced support
- universal Full Neural support on older NVIDIA / AMD / Intel hardware
- Frame Generation as a finished FiveM feature
- bypass of FiveM server plugin policy, Pure Mode, anti-cheat or ReShade restrictions

SECRET EMKO respects the environment it runs in.

## Repository structure

```text
v2/          active SECRET EMKO product
legacy/v1/   retired v1 archival note
.github/     active Windows build and validation workflow
```

Technical references:

- `v2/README.md`
- `v2/COMPATIBILITY.md`
- `v2/VERSIONS.json`
- `v2/MAIN-SYSTEM.json`
- `v2/THIRD_PARTY_NOTICES.md`

## Build validation

The Windows CI validates:

- PowerShell syntax
- live ReShade package catalogs
- official ReShade setup behavior
- source-ZIP rejection before FiveM modification
- exact RenoDX v4.70 live-control binary contract
- native SECRET EMKO build
- release contents
- Full Neural persistence across reinstall
- RP Visual isolation and restore
- missing `plugins` creation
- unsupported Full Neural hardware fail-closed behavior
- artifact creation

## Ownership and third-party technology

**SECRET EMKO Neural Graphics** is the product and integration layer created and maintained by **Secret EMKO**.

Third-party technologies retain their own authorship, trademarks and licenses. SECRET EMKO does not claim ownership of ReShade, RenoDX, DLSS 5 Bridge, NVIDIA DLSS/NGX/Streamline or other external components.

See `v2/THIRD_PARTY_NOTICES.md` for the complete attribution and provenance record.

## License

SECRET EMKO's own v2 source is released under the **MIT License**.

Third-party components remain under their respective licenses and notices.
