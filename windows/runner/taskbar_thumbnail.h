#ifndef RUNNER_TASKBAR_THUMBNAIL_H_
#define RUNNER_TASKBAR_THUMBNAIL_H_

#include <flutter/binary_messenger.h>
#include <flutter/encodable_value.h>
#include <flutter/method_channel.h>
#include <shobjidl.h>
#include <windows.h>
#include <wrl/client.h>

#include <memory>
#include <optional>
#include <string>

// Taskbar hover preview: while a song is loaded, the thumbnail shows its cover
// with previous / play-pause / next buttons below.
//
// The cover comes from a hidden window registered as the main window's only
// taskbar tab. The tab supplies the static thumbnail, while Aero Peek still
// uses the main window itself, so the peek stays live.
class TaskbarThumbnail {
 public:
  TaskbarThumbnail(HWND window, flutter::BinaryMessenger* messenger);
  ~TaskbarThumbnail();

  // Returns a result for handled messages, nullopt to pass them on.
  std::optional<LRESULT> HandleMessage(UINT message, WPARAM wparam,
                                       LPARAM lparam);

 private:
  enum Icon { kPrevious, kPlay, kPause, kNext, kIconCount };

  static LRESULT CALLBACK TabProc(HWND tab, UINT message, WPARAM wparam,
                                  LPARAM lparam);
  LRESULT HandleTabMessage(HWND tab, UINT message, WPARAM wparam,
                           LPARAM lparam);

  void HandleMethodCall(
      const flutter::MethodCall<flutter::EncodableValue>& call,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);
  void UpdateTab();
  void CreateTab();
  void DestroyTab();
  void UpdateButtons();
  void SendThumbnail(int max_width, int max_height);

  HWND window_;
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> channel_;
  UINT taskbar_created_message_;
  Microsoft::WRL::ComPtr<ITaskbarList4> taskbar_;

  // The hidden tab window; exists only while there is a cover to show.
  HWND tab_ = nullptr;
  bool buttons_added_ = false;

  HICON icons_[kIconCount] = {};
  std::wstring tips_[kIconCount];
  std::wstring title_;
  bool visible_ = false;
  bool playing_ = false;

  HBITMAP cover_ = nullptr;
  int cover_width_ = 0;
  int cover_height_ = 0;
};

#endif  // RUNNER_TASKBAR_THUMBNAIL_H_
