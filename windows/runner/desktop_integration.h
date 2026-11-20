#ifndef RUNNER_DESKTOP_INTEGRATION_H_
#define RUNNER_DESKTOP_INTEGRATION_H_

#include <flutter/binary_messenger.h>
#include <flutter/encodable_value.h>
#include <flutter/method_channel.h>
#include <windows.h>

#include <map>
#include <memory>
#include <optional>
#include <string>
#include <vector>

#include "taskbar_thumbnail.h"

namespace Gdiplus {
class Bitmap;
}

// Returns true when a Kanade started from this same exe is already running.
// That instance is asked to show its window, and this one should exit.
bool ActivateRunningInstance();

// Tray icon, close to tray, global hotkeys and start at login, driven from
// Dart over the kanade/desktop channel.
class DesktopIntegration {
 public:
  // The tray menu header reuses |thumbnail|'s cover.
  DesktopIntegration(HWND window, flutter::BinaryMessenger* messenger,
                     const TaskbarThumbnail* thumbnail);
  ~DesktopIntegration();

  // Returns a result for handled messages, nullopt to pass them on.
  std::optional<LRESULT> HandleMessage(UINT message, WPARAM wparam,
                                       LPARAM lparam);

 private:
  // The tray menu is owner drawn; each item's itemData is its index + 1 here.
  struct MenuItem {
    enum Kind { kHeader, kSeparator, kAction } kind;
    std::wstring icon;
    std::wstring text;
    // The header's second line.
    std::wstring detail;
  };

  void MeasureMenuItem(MEASUREITEMSTRUCT& measure) const;
  void DrawMenuItem(const DRAWITEMSTRUCT& draw) const;
  int Px(float dip) const;
  void HandleMethodCall(
      const flutter::MethodCall<flutter::EncodableValue>& call,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);
  void AddTrayIcon();
  void RemoveTrayIcon();
  void ShowTrayMenu();
  void ShowWindow();
  // Close goes through WM_CLOSE again, this time without asking Dart.
  void Quit();
  flutter::EncodableList SetHotkeys(const flutter::EncodableList& hotkeys);

  HWND window_;
  const TaskbarThumbnail* thumbnail_;
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> channel_;
  UINT taskbar_created_message_;
  UINT activate_message_;

  bool tray_added_ = false;
  HICON tray_icon_ = nullptr;
  std::wstring tip_;
  // Menu text from Dart, keyed by item: title, artist, play, pause, previous,
  // next, show, exit.
  std::map<std::string, std::wstring> labels_;
  // Material Icons glyphs from Dart, keyed by item plus "song".
  std::map<std::string, std::wstring> icons_;
  bool playing_ = false;

  ULONG_PTR gdiplus_ = 0;
  std::wstring icon_font_path_;
  bool icon_font_loaded_ = false;
  HBRUSH menu_brush_ = nullptr;

  // Only valid while the tray menu is open.
  std::vector<MenuItem> menu_items_;
  UINT menu_dpi_ = 96;
  HFONT text_font_ = nullptr;
  HFONT title_font_ = nullptr;
  HFONT small_font_ = nullptr;
  HFONT icon_font_ = nullptr;
  std::unique_ptr<Gdiplus::Bitmap> menu_cover_;

  // Set once Dart handles close; until then WM_CLOSE closes as usual.
  bool intercept_close_ = false;
  bool quitting_ = false;

  // Registered hotkey id - 1 -> action name.
  std::vector<std::string> hotkeys_;
};

#endif  // RUNNER_DESKTOP_INTEGRATION_H_
