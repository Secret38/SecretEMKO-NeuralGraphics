/*
 * SECRET EMKO RenoDX live adapter
 *
 * Derived from the MIT-licensed RenoDX v4.7 UI bridge used by DLSS 5 Swapper
 * (Copyright (c) 2026 Rakan Alkhaldi).
 *
 * This is deliberately NOT a generic memory patcher and NOT a public RenoDX API.
 * It only activates for the exact verified RenoDX DLSS5 v4.70 binary:
 *   size   1,732,608 bytes
 *   SHA256 D5ADF82EB44B065F4C590AC91FE824BAB07AFEA0EB9F994BDE936710C8593952
 *
 * The adapter temporarily replaces RenoDX's private ImGui dispatch table only
 * for one synchronous invocation of RenoDX's own registered settings callback.
 * It never keeps pointers to RenoDX setting variables and refuses unknown builds.
 */

#pragma once

#include <windows.h>
#include <wincrypt.h>

#include <algorithm>
#include <array>
#include <cmath>
#include <cstring>
#include <cstdint>
#include <mutex>
#include <string>
#include <vector>

#pragma comment(lib, "advapi32.lib")

namespace secretemko_live {

struct Desired {
  int enabled = 1;
  int enable_upscaling = 0;
  int preset = 0;
  int style = 1;
  float intensity = 1.f;
  float global_tone = 1.f;
  float local_tone = 1.f;
  float local_structure = 1.f;
  float skin_structure = 1.f;
  int auto_mask = 1;
  int ui_correction = 1;
  float diffuse_white_nits = 203.f;
  int depth_mode = 0;
  float mv_scale_x = 1.f;
  float mv_scale_y = 1.f;
};

enum class Kind : uint32_t {
  Float = 0,
  Bool = 1,
  Combo = 4,
};

struct Field {
  const char* label;
  Kind kind;
  float requested = 0.f;
  float current = 0.f;
  float min = 0.f;
  float max = 1.f;
  bool seen = false;
  bool pending = false;
  bool confirming = false;
  bool confirmed = false;
};

class RenoDxLiveAdapter {
 public:
  void set_baseline(const Desired& desired) {
    const auto values = values_from(desired);
    for (size_t i = 0; i < fields_.size(); ++i) {
      last_desired_[i] = values[i];
      fields_[i].pending = false;
      fields_[i].confirming = false;
      fields_[i].confirmed = false;
    }
    have_baseline_ = true;
  }

  void synchronize_all(const Desired& desired) {
    set_baseline(desired);
    const auto values = values_from(desired);
    for (size_t i = 0; i < fields_.size(); ++i) {
      fields_[i].requested = values[i];
      fields_[i].pending = true;
      fields_[i].confirming = false;
      fields_[i].confirmed = false;
    }
    ++pending_generation_;
  }

  void queue_diff(const Desired& desired) {
    const auto values = values_from(desired);
    if (!have_baseline_) {
      set_baseline(desired);
      for (size_t i = 0; i < fields_.size(); ++i) {
        fields_[i].requested = values[i];
        fields_[i].pending = true;
      }
      pending_generation_++;
      return;
    }

    bool any = false;
    for (size_t i = 0; i < fields_.size(); ++i) {
      const float old = last_desired_[i];
      const float next = values[i];
      const bool changed = fields_[i].kind == Kind::Float
          ? std::fabs(old - next) > 0.0001f
          : old != next;
      if (!changed) continue;

      last_desired_[i] = next;
      fields_[i].requested = next;
      fields_[i].pending = true;
      fields_[i].confirming = false;
      fields_[i].confirmed = false;
      any = true;
    }
    if (any) pending_generation_++;
  }

  bool tick(reshade::api::effect_runtime* runtime) {
    if (!runtime) return false;
    if (!prepare_module()) return false;

    // Discover controls once even before a change so the SECRET EMKO UI knows
    // whether the supplied binary can be controlled live.
    const bool need_call = !active_ || has_pending() || has_confirming();
    if (!need_call) return true;

    const bool first = invoke(runtime);
    if (!first) return false;

    // RenoDX handles the ImGui "changed" return value after the widget call.
    // A second synchronous hidden invocation reads back the value from RenoDX's
    // own state in the same frame and gives us a real confirmation.
    if (has_confirming()) {
      if (!invoke(runtime)) return false;
    }

    return active_;
  }

  bool available() const { return valid_ && active_; }
  bool binary_valid() const { return valid_; }
  bool overlay_hidden() const { return overlay_hidden_; }
  bool has_pending() const {
    for (const auto& f : fields_) if (f.pending) return true;
    return false;
  }
  bool has_confirming() const {
    for (const auto& f : fields_) if (f.confirming) return true;
    return false;
  }
  bool last_apply_confirmed() const {
    return last_applied_generation_ == pending_generation_ &&
           !has_pending() && !has_confirming();
  }
  const std::string& reason() const { return reason_; }

  void shutdown() {
    restore_overlay();
    active_ = false;
    valid_ = false;
    module_ = nullptr;
    checked_module_ = nullptr;
    original_ = nullptr;
    reason_ = "RenoDX live control shut down";
  }

 private:
  static constexpr DWORD kRequiredSize = 1732608;
  static constexpr uintptr_t kImGuiSlotOffset = 0x196ca0;
  static constexpr uintptr_t kOverlayCallbackOffset = 0x2a600;
  static constexpr uintptr_t kInitFingerprintOffset = 0x23ff8;
  static constexpr uintptr_t kCallbackFingerprintOffset = 0x2607c;

  std::array<Field, 15> fields_ = {{
      {"Structure Intensity", Kind::Float},
      {"Global Tone Intensity", Kind::Float},
      {"Enable DLSS Neural Rendering", Kind::Bool},
      {"Automatic / Character Mask", Kind::Bool},
      {"Character/Skin Structure", Kind::Float},
      {"Overall Intensity", Kind::Float},
      {"Local Tone Intensity", Kind::Float},
      {"Diffuse White (nits)", Kind::Float},
      {"Motion Scale X Multiplier", Kind::Float},
      {"Motion Scale Y Multiplier", Kind::Float},
      {"NR UI Correction", Kind::Bool},
      {"Enable Upscaling (WIP)", Kind::Bool},
      {"NR Preset", Kind::Combo},
      {"NR Style", Kind::Combo},
      {"Depth Convention", Kind::Combo},
  }};
  std::array<float, 15> last_desired_ = {};
  std::array<bool, 15> touched_ = {};

  HMODULE module_ = nullptr;
  HMODULE checked_module_ = nullptr;
  const imgui_function_table* original_ = nullptr;
  bool valid_ = false;
  bool active_ = false;
  bool overlay_hidden_ = false;
  bool apply_failed_ = false;
  bool have_baseline_ = false;
  uint64_t pending_generation_ = 0;
  uint64_t last_applied_generation_ = 0;
  std::string reason_ = "RenoDX live control not initialized";

  static inline thread_local RenoDxLiveAdapter* current_ = nullptr;
  static inline std::mutex invocation_mutex_;

  static std::array<float, 15> values_from(const Desired& d) {
    return {{
        d.local_structure,
        d.global_tone,
        static_cast<float>(d.enabled),
        static_cast<float>(d.auto_mask),
        d.skin_structure,
        d.intensity,
        d.local_tone,
        d.diffuse_white_nits,
        d.mv_scale_x,
        d.mv_scale_y,
        static_cast<float>(d.ui_correction),
        static_cast<float>(d.enable_upscaling),
        static_cast<float>(d.preset),
        static_cast<float>(d.style),
        static_cast<float>(d.depth_mode),
    }};
  }

  bool hash_matches(HMODULE module) {
    wchar_t filename[32768] = {};
    if (!GetModuleFileNameW(module, filename, static_cast<DWORD>(_countof(filename))))
      return false;

    HANDLE file = CreateFileW(
        filename, GENERIC_READ,
        FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE,
        nullptr, OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, nullptr);
    if (file == INVALID_HANDLE_VALUE) return false;

    const DWORD size = GetFileSize(file, nullptr);
    if (size != kRequiredSize) {
      CloseHandle(file);
      return false;
    }

    std::vector<unsigned char> data(size);
    DWORD read = 0;
    const bool read_ok = ReadFile(file, data.data(), size, &read, nullptr) && read == size;
    CloseHandle(file);
    if (!read_ok) return false;

    HCRYPTPROV provider = 0;
    HCRYPTHASH hash = 0;
    BYTE digest[32] = {};
    DWORD digest_size = sizeof(digest);
    bool matches = false;

    if (CryptAcquireContextW(&provider, nullptr, nullptr, PROV_RSA_AES, CRYPT_VERIFYCONTEXT) &&
        CryptCreateHash(provider, CALG_SHA_256, 0, 0, &hash) &&
        CryptHashData(hash, data.data(), size, 0) &&
        CryptGetHashParam(hash, HP_HASHVAL, digest, &digest_size, 0)) {
      constexpr unsigned char expected[32] = {
          0xD5,0xAD,0xF8,0x2E,0xB4,0x4B,0x06,0x5F,
          0x4C,0x59,0x0A,0xC9,0x1F,0xE8,0x24,0xBA,
          0xB0,0x7A,0xFE,0xA0,0xEB,0x9F,0x99,0x4B,
          0xDE,0x93,0x67,0x10,0xC8,0x59,0x39,0x52
      };
      matches = digest_size == sizeof(expected) &&
                std::memcmp(digest, expected, sizeof(expected)) == 0;
    }

    if (hash) CryptDestroyHash(hash);
    if (provider) CryptReleaseContext(provider, 0);
    return matches;
  }

  bool fingerprints_match(unsigned char* base) {
    constexpr unsigned char init[] = {
        0xB9,0x32,0x4B,0x00,0x00,0xFF,0xD0,
        0x48,0x89,0x05,0x9A,0x2C,0x17,0x00
    };
    constexpr unsigned char callback[] = {
        0x48,0x8D,0x15,0x7D,0x45,0x00,0x00,0xFF,0xD0
    };
    return std::memcmp(base + kInitFingerprintOffset, init, sizeof(init)) == 0 &&
           std::memcmp(base + kCallbackFingerprintOffset, callback, sizeof(callback)) == 0;
  }

  bool prepare_module() {
    HMODULE module = GetModuleHandleW(L"renodx-dlss5.addon64");
    if (!module) {
      module_ = nullptr;
      active_ = false;
      valid_ = false;
      reason_ = "RenoDX backend is not loaded in this session";
      return false;
    }

    module_ = module;
    if (checked_module_ != module) {
      checked_module_ = module;
      valid_ = hash_matches(module);
      active_ = false;
      overlay_hidden_ = false;
      reason_ = valid_
          ? "Verified RenoDX v4.70; discovering live controls"
          : "RenoDX binary is not the verified v4.70 build; live adapter refused";
    }

    if (!valid_) return false;

    auto* base = reinterpret_cast<unsigned char*>(module_);
    if (!fingerprints_match(base)) {
      valid_ = false;
      active_ = false;
      reason_ = "RenoDX v4.70 code fingerprint mismatch; live adapter refused";
      return false;
    }

    original_ = imgui_function_table_instance();
    auto** slot = reinterpret_cast<const imgui_function_table**>(base + kImGuiSlotOffset);
    if (*slot != original_) {
      restore_overlay();
      active_ = false;
      reason_ = "RenoDX ImGui dispatch is already replaced by another component; original RenoDX UI kept available";
      return false;
    }

    return true;
  }

  void hide_overlay() {
    if (overlay_hidden_ || !module_ || !valid_) return;
    auto* base = reinterpret_cast<unsigned char*>(module_);
    auto callback = reinterpret_cast<void(*)(reshade::api::effect_runtime*)>(
        base + kOverlayCallbackOffset);
    reshade::unregister_overlay("RenoDX-DLSSNR", callback);
    overlay_hidden_ = true;
  }

  void restore_overlay() {
    if (!overlay_hidden_ || !module_) return;
    auto* base = reinterpret_cast<unsigned char*>(module_);
    auto callback = reinterpret_cast<void(*)(reshade::api::effect_runtime*)>(
        base + kOverlayCallbackOffset);
    reshade::register_overlay("RenoDX-DLSSNR", callback);
    overlay_hidden_ = false;
  }

  bool visit(const char* label, Kind kind, float& value, float lo, float hi) {
    for (size_t i = 0; i < fields_.size(); ++i) {
      auto& f = fields_[i];
      if (f.kind != kind || std::strcmp(f.label, label) != 0) continue;

      if (!std::isfinite(value) || !std::isfinite(lo) || !std::isfinite(hi) || lo > hi)
        return false;

      f.seen = true;
      f.current = value;

      // Hidden/disabled provider controls must never be forced live. This keeps
      // SECRET EMKO aligned with RenoDX's own availability rules.
      if (disabled_depth_ != 0) {
        if (f.pending) {
          f.pending = false;
          f.confirming = false;
          f.confirmed = false;
          apply_failed_ = true;
          reason_ = std::string("RenoDX currently disables live control: ") + label;
        }
        return false;
      }
      f.min = lo;
      f.max = hi;

      if (f.confirming) {
        const bool same = kind == Kind::Float
            ? std::fabs(value - f.requested) < 0.0001f
            : value == f.requested;
        if (same) {
          f.confirmed = true;
          f.confirming = false;
        } else {
          f.confirming = false;
          f.confirmed = false;
          reason_ = std::string("RenoDX did not confirm live value for ") + label;
        }
      }

      if (!f.pending) return false;
      if (f.requested < lo || f.requested > hi) {
        f.pending = false;
        f.confirmed = false;
        apply_failed_ = true;
        reason_ = std::string("Requested value is outside RenoDX range for ") + label;
        return false;
      }

      f.pending = false;
      f.confirming = true;
      f.confirmed = false;
      touched_[i] = true;
      value = f.requested;
      return true;
    }
    return false;
  }

  static bool slider(
      const char* label, float* value, float lo, float hi,
      const char*, ImGuiSliderFlags) {
    if (!current_) return false;
    return current_->visit(label, Kind::Float, *value, lo, hi);
  }

  static bool checkbox(const char* label, bool* value) {
    if (!current_) return false;
    float v = *value ? 1.f : 0.f;
    if (!current_->visit(label, Kind::Bool, v, 0.f, 1.f)) return false;
    *value = v != 0.f;
    return true;
  }

  static bool combo(
      const char* label, int* value,
      const char* const[], int count, int) {
    if (!current_ || count <= 0) return false;
    float v = static_cast<float>(*value);
    if (!current_->visit(label, Kind::Combo, v, 0.f, static_cast<float>(count - 1)))
      return false;
    *value = static_cast<int>(v);
    return true;
  }

  static bool combo2(const char* label, int* value, const char* items, int height) {
    if (!current_ || !items) return false;
    int count = 0;
    const char* p = items;
    size_t used = 0;
    while (*p && count < 32 && used < 4096) {
      const size_t n = strnlen_s(p, 256);
      if (n >= 256) return false;
      ++count;
      p += n + 1;
      used += n + 1;
    }
    return combo(label, value, nullptr, count, height);
  }

  static bool button(const char*, const ImVec2&) { return false; }
  static bool small_button(const char*) { return false; }
  static bool invisible_button(const char*, const ImVec2&, ImGuiButtonFlags) { return false; }

  static void begin_disabled(bool disabled) {
    if (!current_ || !current_->original_) return;
    current_->disabled_stack_.push_back(disabled);
    if (disabled) ++current_->disabled_depth_;
    current_->original_->BeginDisabled(disabled);
  }

  static void end_disabled() {
    if (!current_ || !current_->original_) return;
    if (!current_->disabled_stack_.empty()) {
      if (current_->disabled_stack_.back() && current_->disabled_depth_ > 0)
        --current_->disabled_depth_;
      current_->disabled_stack_.pop_back();
    }
    current_->original_->EndDisabled();
  }

  bool invoke(reshade::api::effect_runtime* runtime) {
    if (!prepare_module()) return false;

    std::unique_lock<std::mutex> lock(invocation_mutex_, std::try_to_lock);
    if (!lock.owns_lock() || current_) {
      reason_ = "RenoDX live adapter is busy";
      return false;
    }

    auto* base = reinterpret_cast<unsigned char*>(module_);
    auto* atomic_slot = reinterpret_cast<void* volatile*>(base + kImGuiSlotOffset);
    auto** slot = reinterpret_cast<const imgui_function_table**>(base + kImGuiSlotOffset);
    if (*slot != original_) {
      reason_ = "RenoDX ImGui dispatch changed before live apply";
      active_ = false;
      return false;
    }

    imgui_function_table table = *original_;
    table.SliderFloat = slider;
    table.Checkbox = checkbox;
    table.Button = button;
    table.SmallButton = small_button;
    table.InvisibleButton = invisible_button;
    table.Combo = combo;
    table.Combo2 = combo2;
    table.BeginDisabled = begin_disabled;
    table.EndDisabled = end_disabled;

    for (auto& f : fields_) f.seen = false;
    apply_failed_ = false;
    disabled_stack_.clear();
    disabled_depth_ = 0;

    ImGui::SetNextWindowPos(ImVec2(-30000.f, -30000.f));
    ImGui::SetNextWindowSize(ImVec2(600.f, 1000.f));
    ImGui::Begin(
        "##SecretEMKO_RenoDXLiveAdapter",
        nullptr,
        ImGuiWindowFlags_NoInputs |
        ImGuiWindowFlags_NoSavedSettings |
        ImGuiWindowFlags_NoBackground);

    if (InterlockedCompareExchangePointer(
            atomic_slot, &table,
            const_cast<imgui_function_table*>(original_)) != original_) {
      ImGui::End();
      reason_ = "RenoDX ImGui dispatch raced with another component";
      active_ = false;
      return false;
    }

    struct Guard {
      void* volatile* slot;
      const imgui_function_table* original;
      imgui_function_table* temporary;
      ~Guard() {
        InterlockedCompareExchangePointer(
            slot,
            const_cast<imgui_function_table*>(original),
            temporary);
        current_ = nullptr;
      }
    } guard{atomic_slot, original_, &table};

    current_ = this;
    reinterpret_cast<void(*)(reshade::api::effect_runtime*)>(
        base + kOverlayCallbackOffset)(runtime);

    ImGui::End();

    active_ = fields_[0].seen && fields_[1].seen && fields_[2].seen;
    if (!active_) {
      restore_overlay();
      reason_ = "Verified RenoDX v4.70 loaded, but expected live controls were not found; original RenoDX UI kept available";
      return false;
    }

    // Only hide RenoDX's own page after one successful hidden discovery call.
    // This guarantees a visible fallback if the adapter cannot prove that it
    // understands the loaded provider in this session.
    hide_overlay();

    bool any_failed = false;
    for (auto& f : fields_) {
      if (f.pending && !f.seen) {
        f.pending = false;
        f.confirming = false;
        f.confirmed = false;
        any_failed = true;
        apply_failed_ = true;
      }
    }

    if (any_failed || apply_failed_) {
      if (reason_.empty() || reason_ == "Applying RenoDX live values")
        reason_ = "One or more RenoDX controls are unavailable in the current state";
      return false;
    }

    if (!has_pending() && !has_confirming()) {
      last_applied_generation_ = pending_generation_;
      reason_ = "Live RenoDX values confirmed by provider callback";
    } else {
      reason_ = "Applying RenoDX live values";
    }
    return true;
  }

  unsigned disabled_depth_ = 0;
  std::vector<bool> disabled_stack_;
};

} // namespace secretemko_live
