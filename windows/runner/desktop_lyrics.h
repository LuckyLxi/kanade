#ifndef RUNNER_DESKTOP_LYRICS_H_
#define RUNNER_DESKTOP_LYRICS_H_

#include <d2d1.h>
#include <dwrite_3.h>
#include <windows.h>
#include <wrl/client.h>

#include <algorithm>
#include <chrono>
#include <cstdint>
#include <functional>
#include <map>
#include <optional>
#include <string>
#include <vector>

// The desktop lyric window: a topmost layered window with two lines that take
// turns, filled word by word. It advances the play position by itself between
// syncs from Dart. Locked, it lets clicks through to the windows below.
class DesktopLyrics {
 public:
  // Same order as Dart's LyricsAlign. Stagger: the first row left, the second
  // indented; with one row it centers.
  enum class Align { kLeft, kCenter, kRight, kStagger };
  struct Word {
    int32_t start;
    int32_t duration;
    // UTF-16 units of the line's text this word covers.
    int32_t length;
  };
  struct Line {
    int32_t time;
    std::wstring text;
    std::wstring trans;
    std::wstring roma;
    // Empty when the line fills by time instead.
    std::vector<Word> words;
  };
  struct Config {
    bool visible = false;
    bool locked = false;
    // Logical pixels.
    int font_size = 32;
    // ARGB.
    uint32_t sung = 0xFFD4FF3A;
    uint32_t unsung = 0xFFFFFFFF;
    bool single_line = false;
    Align align = Align::kStagger;
    // With either on and the song has it, the current line shows alone with
    // its romaji and translation under it.
    bool translation = false;
    bool romaji = false;
    // Top-left in screen pixels; only used when the window is first placed.
    std::optional<POINT> position;
    // Toolbar Material Icons glyphs: previous, play, pause, next, smaller,
    // bigger, translation, romaji, lock, unlock, close.
    std::map<std::string, std::wstring> icons;
  };

  // |on_action| gets the toolbar's playback buttons (previous, toggle, next).
  // |on_state| runs after the user moves, resizes, locks or closes the window.
  DesktopLyrics(const std::wstring& icon_font_path,
                std::function<void(const char*)> on_action,
                std::function<void()> on_state);
  ~DesktopLyrics();

  void SetConfig(const Config& config);
  // |title| shows while there are no timed lines.
  void SetContent(std::wstring title, std::vector<Line> lines);
  void Sync(int64_t position_ms, bool playing);
  void SetVisible(bool visible);
  void SetLocked(bool locked);

  bool visible() const { return visible_; }
  bool locked() const { return locked_; }
  int font_size() const { return font_size_; }
  bool translation() const { return translation_; }
  bool romaji() const { return romaji_; }
  std::optional<POINT> position() const { return position_; }

 private:
  static constexpr int kTitle = -1;
  static constexpr int kEmpty = -2;
  // Two lyric rows, then the romaji and translation rows.
  static constexpr int kSlots = 4;

  // A 32-bit premultiplied top-down DIB selected into its own DC.
  struct Surface {
    ~Surface();
    bool Resize(int width, int height);
    void Reset();

    HDC dc = nullptr;
    HBITMAP bitmap = nullptr;
    HGDIOBJ old = nullptr;
    uint32_t* bits = nullptr;
    int width = 0;
    int height = 0;
  };
  // What a slot shows of its line.
  enum Part { kText, kRoma, kTrans };
  // One row, drawn once in both colors.
  struct Slot {
    // Index into lines_, kTitle or kEmpty.
    int line = kEmpty;
    uint64_t version = 0;
    Surface sung;
    Surface unsung;
    // Pixel x before each UTF-16 unit, plus the end.
    std::vector<float> char_x;
    int width = 0;
  };
  struct Button {
    const char* id;
    D2D1_RECT_F rect;
  };
  struct FrameKey {
    int lines[kSlots];
    long edge;
    // 0 nothing, 1 toolbar, 2 unlock button, 3 unlock button under the mouse.
    int overlay;
    int hot;
    bool playing;
    uint64_t version;
    bool operator==(const FrameKey& o) const {
      return std::equal(lines, lines + kSlots, o.lines) && edge == o.edge &&
             overlay == o.overlay && hot == o.hot && playing == o.playing &&
             version == o.version;
    }
  };

  static LRESULT CALLBACK WndProc(HWND window, UINT message, WPARAM wparam,
                                  LPARAM lparam);
  std::optional<LRESULT> HandleMessage(UINT message, WPARAM wparam,
                                       LPARAM lparam);
  void EnsureWindow();
  // Sizes, fonts and toolbar buttons for the current font size and DPI.
  void Layout();
  RECT WorkArea() const;
  void MoveTo(int x, int y);
  void SetFontSize(int size);
  // Lays out again for a new size, keeping the bottom center in place.
  void Relayout();
  void Press(const char* id);
  int HitButton(LPARAM lparam) const;
  void UpdateTimer();
  // Locked, the window never sees the mouse; this checks the cursor instead
  // and lets clicks reach the window only over the unlock button.
  void PollLocked();
  bool OverUnlock(LPARAM lparam) const;
  void SetClickThrough(bool through);
  int Px(float dip) const;
  int64_t Position() const;
  int CurrentLine(int64_t position) const;
  void RenderSlot(Slot& slot, int line, Part part);
  // Pixel x the fill has reached in |slot|, which shows the current line.
  float FillEdge(const Slot& slot, int64_t position) const;
  // Left x of |slot|: |fit| when it fits, otherwise scrolled so |edge| stays
  // in view, or by |progress| of the overflow when there is no edge.
  int SlotX(const Slot& slot, int fit, float edge, float progress) const;
  void DrawSlot(const Slot& slot, int x0, int y0, float edge);
  void DrawToolbar();
  void DrawUnlock();
  void Render();

  std::function<void(const char*)> on_action_;
  std::function<void()> on_state_;

  Microsoft::WRL::ComPtr<ID2D1Factory> d2d_;
  Microsoft::WRL::ComPtr<IDWriteFactory> dwrite_;
  Microsoft::WRL::ComPtr<IDWriteFontCollection1> icon_fonts_;
  Microsoft::WRL::ComPtr<ID2D1DCRenderTarget> target_;
  Microsoft::WRL::ComPtr<ID2D1SolidColorBrush> brush_;
  Microsoft::WRL::ComPtr<ID2D1SolidColorBrush> outline_brush_;
  Microsoft::WRL::ComPtr<ID2D1StrokeStyle> stroke_;
  Microsoft::WRL::ComPtr<IDWriteTextFormat> text_format_;
  Microsoft::WRL::ComPtr<IDWriteTextFormat> sub_format_;
  Microsoft::WRL::ComPtr<IDWriteTextFormat> icon_format_;

  HWND window_ = nullptr;
  UINT dpi_ = 96;
  int width_ = 0;
  int height_ = 0;
  Surface frame_;
  Slot slots_[kSlots];
  // Bumped whenever the slots have to be drawn again.
  uint64_t version_ = 1;
  std::optional<FrameKey> last_frame_;
  std::vector<Button> buttons_;

  bool visible_ = false;
  bool locked_ = false;
  int font_size_ = 32;
  uint32_t sung_ = 0xFFD4FF3A;
  uint32_t unsung_ = 0xFFFFFFFF;
  bool single_line_ = false;
  Align align_ = Align::kStagger;
  bool translation_ = false;
  bool romaji_ = false;
  std::optional<POINT> position_;
  std::map<std::string, std::wstring> icons_;

  std::wstring title_;
  std::vector<Line> lines_;
  // Whether any line has a translation or romaji.
  bool has_trans_ = false;
  bool has_roma_ = false;
  int64_t base_position_ = 0;
  std::chrono::steady_clock::time_point base_time_;
  bool playing_ = false;

  bool hovered_ = false;
  int hot_button_ = -1;
  int pressed_button_ = -1;

  // Locked only: the cursor is over the window, over the unlock button.
  bool locked_hover_ = false;
  bool unlock_hot_ = false;
  bool unlock_pressed_ = false;
  D2D1_RECT_F unlock_rect_ = {};
};

#endif  // RUNNER_DESKTOP_LYRICS_H_
