# SECRET EMKO Neural Graphics

Current product: **v2.0.0-rc3** for FiveM GTA V Legacy x64.

## End users: use the built package

**Do not use GitHub `Code -> Download ZIP` as the Full Neural installer.** The source archive intentionally does not contain the compiled `SecretEMKO.addon64` and packaged bridge.

Use the latest successful GitHub Actions artifact named:

```text
SecretEMKO-NeuralGraphics-v2.0.0-rc3
```

Extract it completely, close FiveM/GTA V, then run one of:

```text
INSTALL_SECRET_EMKO.bat
INSTALL_SECRET_EMKO_FULL_NEURAL.bat
```

- **RP Visual** is the default path for ordinary RP use: official standard ReShade + Main/Stream presets + public shader dependencies.
- **Full Neural** is the explicit RTX 50 Series path for environments where the server/user policy permits ReShade Full Add-on client add-ons.
- Missing `FiveM.app\plugins` is created automatically.
- An existing unrelated `plugins` directory is isolated as `plugins.before-secret-emko.<timestamp>` instead of being modified in place.
- Failed first installs attempt automatic rollback.
- Uninstall restores the preserved pre-SECRET-EMKO plugins directory.
- FiveM Enhanced is not modified by this Legacy release.
- Proprietary effects such as QuantV are never fetched from unofficial mirrors.
- Frame Generation remains gated; DLL presence is not treated as proof of a functional FiveM FG path.

FiveM server plugin policy, Pure Mode, anti-cheat and ReShade restrictions are respected; SECRET EMKO contains no bypass.

## Repository layout

```text
v2/          active product, installer, RenoDX add-on source, presets and policy
legacy/v1/   archival note for the retired v1 prototype
.github/     active v2 CI only
```

Current technical details:

- `v2/README.md`
- `v2/COMPATIBILITY.md`
- `v2/VERSIONS.json`
- `v2/MAIN-SYSTEM.json`

The Windows CI validates PowerShell syntax, live ReShade catalogs, official ReShade installation, RenoDX compilation, source-ZIP rejection before FiveM modification, plugin isolation/restore, missing-plugin-folder creation, unsupported Full Neural rejection, release contents and artifact upload.


### v2 RC3 backend orchestration

In Full Neural mode, SECRET EMKO is the single intended settings surface. The verified RenoDX v4.70 consumer and DLSS 5 Bridge remain real backend dependencies, but SECRET EMKO controls their live/persisted state and uses ReShade's `DisabledAddons` policy to skip loading those backends on the next start when Neural Rendering is disabled. Runtime `FreeLibrary` unloading is intentionally not used.
