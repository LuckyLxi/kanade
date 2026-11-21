#include "desktop_integration.h"

#include <dwmapi.h>
#include <flutter/standard_method_codec.h>
#include <flutter_windows.h>
#include <shellapi.h>

#include <algorithm>
#include <cmath>
#include <functional>

// GDI+ headers want the min/max macros that NOMINMAX turns off.
namespace Gdiplus {
using std::max;
using std::min;
}  // namespace Gdiplus
#include <gdiplus.h>

#include "resource.h"
#include "utils.h"

namespace {

// Tray menu look, in logical pixels and the app's fixed dark palette.
constexpr float kMenuWidth = 240;
constexpr float kHeaderHeight = 60;
constexpr float kItemHeight = 36;
constexpr float kSeparatorHeight = 9;
constexpr float kCoverSize = 40;
constexpr COLORREF kMenuBackground = RGB(0x1A, 0x1A, 0x1A);
constexpr COLORREF kMenuText = RGB(0xF2, 0xF2, 0xF2);
constexpr COLORREF kMenuSecondary = RGB(0x8C, 0x8C, 0x8C);
constexpr COLORREF kMenuSeparator = RGB(0x2E, 0x2E, 0x2E);
constexpr COLORREF kMenuBorder = RGB(0x33, 0x33, 0x33);
constexpr COLORREF kMenuPlaceholder = RGB(0x2A, 0x2A, 0x2A);
constexpr COLORREF kAccent = RGB(0xD4, 0xFF, 0x3A);
constexpr COLORREF kOnAccent = RGB(0x00, 0x00, 0x00);

Gdiplus::Color GdiplusColor(COLORREF c) {
  return Gdiplus::Color(255, GetRValue(c), GetGValue(c), GetBValue(c));
}

void AddRoundRect(Gdiplus::GraphicsPath& path, Gdiplus::RectF r, float radius) {
  const float d = radius * 2;
  path.AddArc(r.X, r.Y, d, d, 180, 90);
  path.AddArc(r.GetRight() - d, r.Y, d, d, 270, 90);
  path.AddArc(r.GetRight() - d, r.GetBottom() - d, d, d, 0, 90);
  path.AddArc(r.X, r.GetBottom() - d, d, d, 90, 90);
  path.CloseFigure();
}

HFONT CreateMenuFont(const wchar_t* face, int height, int weight) {
  LOGFONT font = {};
  font.lfHeight = -height;
  font.lfWeight = weight;
  font.lfCharSet = DEFAULT_CHARSET;
  font.lfQuality = CLEARTYPE_QUALITY;
  wcsncpy_s(font.lfFaceName, face, _TRUNCATE);
  return CreateFontIndirect(&font);
}

void DrawMenuText(HDC dc, HFONT font, COLORREF color, const std::wstring& text,
                  RECT rect, UINT format) {
  HGDIOBJ old = SelectObject(dc, font);
  SetTextColor(dc, color);
  DrawText(dc, text.c_str(), static_cast<int>(text.size()), &rect,
           format | DT_SINGLELINE | DT_NOPREFIX);
  SelectObject(dc, old);
}

constexpr UINT kTrayMessage = WM_APP + 1;
constexpr UINT kTrayId = 1;

constexpr wchar_t kRunKey[] =
    L"Software\\Microsoft\\Windows\\CurrentVersion\\Run";
// Where Task Manager and Settings > Startup apps record turning an entry off.
constexpr wchar_t kStartupApprovedKey[] =
    L"Software\\Microsoft\\Windows\\CurrentVersion\\Explorer\\StartupApproved"
    L"\\Run";
constexpr wchar_t kRunValue[] = L"Kanade";

enum MenuCommand {
  kMenuToggle = 1,
  kMenuPrevious,
  kMenuNext,
  kMenuLyrics,
  kMenuLyricsUnlock,
  kMenuShow,
  kMenuExit
};

using flutter::EncodableList;
using flutter::EncodableMap;
using flutter::EncodableValue;

const EncodableValue* Find(const EncodableMap& map, const char* key) {
  auto it = map.find(EncodableValue(key));
  return it == map.end() ? nullptr : &it->second;
}

std::wstring Glyph(uint32_t code) {
  std::wstring glyph;
  if (code > 0xFFFF) {
    glyph += static_cast<wchar_t>(0xD800 + ((code - 0x10000) >> 10));
    glyph += static_cast<wchar_t>(0xDC00 + ((code - 0x10000) & 0x3FF));
  } else {
    glyph += static_cast<wchar_t>(code);
  }
  return glyph;
}

std::map<std::string, std::wstring> Glyphs(const EncodableMap& map) {
  std::map<std::string, std::wstring> glyphs;
  for (const auto& [key, value] : map) {
    glyphs[std::get<std::string>(key)] =
        Glyph(static_cast<uint32_t>(value.LongValue()));
  }
  return glyphs;
}

DesktopLyrics::Config LyricsConfig(const EncodableMap& map) {
  DesktopLyrics::Config config;
  config.visible = std::get<bool>(*Find(map, "visible"));
  config.locked = std::get<bool>(*Find(map, "locked"));
  config.font_size = static_cast<int>(Find(map, "fontSize")->LongValue());
  config.sung = static_cast<uint32_t>(Find(map, "sung")->LongValue());
  config.unsung = static_cast<uint32_t>(Find(map, "unsung")->LongValue());
  config.single_line = std::get<bool>(*Find(map, "singleLine"));
  config.outline = std::get<bool>(*Find(map, "outline"));
  config.align = static_cast<DesktopLyrics::Align>(Find(map, "align")->LongValue());
  config.translation = std::get<bool>(*Find(map, "translation"));
  config.romaji = std::get<bool>(*Find(map, "romaji"));
  const EncodableValue* x = Find(map, "x");
  const EncodableValue* y = Find(map, "y");
  if (x && y && !x->IsNull() && !y->IsNull()) {
    config.position = POINT{static_cast<LONG>(x->LongValue()),
                            static_cast<LONG>(y->LongValue())};
  }
  config.icons = Glyphs(std::get<EncodableMap>(*Find(map, "icons")));
  return config;
}

std::vector<DesktopLyrics::Line> LyricsLines(const EncodableList& list) {
  std::vector<DesktopLyrics::Line> lines;
  lines.reserve(list.size());
  for (const auto& item : list) {
    const auto& map = std::get<EncodableMap>(item);
    DesktopLyrics::Line line;
    line.time = static_cast<int32_t>(Find(map, "time")->LongValue());
    line.text = Utf16FromUtf8(std::get<std::string>(*Find(map, "text")));
    line.trans = Utf16FromUtf8(std::get<std::string>(*Find(map, "trans")));
    line.roma = Utf16FromUtf8(std::get<std::string>(*Find(map, "roma")));
    // start, duration, length for each word.
    const auto& words = std::get<std::vector<int32_t>>(*Find(map, "words"));
    for (size_t i = 0; i + 2 < words.size(); i += 3) {
      line.words.push_back({words[i], words[i + 1], words[i + 2]});
    }
    lines.push_back(std::move(line));
  }
  return lines;
}

std::wstring ExePath() {
  wchar_t path[MAX_PATH];
  const DWORD length = GetModuleFileName(nullptr, path, MAX_PATH);
  return std::wstring(path, length);
}

// Separate builds (installed, debug, a portable copy) may run side by side;
// only a second launch of the same exe is redirected.
std::wstring InstanceName(const wchar_t* prefix) {
  std::wstring path = ExePath();
  CharLowerBuff(path.data(), static_cast<DWORD>(path.size()));
  return prefix + std::to_wstring(std::hash<std::wstring>{}(path));
}

UINT ActivateMessage() {
  return RegisterWindowMessage(InstanceName(L"Kanade.Activate.").c_str());
}

std::wstring AutostartCommand() {
  return L"\"" + ExePath() + L"\" --autostart";
}

bool SamePath(const std::wstring& a, const std::wstring& b) {
  return CompareStringOrdinal(a.c_str(), -1, b.c_str(), -1, TRUE) ==
         CSTR_EQUAL;
}

// The exe the Run value starts, or empty when there is none. The value is
// shared by every copy of Kanade (installed, debug build, portable).
std::wstring RunValuePath() {
  wchar_t command[MAX_PATH * 2] = {};
  DWORD size = sizeof(command);
  if (RegGetValue(HKEY_CURRENT_USER, kRunKey, kRunValue, RRF_RT_REG_SZ,
                  nullptr, command, &size) != ERROR_SUCCESS ||
      command[0] != L'"') {
    return std::wstring();
  }
  const std::wstring value(command);
  const size_t end = value.find(L'"', 1);
  return end == std::wstring::npos ? std::wstring() : value.substr(1, end - 1);
}

bool RunValueIsOurs() {
  return SamePath(RunValuePath(), ExePath());
}

void WriteRunValue() {
  const std::wstring command = AutostartCommand();
  RegSetKeyValue(HKEY_CURRENT_USER, kRunKey, kRunValue, REG_SZ,
                 command.c_str(),
                 static_cast<DWORD>((command.size() + 1) * sizeof(wchar_t)));
}

bool AutostartEnabled() {
  if (!RunValueIsOurs()) {
    return false;
  }
  BYTE state[12] = {};
  DWORD size = sizeof(state);
  // An odd first byte means the user turned it off there.
  return RegGetValue(HKEY_CURRENT_USER, kStartupApprovedKey, kRunValue,
                     RRF_RT_REG_BINARY, nullptr, state, &size) !=
             ERROR_SUCCESS ||
         size == 0 || (state[0] & 1) == 0;
}

void SetAutostart(bool enabled) {
  if (enabled) {
    WriteRunValue();
    RegDeleteKeyValue(HKEY_CURRENT_USER, kStartupApprovedKey, kRunValue);
  } else if (RunValueIsOurs()) {
    RegDeleteKeyValue(HKEY_CURRENT_USER, kRunKey, kRunValue);
  }
}

// Lets popup menus follow the system dark theme. uxtheme exports this only by
// ordinal (135, SetPreferredAppMode); 1 means AllowDark.
void AllowDarkMenus() {
  HMODULE uxtheme =
      LoadLibraryEx(L"uxtheme.dll", nullptr, LOAD_LIBRARY_SEARCH_SYSTEM32);
  if (!uxtheme) {
    return;
  }
  using SetPreferredAppMode = int(WINAPI*)(int);
  auto set = reinterpret_cast<SetPreferredAppMode>(
      GetProcAddress(uxtheme, MAKEINTRESOURCEA(135)));
  if (set) {
    set(1);
  }
}

// Owner drawing only covers the items. The menu window itself still has the
// classic light 1px frame and square corners, so the tray menu's window is
// caught as it is created and restyled here.
HHOOK menu_hook = nullptr;
WNDPROC menu_window_proc = nullptr;

LRESULT CALLBACK MenuWindowProc(HWND window, UINT message, WPARAM wparam,
                                LPARAM lparam) {
  switch (message) {
    case WM_CREATE: {
      // Values from newer SDKs: DWMWA_WINDOW_CORNER_PREFERENCE, DWMWCP_ROUND,
      // DWMWA_BORDER_COLOR. Older Windows ignores them and keeps square
      // corners.
      const DWORD round = 2;
      DwmSetWindowAttribute(window, 33, &round, sizeof(round));
      const COLORREF border = kMenuBorder;
      DwmSetWindowAttribute(window, 34, &border, sizeof(border));
      break;
    }
    case WM_NCPAINT: {
      RECT frame;
      GetWindowRect(window, &frame);
      POINT client_origin = {0, 0};
      ClientToScreen(window, &client_origin);
      RECT client;
      GetClientRect(window, &client);
      OffsetRect(&client, client_origin.x - frame.left,
                 client_origin.y - frame.top);
      OffsetRect(&frame, -frame.left, -frame.top);
      HDC dc = GetWindowDC(window);
      ExcludeClipRect(dc, client.left, client.top, client.right, client.bottom);
      HBRUSH brush = CreateSolidBrush(kMenuBackground);
      FillRect(dc, &frame, brush);
      DeleteObject(brush);
      ReleaseDC(window, dc);
      return 0;
    }
  }
  return CallWindowProc(menu_window_proc, window, message, wparam, lparam);
}

LRESULT CALLBACK MenuHookProc(int code, WPARAM wparam, LPARAM lparam) {
  if (code == HCBT_CREATEWND) {
    HWND window = reinterpret_cast<HWND>(wparam);
    wchar_t name[16];
    if (GetClassName(window, name, 16) && wcscmp(name, L"#32768") == 0) {
      // The classic drop shadow is a square window behind the menu; DWM draws
      // a rounded one instead.
      SetClassLongPtr(window, GCL_STYLE,
                      GetClassLongPtr(window, GCL_STYLE) & ~CS_DROPSHADOW);
      menu_window_proc = reinterpret_cast<WNDPROC>(SetWindowLongPtr(
          window, GWLP_WNDPROC, reinterpret_cast<LONG_PTR>(&MenuWindowProc)));
    }
  }
  return CallNextHookEx(menu_hook, code, wparam, lparam);
}

}  // namespace

bool ActivateRunningInstance() {
  // Held for the life of the process.
  CreateMutex(nullptr, FALSE, InstanceName(L"Local\\Kanade.").c_str());
  if (GetLastError() != ERROR_ALREADY_EXISTS) {
    return false;
  }
  AllowSetForegroundWindow(ASFW_ANY);
  PostMessage(HWND_BROADCAST, ActivateMessage(), 0, 0);
  return true;
}

DesktopIntegration::DesktopIntegration(HWND window,
                                       flutter::BinaryMessenger* messenger,
                                       const TaskbarThumbnail* thumbnail)
    : window_(window),
      thumbnail_(thumbnail),
      taskbar_created_message_(RegisterWindowMessage(L"TaskbarCreated")),
      activate_message_(ActivateMessage()) {
  AllowDarkMenus();
  Gdiplus::GdiplusStartupInput startup;
  Gdiplus::GdiplusStartup(&gdiplus_, &startup, nullptr);
  menu_brush_ = CreateSolidBrush(kMenuBackground);
  // The same icon font Flutter draws with, so the menu matches the app.
  const std::wstring exe = ExePath();
  icon_font_path_ = exe.substr(0, exe.find_last_of(L'\\')) +
                    L"\\data\\flutter_assets\\fonts\\MaterialIcons-Regular.otf";
  icon_font_loaded_ =
      AddFontResourceEx(icon_font_path_.c_str(), FR_PRIVATE, nullptr) > 0;
  // A portable copy may have moved since autostart was turned on. An entry
  // that still starts another copy is left to that copy.
  const std::wstring run = RunValuePath();
  if (!run.empty() &&
      GetFileAttributes(run.c_str()) == INVALID_FILE_ATTRIBUTES) {
    WriteRunValue();
  }
  channel_ = std::make_unique<flutter::MethodChannel<EncodableValue>>(
      messenger, "kanade/desktop",
      &flutter::StandardMethodCodec::GetInstance());
  channel_->SetMethodCallHandler([this](const auto& call, auto result) {
    HandleMethodCall(call, std::move(result));
  });
  lyrics_ = std::make_unique<DesktopLyrics>(
      icon_font_path_,
      [this](const char* action) {
        channel_->InvokeMethod("tray", std::make_unique<EncodableValue>(action));
      },
      [this] { SendLyricsState(); });
}

DesktopIntegration::~DesktopIntegration() {
  channel_->SetMethodCallHandler(nullptr);
  SetHotkeys({});
  RemoveTrayIcon();
  if (tray_icon_) {
    DestroyIcon(tray_icon_);
  }
  DeleteObject(menu_brush_);
  if (icon_font_loaded_) {
    RemoveFontResourceEx(icon_font_path_.c_str(), FR_PRIVATE, nullptr);
  }
  Gdiplus::GdiplusShutdown(gdiplus_);
}

std::optional<LRESULT> DesktopIntegration::HandleMessage(UINT message,
                                                         WPARAM wparam,
                                                         LPARAM lparam) {
  if (message == activate_message_) {
    ShowWindow();
    return 0;
  }
  if (message == taskbar_created_message_) {
    // Explorer restarted and lost the icon.
    if (tray_added_) {
      tray_added_ = false;
      AddTrayIcon();
    }
    return std::nullopt;
  }

  switch (message) {
    case WM_CLOSE:
      if (intercept_close_ && !quitting_) {
        channel_->InvokeMethod("closeRequested", nullptr);
        return 0;
      }
      break;
    case WM_HOTKEY: {
      const size_t index = static_cast<size_t>(wparam) - 1;
      if (index >= hotkeys_.size()) {
        break;
      }
      if (hotkeys_[index] == "window") {
        if (GetForegroundWindow() == window_ && !IsIconic(window_)) {
          ::ShowWindow(window_, SW_HIDE);
        } else {
          ShowWindow();
        }
      } else if (hotkeys_[index] == "lyrics") {
        lyrics_->SetVisible(!lyrics_->visible());
        SendLyricsState();
      } else {
        channel_->InvokeMethod(
            "hotkey", std::make_unique<EncodableValue>(hotkeys_[index]));
      }
      return 0;
    }
    case kTrayMessage:
      switch (LOWORD(lparam)) {
        case NIN_SELECT:
        case NIN_KEYSELECT:
          if (IsWindowVisible(window_) && !IsIconic(window_)) {
            ::ShowWindow(window_, SW_HIDE);
          } else {
            ShowWindow();
          }
          break;
        case WM_CONTEXTMENU:
          ShowTrayMenu();
          break;
      }
      return 0;
    case WM_COMMAND:
      if (HIWORD(wparam) != 0 || lparam != 0) {
        break;
      }
      switch (LOWORD(wparam)) {
        case kMenuToggle:
          channel_->InvokeMethod("tray",
                                 std::make_unique<EncodableValue>("toggle"));
          return 0;
        case kMenuPrevious:
          channel_->InvokeMethod("tray",
                                 std::make_unique<EncodableValue>("previous"));
          return 0;
        case kMenuNext:
          channel_->InvokeMethod("tray",
                                 std::make_unique<EncodableValue>("next"));
          return 0;
        case kMenuLyrics:
          lyrics_->SetVisible(!lyrics_->visible());
          SendLyricsState();
          return 0;
        case kMenuLyricsUnlock:
          lyrics_->SetLocked(false);
          SendLyricsState();
          return 0;
        case kMenuShow:
          ShowWindow();
          return 0;
        case kMenuExit:
          Quit();
          return 0;
      }
      break;
    case WM_MEASUREITEM: {
      auto* measure = reinterpret_cast<MEASUREITEMSTRUCT*>(lparam);
      if (measure->CtlType != ODT_MENU || measure->itemData == 0 ||
          measure->itemData > menu_items_.size()) {
        break;
      }
      MeasureMenuItem(*measure);
      return TRUE;
    }
    case WM_DRAWITEM: {
      const auto* draw = reinterpret_cast<const DRAWITEMSTRUCT*>(lparam);
      if (draw->CtlType != ODT_MENU || draw->itemData == 0 ||
          draw->itemData > menu_items_.size()) {
        break;
      }
      DrawMenuItem(*draw);
      return TRUE;
    }
  }
  return std::nullopt;
}

void DesktopIntegration::HandleMethodCall(
    const flutter::MethodCall<EncodableValue>& call,
    std::unique_ptr<flutter::MethodResult<EncodableValue>> result) {
  const std::string& method = call.method_name();
  const EncodableValue* args = call.arguments();

  if (method == "interceptClose") {
    intercept_close_ = std::get<bool>(*args);
    result->Success();
  } else if (method == "hide") {
    ::ShowWindow(window_, SW_HIDE);
    result->Success();
  } else if (method == "show") {
    ShowWindow();
    result->Success();
  } else if (method == "quit") {
    Quit();
    result->Success();
  } else if (method == "updateTray") {
    const auto& map = std::get<EncodableMap>(*args);
    tip_ = Utf16FromUtf8(std::get<std::string>(*Find(map, "tip")));
    playing_ = std::get<bool>(*Find(map, "playing"));
    for (const auto& [key, value] : std::get<EncodableMap>(*Find(map, "labels"))) {
      labels_[std::get<std::string>(key)] =
          Utf16FromUtf8(std::get<std::string>(value));
    }
    for (auto& [key, glyph] :
         Glyphs(std::get<EncodableMap>(*Find(map, "icons")))) {
      icons_[key] = glyph;
    }
    AddTrayIcon();
    result->Success();
  } else if (method == "lyricsConfig") {
    lyrics_->SetConfig(LyricsConfig(std::get<EncodableMap>(*args)));
    result->Success();
  } else if (method == "lyricsContent") {
    const auto& map = std::get<EncodableMap>(*args);
    lyrics_->SetContent(
        Utf16FromUtf8(std::get<std::string>(*Find(map, "title"))),
        LyricsLines(std::get<EncodableList>(*Find(map, "lines"))));
    result->Success();
  } else if (method == "lyricsSync") {
    const auto& map = std::get<EncodableMap>(*args);
    lyrics_->Sync(Find(map, "position")->LongValue(),
                  std::get<bool>(*Find(map, "playing")));
    result->Success();
  } else if (method == "setHotkeys") {
    result->Success(EncodableValue(SetHotkeys(std::get<EncodableList>(*args))));
  } else if (method == "getAutostart") {
    result->Success(EncodableValue(AutostartEnabled()));
  } else if (method == "setAutostart") {
    SetAutostart(std::get<bool>(*args));
    result->Success();
  } else if (method == "virtualKey") {
    // Scan code to virtual key under the current keyboard layout.
    result->Success(EncodableValue(static_cast<int>(
        MapVirtualKey(static_cast<UINT>(std::get<int>(*args)),
                      MAPVK_VSC_TO_VK))));
  } else if (method == "removeTray") {
    RemoveTrayIcon();
    result->Success();
  } else {
    result->NotImplemented();
  }
}

void DesktopIntegration::AddTrayIcon() {
  NOTIFYICONDATA data = {sizeof(data)};
  data.hWnd = window_;
  data.uID = kTrayId;
  data.uFlags = NIF_TIP | NIF_SHOWTIP;
  wcsncpy_s(data.szTip, tip_.c_str(), _TRUNCATE);
  if (tray_added_) {
    Shell_NotifyIcon(NIM_MODIFY, &data);
    return;
  }
  if (!tray_icon_) {
    // The notification area scales with the system DPI, not the window's.
    const UINT dpi = GetDpiForSystem();
    tray_icon_ = static_cast<HICON>(LoadImage(
        GetModuleHandle(nullptr), MAKEINTRESOURCE(IDI_APP_ICON), IMAGE_ICON,
        GetSystemMetricsForDpi(SM_CXSMICON, dpi),
        GetSystemMetricsForDpi(SM_CYSMICON, dpi), LR_DEFAULTCOLOR));
  }
  data.uFlags |= NIF_ICON | NIF_MESSAGE;
  data.uCallbackMessage = kTrayMessage;
  data.hIcon = tray_icon_;
  if (!Shell_NotifyIcon(NIM_ADD, &data)) {
    return;
  }
  data.uVersion = NOTIFYICON_VERSION_4;
  Shell_NotifyIcon(NIM_SETVERSION, &data);
  tray_added_ = true;
}

void DesktopIntegration::RemoveTrayIcon() {
  if (!tray_added_) {
    return;
  }
  NOTIFYICONDATA data = {sizeof(data)};
  data.hWnd = window_;
  data.uID = kTrayId;
  Shell_NotifyIcon(NIM_DELETE, &data);
  tray_added_ = false;
  if (tray_icon_) {
    DestroyIcon(tray_icon_);
    tray_icon_ = nullptr;
  }
}

void DesktopIntegration::ShowTrayMenu() {
  HMENU menu = CreatePopupMenu();
  MENUINFO info = {sizeof(info)};
  info.fMask = MIM_BACKGROUND;
  info.hbrBack = menu_brush_;
  SetMenuInfo(menu, &info);

  menu_items_.clear();
  auto add = [&](MenuItem item, UINT id) {
    menu_items_.push_back(std::move(item));
    AppendMenu(menu, MF_OWNERDRAW | (id ? 0 : MF_DISABLED), id,
               reinterpret_cast<LPCWSTR>(menu_items_.size()));
  };
  auto action = [&](UINT id, const char* name) {
    add({MenuItem::kAction, icons_[name], labels_[name]}, id);
  };
  const MenuItem separator = {MenuItem::kSeparator};
  if (!labels_["title"].empty()) {
    add({MenuItem::kHeader, icons_["song"], labels_["title"],
         labels_["artist"]},
        0);
    add(separator, 0);
  }
  action(kMenuToggle, playing_ ? "pause" : "play");
  action(kMenuPrevious, "previous");
  action(kMenuNext, "next");
  add(separator, 0);
  action(kMenuLyrics, lyrics_->visible() ? "lyricsHide" : "lyricsShow");
  if (lyrics_->visible() && lyrics_->locked()) {
    action(kMenuLyricsUnlock, "lyricsUnlock");
  }
  add(separator, 0);
  action(kMenuShow, "show");
  action(kMenuExit, "exit");

  POINT cursor;
  GetCursorPos(&cursor);
  // The menu opens on the taskbar's monitor, which may not be the window's.
  menu_dpi_ = FlutterDesktopGetDpiForMonitor(
      MonitorFromPoint(cursor, MONITOR_DEFAULTTONEAREST));
  NONCLIENTMETRICS metrics = {sizeof(metrics)};
  SystemParametersInfoForDpi(SPI_GETNONCLIENTMETRICS, sizeof(metrics),
                             &metrics, 0, menu_dpi_);
  const wchar_t* face = metrics.lfMessageFont.lfFaceName;
  text_font_ = CreateMenuFont(face, Px(14), FW_NORMAL);
  title_font_ = CreateMenuFont(face, Px(14), FW_SEMIBOLD);
  small_font_ = CreateMenuFont(face, Px(12), FW_NORMAL);
  icon_font_ = CreateMenuFont(L"Material Icons", Px(20), FW_NORMAL);
  if (HBITMAP cover = thumbnail_->cover()) {
    // Scaled once here; the texture brush in DrawMenuItem then only rounds it.
    Gdiplus::Bitmap source(cover, nullptr);
    const int size = Px(kCoverSize);
    menu_cover_ =
        std::make_unique<Gdiplus::Bitmap>(size, size, PixelFormat32bppARGB);
    Gdiplus::Graphics g(menu_cover_.get());
    g.SetInterpolationMode(Gdiplus::InterpolationModeHighQualityBicubic);
    g.SetPixelOffsetMode(Gdiplus::PixelOffsetModeHalf);
    // Center crop, like the app's covers.
    const float side = static_cast<float>(
        std::min(source.GetWidth(), source.GetHeight()));
    g.DrawImage(&source, Gdiplus::RectF(0, 0, float(size), float(size)),
                (source.GetWidth() - side) / 2, (source.GetHeight() - side) / 2,
                side, side, Gdiplus::UnitPixel);
  }

  // Without this the menu stays open after clicking elsewhere.
  SetForegroundWindow(window_);
  menu_hook = SetWindowsHookEx(WH_CBT, MenuHookProc, nullptr,
                               GetCurrentThreadId());
  TrackPopupMenuEx(menu,
                   TPM_RIGHTBUTTON |
                       (GetSystemMetrics(SM_MENUDROPALIGNMENT) ? TPM_RIGHTALIGN
                                                               : TPM_LEFTALIGN),
                   cursor.x, cursor.y, window_, nullptr);
  UnhookWindowsHookEx(menu_hook);
  menu_hook = nullptr;
  PostMessage(window_, WM_NULL, 0, 0);
  DestroyMenu(menu);
  menu_items_.clear();
  for (HFONT* font : {&text_font_, &title_font_, &small_font_, &icon_font_}) {
    DeleteObject(*font);
    *font = nullptr;
  }
  menu_cover_.reset();
}

int DesktopIntegration::Px(float dip) const {
  return static_cast<int>(std::lround(dip * menu_dpi_ / 96.0f));
}

void DesktopIntegration::MeasureMenuItem(MEASUREITEMSTRUCT& measure) const {
  const MenuItem& item = menu_items_[measure.itemData - 1];
  measure.itemWidth = Px(kMenuWidth);
  measure.itemHeight = Px(item.kind == MenuItem::kHeader      ? kHeaderHeight
                          : item.kind == MenuItem::kSeparator ? kSeparatorHeight
                                                              : kItemHeight);
}

void DesktopIntegration::DrawMenuItem(const DRAWITEMSTRUCT& draw) const {
  const MenuItem& item = menu_items_[draw.itemData - 1];
  HDC dc = draw.hDC;
  const RECT& r = draw.rcItem;
  const float left = static_cast<float>(r.left);
  const float top = static_cast<float>(r.top);
  const float width = static_cast<float>(r.right - r.left);
  const float height = static_cast<float>(r.bottom - r.top);
  const bool hot = item.kind == MenuItem::kAction &&
                   (draw.itemState & ODS_SELECTED) != 0;
  const float cover_left = left + Px(12);
  const float cover_top = top + (height - Px(kCoverSize)) / 2;
  {
    Gdiplus::Graphics g(dc);
    g.SetSmoothingMode(Gdiplus::SmoothingModeAntiAlias);
    g.SetPixelOffsetMode(Gdiplus::PixelOffsetModeHalf);
    Gdiplus::SolidBrush background(GdiplusColor(kMenuBackground));
    g.FillRectangle(&background, left, top, width, height);
    switch (item.kind) {
      case MenuItem::kSeparator: {
        Gdiplus::SolidBrush line(GdiplusColor(kMenuSeparator));
        g.FillRectangle(&line, left + Px(12),
                        top + std::floor(height / 2), width - Px(24),
                        static_cast<float>(std::max(1, Px(1))));
        break;
      }
      case MenuItem::kHeader: {
        Gdiplus::GraphicsPath path;
        AddRoundRect(path,
                     Gdiplus::RectF(cover_left, cover_top, float(Px(kCoverSize)),
                                    float(Px(kCoverSize))),
                     float(Px(6)));
        if (menu_cover_) {
          Gdiplus::TextureBrush brush(menu_cover_.get());
          brush.TranslateTransform(cover_left, cover_top);
          g.FillPath(&brush, &path);
        } else {
          Gdiplus::SolidBrush placeholder(GdiplusColor(kMenuPlaceholder));
          g.FillPath(&placeholder, &path);
        }
        break;
      }
      case MenuItem::kAction:
        if (hot) {
          Gdiplus::GraphicsPath path;
          AddRoundRect(path,
                       Gdiplus::RectF(left + Px(6), top + Px(1),
                                      width - Px(12), height - Px(2)),
                       float(Px(8)));
          Gdiplus::SolidBrush accent(GdiplusColor(kAccent));
          g.FillPath(&accent, &path);
        }
        break;
    }
  }

  SetBkMode(dc, TRANSPARENT);
  const LONG text_left = r.left + Px(48);
  const LONG text_right = r.right - Px(16);
  if (item.kind == MenuItem::kHeader) {
    if (!menu_cover_ && icon_font_loaded_) {
      const RECT icon = {LONG(cover_left), LONG(cover_top),
                         LONG(cover_left) + Px(kCoverSize),
                         LONG(cover_top) + Px(kCoverSize)};
      DrawMenuText(dc, icon_font_, kMenuSecondary, item.icon, icon,
                   DT_CENTER | DT_VCENTER);
    }
    const LONG middle = r.top + (r.bottom - r.top) / 2;
    const LONG header_left = LONG(cover_left) + Px(kCoverSize) + Px(12);
    DrawMenuText(dc, title_font_, kMenuText, item.text,
                 {header_left, r.top, text_right, middle + Px(1)},
                 DT_BOTTOM | DT_END_ELLIPSIS);
    DrawMenuText(dc, small_font_, kMenuSecondary, item.detail,
                 {header_left, middle + Px(3), text_right, r.bottom},
                 DT_TOP | DT_END_ELLIPSIS);
  } else if (item.kind == MenuItem::kAction) {
    const COLORREF color = hot ? kOnAccent : kMenuText;
    if (icon_font_loaded_) {
      DrawMenuText(dc, icon_font_, color, item.icon,
                   {r.left + Px(16), r.top, r.left + Px(40), r.bottom},
                   DT_CENTER | DT_VCENTER);
    }
    DrawMenuText(dc, text_font_, color, item.text,
                 {text_left, r.top, text_right, r.bottom},
                 DT_VCENTER | DT_END_ELLIPSIS);
  }
}

void DesktopIntegration::ShowWindow() {
  if (!IsWindowVisible(window_)) {
    ::ShowWindow(window_, SW_SHOW);
  }
  if (IsIconic(window_)) {
    ::ShowWindow(window_, SW_RESTORE);
  }
  SetForegroundWindow(window_);
}

void DesktopIntegration::Quit() {
  quitting_ = true;
  PostMessage(window_, WM_CLOSE, 0, 0);
}

EncodableList DesktopIntegration::SetHotkeys(const EncodableList& hotkeys) {
  for (size_t i = 0; i < hotkeys_.size(); ++i) {
    UnregisterHotKey(window_, static_cast<int>(i + 1));
  }
  hotkeys_.clear();
  EncodableList registered;
  for (const auto& item : hotkeys) {
    const auto& map = std::get<EncodableMap>(item);
    hotkeys_.push_back(std::get<std::string>(*Find(map, "action")));
    const UINT modifiers =
        static_cast<UINT>(std::get<int>(*Find(map, "modifiers")));
    const UINT key = static_cast<UINT>(std::get<int>(*Find(map, "key")));
    registered.push_back(EncodableValue(
        RegisterHotKey(window_, static_cast<int>(hotkeys_.size()),
                       modifiers | MOD_NOREPEAT, key) != 0));
  }
  return registered;
}

void DesktopIntegration::SendLyricsState() {
  EncodableMap state = {
      {EncodableValue("visible"), EncodableValue(lyrics_->visible())},
      {EncodableValue("locked"), EncodableValue(lyrics_->locked())},
      {EncodableValue("fontSize"), EncodableValue(lyrics_->font_size())},
      {EncodableValue("translation"), EncodableValue(lyrics_->translation())},
      {EncodableValue("romaji"), EncodableValue(lyrics_->romaji())},
  };
  if (const auto position = lyrics_->position()) {
    state[EncodableValue("x")] = EncodableValue(static_cast<int>(position->x));
    state[EncodableValue("y")] = EncodableValue(static_cast<int>(position->y));
  }
  channel_->InvokeMethod("lyricsState",
                         std::make_unique<EncodableValue>(std::move(state)));
}
