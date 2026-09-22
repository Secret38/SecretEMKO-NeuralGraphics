# SECRET EMKO Neural Graphics

FiveM GTA V Legacy neural-graphics project.

## v2 RC2 — current development line

SECRET EMKO v2 is a ReShade-native FiveM Legacy integration layer around RenoDX/DLSS 5 infrastructure with a transactional installer.

Key RC2 behavior:

- automatically resolves standard and custom FiveM Legacy installations;
- creates `FiveM.app\plugins` when missing;
- isolates an existing non-SECRET-EMKO plugins folder as `plugins.before-secret-emko.<timestamp>`;
- creates a clean active plugins folder and migrates only a compatible ReShade loader plus the old `reshade-shaders` library;
- automatically rolls back the original plugins folder when a first isolated install fails;
- restores the original plugins folder on uninstall;
- installs the current official ReShade Full Add-on build when needed;
- installs current official ReShade shader packages and `swapchain_override`;
- keeps `Secret_Emko_Main.ini` and `Secret_Emko_Stream.ini` portable;
- disables missing external/proprietary techniques instead of shipping a broken default;
- enables the full DLSS 5 Neural stack automatically only on detected RTX 50 Series GPUs;
- uses visual-compatibility mode on other GPUs rather than making a false Neural Rendering claim;
- refuses to guess-install into FiveM for GTAV Enhanced;
- respects FiveM server plugin policy, Pure Mode, anti-cheat and ReShade restrictions.

The v2 package includes the `SecretEMKO.addon64` ReShade UI with Overview, Styles, Neural, Quality, Bridge, Frame Generation, Diagnostics and About pages.

Public ReShade content follows the current official catalogs. RenoDX is resolved from current upstream main at build time and the exact SHA is recorded in the build manifest. Binary-sensitive DLSS/NR/Bridge runtime combinations remain pinned and SHA-256 verified.

FiveM Frame Generation remains gated until a real FiveM motion/depth/HUD-less-colour/swapchain/pacing path is validated. The current RenoDX DLSS 5 consumer path remains one real pass.

See `v2/README.md`, `v2/COMPATIBILITY.md`, `v2/VERSIONS.json` and `v2/THIRD_PARTY_NOTICES.md`.
