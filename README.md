# SECRET EMKO Neural Graphics

FiveM GTA V Legacy neural-graphics project.

## v2 RC2

RC2 separates broad RP compatibility from the advanced neural add-on path.

- `INSTALL_SECRET_EMKO.bat` is the default **RP Visual** installer: standard signed ReShade, Main/Stream presets and public shader dependencies, with no external ReShade add-ons.
- `INSTALL_SECRET_EMKO_FULL_NEURAL.bat` is the explicit **Full Neural** installer for RTX 50 Series systems where the server/environment permits the ReShade Full Add-on stack.
- Standard/custom FiveM Legacy paths are resolved automatically where possible.
- Missing `FiveM.app\plugins` is created automatically.
- Existing plugins are isolated as `plugins.before-secret-emko.<timestamp>`; only `reshade-shaders` is migrated automatically.
- Failed first installs attempt rollback, and uninstall restores the original plugins directory.
- FiveM Enhanced is not modified by the Legacy installer.
- Missing proprietary preset effects are disabled in the installed preset rather than downloaded from unofficial mirrors.
- Frame Generation remains gated; the current DLSS 5 path is treated as one real pass.

FiveM server plugin policy, Pure Mode, anti-cheat and ReShade restrictions are respected; RC2 contains no bypass.

See `v2/README.md`, `v2/COMPATIBILITY.md`, `v2/VERSIONS.json` and `v2/MAIN-SYSTEM.json`.
