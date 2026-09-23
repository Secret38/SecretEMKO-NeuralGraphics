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
#include <cwctype>
#include <filesystem>
#include <fstream>
#include <sstream>
#include <string>
#include <unordered_map>
#include <vector>
#include <utility>

#include <deps/imgui/imgui.h>
#include <include/reshade.hpp>
#include "renodx_live_adapter.hpp"

namespace {

constexpr const char* kProduct = "SECRET EMKO Neural Graphics";
constexpr const char* kVersion = "2.0.0-rc5.1";
constexpr const char* kProviderSection = "RenoDX.DLSS5";
constexpr const char* kOwnSection = "SecretEMKO";

HMODULE g_module = nullptr;
std::filesystem::path g_dir;
bool g_restart_required = false;
bool g_loaded = false;
bool g_policy_synced = false;
bool g_temporal_policy_synced = false;
bool g_backends_next_start = true;
bool g_backend_transition_pending = false;
bool g_provider_restart_pending = false;
std::string g_backend_status;

// Full Neural runtime bootstrap. FiveM launches GTA V Legacy through a dynamic
// FiveM.app\\data\\cache\\subprocess host. Upstream NGX resolves the DLSS SR
// feature snippet relative to that host executable, while SECRET EMKO installs
// the verified runtime beside the ReShade add-ons. Keep one plugin-local module
// reference alive for the process and, for FiveM's disposable subprocess only,
// relay the same file beside the host so both Windows module resolution and NGX's
// file lookup see one deterministic runtime without asking the user to copy DLLs.
HMODULE g_sr_runtime_pin = nullptr;
std::filesystem::path g_host_dir;
bool g_sr_runtime_source_ready = false;
bool g_sr_runtime_module_ready = false;
bool g_sr_runtime_host_ready = false;
std::string g_sr_runtime_status;

struct BridgeRuntimeSnapshot {
  bool log_found = false;
  bool delivery_confirmed = false;
  bool synth_blocked = false;
  bool optical_flow_seen = false;
  bool depth_seen = false;
  std::string state = "Waiting for bridge telemetry.";
  std::string blocker;
};
BridgeRuntimeSnapshot g_bridge_runtime;
ULONGLONG g_bridge_runtime_last_scan = 0;

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
  int ofa_grid;
  int ofa_perf;
};

constexpr std::array<Profile, 6> kProfiles = {{
    {"Natural", "Very restrained neural reconstruction. Best first compatibility check.",
     1, 0.90f, 1.00f, 0.85f, 0.85f, 0.75f, 2, 20},
    {"Clean", "Low-artifact presentation with reduced structure emphasis.",
     0, 0.82f, 0.95f, 0.75f, 0.70f, 0.60f, 2, 20},
    {"Detail", "Sharper surfaces and micro-structure without pushing the model to the limit.",
     1, 1.08f, 1.02f, 0.95f, 1.28f, 0.95f, 2, 10},
    {"Enhanced", "Recommended quality-first daily profile. All profile-controlled RenoDX values apply live.",
     1, 1.20f, 1.05f, 1.05f, 1.35f, 1.00f, 2, 10},
    {"Cinematic", "Softer structure with stronger tonal shaping. Uses Natural model style for stability.",
     1, 1.12f, 1.18f, 1.28f, 1.08f, 0.90f, 2, 10},
    {"Ultra Detail", "Aggressive detail profile. Inspect foliage, wires and faces for temporal artifacts.",
     1, 1.34f, 1.10f, 1.12f, 1.68f, 1.00f, 1, 5},
}};

// RC5 user-facing looks. These are intentionally product-level looks rather
// than raw NVIDIA model names. All three stay on the provider's proven Natural
// model style; the one Strength control below is the live master intensity.
struct GamingStyle {
  const char* name;
  const char* tagline;
  float global_tone;
  float local_tone;
  float local_structure;
  float skin_structure;
  float default_strength;
};

constexpr std::array<GamingStyle, 3> kGamingStyles = {{
    {"Natural", "Clean, stable and close to the original GTA image.",
     1.05f, 1.05f, 1.35f, 1.00f, 1.20f},
    {"Cinematic", "Softer detail with stronger local and global tone shaping.",
     1.18f, 1.28f, 1.08f, 0.90f, 1.10f},
    {"Detail", "Sharper surfaces and stronger micro-structure for high-end displays.",
     1.08f, 1.08f, 1.58f, 1.00f, 1.28f},
}};

NeuralSettings g_nr;
NeuralSettings g_saved_nr;
BridgeSettings g_bridge;
secretemko_live::RenoDxLiveAdapter g_live;
int g_profile_index = 3;
int g_gaming_style = 0; // Natural / Cinematic / Detail
int g_fg_policy = 0; // 0 off, 1 2x, 2 3x
int g_motion_path = 0; // 0 auto, 1 compatibility optical-flow NR, 2 native GTA inputs
int g_nr_restore_after_fg = 0;
int g_fg_auto_base_fps = 1;
int g_fg_base_fps = 60;
int g_fg_hud_mode = 0; // 0 automatic, 1 strict, 2 off
int g_fg_auto_pause = 1;

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

// Runtime helpers below are intentionally placed before the component-status
// helpers because AddonInit needs bootstrap/telemetry early. Declare the two
// status queries they consume; their definitions remain in the component block.
bool RenoDxLoaded();
bool BridgeLoaded();

bool PathExists(const std::filesystem::path& path) {
  std::error_code ec;
  return std::filesystem::exists(path, ec);
}

std::wstring LowerWide(std::wstring value) {
  std::transform(value.begin(), value.end(), value.begin(),
                 [](wchar_t ch) { return static_cast<wchar_t>(std::towlower(ch)); });
  return value;
}

bool IsFiveMSubprocessHost(const std::filesystem::path& dir) {
  const auto lower = LowerWide(dir.wstring());
  return lower.find(L"\\fivem.app\\data\\cache\\subprocess") != std::wstring::npos;
}

void PrepareSyntheticSrRuntime() {
  g_host_dir = ModuleDirectory(nullptr);
  const auto source = g_dir / L"nvngx_dlss.dll";
  const auto host = g_host_dir / L"nvngx_dlss.dll";

  g_sr_runtime_source_ready = PathExists(source);
  g_sr_runtime_module_ready = false;
  g_sr_runtime_host_ready = false;

  if (!g_sr_runtime_source_ready) {
    g_sr_runtime_status = "DLSS SR runtime is missing from the SECRET EMKO plugins directory.";
    return;
  }

  // Load by full path before the synthetic contract is created. Windows reuses
  // an already-loaded module with the same base name, which gives NGX a stable
  // process-local SR snippet even though FiveM's executable directory is dynamic.
  g_sr_runtime_pin = LoadLibraryExW(
      source.c_str(), nullptr,
      LOAD_LIBRARY_SEARCH_DLL_LOAD_DIR | LOAD_LIBRARY_SEARCH_DEFAULT_DIRS);
  if (g_sr_runtime_pin == nullptr)
    g_sr_runtime_pin = LoadLibraryW(source.c_str());
  g_sr_runtime_module_ready = g_sr_runtime_pin != nullptr;

  std::error_code ec;
  const bool same_dir = std::filesystem::equivalent(g_dir, g_host_dir, ec);
  if (!ec && same_dir) {
    g_sr_runtime_host_ready = true;
  } else if (IsFiveMSubprocessHost(g_host_dir)) {
    if (PathExists(host)) {
      g_sr_runtime_host_ready = true;
    } else {
      // Prefer a hardlink: no duplicate 50+ MB runtime and both names refer to
      // the exact same bytes. Cross-volume or policy failures fall back to a copy.
      if (CreateHardLinkW(host.c_str(), source.c_str(), nullptr) != FALSE ||
          CopyFileW(source.c_str(), host.c_str(), TRUE) != FALSE)
        g_sr_runtime_host_ready = true;
    }
  } else {
    // Outside FiveM's disposable subprocess tree we deliberately do not write
    // next to an arbitrary executable. The full-path module preload still gives
    // the process a deterministic runtime.
    g_sr_runtime_host_ready = g_sr_runtime_module_ready;
  }

  if (g_sr_runtime_module_ready && g_sr_runtime_host_ready)
    g_sr_runtime_status = "DLSS SR runtime prepared automatically for the synthetic FiveM contract.";
  else if (g_sr_runtime_module_ready)
    g_sr_runtime_status = "DLSS SR runtime is loaded, but the FiveM host relay could not be created.";
  else
    g_sr_runtime_status = "DLSS SR runtime file exists, but Windows could not load it.";
}

std::string ReadFileTail(const std::filesystem::path& path, std::streamoff max_bytes = 512 * 1024) {
  std::ifstream in(path, std::ios::binary);
  if (!in) return {};
  in.seekg(0, std::ios::end);
  const std::streamoff size = in.tellg();
  const std::streamoff start = size > max_bytes ? size - max_bytes : 0;
  in.seekg(start, std::ios::beg);
  std::string data(static_cast<size_t>(size - start), '\0');
  if (!data.empty()) in.read(data.data(), static_cast<std::streamsize>(data.size()));
  return data;
}

void RefreshBridgeRuntimeSnapshot(bool force = false) {
  const ULONGLONG now = GetTickCount64();
  if (!force && now - g_bridge_runtime_last_scan < 1000) return;
  g_bridge_runtime_last_scan = now;

  BridgeRuntimeSnapshot next;
  const auto log = g_dir / L"dlss5-bridge.log";
  if (!PathExists(log)) {
    next.state = BridgeLoaded() ? "Bridge loaded; waiting for its runtime log." : "Bridge is not loaded.";
    g_bridge_runtime = std::move(next);
    return;
  }

  next.log_found = true;
  std::string tail = ReadFileTail(log);
  // Logs may contain previous sessions. Restrict decisions to the latest attach
  // banner so an old successful run can never make a failed current run look active.
  const auto attach = tail.rfind("dlss5-bridge ");
  if (attach != std::string::npos) tail.erase(0, attach);

  next.delivery_confirmed =
      tail.find("frames delivered so far.") != std::string::npos;
  next.optical_flow_seen =
      tail.find("NVIDIA optical flow") != std::string::npos ||
      tail.find("optical flow engine") != std::string::npos;
  next.depth_seen =
      tail.find("depth (") != std::string::npos &&
      tail.find("bound") != std::string::npos;

  const std::array<const char*, 7> blockers = {{
      "CreateFeature failed",
      "not delivering:",
      "REFUSED",
      "verdict: not viable",
      "five consecutive D3D12 evaluates were refused",
      "feature creation did not complete",
      "could not load"
  }};
  size_t newest_blocker = std::string::npos;
  const char* blocker_text = nullptr;
  for (const char* marker : blockers) {
    const size_t p = tail.rfind(marker);
    if (p != std::string::npos && (newest_blocker == std::string::npos || p > newest_blocker)) {
      newest_blocker = p;
      blocker_text = marker;
    }
  }
  next.synth_blocked = blocker_text != nullptr && !next.delivery_confirmed;
  if (blocker_text) next.blocker = blocker_text;

  if (next.delivery_confirmed)
    next.state = "ACTIVE - bridge has confirmed delivered neural-path frames in this session.";
  else if (next.synth_blocked)
    next.state = "BLOCKED - the bridge reported a synthetic-contract failure; see dlss5-bridge.log.";
  else if (g_sr_runtime_module_ready && BridgeLoaded() && RenoDxLoaded())
    next.state = "ARMED - runtime, bridge and RenoDX are loaded; waiting for delivered-frame confirmation.";
  else
    next.state = "WAITING - the complete neural backend chain is not active yet.";

  g_bridge_runtime = std::move(next);
}

bool ModuleLoaded(const wchar_t* name) {
  return GetModuleHandleW(name) != nullptr;
}

bool NeuralStackInstalled() {
  return FileExists(L"renodx-dlss5.addon64") &&
         FileExists(L"dlss5-bridge.addon64") &&
         FileExists(L"nvngx_dlssnr.dll");
}

bool RenoDxLoaded() {
  return ModuleLoaded(L"renodx-dlss5.addon64");
}

bool BridgeLoaded() {
  return ModuleLoaded(L"dlss5-bridge.addon64");
}

bool NeuralBackendsLoaded() {
  return RenoDxLoaded() && BridgeLoaded();
}

bool FrameGenRuntimeInstalled() {
  return FileExists(L"sl.interposer.dll") &&
         FileExists(L"sl.dlss_g.dll") &&
         FileExists(L"nvngx_dlssg.dll");
}

bool FrameGenProviderInstalled() {
  return FileExists(L"SecretEMKO-FG.addon64");
}

bool FrameGenProviderLoaded() {
  return ModuleLoaded(L"SecretEMKO-FG.addon64");
}

enum FgProviderFlags : uint32_t {
  kFgInitialized       = 1u << 0,
  kFgD3D11Observed     = 1u << 1,
  kFgDepthObserved     = 1u << 2,
  kFgRenderTargetSeen  = 1u << 3,
  kFgNativeMotionReady = 1u << 4,
  kFgHudlessReady      = 1u << 5,
  kFgUiReady           = 1u << 6,
  kFgStreamlineReady   = 1u << 7,
  kFgFrameGenReady     = 1u << 8,
  kFgNrSharedReady     = 1u << 9,
  kFgDiscoveryOnly     = 1u << 10,
};

struct FgProviderStatusV1 {
  uint32_t abi = 0;
  uint32_t struct_size = 0;
  uint64_t presented_frames = 0;
  uint64_t depth_binds = 0;
  uint64_t render_target_binds = 0;
  uint32_t device_api = 0;
  uint32_t flags = 0;
};

bool QueryFrameGenProvider(FgProviderStatusV1& status) {
  HMODULE module = GetModuleHandleW(L"SecretEMKO-FG.addon64");
  if (module == nullptr) return false;
  using Fn = bool (*)(FgProviderStatusV1*, uint32_t);
  auto fn = reinterpret_cast<Fn>(GetProcAddress(module, "SecretEMKO_FG_GetStatus"));
  if (fn == nullptr) return false;
  FgProviderStatusV1 next{};
  if (!fn(&next, sizeof(next)) || next.abi != 1 || next.struct_size < sizeof(FgProviderStatusV1))
    return false;
  status = next;
  return true;
}

bool NativeMotionReady() {
  FgProviderStatusV1 s{};
  return QueryFrameGenProvider(s) && (s.flags & kFgNativeMotionReady) != 0;
}

bool NativeNrSharedReady() {
  FgProviderStatusV1 s{};
  return QueryFrameGenProvider(s) && (s.flags & kFgNrSharedReady) != 0;
}

bool FrameGenReady() {
  FgProviderStatusV1 s{};
  return FrameGenRuntimeInstalled() &&
         QueryFrameGenProvider(s) &&
         (s.flags & kFgFrameGenReady) != 0 &&
         (s.flags & kFgNativeMotionReady) != 0 &&
         (s.flags & kFgHudlessReady) != 0 &&
         (s.flags & kFgUiReady) != 0;
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

  const bool renodx_loaded = RenoDxLoaded();
  const bool bridge_loaded = BridgeLoaded();
  const bool chain_loaded = renodx_loaded && bridge_loaded;
  const bool any_loaded = renodx_loaded || bridge_loaded;

  g_backend_transition_pending = load_next_start != chain_loaded;

  if (load_next_start && !chain_loaded) {
    g_restart_required = true;
    if (any_loaded)
      g_backend_status = "Neural backend chain is only partially loaded; both RenoDX and Bridge are scheduled for the next start.";
    else
      g_backend_status = "Neural backends are scheduled to load on the next start.";
  } else if (!load_next_start && any_loaded) {
    g_backend_status = "Loaded neural backends are being soft-disabled now and are scheduled not to load next start.";
  } else {
    g_backend_status = load_next_start ? "RenoDX and Bridge are loaded for this session." : "Neural backends are not loaded.";
  }
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
  // Desired state lives in ReShade.ini. The bridge cfg is the operational
  // projection and may temporarily contain source=off while Neural is asleep.
  WriteConfig(kOwnSection, "BridgeSynth", g_bridge.synth);
  WriteConfig(kOwnSection, "BridgeSource", g_bridge.source);
  WriteConfig(kOwnSection, "BridgeOfaGrid", g_bridge.ofa_grid);
  WriteConfig(kOwnSection, "BridgeOfaPerf", g_bridge.ofa_perf);
  WriteConfig(kOwnSection, "BridgeStage", g_bridge.stage);
  WriteConfig(kOwnSection, "BridgeMode", g_bridge.mode);
  WriteConfig(kOwnSection, "BridgeSkipGame", g_bridge.skip_game);
  WriteConfig(kOwnSection, "BridgeDred", g_bridge.dred);
  WriteConfig(kOwnSection, "BridgeSkipExe", g_bridge.skip_exe);
  WriteConfig(kOwnSection, "BridgeUnwrap", g_bridge.unwrap);
  WriteConfig(kOwnSection, "BridgeHashOut", g_bridge.hash_out);

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

  // RC3 desired-state keys override the operational cfg. This is what lets
  // source=off persist operationally while Neural is disabled without losing
  // the user's preferred bridge settings for the next enable.
  ReadConfig(kOwnSection, "BridgeSynth", g_bridge.synth);
  ReadConfig(kOwnSection, "BridgeSource", g_bridge.source);
  ReadConfig(kOwnSection, "BridgeOfaGrid", g_bridge.ofa_grid);
  ReadConfig(kOwnSection, "BridgeOfaPerf", g_bridge.ofa_perf);
  ReadConfig(kOwnSection, "BridgeStage", g_bridge.stage);
  ReadConfig(kOwnSection, "BridgeMode", g_bridge.mode);
  ReadConfig(kOwnSection, "BridgeSkipGame", g_bridge.skip_game);
  ReadConfig(kOwnSection, "BridgeDred", g_bridge.dred);
  ReadConfig(kOwnSection, "BridgeSkipExe", g_bridge.skip_exe);
  ReadConfig(kOwnSection, "BridgeUnwrap", g_bridge.unwrap);
  ReadConfig(kOwnSection, "BridgeHashOut", g_bridge.hash_out);
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
    if (RenoDxLoaded() && g_live.available()) {
      g_live.queue_diff(ToLiveDesired(g_nr));
    } else if (RenoDxLoaded() || g_nr.enabled != 0) {
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

void LoadNeuralSettings(bool apply_live = false) {
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
  ReadConfig(kOwnSection, "GamingStyle", g_gaming_style);
  ReadConfig(kOwnSection, "FrameGenerationPolicy", g_fg_policy);
  ReadConfig(kOwnSection, "MotionPath", g_motion_path);
  ReadConfig(kOwnSection, "NRRestoreAfterFG", g_nr_restore_after_fg);
  ReadConfig(kOwnSection, "FrameGenerationAutoBaseFPS", g_fg_auto_base_fps);
  ReadConfig(kOwnSection, "FrameGenerationBaseFPS", g_fg_base_fps);
  ReadConfig(kOwnSection, "FrameGenerationHUDMode", g_fg_hud_mode);
  ReadConfig(kOwnSection, "FrameGenerationAutoPause", g_fg_auto_pause);

  g_profile_index = std::clamp(g_profile_index, 0, static_cast<int>(kProfiles.size()) - 1);
  g_gaming_style = std::clamp(g_gaming_style, 0, static_cast<int>(kGamingStyles.size()) - 1);
  g_fg_policy = std::clamp(g_fg_policy, 0, 2);
  g_motion_path = std::clamp(g_motion_path, 0, 2);
  g_nr_restore_after_fg = g_nr_restore_after_fg ? 1 : 0;
  g_fg_auto_base_fps = g_fg_auto_base_fps ? 1 : 0;
  g_fg_base_fps = std::clamp(g_fg_base_fps, 20, 240);
  g_fg_hud_mode = std::clamp(g_fg_hud_mode, 0, 2);
  g_fg_auto_pause = g_fg_auto_pause ? 1 : 0;
  int backends = g_nr.enabled != 0 ? 1 : 0;
  ReadConfig(kOwnSection, "BackendsNextStart", backends);
  g_backends_next_start = backends != 0;
  g_saved_nr = g_nr;

  // RenoDX reads the persisted [RenoDX.DLSS5] values during its own
  // initialization. Do not rewrite every provider field merely because SECRET
  // EMKO opened: startup is discovery-only. Explicit reloads/user edits may
  // queue a live diff after the verified adapter has established its baseline.
  if (apply_live)
    g_live.queue_diff(ToLiveDesired(g_nr));
  else
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
  // Profiles only touch values covered by the verified v4.70 live-control
  // surface. Restart-only compatibility values keep the user's saved state.
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

void ApplyGamingStyle(int index, bool reset_strength = false) {
  index = std::clamp(index, 0, static_cast<int>(kGamingStyles.size()) - 1);
  const auto& style = kGamingStyles[index];
  g_gaming_style = index;

  // Keep the proven Natural provider model for all product looks. The visible
  // difference comes from live tone/structure tuning, not from pretending that
  // three independent neural networks exist.
  g_nr.style = 1;
  g_nr.preset = 0;
  g_nr.global_tone = style.global_tone;
  g_nr.local_tone = style.local_tone;
  g_nr.local_structure = style.local_structure;
  g_nr.skin_structure = style.skin_structure;
  g_nr.auto_mask = 1;
  g_nr.ui_correction = 1;
  g_nr.enable_upscaling = 0;
  if (reset_strength) g_nr.intensity = style.default_strength;
  g_nr.enabled = (g_fg_policy == 0 || NativeNrSharedReady()) ? 1 : 0;

  WriteConfig(kOwnSection, "GamingStyle", g_gaming_style);
  SetBackendLoadPolicy(true);
  WriteNeuralSettings();
}

void PersistFrameGenerationSettings() {
  WriteConfig(kOwnSection, "FrameGenerationPolicy", g_fg_policy);
  WriteConfig(kOwnSection, "MotionPath", g_motion_path);
  WriteConfig(kOwnSection, "NRRestoreAfterFG", g_nr_restore_after_fg);
  WriteConfig(kOwnSection, "FrameGenerationAutoBaseFPS", g_fg_auto_base_fps);
  WriteConfig(kOwnSection, "FrameGenerationBaseFPS", g_fg_base_fps);
  WriteConfig(kOwnSection, "FrameGenerationHUDMode", g_fg_hud_mode);
  WriteConfig(kOwnSection, "FrameGenerationAutoPause", g_fg_auto_pause);
}

void ApplyCompatibilityMotionPath() {
  g_motion_path = 1;
  if (g_fg_policy != 0) g_fg_policy = 0;
  if (g_nr_restore_after_fg) {
    g_nr.enabled = 1;
    g_nr_restore_after_fg = 0;
    WriteNeuralSettings();
  }

  // The compatibility path belongs to synthetic Neural Rendering only. Keep
  // the bridge's NVIDIA Optical Flow input, but never run it beside native FG.
  g_bridge.synth = 1;
  g_bridge.source = 1;
  if (g_bridge.ofa_grid == 0) g_bridge.ofa_grid = 2;
  g_bridge.stage = 3;
  g_bridge.mode = 2;
  WriteBridgeConfig(g_nr.enabled == 0);
  PersistFrameGenerationSettings();
}

bool ApplyNativeFrameGenPath(int policy);

void EnsureTemporalPolicy() {
  if (g_temporal_policy_synced) return;

  const int requested_motion = g_motion_path;
  const int requested_fg = g_fg_policy;

  if (requested_fg != 0) {
    if (!ApplyNativeFrameGenPath(requested_fg)) {
      // Stale config or provider regression: fail closed, restore the known
      // compatibility path and never present a saved 2x/3x selection as active.
      ApplyCompatibilityMotionPath();
      if (requested_motion == 0) {
        g_motion_path = 0;
        PersistFrameGenerationSettings();
      }
      g_backend_status = "Saved Frame Generation state was rejected because verified GTA shader-motion/HUD inputs are not ready.";
    }
  } else if (requested_motion == 2 && NativeMotionReady()) {
    g_bridge.synth = 0;
    g_bridge.source = 3;
    WriteBridgeConfig(true);
  } else {
    ApplyCompatibilityMotionPath();
    if (requested_motion == 0) {
      g_motion_path = 0;
      PersistFrameGenerationSettings();
    }
  }

  g_temporal_policy_synced = true;
}

bool ApplyNativeFrameGenPath(int policy) {
  policy = std::clamp(policy, 0, 2);
  if (policy == 0) {
    g_fg_policy = 0;
    if (g_motion_path == 0 || g_motion_path == 1) {
      g_motion_path = 1;
      g_bridge.synth = 1;
      g_bridge.source = 1;
      if (g_bridge.ofa_grid == 0) g_bridge.ofa_grid = 2;
      WriteBridgeConfig(g_nr.enabled == 0);
    }
    if (g_nr_restore_after_fg) {
      g_nr.enabled = 1;
      g_nr_restore_after_fg = 0;
      WriteNeuralSettings();
    }
    PersistFrameGenerationSettings();
    return true;
  }

  if (!FrameGenReady()) return false;

  // Native FG and the compatibility OFA contract must not own temporal input
  // simultaneously. The native provider owns motion/depth/HUD/pacing here.
  g_motion_path = 2;
  g_fg_policy = policy;
  g_bridge.synth = 0;
  g_bridge.source = 3;
  WriteBridgeConfig(true);

  // Native motion itself is compatible with NR+FG. Keep NR only when the native
  // provider explicitly advertises a shared, frame-aligned NR contract.
  if (g_nr.enabled && !NativeNrSharedReady()) {
    g_nr_restore_after_fg = 1;
    g_nr.enabled = 0;
    WriteNeuralSettings();
  }

  PersistFrameGenerationSettings();
  return true;
}

void SetNeuralEnabled(bool enabled) {
  if (enabled && g_fg_policy != 0) {
    if (!NativeNrSharedReady()) {
      g_nr.enabled = 0;
      g_backend_status = "Neural Rendering stays off while Frame Generation is active until the GTA shader-motion provider exposes a shared, frame-aligned NR contract.";
      WriteNeuralSettings();
      return;
    }

    g_nr.enabled = 1;
    SetBackendLoadPolicy(true);
    WriteNeuralSettings();
    // Native provider owns temporal input while FG is active; never wake the
    // Optical Flow compatibility bridge in this state.
    WriteBridgeConfig(true);
    return;
  }

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
    if (!g_live.available() && RenoDxLoaded()) {
      g_restart_required = true;
      g_backend_status = "Backends will not load next start. RenoDX is loaded but live shutdown is unavailable in this session, so restart is required for a guaranteed full stop.";
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
  RefreshBridgeRuntimeSnapshot();

  ImGui::PushStyleVar(ImGuiStyleVar_ChildRounding, 10.0f);
  ImGui::PushStyleVar(ImGuiStyleVar_ChildBorderSize, 1.0f);
  ImGui::BeginChild("##se_header", ImVec2(0, 72), true);
  ImGui::TextUnformatted("SECRET EMKO");
  ImGui::SameLine();
  ImGui::TextDisabled("NEURAL GRAPHICS  /  RC5.1");
  ImGui::TextDisabled("FiveM GTA V Legacy");

  const char* neural = !NeuralStackInstalled() ? "VISUAL"
                       : g_bridge_runtime.delivery_confirmed ? "ACTIVE"
                       : g_bridge_runtime.synth_blocked ? "BLOCKED"
                       : "READY";
  const char* fg = FrameGenReady() ? (g_fg_policy == 0 ? "READY" : "ARMED") : "LOCKED";
  ImGui::Text("NEURAL  %s", neural);
  ImGui::SameLine(170.0f);
  ImGui::Text("FRAME GEN  %s", fg);
  ImGui::EndChild();
  ImGui::PopStyleVar(2);

  if (g_restart_required)
    ImGui::TextDisabled("Restart required for a pending backend/provider change.");
}

void DrawGamingGraphics() {
  const bool neural_stack = NeuralStackInstalled();
  ImGui::PushStyleVar(ImGuiStyleVar_ChildRounding, 10.0f);
  ImGui::BeginChild("##graphics_card", ImVec2(0, 0), true);

  ImGui::TextUnformatted("NEURAL GRAPHICS");
  ImGui::TextDisabled("Three looks. One strength control. Changes apply live when the verified provider is active.");
  ImGui::Spacing();

  bool enabled = g_nr.enabled != 0;
  if (ImGui::Checkbox("Enabled", &enabled))
    SetNeuralEnabled(enabled);

  ImGui::Spacing();
  ImGui::TextDisabled("STYLE");

  const float gap = 8.0f;
  const float width = std::max(90.0f, (ImGui::GetContentRegionAvail().x - gap * 2.0f) / 3.0f);
  for (int i = 0; i < static_cast<int>(kGamingStyles.size()); ++i) {
    if (i != 0) ImGui::SameLine(0.0f, gap);
    const bool selected = g_gaming_style == i;
    if (selected) ImGui::PushStyleVar(ImGuiStyleVar_FrameBorderSize, 2.0f);
    std::string label = std::string(kGamingStyles[i].name) + "##gaming_style_" + std::to_string(i);
    if (ImGui::Button(label.c_str(), ImVec2(width, 38.0f)))
      ApplyGamingStyle(i, true);
    if (selected) ImGui::PopStyleVar();
  }

  ImGui::TextWrapped("%s", kGamingStyles[g_gaming_style].tagline);
  ImGui::Spacing();

  float strength = g_nr.intensity;
  ImGui::SetNextItemWidth(-1.0f);
  if (ImGui::SliderFloat("##gaming_strength", &strength, 0.0f, 2.0f, "Strength  %.2f")) {
    g_nr.intensity = strength;
    WriteNeuralSettings();
  }
  ImGui::TextDisabled("0.00 = effect off  |  1.00 = balanced  |  2.00 = maximum");

  ImGui::Spacing();
  if (!neural_stack)
    ImGui::TextWrapped("Full Neural is not installed. The visual ReShade preset remains available.");
  else if (RenoDxLoaded() && g_live.available())
    ImGui::TextDisabled("LIVE  /  provider callback + readback active");
  else if (g_nr.enabled)
    ImGui::TextDisabled("SAVED  /  provider will apply after its backend is available");
  else
    ImGui::TextDisabled("OFF");

  ImGui::EndChild();
  ImGui::PopStyleVar();
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
    const NeuralSettings before_reload = g_nr;
    const bool previous_provider_restart = g_provider_restart_pending;
    LoadNeuralSettings(true);
    LoadBridgeConfig();
    g_provider_restart_pending =
        previous_provider_restart || ProviderRestartOnlyChange(before_reload, g_nr);
    g_restart_required =
        g_provider_restart_pending ||
        (g_nr.enabled != 0 && !NeuralBackendsLoaded());
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
    StatusRow("DLSS 5 Bridge", L"dlss5-bridge.addon64", neural_stack, neural_stack ? "Synthetic GTA V Legacy D3D11 contract with internal NVIDIA Optical Flow fallback." : "Not required in visual compatibility mode.");
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

  if (RenoDxLoaded()) {
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
  ImGui::SeparatorText("Live quality controls");
  changed |= Slider("Diffuse White", &g_nr.diffuse_white_nits, 80.0f, 500.0f, "v4.7 diffuse-white control. This value is part of the verified live RenoDX callback surface.", "%.0f nits");

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
  if (ImGui::TreeNode("Advanced provider compatibility (restart required)")) {
    ImGui::TextWrapped("These three legacy/provider values are persisted, but the verified RenoDX v4.70 settings callback does not expose them. SECRET EMKO therefore never labels them as live.");
    bool restart_changed = false;
    restart_changed |= Slider("Transfer Strength", &g_nr.transfer_strength, 0.0f, 1.0f, "Persisted provider compatibility value. Requires provider recreation/restart in RC3.");
    restart_changed |= Slider("Colour Strength", &g_nr.color_strength, 0.0f, 1.0f, "Persisted provider compatibility value. Requires provider recreation/restart in RC3.");
    restart_changed |= Slider("Scene Paper-White Scale", &g_nr.paper_white_scale, 0.25f, 4.0f, "Persisted HDR compatibility value. Requires provider recreation/restart in RC3.");
    if (restart_changed) WriteNeuralSettings();
    ImGui::TreePop();
  }

  ImGui::Spacing();
  ImGui::SeparatorText("Quality methodology");
  ImGui::TextWrapped("Tune in motion, not on a paused frame. Check thin fences, hair, vegetation, distant signage, emissive edges and translucent HUD elements. A higher structure number is not automatically a higher-quality result if it creates temporal crawl.");
}

void DrawMotionPolicy() {
  ImGui::SeparatorText("Temporal input policy");
  ImGui::TextWrapped("Compatibility Optical Flow and native Frame Generation are mutually exclusive. GTA shader motion is the path that can eventually feed both Neural Rendering and Frame Generation.");

  const char* modes[] = {"Auto (recommended)", "Compatibility motion (NR only)", "GTA shader motion"};
  int requested = g_motion_path;
  ImGui::SetNextItemWidth(320.0f);
  if (ImGui::Combo("Motion / FG input", &requested, modes, IM_ARRAYSIZE(modes))) {
    if (requested == 1) {
      ApplyCompatibilityMotionPath();
    } else if (requested == 2) {
      if (NativeMotionReady()) {
        g_motion_path = 2;
        g_bridge.synth = 0;
        g_bridge.source = 3;
        WriteBridgeConfig(true);
        PersistFrameGenerationSettings();
      }
    } else {
      g_motion_path = 0;
      if (g_fg_policy == 0) ApplyCompatibilityMotionPath();
      g_motion_path = 0;
      PersistFrameGenerationSettings();
    }
  }

  if (g_motion_path == 2 && !NativeMotionReady())
    ImGui::TextWrapped("GTA shader motion is not ready yet; SECRET EMKO keeps Frame Generation locked.");
  else if (g_motion_path == 1)
    ImGui::TextDisabled("Compatibility mode: NVIDIA Optical Flow may feed synthetic NR; Frame Generation is forced off.");
  else
    ImGui::TextDisabled("Auto: compatibility motion while FG is off; native GTA inputs whenever FG is enabled.");
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
  Help("Grid 1/2/4 use the bridge's internal NVIDIA Optical Flow path, so no separate ReShade motion-vector shader is required. Grid 2 is the recommended starting point. Grid 0 explicitly switches to a ReShade motion-vector provider.");

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
  const bool runtime = FrameGenRuntimeInstalled();
  const bool provider = FrameGenProviderInstalled();
  const bool loaded = FrameGenProviderLoaded();
  const bool ready = FrameGenReady();

  ImGui::PushStyleVar(ImGuiStyleVar_ChildRounding, 10.0f);
  ImGui::BeginChild("##fg_card", ImVec2(0, 0), true);
  ImGui::TextUnformatted("FRAME GENERATION");
  ImGui::TextDisabled("Simple controls; the native GTA input provider owns timing, HUD separation and generated-frame delivery.");
  ImGui::Spacing();

  FgProviderStatusV1 provider_status{};
  const bool provider_status_ok = QueryFrameGenProvider(provider_status);
  if (!ready) {
    ImGui::TextWrapped("Locked until GTA shader motion, depth, HUD-less colour and UI inputs are all verified.");
    ImGui::TextDisabled("Runtime: %s  |  Provider: %s",
                        runtime ? "ready" : "missing",
                        provider ? (loaded ? "discovery" : "restart required") : "missing");
    if (provider_status_ok) {
      ImGui::TextDisabled("Discovery: D3D11 %s / depth %s / render targets %s / shader motion %s",
                          (provider_status.flags & kFgD3D11Observed) ? "yes" : "no",
                          (provider_status.flags & kFgDepthObserved) ? "yes" : "no",
                          (provider_status.flags & kFgRenderTargetSeen) ? "yes" : "no",
                          (provider_status.flags & kFgNativeMotionReady) ? "ready" : "not ready");
    }
  }

  ImGui::TextDisabled("MODE");
  const float gap = 8.0f;
  const float width = std::max(90.0f, (ImGui::GetContentRegionAvail().x - gap * 2.0f) / 3.0f);
  if (ImGui::Button("Off", ImVec2(width, 38.0f)))
    (void)ApplyNativeFrameGenPath(0);
  ImGui::SameLine(0.0f, gap);
  ImGui::BeginDisabled(!ready);
  if (ImGui::Button("2x", ImVec2(width, 38.0f)))
    (void)ApplyNativeFrameGenPath(1);
  ImGui::SameLine(0.0f, gap);
  if (ImGui::Button("3x", ImVec2(width, 38.0f)))
    (void)ApplyNativeFrameGenPath(2);
  ImGui::EndDisabled();

  ImGui::BeginDisabled(!ready || g_fg_policy == 0);
  ImGui::Spacing();
  if (g_fg_policy == 0)
    ImGui::TextDisabled("Input path: Compatibility motion for Neural Rendering");
  else
    ImGui::TextDisabled("Input path: GTA shader motion + depth + HUD separation");

  ImGui::Spacing();
  bool auto_base = g_fg_auto_base_fps != 0;
  if (ImGui::Checkbox("Automatic base FPS", &auto_base)) {
    g_fg_auto_base_fps = auto_base ? 1 : 0;
    PersistFrameGenerationSettings();
  }
  Help("The provider will derive a stable base-frame target from display timing and the selected multiplier.");

  if (!g_fg_auto_base_fps) {
    ImGui::SetNextItemWidth(-1.0f);
    if (ImGui::SliderInt("##base_fps", &g_fg_base_fps, 20, 240, "Base FPS  %d")) {
      PersistFrameGenerationSettings();
    }
  } else {
    ImGui::TextDisabled("Base FPS  AUTO");
  }

  ImGui::Spacing();
  ImGui::TextDisabled("HUD PROTECTION");
  const char* hud_modes[] = {"Automatic", "Strict", "Off"};
  ImGui::SetNextItemWidth(-1.0f);
  if (ImGui::Combo("##hud_mode", &g_fg_hud_mode, hud_modes, IM_ARRAYSIZE(hud_modes)))
    PersistFrameGenerationSettings();
  Help("Automatic is the normal mode: capture HUD-less scene color and UI alpha separately, then recompose UI after generated frames.");

  bool auto_pause = g_fg_auto_pause != 0;
  if (ImGui::Checkbox("Pause FG in menus / loading / resolution changes", &auto_pause)) {
    g_fg_auto_pause = auto_pause ? 1 : 0;
    PersistFrameGenerationSettings();
  }
  ImGui::EndDisabled();

  ImGui::Spacing();
  ImGui::TextDisabled("Quality policy: no Optical Flow-only FG. The target provider requires shader-injected GTA motion, depth, HUD-less color and UI data.");
  ImGui::EndChild();
  ImGui::PopStyleVar();
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
      {L"SecretEMKO-FG.addon64", "SECRET EMKO FG Provider"},
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
  ImGui::SeparatorText("GTA shader-motion / Frame Gen provider");
  FgProviderStatusV1 fg_status{};
  if (QueryFrameGenProvider(fg_status)) {
    ImGui::Text("Provider ABI: %u  |  frames observed: %llu",
                fg_status.abi, static_cast<unsigned long long>(fg_status.presented_frames));
    ImGui::BulletText("D3D11 observed: %s", (fg_status.flags & kFgD3D11Observed) ? "yes" : "no");
    ImGui::BulletText("Depth activity: %s", (fg_status.flags & kFgDepthObserved) ? "yes" : "no");
    ImGui::BulletText("Render-target activity: %s", (fg_status.flags & kFgRenderTargetSeen) ? "yes" : "no");
    ImGui::BulletText("GTA shader motion: %s", (fg_status.flags & kFgNativeMotionReady) ? "ready" : "discovery");
    ImGui::BulletText("HUD-less color: %s", (fg_status.flags & kFgHudlessReady) ? "ready" : "discovery");
    ImGui::BulletText("UI input: %s", (fg_status.flags & kFgUiReady) ? "ready" : "discovery");
    ImGui::BulletText("Frame Generation: %s", (fg_status.flags & kFgFrameGenReady) ? "ready" : "locked");
    ImGui::BulletText("Shared NR contract: %s", (fg_status.flags & kFgNrSharedReady) ? "ready" : "not ready");
  } else {
    ImGui::TextDisabled("Native provider status unavailable.");
  }

  ImGui::Spacing();
  ImGui::SeparatorText("Synthetic runtime bootstrap");
  ImGui::Text("Plugin SR runtime: %s", g_sr_runtime_source_ready ? "present" : "missing");
  ImGui::Text("SR module preloaded: %s", g_sr_runtime_module_ready ? "yes" : "no");
  ImGui::Text("FiveM host relay: %s", g_sr_runtime_host_ready ? "ready" : "not ready");
  ImGui::TextWrapped("%s", g_sr_runtime_status.c_str());
  if (!g_host_dir.empty()) {
    ImGui::TextDisabled("Current host directory:");
    ImGui::TextWrapped("%ls", g_host_dir.c_str());
  }

  RefreshBridgeRuntimeSnapshot();
  ImGui::Spacing();
  ImGui::SeparatorText("Neural pipeline state");
  ImGui::TextWrapped("%s", g_bridge_runtime.state.c_str());
  ImGui::BulletText("Bridge telemetry: %s", g_bridge_runtime.log_found ? "available" : "waiting");
  ImGui::BulletText("NVIDIA Optical Flow observed: %s", g_bridge_runtime.optical_flow_seen ? "yes" : "not confirmed yet");
  ImGui::BulletText("Depth binding observed: %s", g_bridge_runtime.depth_seen ? "yes" : "not confirmed yet");
  ImGui::BulletText("Delivered frames confirmed: %s", g_bridge_runtime.delivery_confirmed ? "yes" : "not yet");
  if (!g_bridge_runtime.blocker.empty())
    ImGui::TextWrapped("Latest blocking marker: %s", g_bridge_runtime.blocker.c_str());

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
  EnsureTemporalPolicy();

  // Validate/hide the RenoDX backend page and discover its live controls before
  // drawing SECRET EMKO. This does not patch unknown RenoDX builds.
  g_live.tick(runtime);

  DrawHeader();

  if (ImGui::BeginTabBar("##se_tabs")) {
    if (ImGui::BeginTabItem("Graphics")) { DrawGamingGraphics(); ImGui::EndTabItem(); }
    if (ImGui::BeginTabItem("Frame Gen")) { DrawFrameGeneration(); ImGui::EndTabItem(); }
    if (ImGui::BeginTabItem("Advanced")) {
      if (ImGui::CollapsingHeader("Motion / Frame Gen policy", ImGuiTreeNodeFlags_DefaultOpen)) DrawMotionPolicy();
      if (ImGui::CollapsingHeader("Neural provider")) DrawNeural();
      if (ImGui::CollapsingHeader("Quality")) DrawQuality();
      if (ImGui::CollapsingHeader("Compatibility bridge")) DrawBridge();
      if (ImGui::CollapsingHeader("Legacy profiles")) DrawProfiles();
      if (ImGui::CollapsingHeader("About")) DrawAbout();
      ImGui::EndTabItem();
    }
    if (ImGui::BeginTabItem("Status")) { DrawDiagnostics(); ImGui::EndTabItem(); }
    ImGui::EndTabBar();
  }

  // Apply changes queued by the SECRET EMKO widgets in this same frame and ask
  // RenoDX's own callback for an immediate readback confirmation.
  if (RenoDxLoaded()) {
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
  EnsureTemporalPolicy();

  g_live.tick(runtime);

  if (!g_policy_synced) {
    SetBackendLoadPolicy(g_nr.enabled != 0);
    if (g_nr.enabled == 0)
      WriteBridgeConfig(true);
    g_policy_synced = true;
  }
}

void Attach() {
  // Keep DllMain loader-lock work minimal. Config/file I/O is deferred to the
  // first ReShade overlay frame in OnOverlayFrame/DrawOverlay.
  g_loaded = false;
  reshade::register_event<reshade::addon_event::reshade_overlay>(OnOverlayFrame);
  reshade::register_overlay(kProduct, DrawOverlay);
}

void Detach() {
  // Do not re-register the provider page during process teardown. ReShade is
  // dismantling its own overlay at this point, and the next process start will
  // reconstruct the full add-on registry from scratch.
  reshade::unregister_event<reshade::addon_event::reshade_overlay>(OnOverlayFrame);
  reshade::unregister_overlay(kProduct, DrawOverlay);
}

} // namespace

extern "C" __declspec(dllexport) constexpr const char* NAME = "SECRET EMKO Neural Graphics";
extern "C" __declspec(dllexport) constexpr const char* DESCRIPTION =
    "FiveM GTA V Legacy neural graphics control surface for RenoDX / ReShade";

extern "C" __declspec(dllexport) bool AddonInit(HMODULE addon_module, HMODULE reshade_module) {
  g_module = addon_module;
  g_dir = ModuleDirectory(addon_module);
  if (!reshade::register_addon(addon_module, reshade_module)) return false;
  PrepareSyntheticSrRuntime();
  RefreshBridgeRuntimeSnapshot(true);
  Attach();
  return true;
}

extern "C" __declspec(dllexport) void AddonUninit(HMODULE addon_module, HMODULE) {
  Detach();
  reshade::unregister_addon(addon_module);
}

BOOL APIENTRY DllMain(HMODULE, DWORD, LPVOID) {
  // Keep DllMain side-effect free. The adapter uses thread-local state, so
  // thread notifications are deliberately left at the Windows default.
  return TRUE;
}
