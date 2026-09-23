/*
 * SECRET EMKO Neural Graphics v2
 * Copyright (c) 2026 Secret EMKO
 * SPDX-License-Identifier: MIT
 *
 * ReShade-native control surface for the RenoDX DLSS 5 neural consumer
 * and NIGos DLSS 5 Bridge. This module does not contain NVIDIA code.
 */

#define ImTextureID ImU64
#define NOMINMAX

#include <windows.h>

#include <algorithm>
#include <array>
#include <cctype>
#include <filesystem>
#include <fstream>
#include <sstream>
#include <string>
#include <unordered_map>
#include <vector>

#include <deps/imgui/imgui.h>
#include <include/reshade.hpp>
#include <include/imgui_function_table.hpp>
#include "renodx_live_adapter.hpp"

namespace {

constexpr const char* kProduct = "SECRET EMKO Neural Graphics";
constexpr const char* kVersion = "2.0.0-rc3";
constexpr const char* kProviderSection = "RenoDX.DLSS5";
constexpr const char* kOwnSection = "SecretEMKO";

HMODULE g_module = nullptr;
std::filesystem::path g_dir;
bool g_restart_required = false;
bool g_loaded = false;
bool g_policy_synced = false;
bool g_backends_next_start = true;
bool g_backend_transition_pending = false;
bool g_provider_restart_pending = false;
std::string g_backend_status;

struct NeuralSettings {
  int enabled = 1;
  int enable_upscaling = 0;
  int preset = 0;
  int style = 1;
  float intensity = 1.20f;
  float global_tone = 1.05f;
  float local_tone = 1.05f;
  float local_structure = 1.35f;
  float skin_structure = 1.00f;
  int auto_mask = 1;
  int ui_correction = 1;
  float diffuse_white_nits = 203.f;
  float paper_white_scale = 1.0f;
  float transfer_strength = 1.0f;
  float color_strength = 0.95f;
  int depth_mode = 0;
  float mv_scale_x = 1.0f;
  float mv_scale_y = 1.0f;
};

struct BridgeSettings {
  int synth = 1;
  int source = 1; // 0 auto, 1 synth, 2 mirror, 3 off
  int ofa_grid = 2;
  int ofa_perf = 10;
  int stage = 3;
  int mode = 2;
  int skip_game = 1;
  int dred = 1;
  int skip_exe = 1;
  int unwrap = 1;
  int hash_out = 1;
};

struct Profile {
  const char* name;
  const char* description;
  int style;
  float intensity;
  float global_tone;
  float local_tone;
  float local_structure;
  float skin_structure;
  float transfer_strength;
  float color_strength;
  int ofa_grid;
  int ofa_perf;
};

constexpr std::array<Profile, 6> kProfiles = {{
    {"Natural", "Very restrained neural reconstruction. Best first compatibility check.",
     1, 0.90f, 1.00f, 0.85f, 0.85f, 0.75f, 1.00f, 0.88f, 2, 20},
    {"Clean", "Low-artifact presentation with reduced structure emphasis.",
     0, 0.82f, 0.95f, 0.75f, 0.70f, 0.60f, 0.95f, 0.82f, 2, 20},
    {"Detail", "Sharper surfaces and micro-structure without pushing the model to the limit.",
     1, 1.08f, 1.02f, 0.95f, 1.28f, 0.95f, 1.00f, 0.92f, 2, 10},
    {"Enhanced", "Recommended quality-first profile for 3440x1440-class RTX 50 systems.",
     1, 1.20f, 1.05f, 1.05f, 1.35f, 1.00f, 1.00f, 0.95f, 2, 10},
    {"Cinematic", "Softer structure with stronger tonal shaping. Uses Natural model style for stability.",
     1, 1.12f, 1.18f, 1.28f, 1.08f, 0.90f, 1.00f, 0.90f, 2, 10},
    {"Ultra Detail", "Aggressive detail profile. Inspect foliage, wires and faces for temporal artifacts.",
     1, 1.34f, 1.10f, 1.12f, 1.68f, 1.00f, 1.00f, 1.00f, 1, 5},
}};

NeuralSettings g_nr;
NeuralSettings g_saved_nr;
BridgeSettings g_bridge;
secretemko_live::RenoDxLiveAdapter g_live;
int g_profile_index = 3;
int g_fg_policy = 0; // 0 off, 1 2x, 2 3x; policy only until provider exists.

template <typename T>
void WriteConfig(const char* section, const char* key, const T& value) {
  reshade::set_config_value(nullptr, section, key, value);
}

template <typename T>
void ReadConfig(const char* section, const char* key, T& value) {
  reshade::get_config_value(nullptr, section, key, value);
}

std::filesystem::path ModuleDirectory(HMODULE module) {
  std::wstring buffer(32768, L'\0');
  DWORD size = GetModuleFileNameW(module, buffer.data(), static_cast<DWORD>(buffer.size()));
  if (size == 0) return std::filesystem::current_path();
  buffer.resize(size);
  return std::filesystem::path(buffer).parent_path();
}

bool FileExists(const wchar_t* name) {
  std::error_code ec;
  return std::filesystem::exists(g_dir / name, ec);
}

bool ModuleLoaded(const wchar_t* name) {
  return GetModuleHandleW(name) != nullptr;
}

bool NeuralStackInstalled() {
  return FileExists(L"renodx-dlss5.addon64") &&
         FileExists(L"dlss5-bridge.addon64") &&
         FileExists(L"nvngx_dlssnr.dll");
}

bool NeuralBackendsLoaded() {
  return ModuleLoaded(L"renodx-dlss5.addon64") &&
         ModuleLoaded(L"dlss5-bridge.addon64");
}

std::string ReadConfigString(const char* section, const char* key) {
  size_t size = 0;
  if (!reshade::get_config_value(nullptr, section, key, nullptr, &size) || size == 0)
    return {};
  std::vector<char> buffer(size + 1, '\0');
  if (!reshade::get_config_value(nullptr, section, key, buffer.data(), &size))
    return {};
  return std::string(buffer.data());
}

std::string Trim(std::string value) {
  const auto not_space = [](unsigned char ch) { return !std::isspace(ch); };
  value.erase(value.begin(), std::find_if(value.begin(), value.end(), not_space));
  value.erase(std::find_if(value.rbegin(), value.rend(), not_space).base(), value.end());
  return value;
}

bool EntryTargetsFile(const std::string& entry, const char* file) {
  const auto at = entry.find('@');
  if (at == std::string::npos) return false;
  std::string tail = Trim(entry.substr(at + 1));
  std::string wanted = file;
  std::transform(tail.begin(), tail.end(), tail.begin(), [](unsigned char ch) { return static_cast<char>(std::tolower(ch)); });
  std::transform(wanted.begin(), wanted.end(), wanted.begin(), [](unsigned char ch) { return static_cast<char>(std::tolower(ch)); });
  return tail == wanted;
}

void SetBackendLoadPolicy(bool load_next_start) {
  std::vector<std::string> entries;
  std::stringstream stream(ReadConfigString("ADDON", "DisabledAddons"));
  std::string item;
  while (std::getline(stream, item, ',')) {
    item = Trim(item);
    if (item.empty()) continue;
    if (EntryTargetsFile(item, "renodx-dlss5.addon64") ||
        EntryTargetsFile(item, "dlss5-bridge.addon64"))
      continue;
    entries.push_back(item);
  }

  if (!load_next_start) {
    entries.emplace_back("SECRET EMKO RenoDX backend@renodx-dlss5.addon64");
    entries.emplace_back("SECRET EMKO DLSS5 bridge@dlss5-bridge.addon64");
  }

  std::ostringstream joined;
  for (size_t i = 0; i < entries.size(); ++i) {
    if (i) joined << ',';
    joined << entries[i];
  }
  reshade::set_config_value(nullptr, "ADDON", "DisabledAddons", joined.str().c_str());

  g_backends_next_start = load_next_start;
  WriteConfig(kOwnSection, "BackendsNextStart", load_next_start ? 1 : 0);

  const bool loaded_now = NeuralBackendsLoaded();
  g_backend_transition_pending = load_next_start != loaded_now;
  if (!load_next_start && loaded_now)
    g_backend_status = "Backends are scheduled not to load next start; current-session shutdown is being applied where verified.";
  else if (load_next_start && !loaded_now)
    g_backend_status = "Backends are scheduled to load on the next start.";
  else
    g_backend_status = load_next_start ? "Backends are loaded for this session." : "Backends are not loaded.";
}

secretemko_live::Desired ToLiveDesired(const NeuralSettings& value) {
  secretemko_live::Desired d;
  d.enabled = value.enabled;
  d.enable_upscaling = value.enable_upscaling;
  d.preset = value.preset;
  d.style = value.style;
  d.intensity = value.intensity;
  d.global_tone = value.global_tone;
  d.local_tone = value.local_tone;
  d.local_structure = value.local_structure;
  d.skin_structure = value.skin_structure;
  d.auto_mask = value.auto_mask;
  d.ui_correction = value.ui_correction;
  d.diffuse_white_nits = value.diffuse_white_nits;
  d.depth_mode = value.depth_mode;
  d.mv_scale_x = value.mv_scale_x;
  d.mv_scale_y = value.mv_scale_y;
  return d;
}

bool AnyNeuralChange(const NeuralSettings& a, const NeuralSettings& b) {
  return a.enabled != b.enabled ||
         a.enable_upscaling != b.enable_upscaling ||
         a.preset != b.preset ||
         a.style != b.style ||
         std::fabs(a.intensity - b.intensity) > 0.0001f ||
         std::fabs(a.global_tone - b.global_tone) > 0.0001f ||
         std::fabs(a.local_tone - b.local_tone) > 0.0001f ||
         std::fabs(a.local_structure - b.local_structure) > 0.0001f ||
         std::fabs(a.skin_structure - b.skin_structure) > 0.0001f ||
         a.auto_mask != b.auto_mask ||
         a.ui_correction != b.ui_correction ||
         std::fabs(a.diffuse_white_nits - b.diffuse_white_nits) > 0.01f ||
         std::fabs(a.paper_white_scale - b.paper_white_scale) > 0.0001f ||
         std::fabs(a.transfer_strength - b.transfer_strength) > 0.0001f ||
         std::fabs(a.color_strength - b.color_strength) > 0.0001f ||
         a.depth_mode != b.depth_mode ||
         std::fabs(a.mv_scale_x - b.mv_scale_x) > 0.0001f ||
         std::fabs(a.mv_scale_y - b.mv_scale_y) > 0.0001f;
}

bool ProviderRestartOnlyChange(const NeuralSettings& a, const NeuralSettings& b) {
  return std::fabs(a.paper_white_scale - b.paper_white_scale) > 0.0001f ||
         std::fabs(a.transfer_strength - b.transfer_strength) > 0.0001f ||
         std::fabs(a.color_strength - b.color_strength) > 0.0001f;
}

std::filesystem::path BridgeConfigPath() {
  return g_dir / L"dlss5-bridge.cfg";
}

std::unordered_map<std::string, std::string> ReadBridgeMap() {
  std::unordered_map<std::string, std::string> values;
  std::ifstream in(BridgeConfigPath());
  std::string line;
  while (std::getline(in, line)) {
    auto pos = line.find('=');
    if (pos == std::string::npos) continue;
    auto key = line.substr(0, pos);
    auto value = line.substr(pos + 1);
    key.erase(std::remove_if(key.begin(), key.end(), ::isspace), key.end());
    value.erase(std::remove_if(value.begin(), value.end(), [](unsigned char c) { return c == '\r' || c == '\n'; }), value.end());
    values[key] = value;
  }
  return values;
}

int ParseInt(const std::unordered_map<std::string, std::string>& map, const char* key, int fallback) {
  auto it = map.find(key);
  if (it == map.end()) return fallback;
  try { return std::stoi(it->second); } catch (...) { return fallback; }
}

void WriteBridgeConfig(bool force_off = false) {
  std::ofstream out(BridgeConfigPath(), std::ios::trunc);
  if (!out) return;

  out << "# dlss5-bridge keep\n";
  out << "# Managed by SECRET EMKO Neural Graphics. Unknown bridge defaults remain upstream defaults.\n";
  out << "synth=" << (force_off ? 0 : g_bridge.synth) << "\n";
  static const char* sources[] = {"auto", "synth", "mirror", "off"};
  out << "source=" << (force_off ? "off" : sources[std::clamp(g_bridge.source, 0, 3)]) << "\n";
  out << "ofa_grid=" << g_bridge.ofa_grid << "\n";
  out << "ofa_perf=" << g_bridge.ofa_perf << "\n";
  out << "stage=" << g_bridge.stage << "\n";
  out << "mode=" << g_bridge.mode << "\n";
  out << "skip_game=" << g_bridge.skip_game << "\n";
  out << "dred=" << g_bridge.dred << "\n";
  out << "skip_exe=" << g_bridge.skip_exe << "\n";
  out << "unwrap=" << g_bridge.unwrap << "\n";
  out << "hash_out=" << g_bridge.hash_out << "\n";
}

void LoadBridgeConfig() {
  const auto map = ReadBridgeMap();
  g_bridge.synth = ParseInt(map, "synth", 1);
  g_bridge.ofa_grid = ParseInt(map, "ofa_grid", 2);
  g_bridge.ofa_perf = ParseInt(map, "ofa_perf", 10);
  g_bridge.stage = ParseInt(map, "stage", 3);
  g_bridge.mode = ParseInt(map, "mode", 2);
  g_bridge.skip_game = ParseInt(map, "skip_game", 1);
  g_bridge.dred = ParseInt(map, "dred", 1);
  g_bridge.skip_exe = ParseInt(map, "skip_exe", 1);
  g_bridge.unwrap = ParseInt(map, "unwrap", 1);
  g_bridge.hash_out = ParseInt(map, "hash_out", 1);

  auto it = map.find("source");
  if (it != map.end()) {
    if (it->second == "auto") g_bridge.source = 0;
    else if (it->second == "synth") g_bridge.source = 1;
    else if (it->second == "mirror") g_bridge.source = 2;
    else if (it->second == "off") g_bridge.source = 3;
  }
}

void WriteNeuralSettings() {
  const NeuralSettings before = g_saved_nr;

  WriteConfig(kProviderSection, "EnableHooks", 2);
  WriteConfig(kProviderSection, "NeuralUplift", g_nr.enabled);
  WriteConfig(kProviderSection, "NREnableUpscaling", g_nr.enable_upscaling);
  WriteConfig(kProviderSection, "NRPreset", g_nr.preset);
  WriteConfig(kProviderSection, "NRStyle", g_nr.style);
  WriteConfig(kProviderSection, "NRIntensity", g_nr.intensity);
  WriteConfig(kProviderSection, "NRGlobalTone", g_nr.global_tone);
  WriteConfig(kProviderSection, "NRLocalTone", g_nr.local_tone);
  WriteConfig(kProviderSection, "NRLocalStructure", g_nr.local_structure);
  WriteConfig(kProviderSection, "NRSkinStructure", g_nr.skin_structure);
  WriteConfig(kProviderSection, "NRAutoMask", g_nr.auto_mask);
  WriteConfig(kProviderSection, "NRUICorrection", g_nr.ui_correction);
  WriteConfig(kProviderSection, "NRDiffuseWhiteNits", g_nr.diffuse_white_nits);
  WriteConfig(kProviderSection, "NRPaperWhiteScale", g_nr.paper_white_scale);
  WriteConfig(kProviderSection, "NRTransferStrength", g_nr.transfer_strength);
  WriteConfig(kProviderSection, "NRColorStrength", g_nr.color_strength);
  WriteConfig(kProviderSection, "NRDepthMode", g_nr.depth_mode);
  WriteConfig(kProviderSection, "NRMVecScaleX", g_nr.mv_scale_x);
  WriteConfig(kProviderSection, "NRMVecScaleY", g_nr.mv_scale_y);
  WriteConfig(kProviderSection, "NRToggleKey", 0);
  WriteConfig(kProviderSection, "NRScreenshotKey", 0);

  if (AnyNeuralChange(before, g_nr)) {
    if (NeuralBackendsLoaded() && g_live.available()) {
      g_live.queue_diff(ToLiveDesired(g_nr));
    } else if (NeuralBackendsLoaded() || g_nr.enabled != 0) {
      // Backends are present but cannot be controlled by the verified adapter,
      // or they are absent and need to be loaded. Never claim an immediate
      // runtime transition in either case.
      g_restart_required = true;
    }

    // These legacy/provider values are persisted but are not exposed by the
    // verified RenoDX v4.70 UI callback, so SECRET EMKO never pretends that
    // they were changed live.
    if (ProviderRestartOnlyChange(before, g_nr)) {
      g_provider_restart_pending = true;
      g_restart_required = true;
    }
  }

  g_saved_nr = g_nr;
}

void LoadNeuralSettings() {
  ReadConfig(kProviderSection, "NeuralUplift", g_nr.enabled);
  ReadConfig(kProviderSection, "NREnableUpscaling", g_nr.enable_upscaling);
  ReadConfig(kProviderSection, "NRPreset", g_nr.preset);
  ReadConfig(kProviderSection, "NRStyle", g_nr.style);
  ReadConfig(kProviderSection, "NRIntensity", g_nr.intensity);
  ReadConfig(kProviderSection, "NRGlobalTone", g_nr.global_tone);
  ReadConfig(kProviderSection, "NRLocalTone", g_nr.local_tone);
  ReadConfig(kProviderSection, "NRLocalStructure", g_nr.local_structure);
  ReadConfig(kProviderSection, "NRSkinStructure", g_nr.skin_structure);
  ReadConfig(kProviderSection, "NRAutoMask", g_nr.auto_mask);
  ReadConfig(kProviderSection, "NRUICorrection", g_nr.ui_correction);
  ReadConfig(kProviderSection, "NRDiffuseWhiteNits", g_nr.diffuse_white_nits);
  ReadConfig(kProviderSection, "NRPaperWhiteScale", g_nr.paper_white_scale);
  ReadConfig(kProviderSection, "NRTransferStrength", g_nr.transfer_strength);
  ReadConfig(kProviderSection, "NRColorStrength", g_nr.color_strength);
  ReadConfig(kProviderSection, "NRDepthMode", g_nr.depth_mode);
  ReadConfig(kProviderSection, "NRMVecScaleX", g_nr.mv_scale_x);
  ReadConfig(kProviderSection, "NRMVecScaleY", g_nr.mv_scale_y);
  ReadConfig(kOwnSection, "Profile", g_profile_index);
  ReadConfig(kOwnSection, "FrameGenerationPolicy", g_fg_policy);

  g_profile_index = std::clamp(g_profile_index, 0, static_cast<int>(kProfiles.size()) - 1);
  g_fg_policy = std::clamp(g_fg_policy, 0, 2);
  int backends = g_nr.enabled != 0 ? 1 : 0;
  ReadConfig(kOwnSection, "BackendsNextStart", backends);
  g_backends_next_start = backends != 0;
  g_saved_nr = g_nr;
  g_provider_restart_pending = false;
  g_live.set_baseline(ToLiveDesired(g_nr));
}

void ApplyProfile(int index) {
  index = std::clamp(index, 0, static_cast<int>(kProfiles.size()) - 1);
  const auto& p = kProfiles[index];
  g_profile_index = index;
  g_nr.style = p.style;
  g_nr.intensity = p.intensity;
  g_nr.global_tone = p.global_tone;
  g_nr.local_tone = p.local_tone;
  g_nr.local_structure = p.local_structure;
  g_nr.skin_structure = p.skin_structure;
  g_nr.transfer_strength = p.transfer_strength;
  g_nr.color_strength = p.color_strength;
  g_nr.enabled = 1;
  g_nr.enable_upscaling = 0;
  g_nr.preset = 0;
  g_nr.auto_mask = 1;
  g_nr.ui_correction = 1;
  g_nr.depth_mode = 0;
  g_nr.mv_scale_x = 1.0f;
  g_nr.mv_scale_y = 1.0f;

  g_bridge.synth = 1;
  g_bridge.source = 1;
  g_bridge.stage = 3;
  g_bridge.mode = 2;
  g_bridge.ofa_grid = p.ofa_grid;
  g_bridge.ofa_perf = p.ofa_perf;

  WriteConfig(kOwnSection, "Profile", g_profile_index);
  SetBackendLoadPolicy(true);
  WriteNeuralSettings();
  WriteBridgeConfig(false);
}

void SetNeuralEnabled(bool enabled) {
  g_nr.enabled = enabled ? 1 : 0;

  if (enabled) {
    if (g_bridge.synth == 0) g_bridge.synth = 1;
    if (g_bridge.source == 3) g_bridge.source = 1;
    SetBackendLoadPolicy(true);
    WriteNeuralSettings();
    WriteBridgeConfig(false);
    if (!NeuralBackendsLoaded()) g_restart_required = true;
  } else {
    // First turn the active provider and bridge into an idle state. Loaded
    // modules remain mapped for the rest of this process; unloading arbitrary
    // ReShade add-ons mid-frame is intentionally avoided.
    WriteNeuralSettings();
    WriteBridgeConfig(true);
    SetBackendLoadPolicy(false);
    if (!g_live.available() && NeuralBackendsLoaded()) {
      g_restart_required = true;
      g_backend_status = "Backends will not load next start. RenoDX live shutdown is unavailable in this session, so restart is required for a guaranteed full stop.";
    }
  }
}

void Help(const char* text) {
  ImGui::SameLine();
  ImGui::TextDisabled("(?)");
  if (ImGui::IsItemHovered(ImGuiHoveredFlags_DelayShort)) {
    ImGui::BeginTooltip();
    ImGui::PushTextWrapPos(ImGui::GetFontSize() * 32.0f);
    ImGui::TextUnformatted(text);
    ImGui::PopTextWrapPos();
    ImGui::EndTooltip();
  }
}

void StatusRow(const char* label, const wchar_t* file, bool required, const char* note = nullptr) {
  const bool present = FileExists(file);
  const bool loaded = ModuleLoaded(file);
  ImGui::TableNextRow();
  ImGui::TableSetColumnIndex(0);
  ImGui::TextUnformatted(label);
  ImGui::TableSetColumnIndex(1);
  if (loaded) ImGui::TextUnformatted("Loaded");
  else if (present) ImGui::TextUnformatted("Ready");
  else ImGui::TextUnformatted(required ? "Missing" : "Optional");
  ImGui::TableSetColumnIndex(2);
  if (note) ImGui::TextWrapped("%s", note);
  else ImGui::TextUnformatted(present ? "File found in FiveM plugins." : "File not found.");
}

int CountReady() {
  const bool neural_stack = FileExists(L"renodx-dlss5.addon64") || FileExists(L"nvngx_dlssnr.dll");
  if (!neural_stack) {
    const wchar_t* files[] = {
        L"dxgi.dll",
        L"SecretEMKO.addon64",
        L"swapchain_override.addon64",
        L"Secret_Emko_Main.ini",
        L"Secret_Emko_Stream.ini",
    };
    int ready = 0;
    for (auto* f : files) if (FileExists(f)) ++ready;
    return ready * 6 / 5;
  }

  const wchar_t* files[] = {
      L"dxgi.dll",
      L"SecretEMKO.addon64",
      L"dlss5-bridge.addon64",
      L"renodx-dlss5.addon64",
      L"nvngx_dlss.dll",
      L"nvngx_dlssnr.dll",
  };
  int ready = 0;
  for (auto* f : files) if (FileExists(f)) ++ready;
  return ready;
}

void DrawHeader() {
  ImGui::PushStyleVar(ImGuiStyleVar_ChildRounding, 8.0f);
  ImGui::BeginChild("##se_header", ImVec2(0, 86), true);
  ImGui::TextUnformatted("SECRET EMKO");
  ImGui::SameLine();
  ImGui::TextDisabled("NEURAL GRAPHICS");
  const bool neural_stack = NeuralStackInstalled();
  ImGui::TextDisabled(neural_stack
      ? "FiveM GTA V Legacy  |  Full Neural mode  |  v2.0 RC3"
      : "FiveM GTA V Legacy  |  Visual compatibility mode  |  v2.0 RC3");
  const float readiness = static_cast<float>(CountReady()) / 6.0f;
  char overlay[64];
  sprintf_s(overlay, "Core stack %.0f%% ready", readiness * 100.0f);
  ImGui::ProgressBar(readiness, ImVec2(-1, 0), overlay);
  ImGui::EndChild();
  ImGui::PopStyleVar();

  if (g_restart_required) {
    ImGui::TextWrapped("Restart required for at least one pending change: either a backend must be loaded for the next session or a provider-only value is not part of the verified RenoDX v4.70 live-control surface.");
  }
  if (!g_backend_status.empty()) {
    ImGui::TextDisabled("%s", g_backend_status.c_str());
  }
}

void DrawOverview() {
  const bool neural_stack = NeuralStackInstalled();
  if (neural_stack) {
    if (ImGui::Button("Apply Enhanced (Recommended)", ImVec2(230, 34))) {
      ApplyProfile(3);
    }
    ImGui::SameLine();
  }
  if (ImGui::Button("Reload settings", ImVec2(150, 34))) {
    LoadNeuralSettings();
    LoadBridgeConfig();
    g_restart_required = false;
  }
  if (!neural_stack) {
    ImGui::TextWrapped("Visual compatibility mode is active. ReShade presets remain available, but the RTX 50 DLSS 5 Neural stack is not installed.");
  }

  ImGui::Spacing();
  ImGui::SeparatorText("Runtime stack");
  if (ImGui::BeginTable("##status", 3, ImGuiTableFlags_BordersInnerH | ImGuiTableFlags_RowBg | ImGuiTableFlags_SizingStretchProp)) {
    ImGui::TableSetupColumn("Component", ImGuiTableColumnFlags_WidthFixed, 185.0f);
    ImGui::TableSetupColumn("Status", ImGuiTableColumnFlags_WidthFixed, 90.0f);
    ImGui::TableSetupColumn("Purpose");
    ImGui::TableHeadersRow();
    StatusRow("ReShade Full Add-on", L"dxgi.dll", true, "Loader and native overlay host.");
    StatusRow("SECRET EMKO UI", L"SecretEMKO.addon64", true, "Profiles, diagnostics and policy.");
    StatusRow("DLSS 5 Bridge", L"dlss5-bridge.addon64", neural_stack, neural_stack ? "Synthesizes the DLSS contract for GTA V Legacy D3D11." : "Not required in visual compatibility mode.");
    StatusRow("RenoDX DLSS 5", L"renodx-dlss5.addon64", neural_stack, neural_stack ? "Neural Rendering consumer." : "Not installed in visual compatibility mode.");
    StatusRow("DLSS SR runtime", L"nvngx_dlss.dll", neural_stack, neural_stack ? "NGX DLSS runtime used by the synthetic contract." : "Not required in visual compatibility mode.");
    StatusRow("DLSS NR runtime", L"nvngx_dlssnr.dll", neural_stack, neural_stack ? "NVIDIA Neural Rendering model runtime." : "RTX 50 Neural runtime is intentionally absent.");
    StatusRow("DLSS Frame Generation", L"nvngx_dlssg.dll", false, "Runtime file only; FiveM FG integration is not armed by v2 yet.");
    ImGui::EndTable();
  }

  ImGui::Spacing();
  ImGui::SeparatorText("Current design");
  ImGui::BulletText("FiveM keeps its normal D3D11 device creation path.");
  ImGui::BulletText("SECRET EMKO is the only user-facing control surface.");
  ImGui::BulletText("RenoDX DLSS 5 and DLSS 5 Bridge are treated as managed backends and are only scheduled to load when Neural Rendering is enabled.");
  ImGui::BulletText("Loaded backends are soft-disabled immediately when Neural Rendering is turned off; ReShade skips loading them on the next start.");
  ImGui::BulletText("The bridge uses a synthetic DLSS contract because GTA V Legacy has no native DLSS.");
  ImGui::BulletText("Neural Rendering is tuned by Secret EMKO profiles; raw controls remain available.");
  ImGui::BulletText("No PureDark code, authentication or paid-mod assets are used.");
}

void DrawProfiles() {
  if (!NeuralStackInstalled()) {
    ImGui::SeparatorText("Neural style profiles");
    ImGui::TextWrapped("Unavailable in visual compatibility mode. Use the ReShade Home tab to switch between Secret_Emko_Main.ini and Secret_Emko_Stream.ini.");
    return;
  }

  ImGui::SeparatorText("Style profile");
  const char* names[] = {"Natural", "Clean", "Detail", "Enhanced", "Cinematic", "Ultra Detail"};
  ImGui::SetNextItemWidth(260.0f);
  if (ImGui::Combo("Profile", &g_profile_index, names, IM_ARRAYSIZE(names))) {
    WriteConfig(kOwnSection, "Profile", g_profile_index);
  }
  Help("Profiles are explicit parameter bundles. They do not pretend to be additional NVIDIA model networks.");

  const auto& p = kProfiles[g_profile_index];
  ImGui::TextWrapped("%s", p.description);
  ImGui::TextDisabled("Model style: %s | Optical flow grid: %d | OFA effort: %s",
                      p.style == 1 ? "Natural" : (p.style == 0 ? "Default" : "Cinematic"),
                      p.ofa_grid, p.ofa_perf == 5 ? "Slow/quality" : (p.ofa_perf == 10 ? "Medium" : "Fast"));

  if (ImGui::Button("Apply selected profile", ImVec2(210, 32))) {
    ApplyProfile(g_profile_index);
  }

  ImGui::Spacing();
  ImGui::SeparatorText("Recommended use");
  if (ImGui::BeginTable("##profiles_table", 3, ImGuiTableFlags_RowBg | ImGuiTableFlags_BordersInnerH | ImGuiTableFlags_SizingStretchProp)) {
    ImGui::TableSetupColumn("Profile", ImGuiTableColumnFlags_WidthFixed, 110.f);
    ImGui::TableSetupColumn("Use");
    ImGui::TableSetupColumn("Watch for");
    ImGui::TableHeadersRow();
    const char* use[] = {
      "Compatibility / natural image",
      "Minimal processing",
      "Sharper textures",
      "Quality-first daily preset",
      "Tone-shaped presentation",
      "Maximum visible micro-detail"
    };
    const char* watch[] = {
      "Usually the safest baseline",
      "May look less dramatic",
      "Fine foliage shimmer",
      "Small-text / fence stability",
      "Highlight / skin tone changes",
      "Temporal crawl and GPU cost"
    };
    for (int i = 0; i < 6; ++i) {
      ImGui::TableNextRow();
      ImGui::TableSetColumnIndex(0); ImGui::TextUnformatted(kProfiles[i].name);
      ImGui::TableSetColumnIndex(1); ImGui::TextWrapped("%s", use[i]);
      ImGui::TableSetColumnIndex(2); ImGui::TextWrapped("%s", watch[i]);
    }
    ImGui::EndTable();
  }
}

bool Slider(const char* label, float* value, float lo, float hi, const char* help, const char* format = "%.2f") {
  ImGui::SetNextItemWidth(280.0f);
  const bool changed = ImGui::SliderFloat(label, value, lo, hi, format);
  Help(help);
  return changed;
}

void DrawNeural() {
  bool changed = false;
  const bool neural_stack = NeuralStackInstalled();
  if (!neural_stack) {
    ImGui::TextWrapped("Neural Rendering is unavailable in this installation. SECRET EMKO is running in visual compatibility mode. Official DLSS 5 3D-Guided Neural Rendering requires GeForce RTX 50-series hardware.");
    return;
  }

  bool enabled = g_nr.enabled != 0;
  if (ImGui::Checkbox("Enable DLSS Neural Rendering", &enabled)) {
    SetNeuralEnabled(enabled);
  }
  Help("Master switch for the complete managed backend chain. OFF idles the active provider/bridge immediately and schedules RenoDX + Bridge not to load next start. ON reuses loaded backends immediately or schedules them for the next start if they are currently absent.");

  if (NeuralBackendsLoaded()) {
    if (g_live.available())
      ImGui::TextDisabled("Live provider control: verified RenoDX v4.70, provider callback + readback active.");
    else
      ImGui::TextWrapped("Live provider control unavailable: %s. Values are still persisted, but unsupported changes require a restart.", g_live.reason().c_str());
  } else if (g_nr.enabled) {
    ImGui::TextWrapped("Neural backends are not loaded in this session. They are enabled for the next start.");
  } else {
    ImGui::TextDisabled("Neural backends are sleeping and scheduled not to load next start.");
  }

  ImGui::Spacing();
  ImGui::SeparatorText("Model");

  const char* styles[] = {"Default", "Natural", "Cinematic (experimental)"};
  ImGui::SetNextItemWidth(280.f);
  if (ImGui::Combo("NVIDIA model style", &g_nr.style, styles, IM_ARRAYSIZE(styles))) changed = true;
  Help("Natural is used by all Secret EMKO production profiles. Style 2/Cinematic has caused startup faults on at least one recent RenoDX DLSS 5 reference setup, so it is intentionally not a profile default.");
  if (g_nr.style == 2) {
    ImGui::TextWrapped("Experimental: if FiveM crashes during startup, return NRStyle to Default or Natural in ReShade.ini.");
  }

  const char* presets[] = {"Default", "Preset #1", "Preset #2", "Preset #3"};
  ImGui::SetNextItemWidth(280.f);
  if (ImGui::Combo("NR preset hint", &g_nr.preset, presets, IM_ARRAYSIZE(presets))) changed = true;
  Help("Render-preset hint exposed by the provider. Leave Default unless testing a specific model behavior.");

  changed |= Slider("Overall Intensity", &g_nr.intensity, 0.0f, 2.0f, "Overall neural relighting strength. Enhanced uses 1.20.");
  changed |= Slider("Global Tone Intensity", &g_nr.global_tone, 0.0f, 2.0f, "v4.7+ global tonal-strength control.");
  changed |= Slider("Local Tone Intensity", &g_nr.local_tone, 0.0f, 2.0f, "Local contrast/tone contribution. High values can exaggerate lighting boundaries.");
  changed |= Slider("Structure Intensity", &g_nr.local_structure, 0.0f, 2.0f, "Primary micro-detail control. Above ~1.5 should be checked carefully in motion.");
  changed |= Slider("Character / Skin Structure", &g_nr.skin_structure, 0.0f, 2.0f, "Secret EMKO exposes an extended 0-2 range. Current public v4.7 observations are concentrated at <=1, so values above 1 are expert territory.");

  bool auto_mask = g_nr.auto_mask != 0;
  if (ImGui::Checkbox("Automatic / Character Mask", &auto_mask)) { g_nr.auto_mask = auto_mask ? 1 : 0; changed = true; }
  Help("Lets the provider use its character-aware mask behavior.");

  bool ui_corr = g_nr.ui_correction != 0;
  if (ImGui::Checkbox("NR UI Correction", &ui_corr)) { g_nr.ui_correction = ui_corr ? 1 : 0; changed = true; }
  Help("Keep enabled. It reduces the chance of HUD/UI being altered by the neural pass.");

  ImGui::Spacing();
  ImGui::SeparatorText("Pass topology");
  ImGui::TextUnformatted("Active model passes: 1");
  Help("The current RenoDX DLSS 5 v4.7 consumer is a single-pass core. Secret EMKO does not fake 2/3-pass controls. Multi-pass will only be enabled when the current core exposes a safe, testable API for independent feature histories.");
  ImGui::TextDisabled("Latest-core policy: one correct temporal pass is preferred over stacking an older incompatible consumer.");

  if (changed) WriteNeuralSettings();
}

void DrawQuality() {
  if (!NeuralStackInstalled()) {
    ImGui::TextWrapped("Neural quality controls are unavailable in visual compatibility mode. ReShade post-processing remains active.");
    return;
  }
  bool changed = false;
  ImGui::SeparatorText("Colour bridge");
  changed |= Slider("Transfer Strength", &g_nr.transfer_strength, 0.0f, 1.0f, "Legacy colour-transfer strength retained by v4.7. 1.0 preserves the full bridge response.");
  changed |= Slider("Colour Strength", &g_nr.color_strength, 0.0f, 1.0f, "Chroma contribution. Enhanced uses 0.95 to avoid oversaturated fine detail.");

  changed |= Slider("Scene Paper-White Scale", &g_nr.paper_white_scale, 0.25f, 4.0f, "Use 1.0 for FiveM SDR. This exists mainly for HDR contracts.");
  changed |= Slider("Diffuse White", &g_nr.diffuse_white_nits, 80.0f, 500.0f, "v4.7 HDR diffuse-white reference. It is effectively informational for a normal SDR FiveM contract.", "%.0f nits");

  ImGui::Spacing();
  ImGui::SeparatorText("Geometry guidance");
  const char* depth_modes[] = {"Use NGX flag", "Force normal depth", "Force inverted depth"};
  ImGui::SetNextItemWidth(280.f);
  if (ImGui::Combo("Depth convention", &g_nr.depth_mode, depth_modes, IM_ARRAYSIZE(depth_modes))) changed = true;
  Help("Leave on Use NGX flag unless diagnostics prove that FiveM's depth convention is wrong.");

  changed |= Slider("Motion Scale X", &g_nr.mv_scale_x, 0.25f, 2.0f, "Multiplier applied by the neural consumer. 1.0 is neutral.");
  changed |= Slider("Motion Scale Y", &g_nr.mv_scale_y, 0.25f, 2.0f, "Multiplier applied by the neural consumer. 1.0 is neutral.");

  bool nr_upscale = g_nr.enable_upscaling != 0;
  if (ImGui::Checkbox("Neural pass performs upscaling", &nr_upscale)) {
    g_nr.enable_upscaling = nr_upscale ? 1 : 0;
    changed = true;
  }
  Help("Leave OFF for the GTA V Legacy synthetic 1:1 contract. The bridge/provider path is being used for Neural Rendering, not as a replacement for GTA's render-resolution controls.");
  if (g_nr.enable_upscaling) ImGui::TextWrapped("Not recommended for the current FiveM synthetic path.");

  if (changed) WriteNeuralSettings();

  ImGui::Spacing();
  ImGui::SeparatorText("Quality methodology");
  ImGui::TextWrapped("Tune in motion, not on a paused frame. Check thin fences, hair, vegetation, distant signage, emissive edges and translucent HUD elements. A higher structure number is not automatically a higher-quality result if it creates temporal crawl.");
}

void DrawBridge() {
  if (!NeuralStackInstalled()) {
    ImGui::TextWrapped("DLSS 5 Bridge is not installed in visual compatibility mode.");
    return;
  }

  bool changed = false;
  bool synth = g_bridge.synth != 0;
  if (ImGui::Checkbox("Replace / synthesize DLSS contract", &synth)) {
    g_bridge.synth = synth ? 1 : 0;
    changed = true;
  }
  Help("GTA V Legacy has no native DLSS contract, so this must be enabled for the bridge route.");

  const char* sources[] = {"Auto", "Synthetic", "Mirror native", "Off"};
  ImGui::SetNextItemWidth(260.f);
  if (ImGui::Combo("Bridge source", &g_bridge.source, sources, IM_ARRAYSIZE(sources))) changed = true;
  Help("Synthetic is the explicit GTA V Legacy route. Auto is useful when testing a game that may already expose DLSS.");

  const char* grids[] = {"1 (dense)", "2 (recommended)", "4 (lighter)", "0 (ReShade MV shader)"};
  int grid_idx = g_bridge.ofa_grid == 1 ? 0 : g_bridge.ofa_grid == 2 ? 1 : g_bridge.ofa_grid == 4 ? 2 : 3;
  ImGui::SetNextItemWidth(260.f);
  if (ImGui::Combo("Optical-flow grid", &grid_idx, grids, IM_ARRAYSIZE(grids))) {
    const int vals[] = {1, 2, 4, 0};
    g_bridge.ofa_grid = vals[grid_idx];
    changed = true;
  }
  Help("Grid 2 is the bridge default and recommended starting point. Grid 1 is reserved for Ultra Detail testing because it costs more.");

  const char* efforts[] = {"5 - Slow / quality", "10 - Medium", "20 - Fast"};
  int effort_idx = g_bridge.ofa_perf == 5 ? 0 : g_bridge.ofa_perf == 10 ? 1 : 2;
  ImGui::SetNextItemWidth(260.f);
  if (ImGui::Combo("Optical-flow effort", &effort_idx, efforts, IM_ARRAYSIZE(efforts))) {
    const int vals[] = {5, 10, 20};
    g_bridge.ofa_perf = vals[effort_idx];
    changed = true;
  }
  Help("These are NVIDIA optical-flow engine effort values documented by DLSS 5 Bridge. Enhanced uses Medium; Ultra Detail uses Slow.");

  ImGui::Text("Bridge stage: %d  |  mode: %d", g_bridge.stage, g_bridge.mode);
  Help("SECRET EMKO fixes normal operation to stage=3 and mode=2. Diagnostic partial modes are intentionally not exposed as normal presets.");

  ImGui::TextWrapped("FiveM online note: ReShade can restrict depth access during network play. SECRET EMKO does not bypass that safety behavior; the bridge therefore prioritizes hardware optical flow on the synthetic route.");

  if (changed) WriteBridgeConfig(g_nr.enabled == 0);

  if (ImGui::Button("Restore GTA/FiveM bridge defaults")) {
    g_bridge = {};
    g_bridge.synth = 1;
    g_bridge.source = 1;
    g_bridge.ofa_grid = 2;
    g_bridge.ofa_perf = 10;
    g_bridge.stage = 3;
    g_bridge.mode = 2;
    g_bridge.skip_game = 1;
    g_bridge.dred = 1;
    g_bridge.skip_exe = 1;
    g_bridge.unwrap = 1;
    g_bridge.hash_out = 1;
    WriteBridgeConfig(g_nr.enabled == 0);
  }
}

void DrawFrameGeneration() {
  const bool files_ready = FileExists(L"sl.dlss_g.dll") && FileExists(L"nvngx_dlssg.dll");
  ImGui::SeparatorText("Frame Generation readiness");
  ImGui::Text("Streamline/DLSSG runtime files: %s", files_ready ? "present" : "not installed");
  ImGui::TextWrapped("The runtime DLLs are only dependencies. FiveM Legacy still needs a validated Frame Generation input path with motion vectors, depth, HUD-less colour, swapchain ownership and frame pacing.");

  ImGui::BeginDisabled(true);
  const char* modes[] = {"Off", "2x total", "3x total"};
  ImGui::SetNextItemWidth(260.f);
  ImGui::Combo("Secret EMKO FG multiplier", &g_fg_policy, modes, IM_ARRAYSIZE(modes));
  ImGui::EndDisabled();
  Help("Intentionally locked in this preview. Secret EMKO will not claim Frame Generation is active just because nvngx_dlssg.dll exists.");

  ImGui::Spacing();
  ImGui::TextWrapped("Product policy remains 2x/3x total maximum. 4x and higher will not be exposed when the FiveM FG provider is implemented.");
}

void DrawDiagnostics() {
  ImGui::SeparatorText("Files");
  if (ImGui::BeginTable("##diag", 3, ImGuiTableFlags_RowBg | ImGuiTableFlags_BordersInnerH | ImGuiTableFlags_SizingStretchProp)) {
    ImGui::TableSetupColumn("File");
    ImGui::TableSetupColumn("On disk");
    ImGui::TableSetupColumn("Loaded");
    ImGui::TableHeadersRow();

    const std::pair<const wchar_t*, const char*> rows[] = {
      {L"dxgi.dll", "ReShade"},
      {L"SecretEMKO.addon64", "Secret EMKO"},
      {L"dlss5-bridge.addon64", "DLSS 5 Bridge"},
      {L"renodx-dlss5.addon64", "RenoDX DLSS 5"},
      {L"nvngx_dlss.dll", "DLSS SR"},
      {L"nvngx_dlssnr.dll", "DLSS NR"},
      {L"sl.interposer.dll", "Streamline Interposer"},
      {L"sl.dlss_g.dll", "Streamline DLSSG"},
      {L"nvngx_dlssg.dll", "DLSSG runtime"},
    };
    for (const auto& [file, label] : rows) {
      ImGui::TableNextRow();
      ImGui::TableSetColumnIndex(0); ImGui::TextUnformatted(label);
      ImGui::TableSetColumnIndex(1); ImGui::TextUnformatted(FileExists(file) ? "yes" : "no");
      ImGui::TableSetColumnIndex(2); ImGui::TextUnformatted(ModuleLoaded(file) ? "yes" : "no");
    }
    ImGui::EndTable();
  }

  ImGui::Spacing();
  ImGui::SeparatorText("Expected logs after a test");
  ImGui::BulletText("ReShade.log");
  ImGui::BulletText("dlss5-bridge.log");
  ImGui::TextWrapped("For a bug report, include both logs plus the FiveM crash dump if the process terminates. A rising FPS counter alone is not proof that Neural Rendering or generated frames are correct.");

  ImGui::Spacing();
  ImGui::Text("Install directory:");
  ImGui::TextWrapped("%ls", g_dir.c_str());
}

void DrawAbout() {
  ImGui::TextUnformatted("SECRET EMKO Neural Graphics");
  ImGui::Text("Version %s", kVersion);
  ImGui::Spacing();
  ImGui::TextWrapped("A FiveM GTA V Legacy control and integration layer built around public ReShade/RenoDX infrastructure and the open-source DLSS 5 Bridge. NVIDIA neural runtimes are separate third-party components.");
  ImGui::Spacing();
  ImGui::SeparatorText("Attribution");
  ImGui::BulletText("RenoDX framework: Carlos Lopez Jr. and contributors - MIT");
  ImGui::BulletText("DLSS 5 Bridge: NIGos and contributors - MIT");
  ImGui::BulletText("ReShade add-on API: Patrick Mours / crosire - BSD-3-Clause");
  ImGui::BulletText("NVIDIA DLSS / Streamline: NVIDIA proprietary runtimes under NVIDIA terms");
  ImGui::TextWrapped("SECRET EMKO branding does not imply authorship of RenoDX, ReShade, DLSS 5 Bridge or NVIDIA technology. See THIRD_PARTY_NOTICES.md and the licenses folder installed with the package.");
}

void DrawOverlay(reshade::api::effect_runtime* runtime) {
  if (!g_loaded) {
    LoadNeuralSettings();
    LoadBridgeConfig();
    g_loaded = true;
  }

  // Validate/hide the RenoDX backend page and discover its live controls before
  // drawing SECRET EMKO. This does not patch unknown RenoDX builds.
  g_live.tick(runtime);

  DrawHeader();

  if (ImGui::BeginTabBar("##se_tabs")) {
    if (ImGui::BeginTabItem("Overview")) { DrawOverview(); ImGui::EndTabItem(); }
    if (ImGui::BeginTabItem("Styles")) { DrawProfiles(); ImGui::EndTabItem(); }
    if (ImGui::BeginTabItem("Neural")) { DrawNeural(); ImGui::EndTabItem(); }
    if (ImGui::BeginTabItem("Quality")) { DrawQuality(); ImGui::EndTabItem(); }
    if (ImGui::BeginTabItem("Bridge")) { DrawBridge(); ImGui::EndTabItem(); }
    if (ImGui::BeginTabItem("Frame Generation")) { DrawFrameGeneration(); ImGui::EndTabItem(); }
    if (ImGui::BeginTabItem("Diagnostics")) { DrawDiagnostics(); ImGui::EndTabItem(); }
    if (ImGui::BeginTabItem("About")) { DrawAbout(); ImGui::EndTabItem(); }
    ImGui::EndTabBar();
  }

  // Apply changes queued by the SECRET EMKO widgets in this same frame and ask
  // RenoDX's own callback for an immediate readback confirmation.
  if (NeuralBackendsLoaded()) {
    const bool live_ok = g_live.tick(runtime);
    if (g_live.has_pending() || g_live.has_confirming() || (!live_ok && g_nr.enabled != 0))
      g_restart_required = true;
    else if (live_ok && g_live.last_apply_confirmed() && !g_provider_restart_pending) {
      // Runtime-supported values have been confirmed by RenoDX's own callback.
      if (g_nr.enabled == 0 || NeuralBackendsLoaded())
        g_restart_required = false;
    }
  }
}

void OnOverlayFrame(reshade::api::effect_runtime* runtime) {
  // ReShade calls this every ImGui frame, independently of which settings page
  // is selected. That lets SECRET EMKO hide the verified RenoDX settings page
  // and service queued live changes without requiring the user to visit it.
  if (!g_loaded) {
    LoadNeuralSettings();
    LoadBridgeConfig();
    g_loaded = true;
  }

  g_live.tick(runtime);

  if (!g_policy_synced) {
    SetBackendLoadPolicy(g_nr.enabled != 0);
    g_policy_synced = true;
  }
}

void Attach() {
  LoadNeuralSettings();
  LoadBridgeConfig();
  g_loaded = true;
  reshade::register_event<reshade::addon_event::reshade_overlay>(OnOverlayFrame);
  reshade::register_overlay(kProduct, DrawOverlay);
}

void Detach() {
  g_live.restore_provider_overlay();
  reshade::unregister_event<reshade::addon_event::reshade_overlay>(OnOverlayFrame);
  reshade::unregister_overlay(kProduct, DrawOverlay);
}

} // namespace

extern "C" __declspec(dllexport) constexpr const char* NAME = "SECRET EMKO Neural Graphics";
extern "C" __declspec(dllexport) constexpr const char* DESCRIPTION =
    "FiveM GTA V Legacy neural graphics control surface for RenoDX / ReShade";

BOOL APIENTRY DllMain(HMODULE h_module, DWORD reason, LPVOID) {
  switch (reason) {
    case DLL_PROCESS_ATTACH:
      g_module = h_module;
      g_dir = ModuleDirectory(h_module);
      if (!reshade::register_addon(h_module)) return FALSE;
      Attach();
      break;
    case DLL_PROCESS_DETACH:
      Detach();
      reshade::unregister_addon(h_module);
      break;
  }
  return TRUE;
}
