#include "flutter_window.h"

#include <optional>

#include "flutter/generated_plugin_registrant.h"

namespace {

constexpr wchar_t kWindowSettingsKey[] = L"Software\\com.kanade\\kanade";
constexpr wchar_t kWindowPositionValue[] = L"WindowPosition";

void RestoreWindowPosition(HWND window) {
  RECT bounds;
  GetWindowRect(window, &bounds);
  const LONG width = bounds.right - bounds.left;
  const LONG height = bounds.bottom - bounds.top;

  POINT position{};
  DWORD position_size = sizeof(position);
  const LSTATUS result = RegGetValue(
      HKEY_CURRENT_USER, kWindowSettingsKey, kWindowPositionValue,
      RRF_RT_REG_BINARY, nullptr, &position, &position_size);
  const RECT saved_bounds = {position.x, position.y, position.x + width,
                            position.y + height};
  if (result != ERROR_SUCCESS || position_size != sizeof(position) ||
      !MonitorFromRect(&saved_bounds, MONITOR_DEFAULTTONULL)) {
    MONITORINFO monitor_info{};
    monitor_info.cbSize = sizeof(monitor_info);
    if (!GetMonitorInfo(MonitorFromWindow(window, MONITOR_DEFAULTTOPRIMARY),
                        &monitor_info)) {
      return;
    }
    const RECT& work = monitor_info.rcWork;
    position.x = work.left + (work.right - work.left - width) / 2;
    position.y = work.top + (work.bottom - work.top - height) / 2;
  }

  // Position the hidden window before creating the Flutter rendering surface.
  SetWindowPos(window, nullptr, position.x, position.y, 0, 0,
               SWP_NOSIZE | SWP_NOZORDER | SWP_NOACTIVATE);
}

void SaveWindowPosition(HWND window) {
  // Minimized/maximized coordinates must not replace the normal position.
  if (IsIconic(window) || IsZoomed(window)) {
    return;
  }
  RECT bounds;
  if (GetWindowRect(window, &bounds)) {
    const POINT position = {bounds.left, bounds.top};
    RegSetKeyValue(HKEY_CURRENT_USER, kWindowSettingsKey, kWindowPositionValue,
                   REG_BINARY, &position, sizeof(position));
  }
}

}  // namespace

FlutterWindow::FlutterWindow(const flutter::DartProject& project)
    : project_(project) {}

FlutterWindow::~FlutterWindow() {}

bool FlutterWindow::OnCreate() {
  if (!Win32Window::OnCreate()) {
    return false;
  }

  RestoreWindowPosition(GetHandle());

  RECT frame = GetClientArea();

  // The size here must match the window dimensions to avoid unnecessary surface
  // creation / destruction in the startup path.
  flutter_controller_ = std::make_unique<flutter::FlutterViewController>(
      frame.right - frame.left, frame.bottom - frame.top, project_);
  // Ensure that basic setup of the controller was successful.
  if (!flutter_controller_->engine() || !flutter_controller_->view()) {
    return false;
  }
  RegisterPlugins(flutter_controller_->engine());
  taskbar_thumbnail_ = std::make_unique<TaskbarThumbnail>(
      GetHandle(), flutter_controller_->engine()->messenger());
  SetChildContent(flutter_controller_->view()->GetNativeWindow());

  // The window is shown from Dart (window_manager) once the native title bar
  // has been hidden, so it doesn't flash on startup.
  flutter_controller_->engine()->SetNextFrameCallback([&]() {});

  // Flutter can complete the first frame before the "show window" callback is
  // registered. The following call ensures a frame is pending to ensure the
  // window is shown. It is a no-op if the first frame hasn't completed yet.
  flutter_controller_->ForceRedraw();

  return true;
}

void FlutterWindow::OnDestroy() {
  taskbar_thumbnail_ = nullptr;
  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
  // window_manager consumes WM_EXITSIZEMOVE, so save before forwarding it.
  if (message == WM_EXITSIZEMOVE || message == WM_CLOSE) {
    SaveWindowPosition(hwnd);
  }

  if (taskbar_thumbnail_) {
    std::optional<LRESULT> result =
        taskbar_thumbnail_->HandleMessage(message, wparam, lparam);
    if (result) {
      return *result;
    }
  }

  // Give Flutter, including plugins, an opportunity to handle window messages.
  if (flutter_controller_) {
    std::optional<LRESULT> result =
        flutter_controller_->HandleTopLevelWindowProc(hwnd, message, wparam,
                                                      lparam);
    if (result) {
      return *result;
    }
  }

  switch (message) {
    case WM_FONTCHANGE:
      flutter_controller_->engine()->ReloadSystemFonts();
      break;
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}
