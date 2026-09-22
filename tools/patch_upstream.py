from pathlib import Path
import re
import sys

ROOT = Path(sys.argv[1]).resolve()
BUILDS = [1604,2060,2189,2372,2545,2612,2699,2802,2944,3095,3258,3407,3570,3717,3751,3788,3889]

def _encoding(path):
    data = path.read_bytes()[:4]
    if data.startswith(bytes([0xff, 0xfe])) or data.startswith(bytes([0xfe, 0xff])):
        return "utf-16"
    if data.startswith(bytes([0xef, 0xbb, 0xbf])):
        return "utf-8-sig"
    return "utf-8"
def read(rel):
    p = ROOT / rel
    return p.read_text(encoding=_encoding(p))

def write(rel, text):
    p = ROOT / rel
    p.write_text(text, encoding=_encoding(p))

def replace_exact(rel, old, new, count=1):
    text = read(rel)
    found = text.count(old)
    if found != count:
        raise RuntimeError(f"{rel}: expected {count} occurrence(s), found {found}: {old[:100]!r}")
    write(rel, text.replace(old, new))

def replace_regex(rel, pattern, repl, count=1):
    text = read(rel)
    new, n = re.subn(pattern, repl, text, flags=re.S)
    if n != count:
        raise RuntimeError(f"{rel}: expected {count} regex match(es), found {n}: {pattern[:120]!r}")
    write(rel, new)

def set_ini(rel, section, key, value):
    p = ROOT / rel
    lines = p.read_text(encoding="utf-8-sig").splitlines()
    start = next((i for i,x in enumerate(lines) if x.strip() == f"[{section}]"), None)
    if start is None:
        raise RuntimeError(f"Missing INI section [{section}]")
    end = len(lines)
    for i in range(start + 1, len(lines)):
        if re.match(r"^\s*\[.+\]\s*$", lines[i]):
            end = i
            break
    rx = re.compile(rf"^\s*{re.escape(key)}\s*=")
    for i in range(start + 1, end):
        if rx.match(lines[i]):
            lines[i] = f"{key}={value}"
            p.write_text("\n".join(lines) + "\n", encoding="utf-8-sig")
            return
    lines.insert(start + 1, f"{key}={value}")
    p.write_text("\n".join(lines) + "\n", encoding="utf-8-sig")

# Product/config branding.
replace_exact("OptiScaler/resource.h",
              '#define VER_PRODUCT_NAME "OptiScaler v" VER_PRODUCT_VERSION_STR',
              '#define VER_PRODUCT_NAME "SECRET EMKO Neural Graphics v1.1.0"')

for old,new,count in [
    ('if (lCaseFilename == "optiscaler.asi")','if (lCaseFilename == "secretemko.asi")',1),
    ('LOG_INFO("OptiScaler working as OptiScaler.asi");','LOG_INFO("SECRET EMKO working as SecretEMKO.asi");',1),
    ('dllNames.push_back("optiscaler.asi");','dllNames.push_back("secretemko.asi");',1),
    ('dllNamesW.push_back(L"optiscaler.asi");','dllNamesW.push_back(L"secretemko.asi");',1),
    ('dllNames.push_back("optiscaler");','dllNames.push_back("secretemko");',2),
    ('dllNamesW.push_back(L"optiscaler");','dllNamesW.push_back(L"secretemko");',2),
    ('spdlog::warn("OptiScaler is freely downloadable from");','spdlog::warn("SECRET EMKO Neural Graphics - free/open-source build");',1),
    ('spdlog::warn("GitHub : https://github.com/optiscaler/OptiScaler/releases");','spdlog::warn("Licence/credits: see LICENSE and THIRD_PARTY_NOTICES.txt");',1),
]:
    replace_exact("OptiScaler/dllmain.cpp",old,new,count)

replace_exact("OptiScaler/Config.h",'std::wstring fileName = L"OptiScaler.ini";','std::wstring fileName = L"SecretEMKO.ini";')
replace_exact("OptiScaler/Config.h",'CustomOptional<std::wstring> LogFileName { L"OptiScaler.log" };','CustomOptional<std::wstring> LogFileName { L"SecretEMKO.log" };')

# FiveM build resources.
rc_rel = "OptiScaler/OptiScaler.rc"
rc = read(rc_rel)
marker = '#include "winres.h"'
if marker not in rc:
    raise RuntimeError("winres.h marker not found")
resource_lines = ["", "// SECRET EMKO FiveM GTA V Legacy build declarations."]
resource_lines += [f'FX_ASI_BUILD {b} BEGIN "\\0" END' for b in BUILDS]
resource_lines += [""]
rc = rc.replace(marker, marker + "\n" + "\n".join(resource_lines), 1)
rc = rc.replace('"nitec" VALUE "FileDescription", "OptiScaler"', '"Secret EMKO" VALUE "FileDescription", "SECRET EMKO Neural Graphics"')
rc = rc.replace('"OriginalFilename", "OptiScaler.dll"', '"OriginalFilename", "SecretEMKO.asi"')
rc = rc.replace('"OptiScaler" VALUE "ProductVersion"', '"SECRET EMKO Neural Graphics" VALUE "ProductVersion"')
write(rc_rel, rc)

# Neural Rendering menu and requested ranges.
nr = "OptiScaler/dlssnr/DlssNr_Menu.cpp"
replace_exact(nr,
              'if (auto ch = ScopedCollapsingHeader("DLSS Neural Rendering"); ch.IsHeaderOpen())',
              'if (auto ch = ScopedCollapsingHeader("SECRET EMKO Neural Rendering"); ch.IsHeaderOpen())')

replace_regex(
    nr,
    r'bool unlockPasses = config->DlssNrUnlockPasses\.value_or_default\(\);\s*'
    r'if \(ImGui::Checkbox\("Lift model pass limit \(up to 30; expensive\)", &unlockPasses\)\)\s*'
    r'config->DlssNrUnlockPasses = unlockPasses;\s*'
    r'HelpMarker\("Allow up to 30 passes instead of 3\. More passes use more GPU time and VRAM; high values may crash the game\."\);\s*'
    r'const unsigned int passLimit = unlockPasses \? MaxPassCount : DefaultMaxPassCount;',
    'config->DlssNrUnlockPasses = false;\n        const unsigned int passLimit = 3u;'
)

skin_pairs = [
('DeferredSlider("Skin structure", &config->DlssNrSkinStructure, -1.0f, 2.0f, -1.0f);',
 'DeferredSlider("Skin structure", &config->DlssNrSkinStructure, 0.0f, 2.0f, 1.0f);'),
('DeferredSlider("Skin structure", &config->DlssNrPass2SkinStructure, -1.0f, 2.0f, config->DlssNrSkinStructure.value_or_default(), "%.2f", true);',
 'DeferredSlider("Skin structure", &config->DlssNrPass2SkinStructure, 0.0f, 2.0f, config->DlssNrSkinStructure.value_or_default(), "%.2f", true);'),
('DeferredSlider("Skin structure", &config->DlssNrPass3SkinStructure, -1.0f, 2.0f, config->DlssNrSkinStructure.value_or_default(), "%.2f", true);',
 'DeferredSlider("Skin structure", &config->DlssNrPass3SkinStructure, 0.0f, 2.0f, config->DlssNrSkinStructure.value_or_default(), "%.2f", true);'),
('DeferredSlider("Skin structure", &settings.skin, -1.0f, 2.0f, config->DlssNrSkinStructure.value_or_default(), "%.2f", true);',
 'DeferredSlider("Skin structure", &settings.skin, 0.0f, 2.0f, config->DlssNrSkinStructure.value_or_default(), "%.2f", true);'),
]
for old,new in skin_pairs:
    replace_exact(nr,old,new)

replace_exact(nr,
              'if (ImGui::SliderInt("Model resolution", &scalePercent, 25, 200, "%d%%"))',
              'if (ImGui::SliderInt("Model resolution", &scalePercent, 25, 100, "%d%%"))')
replace_exact(nr,
              'config->DlssNrWorkingScale = std::clamp(pendingScale, 25, 200) / 100.0f;',
              'config->DlssNrWorkingScale = std::clamp(pendingScale, 25, 100) / 100.0f;')
replace_exact(nr,
              'if (ImGui::SliderFloat("Colour strength", &colour, 0.0f, 4.0f, "%.2f"))',
              'if (ImGui::SliderFloat("Colour strength", &colour, 0.0f, 2.0f, "%.2f"))')

anchor = '''        ImGui::SeparatorText("Model passes");
        ImGui::TextWrapped("Settings apply when you release a slider.");
        static const char* styles[] = { "Standard", "Natural", "Cinematic" };'''
profiles = '''        ImGui::SeparatorText("Model passes");

        static int secretStyle = 0;
        static const char* secretStyleNames[] = { "Custom", "Natural", "Clean", "Detail", "Enhanced", "Cinematic", "Ultra Detail" };
        if (ImGui::Combo("Secret EMKO Style", &secretStyle, secretStyleNames, IM_ARRAYSIZE(secretStyleNames)))
        {
            switch (secretStyle)
            {
                case 1: config->DlssNrStyle=1u; config->DlssNrIntensity=0.90f; config->DlssNrLocalTone=0.80f; config->DlssNrLocalStructure=0.85f; config->DlssNrSkinStructure=0.80f; break;
                case 2: config->DlssNrStyle=1u; config->DlssNrIntensity=1.00f; config->DlssNrLocalTone=0.85f; config->DlssNrLocalStructure=0.75f; config->DlssNrSkinStructure=0.70f; break;
                case 3: config->DlssNrStyle=0u; config->DlssNrIntensity=1.10f; config->DlssNrLocalTone=1.00f; config->DlssNrLocalStructure=1.30f; config->DlssNrSkinStructure=1.15f; break;
                case 4: config->DlssNrStyle=2u; config->DlssNrIntensity=1.20f; config->DlssNrLocalTone=1.15f; config->DlssNrLocalStructure=1.35f; config->DlssNrSkinStructure=1.20f; break;
                case 5: config->DlssNrStyle=2u; config->DlssNrIntensity=1.25f; config->DlssNrLocalTone=1.35f; config->DlssNrLocalStructure=1.10f; config->DlssNrSkinStructure=1.00f; break;
                case 6: config->DlssNrStyle=2u; config->DlssNrIntensity=1.40f; config->DlssNrLocalTone=1.20f; config->DlssNrLocalStructure=1.70f; config->DlssNrSkinStructure=1.45f; break;
                default: break;
            }
        }
        HelpMarker("Secret EMKO profiles set the real NVIDIA Style plus model strengths. They are parameter profiles, not additional NVIDIA networks.");

        ImGui::TextWrapped("Passes are intentionally limited to 1-3. Settings apply when you release a slider.");
        static const char* styles[] = { "Standard", "Natural", "Cinematic" };'''
replace_exact(nr,anchor,profiles)

# Runtime hard pass cap.
pass_pattern = (r'std::clamp\(cfg\.DlssNrPasses\.value_or_default\(\),\s*1u,\s*'
                r'cfg\.DlssNrUnlockPasses\.value_or_default\(\) \? DlssNr::MaxPassCount\s*'
                r': DlssNr::DefaultMaxPassCount\)')
for rel in ["OptiScaler/shaders/dlssnr/DlssNr_Dx12.cpp","OptiScaler/dlssnr/DlssNrFeature_Vk.cpp"]:
    replace_regex(rel,pass_pattern,'std::clamp(cfg.DlssNrPasses.value_or_default(), 1u, DlssNr::DefaultMaxPassCount)')

# FG: max 3x total (2 interpolated frames), no Dynamic MFG.
mc = "OptiScaler/menu/menu_common.cpp"
replace_exact(mc,'auto maxInterpolationCount = state.dlssgMfgMax.value();','auto maxInterpolationCount = (std::min)(state.dlssgMfgMax.value(), 2);')
replace_exact(mc,'auto maxInterpolationCount = fgOutput->GetMaxInterpolationCount();','auto maxInterpolationCount = (std::min)(fgOutput->GetMaxInterpolationCount(), 2);',2)
replace_exact(mc,'if (state.dlssgGameDMFGSupported && !dlssgInputOrOutput)','if (false && state.dlssgGameDMFGSupported && !dlssgInputOrOutput)')
replace_exact(mc,'if (fgOutput->GetDMFGSupport())','if (false && fgOutput->GetDMFGSupport())')

cfg = "OptiScaler/Config.cpp"
old = '''            FGDLSSGOverrideForceDMFG.set_from_config(readBool("DLSSG", "OverrideForceDMFG"));
            FGDLSSGForceDMFG.set_from_config(readBool("DLSSG", "ForceDMFG"));'''
new = old + '''
            FGDLSSGOverrideForceDMFG = false;
            FGDLSSGForceDMFG = false;'''
replace_exact(cfg,old,new)

# Quality-first defaults.
for section,key,value in [
    ("DlssNr","Enabled","true"),
    ("DlssNr","RunBeforeSR","true"),
    ("DlssNr","Passes","1"),
    ("DlssNr","UnlockPasses","false"),
    ("DlssNr","WorkingScale","1.0"),
    ("DlssNr","Style","2"),
    ("DlssNr","Intensity","1.20"),
    ("DlssNr","LocalTone","1.00"),
    ("DlssNr","LocalStructure","1.35"),
    ("DlssNr","SkinStructure","1.20"),
    ("DlssNr","AutoMask","true"),
    ("DlssNr","TransferStrength","1.0"),
    ("DlssNr","ColourStrength","1.0"),
    ("FrameGen","Enabled","true"),
    ("FrameGen","FGInput","upscaler"),
    ("FrameGen","FGOutput","dlssg"),
    ("FrameGen","FGNvngxReplacement","None"),
    ("DLSSG","InterpolationCount","1"),
    ("DLSSG","OverrideInterpolationCount","auto"),
    ("DLSSG","OverrideForceDMFG","false"),
    ("DLSSG","ForceDMFG","false"),
    ("DLSS","RenderPresetOverride","true"),
    ("DLSS","RenderPresetForAll","11"),
    ("DLSS","UseGenericAppIdWithDlss","true"),
    ("Framerate","FramerateLimit","0"),
    ("Menu","OverlayMenu","true"),
    ("Menu","DisableSplash","true"),
    ("Menu","ShowFps","true"),
    ("Menu","FpsOverlayType","2"),
    ("Libraries","OptiDllPath",".\\SecretEMKO"),
]:
    set_ini("OptiScaler.ini",section,key,value)

print("Secret EMKO source patch complete.")
