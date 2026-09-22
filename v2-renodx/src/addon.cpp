/*
 * SECRET EMKO Neural Graphics v2
 * RenoDX/ReShade control surface for GTA V Legacy / FiveM.
 *
 * Copyright (c) 2026 Secret EMKO contributors
 * SPDX-License-Identifier: MIT
 *
 * RenoDX portions remain Copyright (c) Carlos Lopez Jr. and contributors.
 */

#define ImTextureID ImU64
#define DEBUG_LEVEL_0

#include <windows.h>
#include <algorithm>
#include <array>
#include <filesystem>
#include <string>

#include <deps/imgui/imgui.h>
#include <include/reshade.hpp>

#include "../../utils/settings.hpp"
#include "../../utils/swapchain.hpp"

namespace secret_emko {

static float master_enabled = 1.f;
static float style_profile = 4.f;
static float nr_enabled = 1.f;
static float nr_placement = 0.f;
static float passes = 1.f;
static float model_resolution = 100.f;
static float nr_style = 2.f;
static float intensity = 1.20f;
static float local_tone = 1.00f;
static float local_structure = 1.35f;
static float skin_structure = 1.20f;
static float auto_mask = 1.f;
static float transfer_strength = 1.00f;
static float colour_strength = 1.00f;
static float native_look = 0.f;
static float texture_detail = 1.00f;
static float mip_bias = -0.50f;
static float fg_enabled = 0.f;
static float fg_multiplier = 1.f; // index: 0 Off, 1 2x, 2 3x
static float target_output_fps = 120.f;
static float hud_safe = 1.f;
static float diagnostics = 1.f;

static void ClampAll() {
  passes = std::clamp(passes, 1.f, 3.f);
  model_resolution = std::clamp(model_resolution, 25.f, 100.f);
  intensity = std::clamp(intensity, 0.f, 2.f);
  local_tone = std::clamp(local_tone, 0.f, 2.f);
  local_structure = std::clamp(local_structure, 0.f, 2.f);
  skin_structure = std::clamp(skin_structure, 0.f, 2.f);
  transfer_strength = std::clamp(transfer_strength, 0.f, 2.f);
  colour_strength = std::clamp(colour_strength, 0.f, 2.f);
  fg_multiplier = std::clamp(fg_multiplier, 0.f, 2.f);
  target_output_fps = std::clamp(target_output_fps, 30.f, 240.f);
}

static void ApplyProfile(int profile) {
  switch (profile) {
    case 0: // Natural
      nr_style = 1.f; intensity = 0.90f; local_tone = 0.80f; local_structure = 0.85f; skin_structure = 0.80f;
      transfer_strength = 1.00f; colour_strength = 1.00f; texture_detail = 0.95f; mip_bias = -0.25f;
      break;
    case 1: // Clean
      nr_style = 1.f; intensity = 1.00f; local_tone = 0.85f; local_structure = 0.75f; skin_structure = 0.70f;
      transfer_strength = 1.00f; colour_strength = 0.95f; texture_detail = 0.90f; mip_bias = -0.20f;
      break;
    case 2: // Detail
      nr_style = 0.f; intensity = 1.10f; local_tone = 1.00f; local_structure = 1.30f; skin_structure = 1.15f;
      transfer_strength = 1.00f; colour_strength = 1.00f; texture_detail = 1.10f; mip_bias = -0.50f;
      break;
    case 3: // Cinematic
      nr_style = 2.f; intensity = 1.25f; local_tone = 1.35f; local_structure = 1.10f; skin_structure = 1.00f;
      transfer_strength = 1.00f; colour_strength = 1.00f; texture_detail = 1.00f; mip_bias = -0.35f;
      break;
    case 4: // Enhanced
      nr_style = 2.f; intensity = 1.20f; local_tone = 1.00f; local_structure = 1.35f; skin_structure = 1.20f;
      transfer_strength = 1.00f; colour_strength = 1.00f; texture_detail = 1.10f; mip_bias = -0.50f;
      break;
    case 5: // Ultra Detail
      nr_style = 2.f; intensity = 1.40f; local_tone = 1.20f; local_structure = 1.70f; skin_structure = 1.45f;
      transfer_strength = 1.00f; colour_strength = 1.00f; texture_detail = 1.20f; mip_bias = -0.70f;
      break;
    default: // Custom
      break;
  }
  ClampAll();
}

static bool ModuleLoaded(const wchar_t* name) {
  return GetModuleHandleW(name) != nullptr;
}

static bool FileBesideAddon(const wchar_t* file) {
  wchar_t module_path[MAX_PATH] = {};
  HMODULE self = nullptr;
  if (!GetModuleHandleExW(GET_MODULE_HANDLE_EX_FLAG_FROM_ADDRESS |
                          GET_MODULE_HANDLE_EX_FLAG_UNCHANGED_REFCOUNT,
                          reinterpret_cast<LPCWSTR>(&FileBesideAddon), &self)) {
    return false;
  }
  GetModuleFileNameW(self, module_path, MAX_PATH);
  std::filesystem::path p(module_path);
  p = p.parent_path() / file;
  std::error_code ec;
  return std::filesystem::exists(p, ec);
}

static bool DrawStatusCard() {
  const bool bridge = ModuleLoaded(L"dlss5-bridge.addon64") || FileBesideAddon(L"dlss5-bridge.addon64");
  const bool nr_runtime = ModuleLoaded(L"nvngx_dlssnr.dll") || FileBesideAddon(L"nvngx_dlssnr.dll");
  const bool dlss = ModuleLoaded(L"nvngx_dlss.dll") || FileBesideAddon(L"nvngx_dlss.dll");
  const bool reno_consumer = ModuleLoaded(L"renodx-dlss5.addon64") || FileBesideAddon(L"renodx-dlss5.addon64");
  const bool reshade = ModuleLoaded(L"dxgi.dll") || ModuleLoaded(L"ReShade64.dll");

  ImGui::PushStyleVar(ImGuiStyleVar_FrameRounding, 7.0f);
  ImGui::PushStyleVar(ImGuiStyleVar_ChildRounding, 9.0f);
  ImGui::BeginChild("SecretEmkoStatus", ImVec2(0, 132), true);
  ImGui::TextUnformatted("SECRET EMKO // SYSTEM STATUS");
  ImGui::Separator();
  ImGui::Text("ReShade Full Add-on Host   %s", reshade ? "READY" : "CHECK");
  ImGui::Text("D3D11 -> D3D12 Bridge     %s", bridge ? "READY" : "MISSING");
  ImGui::Text("NVIDIA DLSS NR Runtime    %s", nr_runtime ? "READY" : "MISSING");
  ImGui::Text("NVIDIA DLSS SR Runtime    %s", dlss ? "READY" : "OPTIONAL / CHECK");
  ImGui::Text("Neural Consumer           %s", reno_consumer ? "EXTERNAL DETECTED" : "SECRET EMKO CORE PATH");
  ImGui::EndChild();
  ImGui::PopStyleVar(2);
  return false;
}

static bool DrawRecommendationCard() {
  const int fg = static_cast<int>(fg_multiplier);
  const float base = fg <= 0 ? target_output_fps : target_output_fps / static_cast<float>(fg + 1);

  ImGui::BeginChild("SecretEmkoRecommendation", ImVec2(0, 128), true);
  ImGui::TextUnformatted("QUALITY-FIRST RECOMMENDATION");
  ImGui::Separator();
  ImGui::TextWrapped("3440x1440 / RTX-class target: start with Enhanced, 1 NR pass, 100%% model resolution and DLSS Quality/DLAA.");
  if (fg > 0)
    ImGui::Text("Target %.0f FPS -> base render target about %.0f FPS at %dx total FG.", target_output_fps, base, fg + 1);
  else
    ImGui::Text("Frame Generation is off; target output %.0f FPS.", target_output_fps);
  ImGui::TextWrapped("Increase to 2-3 NR passes only after checking motion stability and frametime. Higher is not automatically sharper.");
  ImGui::EndChild();
  return false;
}

static bool DrawInfo() {
  ImGui::TextWrapped("Secret EMKO v2 is a FiveM-focused RenoDX/ReShade control layer. It keeps game-version-specific executable patching out of the UI path and uses supported add-on/resource tracking where possible.");
  ImGui::Spacing();
  ImGui::TextWrapped("Neural strengths are intentionally bounded to 0.00-2.00 and pass count to 1-3. Frame Generation policy is limited to Off/2x/3x total.");
  ImGui::Spacing();
  ImGui::TextWrapped("Third-party technology keeps its original ownership and licence notices. NVIDIA DLSS/NR/Streamline runtimes are not rebranded as Secret EMKO.");
  return false;
}

static auto* status_setting = new renodx::utils::settings::Setting{
    .key = "",
    .value_type = renodx::utils::settings::SettingValueType::CUSTOM,
    .label = "System status",
    .section = "Overview",
    .can_reset = false,
    .on_draw = DrawStatusCard,
};

static auto* recommendation_setting = new renodx::utils::settings::Setting{
    .key = "",
    .value_type = renodx::utils::settings::SettingValueType::CUSTOM,
    .label = "Recommendation",
    .section = "Overview",
    .can_reset = false,
    .on_draw = DrawRecommendationCard,
};

static auto* about_setting = new renodx::utils::settings::Setting{
    .key = "",
    .value_type = renodx::utils::settings::SettingValueType::CUSTOM,
    .label = "About",
    .section = "About",
    .can_reset = false,
    .on_draw = DrawInfo,
};

static renodx::utils::settings::Settings settings = {
    status_setting,
    recommendation_setting,

    new renodx::utils::settings::Setting{
        .key = "MasterEnabled", .binding = &master_enabled,
        .value_type = renodx::utils::settings::SettingValueType::BOOLEAN,
        .default_value = 1.f, .label = "Secret EMKO Neural Graphics",
        .section = "Core", .tooltip = "Master control for Secret EMKO policy/settings.",
        .labels = {"Disabled", "Enabled"},
        .style = renodx::utils::settings::SettingStyle::SEGMENTED,
        .tint = 0x7B61FF,
    },

    new renodx::utils::settings::Setting{
        .key = "StyleProfile", .binding = &style_profile,
        .value_type = renodx::utils::settings::SettingValueType::INTEGER,
        .default_value = 4.f, .label = "Image Style",
        .section = "Core",
        .tooltip = "One-click parameter profiles. Custom leaves all individual values under your control.",
        .labels = {"Natural", "Clean", "Detail", "Cinematic", "Enhanced", "Ultra Detail", "Custom"},
        .style = renodx::utils::settings::SettingStyle::SEGMENTED | renodx::utils::settings::SettingStyle::MULTILINE,
        .tint = 0x7B61FF,
        .on_change_value = [](float, float current) { ApplyProfile(static_cast<int>(current)); },
    },

    new renodx::utils::settings::Setting{
        .key = "NeuralRendering", .binding = &nr_enabled,
        .value_type = renodx::utils::settings::SettingValueType::BOOLEAN,
        .default_value = 1.f, .label = "Neural Rendering",
        .section = "Neural Rendering",
        .tooltip = "Master neural-rendering request. Backend availability is shown in Overview.",
        .labels = {"Off", "On"}, .style = renodx::utils::settings::SettingStyle::SEGMENTED,
        .tint = 0x00A8FF,
    },
    new renodx::utils::settings::Setting{
        .key = "NRPlacement", .binding = &nr_placement,
        .value_type = renodx::utils::settings::SettingValueType::INTEGER,
        .default_value = 0.f, .label = "Placement",
        .section = "Neural Rendering",
        .tooltip = "Before Upscale preserves lower neural workload; After Upscale maximizes direct output-domain processing where supported.",
        .labels = {"Before Upscale", "After Upscale"},
        .style = renodx::utils::settings::SettingStyle::SEGMENTED,
    },
    new renodx::utils::settings::Setting{
        .key = "Passes", .binding = &passes,
        .value_type = renodx::utils::settings::SettingValueType::INTEGER,
        .default_value = 1.f, .label = "NR Passes",
        .section = "Neural Rendering",
        .tooltip = "Hard product limit: 1-3. Start at 1. Extra passes cost GPU time and can amplify temporal artifacts.",
        .min = 1.f, .max = 3.f, .format = "%d",
        .tint = 0x00A8FF,
    },
    new renodx::utils::settings::Setting{
        .key = "ModelResolution", .binding = &model_resolution,
        .default_value = 100.f, .label = "Model Resolution",
        .section = "Neural Rendering",
        .tooltip = "Neural working resolution. 100% is the quality-first default.",
        .min = 25.f, .max = 100.f, .format = "%.0f%%",
    },
    new renodx::utils::settings::Setting{
        .key = "NRStyle", .binding = &nr_style,
        .value_type = renodx::utils::settings::SettingValueType::INTEGER,
        .default_value = 2.f, .label = "NVIDIA Model Style",
        .section = "Neural Rendering",
        .tooltip = "Real model style selector. Secret EMKO profiles combine this with the strength controls below.",
        .labels = {"Standard", "Natural", "Cinematic"},
        .style = renodx::utils::settings::SettingStyle::SEGMENTED,
    },
    new renodx::utils::settings::Setting{
        .key = "Intensity", .binding = &intensity, .default_value = 1.20f,
        .label = "Intensity", .section = "Neural Rendering",
        .tooltip = "Overall neural-edit strength.", .min = 0.f, .max = 2.f, .format = "%.2f",
    },
    new renodx::utils::settings::Setting{
        .key = "LocalTone", .binding = &local_tone, .default_value = 1.00f,
        .label = "Local Tone", .section = "Neural Rendering",
        .tooltip = "Local luminance/tone response.", .min = 0.f, .max = 2.f, .format = "%.2f",
    },
    new renodx::utils::settings::Setting{
        .key = "LocalStructure", .binding = &local_structure, .default_value = 1.35f,
        .label = "Local Structure", .section = "Neural Rendering",
        .tooltip = "Fine local structure/detail emphasis.", .min = 0.f, .max = 2.f, .format = "%.2f",
    },
    new renodx::utils::settings::Setting{
        .key = "SkinStructure", .binding = &skin_structure, .default_value = 1.20f,
        .label = "Skin Structure", .section = "Neural Rendering",
        .tooltip = "Structure response for skin/face regions.", .min = 0.f, .max = 2.f, .format = "%.2f",
    },
    new renodx::utils::settings::Setting{
        .key = "AutoMask", .binding = &auto_mask,
        .value_type = renodx::utils::settings::SettingValueType::BOOLEAN,
        .default_value = 1.f, .label = "Automatic Skin Mask",
        .section = "Neural Rendering", .labels = {"Off", "On"},
        .style = renodx::utils::settings::SettingStyle::SEGMENTED,
    },

    new renodx::utils::settings::Setting{
        .key = "TransferStrength", .binding = &transfer_strength, .default_value = 1.f,
        .label = "Transfer Strength", .section = "Image Quality",
        .tooltip = "Strength of the neural colour/luminance transfer boundary.", .min = 0.f, .max = 2.f, .format = "%.2f",
        .tint = 0x00C896,
    },
    new renodx::utils::settings::Setting{
        .key = "ColourStrength", .binding = &colour_strength, .default_value = 1.f,
        .label = "Colour Strength", .section = "Image Quality",
        .tooltip = "How strongly neural colour changes are retained.", .min = 0.f, .max = 2.f, .format = "%.2f",
    },
    new renodx::utils::settings::Setting{
        .key = "NativeLook", .binding = &native_look,
        .value_type = renodx::utils::settings::SettingValueType::BOOLEAN,
        .default_value = 0.f, .label = "Native Look",
        .section = "Image Quality",
        .tooltip = "Prefer the game's native tone/color while retaining neural detail when the backend supports this composition mode.",
        .labels = {"Neural Colour", "Native Colour"},
        .style = renodx::utils::settings::SettingStyle::SEGMENTED,
    },
    new renodx::utils::settings::Setting{
        .key = "TextureDetail", .binding = &texture_detail, .default_value = 1.10f,
        .label = "Texture Detail Bias", .section = "Image Quality",
        .tooltip = "Secret EMKO profile control for texture/detail policy; 1.0 is neutral.",
        .min = 0.5f, .max = 1.5f, .format = "%.2f",
    },
    new renodx::utils::settings::Setting{
        .key = "MipBias", .binding = &mip_bias, .default_value = -0.50f,
        .label = "MIP Bias", .section = "Image Quality",
        .tooltip = "Negative values select higher-detail mip levels. Too negative can shimmer in motion.",
        .min = -2.f, .max = 1.f, .format = "%.2f",
    },

    new renodx::utils::settings::Setting{
        .key = "FrameGeneration", .binding = &fg_enabled,
        .value_type = renodx::utils::settings::SettingValueType::BOOLEAN,
        .default_value = 0.f, .label = "Frame Generation",
        .section = "Frame Generation",
        .tooltip = "Enable only after the base render path is stable.",
        .labels = {"Off", "On"}, .style = renodx::utils::settings::SettingStyle::SEGMENTED,
        .tint = 0xFF9B42,
    },
    new renodx::utils::settings::Setting{
        .key = "FGMultiplier", .binding = &fg_multiplier,
        .value_type = renodx::utils::settings::SettingValueType::INTEGER,
        .default_value = 1.f, .label = "FG Mode",
        .section = "Frame Generation",
        .tooltip = "Secret EMKO product policy allows 2x or 3x total only. 4x+ is intentionally not exposed.",
        .labels = {"Off", "2x total", "3x total"},
        .style = renodx::utils::settings::SettingStyle::SEGMENTED,
    },
    new renodx::utils::settings::Setting{
        .key = "TargetOutputFPS", .binding = &target_output_fps, .default_value = 120.f,
        .label = "Target Output FPS", .section = "Frame Generation",
        .tooltip = "Planning target used by the recommendation card. It does not force a limiter by itself.",
        .min = 30.f, .max = 240.f, .format = "%.0f FPS",
    },
    new renodx::utils::settings::Setting{
        .key = "HudSafe", .binding = &hud_safe,
        .value_type = renodx::utils::settings::SettingValueType::BOOLEAN,
        .default_value = 1.f, .label = "HUD Safe Policy",
        .section = "Frame Generation",
        .tooltip = "Prefer processing before HUD composition or backend HUD tagging when available.",
        .labels = {"Off", "Preferred"}, .style = renodx::utils::settings::SettingStyle::SEGMENTED,
    },

    new renodx::utils::settings::Setting{
        .key = "Diagnostics", .binding = &diagnostics,
        .value_type = renodx::utils::settings::SettingValueType::BOOLEAN,
        .default_value = 1.f, .label = "Detailed Diagnostics",
        .section = "Diagnostics",
        .tooltip = "Keep bridge/provider status visible for FiveM testing.",
        .labels = {"Minimal", "Detailed"}, .style = renodx::utils::settings::SettingStyle::SEGMENTED,
        .tint = 0xA0AEC0,
    },

    about_setting,
};

} // namespace secret_emko

extern "C" __declspec(dllexport) constexpr const char* NAME = "SECRET EMKO Neural Graphics";
extern "C" __declspec(dllexport) constexpr const char* DESCRIPTION =
    "Modern FiveM/GTA V Legacy neural graphics control surface built on RenoDX and the ReShade add-on API.";

BOOL APIENTRY DllMain(HMODULE h_module, DWORD fdw_reason, LPVOID) {
  switch (fdw_reason) {
    case DLL_PROCESS_ATTACH:
      if (!reshade::register_addon(h_module)) return FALSE;
      renodx::utils::settings::use_presets = false;
      renodx::utils::settings::overlay_title = "SECRET EMKO // Neural Graphics";
      renodx::utils::settings::global_name = "SecretEMKO";
      renodx::utils::settings::open_sections_by_default = true;
      renodx::utils::settings::default_open_sections = {"Overview", "Core", "Neural Rendering"};
      secret_emko::ApplyProfile(static_cast<int>(secret_emko::style_profile));
      break;
    case DLL_PROCESS_DETACH:
      reshade::unregister_addon(h_module);
      break;
  }

  renodx::utils::settings::Use(fdw_reason, &secret_emko::settings);
  renodx::utils::swapchain::Use(fdw_reason);
  return TRUE;
}
