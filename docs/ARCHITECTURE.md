# Architecture

```text
FiveM_bXXXX_GTAProcess.exe
        |
        v
SecretEMKO.asi
        |
        +-- DXGI / D3D11 / D3D12 hook layer
        +-- NGX routing
        +-- DLSS SR / DLAA
        +-- DLSS Neural Rendering integration
        +-- D3D11 -> D3D12 interoperability where required
        +-- DLSSG / Streamline frame generation path
        +-- HUD/resource tracking
        +-- ImGui menu
        +-- SecretEMKO.ini
        +-- SecretEMKO.log
```

Secret EMKO changes the general-purpose upstream policy/UI to a GTA/FiveM-focused configuration:

- NR pass count hard-capped to 1–3
- Intensity / Local Tone / Local Structure / Skin Structure limited to 0–2
- Secret EMKO named parameter profiles layered over the real model styles
- normal NR model scale capped at 100%
- DLSS FG exposed only as 2x/3x total
- Dynamic MFG disabled
- own product/config/log naming
- FiveM Legacy `FX_ASI_BUILD` resources

The underlying graphics implementation remains covered by its upstream GPL and third-party licences.
