# SECRET EMKO Neural Graphics v1.1.0 — FiveM Legacy

Free/open-source GTA V Legacy / FiveM graphics integration project.

The Windows build produces a real x64 ASI named `SecretEMKO.asi`. The project is based on open-source NR/FG integration work and does not include or bypass PureDark proprietary authentication/code.

## Target

- GTA V Legacy through FiveM
- x64
- D3D11 game path with D3D12/NGX interoperability where required
- all currently declared Legacy builds from 1604 through 3889
- one build-independent ASI carrying the required `FX_ASI_BUILD` resources

## Secret EMKO limits

- Neural Rendering passes: **1–3**
- Intensity: **0.00–2.00**
- Local Tone: **0.00–2.00**
- Local Structure: **0.00–2.00**
- Skin Structure: **0.00–2.00**
- NR model resolution: **25–100%**
- Secret EMKO style profiles: Natural, Clean, Detail, Enhanced, Cinematic, Ultra Detail, Custom
- DLSS Frame Generation: **2x / 3x total maximum**
- Dynamic MFG: disabled
- DLSS preset K by default
- quality-first defaults

## Build

The repository contains a Windows GitHub Actions workflow. A successful run uploads the compiled FiveM package as an artifact.

NVIDIA DLSS/NR/FG runtime binaries remain separate third-party components with their own terms; see `docs/RUNTIME_POLICY.md`.

See `SUPPORTED_FIVEM_BUILDS.md`, `docs/ARCHITECTURE.md`, and `THIRD_PARTY_NOTICES.txt` for details.
