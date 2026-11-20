#include "software_rendering.h"

#include <d3d11.h>
#include <flutter/standard_method_codec.h>
#include <windows.h>

#include <cstring>

namespace {

constexpr wchar_t kSettingsKey[] = L"Software\\com.kanade\\kanade";
constexpr wchar_t kSoftwareRenderingValue[] = L"SoftwareRendering";

decltype(&GetProcAddress) real_get_proc_address = nullptr;
PFN_D3D11_CREATE_DEVICE real_create_device = nullptr;

bool Enabled() {
  DWORD value = 0;
  DWORD size = sizeof(value);
  return RegGetValue(HKEY_CURRENT_USER, kSettingsKey, kSoftwareRenderingValue,
                     RRF_RT_REG_DWORD, nullptr, &value, &size) ==
             ERROR_SUCCESS &&
         value != 0;
}

HRESULT WINAPI CreateWarpDevice(IDXGIAdapter*, D3D_DRIVER_TYPE, HMODULE,
                                UINT flags, const D3D_FEATURE_LEVEL* levels,
                                UINT level_count, UINT sdk_version,
                                ID3D11Device** device,
                                D3D_FEATURE_LEVEL* level,
                                ID3D11DeviceContext** context) {
  return real_create_device(nullptr, D3D_DRIVER_TYPE_WARP, nullptr, flags,
                            levels, level_count, sdk_version, device, level,
                            context);
}

FARPROC WINAPI HookedGetProcAddress(HMODULE module, LPCSTR name) {
  FARPROC proc = real_get_proc_address(module, name);
  if (proc && !IS_INTRESOURCE(name) &&
      std::strcmp(name, "D3D11CreateDevice") == 0) {
    real_create_device = reinterpret_cast<PFN_D3D11_CREATE_DEVICE>(proc);
    return reinterpret_cast<FARPROC>(&CreateWarpDevice);
  }
  return proc;
}

// Redirects |module|'s import of dll!function to |hook|.
bool PatchImport(HMODULE module, const char* dll, const char* function,
                 void* hook, void** original) {
  auto* base = reinterpret_cast<BYTE*>(module);
  auto* dos = reinterpret_cast<IMAGE_DOS_HEADER*>(base);
  auto* nt = reinterpret_cast<IMAGE_NT_HEADERS*>(base + dos->e_lfanew);
  const IMAGE_DATA_DIRECTORY& imports =
      nt->OptionalHeader.DataDirectory[IMAGE_DIRECTORY_ENTRY_IMPORT];
  if (imports.VirtualAddress == 0) {
    return false;
  }
  for (auto* desc = reinterpret_cast<IMAGE_IMPORT_DESCRIPTOR*>(
           base + imports.VirtualAddress);
       desc->Name; ++desc) {
    if (_stricmp(reinterpret_cast<char*>(base + desc->Name), dll) != 0) {
      continue;
    }
    auto* names =
        reinterpret_cast<IMAGE_THUNK_DATA*>(base + desc->OriginalFirstThunk);
    auto* slots = reinterpret_cast<IMAGE_THUNK_DATA*>(base + desc->FirstThunk);
    for (; names->u1.AddressOfData; ++names, ++slots) {
      if (IMAGE_SNAP_BY_ORDINAL(names->u1.Ordinal)) {
        continue;
      }
      auto* by_name = reinterpret_cast<IMAGE_IMPORT_BY_NAME*>(
          base + names->u1.AddressOfData);
      if (std::strcmp(by_name->Name, function) != 0) {
        continue;
      }
      DWORD protect;
      VirtualProtect(&slots->u1.Function, sizeof(slots->u1.Function),
                     PAGE_READWRITE, &protect);
      *original = reinterpret_cast<void*>(slots->u1.Function);
      slots->u1.Function = reinterpret_cast<ULONG_PTR>(hook);
      VirtualProtect(&slots->u1.Function, sizeof(slots->u1.Function), protect,
                     &protect);
      return true;
    }
  }
  return false;
}

}  // namespace

void ApplySoftwareRendering() {
  if (!Enabled()) {
    return;
  }
  // The engine has no switch for this. Its ANGLE looks up D3D11CreateDevice
  // with GetProcAddress at runtime, so hand it one that always creates a WARP
  // (CPU) device. Flutter's own software renderer is far too slow here.
  HMODULE engine = GetModuleHandle(L"flutter_windows.dll");
  if (engine) {
    PatchImport(engine, "KERNEL32.dll", "GetProcAddress",
                reinterpret_cast<void*>(&HookedGetProcAddress),
                reinterpret_cast<void**>(&real_get_proc_address));
  }
}

std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>>
CreateSoftwareRenderingChannel(flutter::BinaryMessenger* messenger) {
  auto channel = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
      messenger, "kanade/rendering",
      &flutter::StandardMethodCodec::GetInstance());
  channel->SetMethodCallHandler([](const auto& call, auto result) {
    if (call.method_name() == "get") {
      result->Success(flutter::EncodableValue(Enabled()));
    } else if (call.method_name() == "set") {
      const auto* enabled = std::get_if<bool>(call.arguments());
      if (!enabled) {
        result->Error("bad_args");
        return;
      }
      const DWORD value = *enabled ? 1 : 0;
      RegSetKeyValue(HKEY_CURRENT_USER, kSettingsKey, kSoftwareRenderingValue,
                     REG_DWORD, &value, sizeof(value));
      result->Success();
    } else {
      result->NotImplemented();
    }
  });
  return channel;
}
