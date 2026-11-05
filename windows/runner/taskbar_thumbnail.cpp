#include "taskbar_thumbnail.h"

#include <dwmapi.h>
#include <flutter/standard_method_codec.h>

#include <algorithm>
#include <cstdint>
#include <vector>

namespace {

enum Button { kButtonPrevious, kButtonToggle, kButtonNext, kButtonCount };

constexpr wchar_t kTabClassName[] = L"KANADE_TASKBAR_TAB";

using flutter::EncodableList;
using flutter::EncodableMap;
using flutter::EncodableValue;

const EncodableValue* Find(const EncodableMap& map, const char* key) {
  auto it = map.find(EncodableValue(key));
  return it == map.end() ? nullptr : &it->second;
}

std::wstring Utf16FromUtf8(const std::string& utf8) {
  if (utf8.empty()) {
    return std::wstring();
  }
  const int length = MultiByteToWideChar(
      CP_UTF8, 0, utf8.data(), static_cast<int>(utf8.size()), nullptr, 0);
  std::wstring utf16(length, L'\0');
  MultiByteToWideChar(CP_UTF8, 0, utf8.data(), static_cast<int>(utf8.size()),
                      utf16.data(), length);
  return utf16;
}

// Top-down 32-bit bitmap; bits points at the BGRA pixels.
HBITMAP CreateDib(int width, int height, uint32_t** bits) {
  BITMAPINFO info = {};
  info.bmiHeader.biSize = sizeof(BITMAPINFOHEADER);
  info.bmiHeader.biWidth = width;
  info.bmiHeader.biHeight = -height;
  info.bmiHeader.biPlanes = 1;
  info.bmiHeader.biBitCount = 32;
  info.bmiHeader.biCompression = BI_RGB;
  void* pixels = nullptr;
  HBITMAP bitmap =
      CreateDIBSection(nullptr, &info, DIB_RGB_COLORS, &pixels, nullptr, 0);
  *bits = static_cast<uint32_t*>(pixels);
  return bitmap;
}

// Dart sends RGBA bytes; Windows bitmaps are BGRA.
HBITMAP CreateDibFromRgba(const std::vector<uint8_t>& rgba, int width,
                          int height) {
  if (width <= 0 || height <= 0 ||
      rgba.size() != static_cast<size_t>(width) * height * 4) {
    return nullptr;
  }
  uint32_t* bits = nullptr;
  HBITMAP bitmap = CreateDib(width, height, &bits);
  if (!bitmap) {
    return nullptr;
  }
  for (size_t i = 0; i < static_cast<size_t>(width) * height; ++i) {
    const uint8_t* p = &rgba[i * 4];
    bits[i] = (uint32_t(p[3]) << 24) | (uint32_t(p[0]) << 16) |
              (uint32_t(p[1]) << 8) | p[2];
  }
  return bitmap;
}

// GDI scaling leaves alpha at 0, which DWM treats as transparent.
void MakeOpaque(uint32_t* bits, size_t count) {
  for (size_t i = 0; i < count; ++i) {
    bits[i] |= 0xFF000000;
  }
}

HICON CreateIconFromRgba(const std::vector<uint8_t>& rgba, int size) {
  HBITMAP color = CreateDibFromRgba(rgba, size, size);
  if (!color) {
    return nullptr;
  }
  // A 32-bit icon uses the color bitmap alpha, so the mask stays all zero.
  std::vector<uint8_t> mask_bits(((size + 15) / 16) * 2 * size, 0);
  HBITMAP mask = CreateBitmap(size, size, 1, 1, mask_bits.data());
  ICONINFO info = {TRUE, 0, 0, mask, color};
  HICON icon = CreateIconIndirect(&info);
  DeleteObject(mask);
  DeleteObject(color);
  return icon;
}

bool SystemUsesLightTheme() {
  DWORD value = 0;
  DWORD size = sizeof(value);
  return RegGetValue(
             HKEY_CURRENT_USER,
             L"Software\\Microsoft\\Windows\\CurrentVersion\\Themes\\Personalize",
             L"SystemUsesLightTheme", RRF_RT_REG_DWORD, nullptr, &value,
             &size) == ERROR_SUCCESS &&
         value != 0;
}

}  // namespace

TaskbarThumbnail::TaskbarThumbnail(HWND window,
                                   flutter::BinaryMessenger* messenger)
    : window_(window),
      taskbar_created_message_(RegisterWindowMessage(L"TaskbarButtonCreated")) {
  channel_ = std::make_unique<flutter::MethodChannel<EncodableValue>>(
      messenger, "kanade/taskbar",
      &flutter::StandardMethodCodec::GetInstance());
  channel_->SetMethodCallHandler([this](const auto& call, auto result) {
    HandleMethodCall(call, std::move(result));
  });
}

TaskbarThumbnail::~TaskbarThumbnail() {
  channel_->SetMethodCallHandler(nullptr);
  DestroyTab();
  for (HICON icon : icons_) {
    if (icon) {
      DestroyIcon(icon);
    }
  }
  if (cover_) {
    DeleteObject(cover_);
  }
}

std::optional<LRESULT> TaskbarThumbnail::HandleMessage(UINT message,
                                                       WPARAM wparam,
                                                       LPARAM lparam) {
  if (message == taskbar_created_message_) {
    // Sent again when Explorer restarts, which drops registered tabs.
    if (!taskbar_ &&
        (FAILED(CoCreateInstance(CLSID_TaskbarList, nullptr,
                                 CLSCTX_INPROC_SERVER,
                                 IID_PPV_ARGS(&taskbar_))) ||
         FAILED(taskbar_->HrInit()))) {
      taskbar_ = nullptr;
      return std::nullopt;
    }
    DestroyTab();
    UpdateTab();
    return std::nullopt;
  }

  switch (message) {
    case WM_SETTINGCHANGE:
      if (lparam &&
          wcscmp(reinterpret_cast<const wchar_t*>(lparam),
                 L"ImmersiveColorSet") == 0) {
        channel_->InvokeMethod("iconSpecChanged", nullptr);
      }
      break;
    case WM_DPICHANGED:
      channel_->InvokeMethod("iconSpecChanged", nullptr);
      break;
  }
  return std::nullopt;
}

LRESULT CALLBACK TaskbarThumbnail::TabProc(HWND tab, UINT message,
                                           WPARAM wparam, LPARAM lparam) {
  if (message == WM_NCCREATE) {
    auto create = reinterpret_cast<CREATESTRUCT*>(lparam);
    SetWindowLongPtr(tab, GWLP_USERDATA,
                     reinterpret_cast<LONG_PTR>(create->lpCreateParams));
  } else if (auto self = reinterpret_cast<TaskbarThumbnail*>(
                 GetWindowLongPtr(tab, GWLP_USERDATA))) {
    return self->HandleTabMessage(tab, message, wparam, lparam);
  }
  return DefWindowProc(tab, message, wparam, lparam);
}

LRESULT TaskbarThumbnail::HandleTabMessage(HWND tab, UINT message,
                                           WPARAM wparam, LPARAM lparam) {
  switch (message) {
    case WM_DWMSENDICONICTHUMBNAIL:
      SendThumbnail(HIWORD(lparam), LOWORD(lparam));
      return 0;
    case WM_COMMAND:
      if (HIWORD(wparam) == THBN_CLICKED) {
        static const char* const kNames[kButtonCount] = {"previous", "toggle",
                                                         "next"};
        const WORD id = LOWORD(wparam);
        if (id < kButtonCount) {
          channel_->InvokeMethod("button",
                                 std::make_unique<EncodableValue>(kNames[id]));
        }
        return 0;
      }
      break;
    case WM_ACTIVATE:
      // The taskbar activates the tab when its thumbnail is clicked.
      if (LOWORD(wparam) != WA_INACTIVE) {
        if (IsIconic(window_)) {
          ShowWindow(window_, SW_RESTORE);
        }
        SetForegroundWindow(window_);
      }
      return 0;
    case WM_SYSCOMMAND:
      // Minimize / restore / close from the taskbar belong to the main window.
      PostMessage(window_, WM_SYSCOMMAND, wparam, lparam);
      return 0;
    case WM_CLOSE:
      PostMessage(window_, WM_CLOSE, 0, 0);
      return 0;
  }
  return DefWindowProc(tab, message, wparam, lparam);
}

void TaskbarThumbnail::HandleMethodCall(
    const flutter::MethodCall<EncodableValue>& call,
    std::unique_ptr<flutter::MethodResult<EncodableValue>> result) {
  const auto* args = std::get_if<EncodableMap>(call.arguments());
  const std::string& method = call.method_name();

  if (method == "iconSpec") {
    const int size =
        GetSystemMetricsForDpi(SM_CXSMICON, GetDpiForWindow(window_));
    result->Success(EncodableValue(EncodableMap{
        {EncodableValue("size"), EncodableValue(size)},
        {EncodableValue("light"), EncodableValue(SystemUsesLightTheme())},
    }));
    return;
  }

  if (method == "setIcons" && args) {
    static const char* const kKeys[kIconCount] = {"previous", "play", "pause",
                                                  "next"};
    const int size = std::get<int>(*Find(*args, "size"));
    HICON old[kIconCount];
    std::copy(std::begin(icons_), std::end(icons_), old);
    for (int i = 0; i < kIconCount; ++i) {
      icons_[i] = CreateIconFromRgba(
          std::get<std::vector<uint8_t>>(*Find(*args, kKeys[i])), size);
    }
    // Hand the new icons to the taskbar before destroying the old ones.
    UpdateButtons();
    for (HICON icon : old) {
      if (icon) {
        DestroyIcon(icon);
      }
    }
    result->Success();
    return;
  }

  if (method == "update" && args) {
    visible_ = std::get<bool>(*Find(*args, "visible"));
    playing_ = std::get<bool>(*Find(*args, "playing"));
    const auto& tips = std::get<EncodableList>(*Find(*args, "tips"));
    for (int i = 0; i < kIconCount && i < static_cast<int>(tips.size());
         ++i) {
      tips_[i] = Utf16FromUtf8(std::get<std::string>(tips[i]));
    }
    title_ = Utf16FromUtf8(std::get<std::string>(*Find(*args, "title")));
    SetWindowText(window_, title_.c_str());
    UpdateTab();
    UpdateButtons();
    result->Success();
    return;
  }

  if (method == "setCover") {
    if (cover_) {
      DeleteObject(cover_);
      cover_ = nullptr;
    }
    if (args) {
      cover_width_ = std::get<int>(*Find(*args, "width"));
      cover_height_ = std::get<int>(*Find(*args, "height"));
      cover_ = CreateDibFromRgba(
          std::get<std::vector<uint8_t>>(*Find(*args, "rgba")), cover_width_,
          cover_height_);
    }
    UpdateTab();
    if (tab_) {
      DwmInvalidateIconicBitmaps(tab_);
    }
    result->Success();
    return;
  }

  result->NotImplemented();
}

void TaskbarThumbnail::UpdateTab() {
  const bool want = taskbar_ && visible_ && cover_;
  if (want && !tab_) {
    CreateTab();
  } else if (!want && tab_) {
    DestroyTab();
  }
  if (tab_) {
    SetWindowText(tab_, title_.c_str());
  }
}

void TaskbarThumbnail::CreateTab() {
  HINSTANCE instance = GetModuleHandle(nullptr);
  static bool registered = false;
  if (!registered) {
    WNDCLASSEX window_class = {sizeof(WNDCLASSEX)};
    window_class.lpfnWndProc = TabProc;
    window_class.hInstance = instance;
    window_class.lpszClassName = kTabClassName;
    registered = RegisterClassEx(&window_class) != 0;
  }
  // Never shown: it only stands in for the main window on the taskbar.
  tab_ = CreateWindowEx(WS_EX_TOOLWINDOW | WS_EX_NOACTIVATE, kTabClassName,
                        title_.c_str(), WS_POPUP | WS_CAPTION | WS_SYSMENU,
                        -32000, -32000, 0, 0, nullptr, nullptr, instance, this);
  if (!tab_) {
    return;
  }
  const BOOL enable = TRUE;
  DwmSetWindowAttribute(tab_, DWMWA_FORCE_ICONIC_REPRESENTATION, &enable,
                        sizeof(enable));
  DwmSetWindowAttribute(tab_, DWMWA_HAS_ICONIC_BITMAP, &enable,
                        sizeof(enable));
  // The thumbnail title shows the tab's icon, so borrow the app icon.
  const LPARAM icon = GetClassLongPtr(window_, GCLP_HICON);
  SendMessage(tab_, WM_SETICON, ICON_SMALL, icon);
  SendMessage(tab_, WM_SETICON, ICON_BIG, icon);

  taskbar_->RegisterTab(tab_, window_);
  taskbar_->SetTabOrder(tab_, nullptr);
  taskbar_->SetTabActive(tab_, window_, 0);
  // Peek shows the live main window instead of a static bitmap from the tab.
  taskbar_->SetTabProperties(tab_, STPF_USEAPPPEEKALWAYS);
  buttons_added_ = false;
  UpdateButtons();
}

void TaskbarThumbnail::DestroyTab() {
  if (!tab_) {
    return;
  }
  if (taskbar_) {
    taskbar_->UnregisterTab(tab_);
  }
  DestroyWindow(tab_);
  tab_ = nullptr;
  buttons_added_ = false;
}

void TaskbarThumbnail::UpdateButtons() {
  if (!tab_) {
    return;
  }
  const bool ready = icons_[kPrevious] && icons_[kPlay] && icons_[kPause] &&
                     icons_[kNext];
  const Icon icons[kButtonCount] = {kPrevious, playing_ ? kPause : kPlay,
                                    kNext};
  THUMBBUTTON buttons[kButtonCount] = {};
  for (int i = 0; i < kButtonCount; ++i) {
    THUMBBUTTON& b = buttons[i];
    b.dwMask = THB_ICON | THB_TOOLTIP | THB_FLAGS;
    b.iId = i;
    b.hIcon = icons_[icons[i]];
    wcsncpy_s(b.szTip, tips_[icons[i]].c_str(), _TRUNCATE);
    // Buttons can only be added once, so hide them until the icons arrive.
    b.dwFlags = ready ? THBF_ENABLED : THBF_HIDDEN;
  }
  if (buttons_added_) {
    taskbar_->ThumbBarUpdateButtons(tab_, kButtonCount, buttons);
  } else {
    buttons_added_ =
        SUCCEEDED(taskbar_->ThumbBarAddButtons(tab_, kButtonCount, buttons));
  }
}

void TaskbarThumbnail::SendThumbnail(int max_width, int max_height) {
  const int side = std::min(max_width, max_height);
  if (!cover_ || side <= 0) {
    return;
  }
  uint32_t* bits = nullptr;
  HBITMAP thumbnail = CreateDib(side, side, &bits);
  if (!thumbnail) {
    return;
  }
  HDC source = CreateCompatibleDC(nullptr);
  HDC target = CreateCompatibleDC(nullptr);
  HGDIOBJ old_source = SelectObject(source, cover_);
  HGDIOBJ old_target = SelectObject(target, thumbnail);
  SetStretchBltMode(target, HALFTONE);
  SetBrushOrgEx(target, 0, 0, nullptr);
  // Center-crop covers that are not square.
  const int crop = std::min(cover_width_, cover_height_);
  StretchBlt(target, 0, 0, side, side, source, (cover_width_ - crop) / 2,
             (cover_height_ - crop) / 2, crop, crop, SRCCOPY);
  SelectObject(source, old_source);
  SelectObject(target, old_target);
  DeleteDC(source);
  DeleteDC(target);
  MakeOpaque(bits, static_cast<size_t>(side) * side);
  DwmSetIconicThumbnail(tab_, thumbnail, 0);
  DeleteObject(thumbnail);
}
