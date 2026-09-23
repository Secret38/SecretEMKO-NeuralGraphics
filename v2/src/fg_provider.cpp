/*
 * SECRET EMKO Native Frame Generation Provider - discovery foundation
 * Copyright (c) 2026 Secret EMKO
 * SPDX-License-Identifier: MIT
 *
 * This module intentionally does not enable DLSS-G yet. It establishes a small
 * ABI and observes GTA/FiveM render state so the main SECRET EMKO UI can fail
 * closed until native motion, HUD-less colour and UI inputs are actually ready.
 */

#define NOMINMAX
#include <windows.h>

#include <algorithm>
#include <atomic>
#include <cstdio>
#include <cstdint>
#include <cstring>
#include <mutex>
#include <unordered_map>
#include <utility>
#include <vector>

#include <include/reshade.hpp>
#include "../../utils/shader.hpp"

namespace {

constexpr uint32_t kAbi = 1;

enum StatusFlags : uint32_t {
  kInitialized       = 1u << 0,
  kD3D11Observed     = 1u << 1,
  kDepthObserved     = 1u << 2,
  kRenderTargetSeen  = 1u << 3,
  kNativeMotionReady = 1u << 4,
  kHudlessReady      = 1u << 5,
  kUiReady           = 1u << 6,
  kStreamlineReady   = 1u << 7,
  kFrameGenReady     = 1u << 8,
  kNrSharedReady     = 1u << 9,
  kDiscoveryOnly     = 1u << 10,
};

struct StatusV1 {
  uint32_t abi;
  uint32_t struct_size;
  uint64_t presented_frames;
  uint64_t depth_binds;
  uint64_t render_target_binds;
  uint32_t device_api;
  uint32_t flags;
};

std::atomic<uint64_t> g_frames{0};
std::atomic<uint64_t> g_depth_binds{0};
std::atomic<uint64_t> g_rt_binds{0};
std::atomic<uint32_t> g_api{0};
std::atomic<uint32_t> g_flags{kDiscoveryOnly};

struct ShaderHits {
  uint64_t depth = 0;
  uint64_t no_depth = 0;
};

std::mutex g_discovery_mutex;
std::unordered_map<reshade::api::command_list*, bool> g_depth_state;
std::unordered_map<uint32_t, ShaderHits> g_vs_hits;
std::unordered_map<uint32_t, ShaderHits> g_ps_hits;
constexpr size_t kMaxTrackedShaders = 8192;

void RecordShaderHit(std::unordered_map<uint32_t, ShaderHits>& table,
                     uint32_t hash,
                     bool depth_bound) {
  if (hash == 0) return;
  auto it = table.find(hash);
  if (it == table.end()) {
    if (table.size() >= kMaxTrackedShaders) return;
    it = table.emplace(hash, ShaderHits{}).first;
  }
  if (depth_bound) ++it->second.depth;
  else ++it->second.no_depth;
}

bool OnDrawCommon(reshade::api::command_list* cmd_list) {
  if (cmd_list == nullptr) return false;
  auto* state = renodx::utils::shader::GetCurrentState(cmd_list);
  if (state == nullptr) return false;

  const uint32_t vs = renodx::utils::shader::GetCurrentVertexShaderHash(state);
  const uint32_t ps = renodx::utils::shader::GetCurrentPixelShaderHash(state);

  std::scoped_lock lock(g_discovery_mutex);
  const auto depth_it = g_depth_state.find(cmd_list);
  const bool depth_bound = depth_it != g_depth_state.end() && depth_it->second;
  RecordShaderHit(g_vs_hits, vs, depth_bound);
  RecordShaderHit(g_ps_hits, ps, depth_bound);
  return false;
}

bool OnDraw(reshade::api::command_list* cmd_list,
            uint32_t, uint32_t, uint32_t, uint32_t) {
  return OnDrawCommon(cmd_list);
}

bool OnDrawIndexed(reshade::api::command_list* cmd_list,
                   uint32_t, uint32_t, uint32_t, int32_t, uint32_t) {
  return OnDrawCommon(cmd_list);
}

std::vector<std::pair<uint32_t, uint64_t>> TopShaderHits(
    const std::unordered_map<uint32_t, ShaderHits>& table,
    bool depth,
    size_t limit) {
  std::vector<std::pair<uint32_t, uint64_t>> out;
  out.reserve(table.size());
  for (const auto& [hash, hits] : table) {
    const uint64_t count = depth ? hits.depth : hits.no_depth;
    if (count != 0) out.emplace_back(hash, count);
  }
  const size_t keep = std::min(limit, out.size());
  std::partial_sort(out.begin(), out.begin() + keep, out.end(),
                    [](const auto& a, const auto& b) { return a.second > b.second; });
  out.resize(keep);
  return out;
}

void LogShaderDiscovery() {
  std::vector<std::pair<uint32_t, uint64_t>> scene_vs;
  std::vector<std::pair<uint32_t, uint64_t>> scene_ps;
  std::vector<std::pair<uint32_t, uint64_t>> no_depth_ps;
  {
    std::scoped_lock lock(g_discovery_mutex);
    scene_vs = TopShaderHits(g_vs_hits, true, 12);
    scene_ps = TopShaderHits(g_ps_hits, true, 12);
    no_depth_ps = TopShaderHits(g_ps_hits, false, 12);
  }

  auto log_group = [](const char* group,
                      const std::vector<std::pair<uint32_t, uint64_t>>& rows) {
    for (const auto& [hash, count] : rows) {
      char line[192];
      sprintf_s(line, "SECRET EMKO FGDISC %s shader=0x%08X draws=%llu",
                group, hash, static_cast<unsigned long long>(count));
      reshade::log::message(reshade::log::level::info, line);
    }
  };

  log_group("SCENE-VS", scene_vs);
  log_group("SCENE-PS", scene_ps);
  // No-depth pixel draws are only candidates: this bucket also contains
  // post-processing. Runtime captures are used to distinguish HUD/UI later.
  log_group("NO-DEPTH-PS", no_depth_ps);
}

void OnBindRenderTargetsAndDepthStencil(
    reshade::api::command_list* cmd_list,
    uint32_t count,
    const reshade::api::resource_view*,
    reshade::api::resource_view dsv) {
  if (cmd_list == nullptr || cmd_list->get_device() == nullptr) return;

  const auto api = cmd_list->get_device()->get_api();
  g_api.store(static_cast<uint32_t>(api), std::memory_order_relaxed);

  uint32_t flags = g_flags.load(std::memory_order_relaxed) | kInitialized | kDiscoveryOnly;
  if (api == reshade::api::device_api::d3d11)
    flags |= kD3D11Observed;

  if (count != 0) {
    g_rt_binds.fetch_add(1, std::memory_order_relaxed);
    flags |= kRenderTargetSeen;
  }
  if (dsv.handle != 0) {
    g_depth_binds.fetch_add(1, std::memory_order_relaxed);
    flags |= kDepthObserved;
  }
  {
    std::scoped_lock lock(g_discovery_mutex);
    g_depth_state[cmd_list] = dsv.handle != 0;
  }
  g_flags.store(flags, std::memory_order_relaxed);
}

void OnPresent(
    reshade::api::command_queue*,
    reshade::api::swapchain* swapchain,
    const reshade::api::rect*,
    const reshade::api::rect*,
    uint32_t,
    const reshade::api::rect*) {
  const uint64_t frame = g_frames.fetch_add(1, std::memory_order_relaxed) + 1;

  if (swapchain != nullptr && swapchain->get_device() != nullptr) {
    const auto api = swapchain->get_device()->get_api();
    g_api.store(static_cast<uint32_t>(api), std::memory_order_relaxed);
    uint32_t flags = g_flags.load(std::memory_order_relaxed) | kInitialized | kDiscoveryOnly;
    if (api == reshade::api::device_api::d3d11)
      flags |= kD3D11Observed;
    g_flags.store(flags, std::memory_order_relaxed);
  }

  if (frame == 1 || frame % 600 == 0) {
    char line[256];
    sprintf_s(line,
              "SECRET EMKO FG discovery: frames=%llu depth_binds=%llu rt_binds=%llu flags=0x%08X. Native motion/HUD inputs are not armed yet.",
              static_cast<unsigned long long>(frame),
              static_cast<unsigned long long>(g_depth_binds.load(std::memory_order_relaxed)),
              static_cast<unsigned long long>(g_rt_binds.load(std::memory_order_relaxed)),
              g_flags.load(std::memory_order_relaxed));
    reshade::log::message(reshade::log::level::info, line);
    if (frame >= 600) LogShaderDiscovery();
  }
}

void Attach() {
  g_flags.store(kInitialized | kDiscoveryOnly, std::memory_order_relaxed);

  // Reuse RenoDX's shader-state tracker so discovery records GTA's actual
  // vertex/pixel shader hashes. No shader bytecode is replaced in RC5.
  renodx::utils::shader::Use(DLL_PROCESS_ATTACH);
  reshade::register_event<reshade::addon_event::bind_render_targets_and_depth_stencil>(
      OnBindRenderTargetsAndDepthStencil);
  reshade::register_event<reshade::addon_event::draw>(OnDraw);
  reshade::register_event<reshade::addon_event::draw_indexed>(OnDrawIndexed);
  reshade::register_event<reshade::addon_event::present>(OnPresent);
}

void Detach() {
  reshade::unregister_event<reshade::addon_event::bind_render_targets_and_depth_stencil>(
      OnBindRenderTargetsAndDepthStencil);
  reshade::unregister_event<reshade::addon_event::draw>(OnDraw);
  reshade::unregister_event<reshade::addon_event::draw_indexed>(OnDrawIndexed);
  reshade::unregister_event<reshade::addon_event::present>(OnPresent);
  renodx::utils::shader::Use(DLL_PROCESS_DETACH);
}

}  // namespace

extern "C" __declspec(dllexport) constexpr const char* NAME =
    "SECRET EMKO Native Frame Generation Provider";
extern "C" __declspec(dllexport) constexpr const char* DESCRIPTION =
    "FiveM GTA V Legacy native motion/HUD discovery provider for SECRET EMKO";
extern "C" __declspec(dllexport) const uint32_t SECRET_EMKO_FG_ABI = kAbi;

extern "C" __declspec(dllexport) bool SecretEMKO_FG_GetStatus(StatusV1* out, uint32_t size) {
  if (out == nullptr || size < sizeof(StatusV1)) return false;
  StatusV1 status{};
  status.abi = kAbi;
  status.struct_size = sizeof(StatusV1);
  status.presented_frames = g_frames.load(std::memory_order_relaxed);
  status.depth_binds = g_depth_binds.load(std::memory_order_relaxed);
  status.render_target_binds = g_rt_binds.load(std::memory_order_relaxed);
  status.device_api = g_api.load(std::memory_order_relaxed);
  status.flags = g_flags.load(std::memory_order_relaxed);
  std::memcpy(out, &status, sizeof(status));
  return true;
}

extern "C" __declspec(dllexport) bool AddonInit(HMODULE addon_module, HMODULE reshade_module) {
  if (!reshade::register_addon(addon_module, reshade_module)) return false;
  Attach();
  return true;
}

extern "C" __declspec(dllexport) void AddonUninit(HMODULE addon_module, HMODULE) {
  Detach();
  reshade::unregister_addon(addon_module);
}
