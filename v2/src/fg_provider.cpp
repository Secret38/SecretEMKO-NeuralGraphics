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

#include <atomic>
#include <cstdio>
#include <cstdint>
#include <cstring>

#include <include/reshade.hpp>

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
  }
}

void Attach() {
  g_flags.store(kInitialized | kDiscoveryOnly, std::memory_order_relaxed);
  reshade::register_event<reshade::addon_event::bind_render_targets_and_depth_stencil>(
      OnBindRenderTargetsAndDepthStencil);
  reshade::register_event<reshade::addon_event::present>(OnPresent);
}

void Detach() {
  reshade::unregister_event<reshade::addon_event::bind_render_targets_and_depth_stencil>(
      OnBindRenderTargetsAndDepthStencil);
  reshade::unregister_event<reshade::addon_event::present>(OnPresent);
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
