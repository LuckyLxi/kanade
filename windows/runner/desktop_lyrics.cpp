#include "desktop_lyrics.h"

#include <flutter_windows.h>

#include <algorithm>
#include <cmath>

using Microsoft::WRL::ComPtr;

namespace {

constexpr wchar_t kClassName[] = L"KanadeDesktopLyrics";
constexpr UINT_PTR kFrameTimer = 1;
constexpr UINT_PTR kLockedTimer = 2;
constexpr UINT kLockedPollMs = 50;

// Layout in logical pixels.
constexpr float kWidth = 960;
constexpr float kToolbarHeight = 44;
constexpr float kButtonSize = 34;
constexpr float kButtonGap = 4;
constexpr float kGroupGap = 20;
constexpr float kIconSize = 22;
constexpr float kPadding = 24;
constexpr float kBottomPadding = 10;
constexpr float kCornerRadius = 14;
// Row height as a multiple of the font size.
constexpr float kRowHeight = 1.45f;
// Width of the soft edge between sung and unsung text.
constexpr float kEdgeWidth = 3;
// Distance from the bottom of the work area when first placed.
constexpr float kDefaultMargin = 72;
constexpr int kMinFontSize = 20;
constexpr int kMaxFontSize = 72;
constexpr int kFontStep = 4;
// How far into the row an overlong current line keeps its fill edge while it
// scrolls.
constexpr float kScrollAnchor = 0.6f;
// Romaji and translation rows against the lyric row.
constexpr float kSubScale = 0.8f;
// How far the second row starts right of the first when staggered, in font
// sizes.
constexpr float kStaggerIndent = 3;

D2D1_COLOR_F ColorF(uint32_t argb) {
  return D2D1::ColorF(((argb >> 16) & 0xFF) / 255.f, ((argb >> 8) & 0xFF) / 255.f,
                      (argb & 0xFF) / 255.f, (argb >> 24) / 255.f);
}

// Premultiplied source over destination.
uint32_t Over(uint32_t src, uint32_t dst) {
  const uint32_t a = src >> 24;
  if (a == 255 || (dst >> 24) == 0) {
    return src;
  }
  const uint32_t k = 255 - a;
  uint32_t out = 0;
  for (int shift = 0; shift < 32; shift += 8) {
    const uint32_t c =
        ((src >> shift) & 0xFF) + (((dst >> shift) & 0xFF) * k + 127) / 255;
    out |= c << shift;
  }
  return out;
}

// |w| of 256 parts |b|, the rest |a|.
uint32_t Mix(uint32_t a, uint32_t b, uint32_t w) {
  uint32_t out = 0;
  for (int shift = 0; shift < 32; shift += 8) {
    const uint32_t c =
        (((a >> shift) & 0xFF) * (256 - w) + ((b >> shift) & 0xFF) * w) >> 8;
    out |= c << shift;
  }
  return out;
}

// Draws text as filled glyph outlines with a stroke behind them, so the lyric
// reads over any background.
class OutlineRenderer : public IDWriteTextRenderer {
 public:
  OutlineRenderer(ID2D1Factory* factory, ID2D1RenderTarget* target,
                  ID2D1Brush* fill, ID2D1Brush* outline,
                  ID2D1StrokeStyle* stroke, float stroke_width)
      : factory_(factory),
        target_(target),
        fill_(fill),
        outline_(outline),
        stroke_(stroke),
        stroke_width_(stroke_width) {}

  // Lives on the stack for one IDWriteTextLayout::Draw call.
  ULONG STDMETHODCALLTYPE AddRef() override { return 1; }
  ULONG STDMETHODCALLTYPE Release() override { return 1; }
  HRESULT STDMETHODCALLTYPE QueryInterface(REFIID iid, void** out) override {
    if (iid == __uuidof(IUnknown) || iid == __uuidof(IDWritePixelSnapping) ||
        iid == __uuidof(IDWriteTextRenderer)) {
      *out = this;
      return S_OK;
    }
    *out = nullptr;
    return E_NOINTERFACE;
  }

  HRESULT STDMETHODCALLTYPE IsPixelSnappingDisabled(void*,
                                                    BOOL* disabled) override {
    *disabled = FALSE;
    return S_OK;
  }
  HRESULT STDMETHODCALLTYPE GetCurrentTransform(void*,
                                                DWRITE_MATRIX* m) override {
    target_->GetTransform(reinterpret_cast<D2D1_MATRIX_3X2_F*>(m));
    return S_OK;
  }
  HRESULT STDMETHODCALLTYPE GetPixelsPerDip(void*, FLOAT* pixels) override {
    *pixels = 1;
    return S_OK;
  }

  HRESULT STDMETHODCALLTYPE DrawGlyphRun(void*, FLOAT x, FLOAT y,
                                         DWRITE_MEASURING_MODE,
                                         const DWRITE_GLYPH_RUN* run,
                                         const DWRITE_GLYPH_RUN_DESCRIPTION*,
                                         IUnknown*) override {
    ComPtr<ID2D1PathGeometry> path;
    ComPtr<ID2D1GeometrySink> sink;
    ComPtr<ID2D1TransformedGeometry> glyphs;
    HRESULT hr = factory_->CreatePathGeometry(&path);
    if (SUCCEEDED(hr)) {
      hr = path->Open(&sink);
    }
    if (SUCCEEDED(hr)) {
      hr = run->fontFace->GetGlyphRunOutline(
          run->fontEmSize, run->glyphIndices, run->glyphAdvances,
          run->glyphOffsets, run->glyphCount, run->isSideways,
          run->bidiLevel % 2, sink.Get());
    }
    if (SUCCEEDED(hr)) {
      hr = sink->Close();
    }
    if (SUCCEEDED(hr)) {
      hr = factory_->CreateTransformedGeometry(
          path.Get(), D2D1::Matrix3x2F::Translation(x, y), &glyphs);
    }
    if (FAILED(hr)) {
      return hr;
    }
    // Centered on the outline, so the fill covers its inner half.
    target_->DrawGeometry(glyphs.Get(), outline_, stroke_width_ * 2, stroke_);
    target_->FillGeometry(glyphs.Get(), fill_);
    return S_OK;
  }
  HRESULT STDMETHODCALLTYPE DrawUnderline(void*, FLOAT, FLOAT,
                                          const DWRITE_UNDERLINE*,
                                          IUnknown*) override {
    return S_OK;
  }
  HRESULT STDMETHODCALLTYPE DrawStrikethrough(void*, FLOAT, FLOAT,
                                              const DWRITE_STRIKETHROUGH*,
                                              IUnknown*) override {
    return S_OK;
  }
  HRESULT STDMETHODCALLTYPE DrawInlineObject(void*, FLOAT, FLOAT,
                                             IDWriteInlineObject*, BOOL, BOOL,
                                             IUnknown*) override {
    return E_NOTIMPL;
  }

 private:
  ID2D1Factory* factory_;
  ID2D1RenderTarget* target_;
  ID2D1Brush* fill_;
  ID2D1Brush* outline_;
  ID2D1StrokeStyle* stroke_;
  float stroke_width_;
};

}  // namespace

DesktopLyrics::Surface::~Surface() {
  Reset();
}

void DesktopLyrics::Surface::Reset() {
  if (dc) {
    SelectObject(dc, old);
    DeleteDC(dc);
  }
  if (bitmap) {
    DeleteObject(bitmap);
  }
  dc = nullptr;
  bitmap = nullptr;
  old = nullptr;
  bits = nullptr;
  width = 0;
  height = 0;
}

bool DesktopLyrics::Surface::Resize(int w, int h) {
  if (dc && w == width && h == height) {
    return true;
  }
  Reset();
  if (w <= 0 || h <= 0) {
    return false;
  }
  BITMAPINFO info = {};
  info.bmiHeader.biSize = sizeof(BITMAPINFOHEADER);
  info.bmiHeader.biWidth = w;
  info.bmiHeader.biHeight = -h;
  info.bmiHeader.biPlanes = 1;
  info.bmiHeader.biBitCount = 32;
  info.bmiHeader.biCompression = BI_RGB;
  void* pixels = nullptr;
  bitmap = CreateDIBSection(nullptr, &info, DIB_RGB_COLORS, &pixels, nullptr, 0);
  if (!bitmap) {
    return false;
  }
  dc = CreateCompatibleDC(nullptr);
  old = SelectObject(dc, bitmap);
  bits = static_cast<uint32_t*>(pixels);
  width = w;
  height = h;
  return true;
}

DesktopLyrics::DesktopLyrics(const std::wstring& icon_font_path,
                             std::function<void(const char*)> on_action,
                             std::function<void()> on_state)
    : on_action_(std::move(on_action)), on_state_(std::move(on_state)) {
  D2D1CreateFactory(D2D1_FACTORY_TYPE_SINGLE_THREADED, d2d_.GetAddressOf());
  DWriteCreateFactory(DWRITE_FACTORY_TYPE_SHARED, __uuidof(IDWriteFactory),
                      reinterpret_cast<IUnknown**>(dwrite_.GetAddressOf()));
  // The app's own icon font, loaded from its file (Windows 10 1703+).
  ComPtr<IDWriteFactory5> factory5;
  ComPtr<IDWriteFontSetBuilder1> builder;
  ComPtr<IDWriteFontFile> file;
  ComPtr<IDWriteFontSet> set;
  if (dwrite_ && SUCCEEDED(dwrite_.As(&factory5)) &&
      SUCCEEDED(factory5->CreateFontSetBuilder(&builder)) &&
      SUCCEEDED(factory5->CreateFontFileReference(icon_font_path.c_str(),
                                                  nullptr, &file)) &&
      SUCCEEDED(builder->AddFontFile(file.Get())) &&
      SUCCEEDED(builder->CreateFontSet(&set))) {
    factory5->CreateFontCollectionFromFontSet(set.Get(), &icon_fonts_);
  }
  if (d2d_) {
    const D2D1_STROKE_STYLE_PROPERTIES stroke = D2D1::StrokeStyleProperties(
        D2D1_CAP_STYLE_ROUND, D2D1_CAP_STYLE_ROUND, D2D1_CAP_STYLE_ROUND,
        D2D1_LINE_JOIN_ROUND);
    d2d_->CreateStrokeStyle(stroke, nullptr, 0, &stroke_);
  }
}

DesktopLyrics::~DesktopLyrics() {
  if (window_) {
    DestroyWindow(window_);
  }
}

void DesktopLyrics::SetConfig(const Config& config) {
  if (!window_) {
    position_ = config.position;
  }
  icons_ = config.icons;
  if (config.sung != sung_ || config.unsung != unsung_) {
    sung_ = config.sung;
    unsung_ = config.unsung;
    ++version_;
  }
  const bool reshape = config.single_line != single_line_ ||
                       config.translation != translation_ ||
                       config.romaji != romaji_;
  single_line_ = config.single_line;
  translation_ = config.translation;
  romaji_ = config.romaji;
  if (config.align != align_) {
    align_ = config.align;
    ++version_;
  }
  if (config.font_size != font_size_) {
    SetFontSize(config.font_size);
  } else if (reshape) {
    Relayout();
  }
  SetLocked(config.locked);
  SetVisible(config.visible);
  last_frame_.reset();
  Render();
}

void DesktopLyrics::SetContent(std::wstring title, std::vector<Line> lines) {
  title_ = std::move(title);
  lines_ = std::move(lines);
  has_trans_ = std::any_of(lines_.begin(), lines_.end(),
                           [](const Line& l) { return !l.trans.empty(); });
  has_roma_ = std::any_of(lines_.begin(), lines_.end(),
                          [](const Line& l) { return !l.roma.empty(); });
  ++version_;
  Render();
}

void DesktopLyrics::Sync(int64_t position_ms, bool playing) {
  base_position_ = position_ms;
  base_time_ = std::chrono::steady_clock::now();
  playing_ = playing;
  UpdateTimer();
  Render();
}

void DesktopLyrics::SetVisible(bool visible) {
  if (visible == visible_ && (!visible || window_)) {
    return;
  }
  visible_ = visible;
  if (visible) {
    EnsureWindow();
    last_frame_.reset();
    Render();
    ShowWindow(window_, SW_SHOWNOACTIVATE);
  } else if (window_) {
    ShowWindow(window_, SW_HIDE);
    hovered_ = false;
    hot_button_ = -1;
    if (locked_ && unlock_hot_) {
      SetClickThrough(true);
    }
    locked_hover_ = false;
    unlock_hot_ = false;
    unlock_pressed_ = false;
  }
  UpdateTimer();
}

void DesktopLyrics::SetLocked(bool locked) {
  if (locked == locked_) {
    return;
  }
  locked_ = locked;
  locked_hover_ = false;
  unlock_hot_ = false;
  unlock_pressed_ = false;
  if (!window_) {
    return;
  }
  SetClickThrough(locked);
  if (locked) {
    hovered_ = false;
    hot_button_ = -1;
    pressed_button_ = -1;
  }
  UpdateTimer();
  Render();
}

void DesktopLyrics::SetClickThrough(bool through) {
  const LONG_PTR style = GetWindowLongPtr(window_, GWL_EXSTYLE);
  SetWindowLongPtr(window_, GWL_EXSTYLE,
                   through ? style | WS_EX_TRANSPARENT
                           : style & ~WS_EX_TRANSPARENT);
}

bool DesktopLyrics::OverUnlock(LPARAM lparam) const {
  const float x = static_cast<float>(static_cast<short>(LOWORD(lparam)));
  const float y = static_cast<float>(static_cast<short>(HIWORD(lparam)));
  return x >= unlock_rect_.left && x < unlock_rect_.right &&
         y >= unlock_rect_.top && y < unlock_rect_.bottom;
}

void DesktopLyrics::PollLocked() {
  POINT cursor;
  RECT r;
  if (!GetCursorPos(&cursor) || !GetWindowRect(window_, &r)) {
    return;
  }
  const bool inside = PtInRect(&r, cursor) != 0;
  const bool over =
      inside && OverUnlock(MAKELPARAM(cursor.x - r.left, cursor.y - r.top));
  if (over != unlock_hot_) {
    SetClickThrough(!over);
  }
  if (!over && unlock_pressed_ && GetCapture() != window_) {
    unlock_pressed_ = false;
  }
  locked_hover_ = inside;
  unlock_hot_ = over;
  Render();
}

void DesktopLyrics::EnsureWindow() {
  if (window_) {
    return;
  }
  static const bool registered = [] {
    WNDCLASS window_class = {};
    window_class.lpfnWndProc = WndProc;
    window_class.hInstance = GetModuleHandle(nullptr);
    window_class.hCursor = LoadCursor(nullptr, IDC_ARROW);
    window_class.lpszClassName = kClassName;
    return RegisterClass(&window_class) != 0;
  }();
  if (!registered) {
    return;
  }
  // A saved position no longer on any screen (monitor unplugged) is dropped.
  if (position_) {
    const POINT p = *position_;
    if (!MonitorFromPoint(p, MONITOR_DEFAULTTONULL)) {
      position_.reset();
    }
  }
  const HMONITOR monitor =
      position_ ? MonitorFromPoint(*position_, MONITOR_DEFAULTTONEAREST)
                : MonitorFromPoint({0, 0}, MONITOR_DEFAULTTOPRIMARY);
  dpi_ = FlutterDesktopGetDpiForMonitor(monitor);
  Layout();
  POINT origin;
  if (position_) {
    origin = *position_;
  } else {
    MONITORINFO info = {sizeof(info)};
    GetMonitorInfo(monitor, &info);
    const RECT& work = info.rcWork;
    origin = {(work.left + work.right - width_) / 2,
              work.bottom - height_ - Px(kDefaultMargin)};
  }
  window_ = CreateWindowEx(
      WS_EX_LAYERED | WS_EX_TOPMOST | WS_EX_TOOLWINDOW | WS_EX_NOACTIVATE |
          (locked_ ? WS_EX_TRANSPARENT : 0),
      kClassName, L"Kanade", WS_POPUP, origin.x, origin.y, width_, height_,
      nullptr, nullptr, GetModuleHandle(nullptr), this);
  if (!window_) {
    return;
  }
  const UINT dpi = GetDpiForWindow(window_);
  if (dpi != dpi_) {
    dpi_ = dpi;
    Layout();
  }
  RECT r;
  GetWindowRect(window_, &r);
  MoveTo(r.left, r.top);
}

void DesktopLyrics::Layout() {
  if (!d2d_ || !dwrite_) {
    return;
  }
  const float row = font_size_ * kRowHeight;
  const RECT work = WorkArea();
  width_ = std::min(Px(kWidth),
                    static_cast<int>((work.right - work.left) * 0.9f));
  float lyrics = single_line_ ? row : row * 2;
  if (translation_ || romaji_) {
    lyrics = std::max(lyrics, row + row * kSubScale * (translation_ + romaji_));
  }
  height_ = Px(kToolbarHeight + lyrics + kBottomPadding);
  frame_.Resize(width_, height_);

  text_format_.Reset();
  dwrite_->CreateTextFormat(L"Microsoft YaHei UI", nullptr,
                            DWRITE_FONT_WEIGHT_BOLD, DWRITE_FONT_STYLE_NORMAL,
                            DWRITE_FONT_STRETCH_NORMAL,
                            font_size_ * dpi_ / 96.0f, L"zh-cn", &text_format_);
  if (text_format_) {
    text_format_->SetWordWrapping(DWRITE_WORD_WRAPPING_NO_WRAP);
  }
  sub_format_.Reset();
  dwrite_->CreateTextFormat(L"Microsoft YaHei UI", nullptr,
                            DWRITE_FONT_WEIGHT_BOLD, DWRITE_FONT_STYLE_NORMAL,
                            DWRITE_FONT_STRETCH_NORMAL,
                            font_size_ * kSubScale * dpi_ / 96.0f, L"zh-cn",
                            &sub_format_);
  if (sub_format_) {
    sub_format_->SetWordWrapping(DWRITE_WORD_WRAPPING_NO_WRAP);
  }
  icon_format_.Reset();
  if (icon_fonts_) {
    dwrite_->CreateTextFormat(L"Material Icons", icon_fonts_.Get(),
                              DWRITE_FONT_WEIGHT_NORMAL,
                              DWRITE_FONT_STYLE_NORMAL,
                              DWRITE_FONT_STRETCH_NORMAL,
                              static_cast<float>(Px(kIconSize)), L"",
                              &icon_format_);
  }
  if (icon_format_) {
    icon_format_->SetTextAlignment(DWRITE_TEXT_ALIGNMENT_CENTER);
    icon_format_->SetParagraphAlignment(DWRITE_PARAGRAPH_ALIGNMENT_CENTER);
  }

  // Playback, font size, translation and romaji, then lock and close,
  // centered in the toolbar.
  static const char* const kGroups[][3] = {{"previous", "toggle", "next"},
                                           {"smaller", "bigger"},
                                           {"translation", "romaji"},
                                           {"lock", "close"}};
  const float size = static_cast<float>(Px(kButtonSize));
  const float gap = static_cast<float>(Px(kButtonGap));
  const float group_gap = static_cast<float>(Px(kGroupGap));
  float total = 0;
  for (const auto& group : kGroups) {
    for (const char* id : group) {
      if (id) {
        total += size + gap;
      }
    }
    total += group_gap - gap;
  }
  total -= group_gap;
  float x = (width_ - total) / 2;
  const float y = (Px(kToolbarHeight) - size) / 2 + Px(4);
  buttons_.clear();
  for (const auto& group : kGroups) {
    for (const char* id : group) {
      if (id) {
        buttons_.push_back({id, D2D1::RectF(x, y, x + size, y + size)});
        x += size + gap;
      }
    }
    x += group_gap - gap;
  }
  // Locked, the unlock button takes the lock button's place.
  for (const Button& button : buttons_) {
    if (std::string(button.id) == "lock") {
      unlock_rect_ = button.rect;
    }
  }

  target_.Reset();
  brush_.Reset();
  outline_brush_.Reset();
  // Software, so the window never adds GPU work next to the Flutter view.
  const D2D1_RENDER_TARGET_PROPERTIES props = D2D1::RenderTargetProperties(
      D2D1_RENDER_TARGET_TYPE_SOFTWARE,
      D2D1::PixelFormat(DXGI_FORMAT_B8G8R8A8_UNORM,
                        D2D1_ALPHA_MODE_PREMULTIPLIED));
  if (SUCCEEDED(d2d_->CreateDCRenderTarget(&props, &target_))) {
    target_->SetTextAntialiasMode(D2D1_TEXT_ANTIALIAS_MODE_GRAYSCALE);
    target_->CreateSolidColorBrush(D2D1::ColorF(D2D1::ColorF::White), &brush_);
    target_->CreateSolidColorBrush(D2D1::ColorF(0, 0, 0, 0.7f),
                                   &outline_brush_);
  }
  ++version_;
  last_frame_.reset();
}

RECT DesktopLyrics::WorkArea() const {
  HMONITOR monitor;
  if (window_) {
    monitor = MonitorFromWindow(window_, MONITOR_DEFAULTTONEAREST);
  } else if (position_) {
    monitor = MonitorFromPoint(*position_, MONITOR_DEFAULTTONEAREST);
  } else {
    monitor = MonitorFromPoint({0, 0}, MONITOR_DEFAULTTOPRIMARY);
  }
  MONITORINFO info = {sizeof(info)};
  GetMonitorInfo(monitor, &info);
  return info.rcWork;
}

void DesktopLyrics::MoveTo(int x, int y) {
  RECT target = {x, y, x + width_, y + height_};
  MONITORINFO info = {sizeof(info)};
  GetMonitorInfo(MonitorFromRect(&target, MONITOR_DEFAULTTONEAREST), &info);
  const RECT& work = info.rcWork;
  x = std::clamp(x, static_cast<int>(work.left),
                 std::max(static_cast<int>(work.left),
                          static_cast<int>(work.right) - width_));
  y = std::clamp(y, static_cast<int>(work.top),
                 std::max(static_cast<int>(work.top),
                          static_cast<int>(work.bottom) - height_));
  position_ = POINT{x, y};
  if (window_) {
    SetWindowPos(window_, nullptr, x, y, width_, height_,
                 SWP_NOZORDER | SWP_NOACTIVATE);
  }
}

void DesktopLyrics::SetFontSize(int size) {
  size = std::clamp(size, kMinFontSize, kMaxFontSize);
  if (size == font_size_) {
    return;
  }
  font_size_ = size;
  Relayout();
}

void DesktopLyrics::Relayout() {
  if (!window_) {
    return;
  }
  // Grows and shrinks around the bottom center, where it usually sits.
  RECT before;
  GetWindowRect(window_, &before);
  Layout();
  MoveTo((before.left + before.right - width_) / 2, before.bottom - height_);
  Render();
}

void DesktopLyrics::Press(const char* id) {
  const std::string action = id;
  if (action == "previous" || action == "toggle" || action == "next") {
    on_action_(id);
    return;
  }
  if (action == "smaller" || action == "bigger") {
    SetFontSize(font_size_ + (action == "bigger" ? kFontStep : -kFontStep));
  } else if (action == "translation") {
    translation_ = !translation_;
    Relayout();
  } else if (action == "romaji") {
    romaji_ = !romaji_;
    Relayout();
  } else if (action == "lock") {
    SetLocked(true);
  } else if (action == "close") {
    SetVisible(false);
  }
  on_state_();
}

int DesktopLyrics::HitButton(LPARAM lparam) const {
  const float x = static_cast<float>(static_cast<short>(LOWORD(lparam)));
  const float y = static_cast<float>(static_cast<short>(HIWORD(lparam)));
  for (size_t i = 0; i < buttons_.size(); ++i) {
    const D2D1_RECT_F& r = buttons_[i].rect;
    if (x >= r.left && x < r.right && y >= r.top && y < r.bottom) {
      return static_cast<int>(i);
    }
  }
  return -1;
}

void DesktopLyrics::UpdateTimer() {
  if (!window_) {
    return;
  }
  if (visible_ && playing_) {
    SetTimer(window_, kFrameTimer, USER_TIMER_MINIMUM, nullptr);
  } else {
    KillTimer(window_, kFrameTimer);
  }
  if (visible_ && locked_) {
    SetTimer(window_, kLockedTimer, kLockedPollMs, nullptr);
  } else {
    KillTimer(window_, kLockedTimer);
  }
}

int DesktopLyrics::Px(float dip) const {
  return static_cast<int>(std::lround(dip * dpi_ / 96.0f));
}

int64_t DesktopLyrics::Position() const {
  if (!playing_) {
    return base_position_;
  }
  return base_position_ +
         std::chrono::duration_cast<std::chrono::milliseconds>(
             std::chrono::steady_clock::now() - base_time_)
             .count();
}

int DesktopLyrics::CurrentLine(int64_t position) const {
  const auto it = std::upper_bound(
      lines_.begin(), lines_.end(), position,
      [](int64_t p, const Line& line) { return p < line.time; });
  return static_cast<int>(it - lines_.begin()) - 1;
}

void DesktopLyrics::RenderSlot(Slot& slot, int line, Part part) {
  slot.line = line;
  slot.version = version_;
  slot.width = 0;
  slot.char_x.clear();
  static const std::wstring kNone;
  const std::wstring& text = line == kTitle  ? title_
                             : line < 0      ? kNone
                             : part == kRoma  ? lines_[line].roma
                             : part == kTrans ? lines_[line].trans
                                              : lines_[line].text;
  IDWriteTextFormat* format =
      part == kText ? text_format_.Get() : sub_format_.Get();
  if (text.empty() || !format || !target_) {
    return;
  }
  ComPtr<IDWriteTextLayout> layout;
  if (FAILED(dwrite_->CreateTextLayout(text.c_str(),
                                       static_cast<UINT32>(text.size()), format,
                                       100000.f, static_cast<float>(height_),
                                       &layout))) {
    return;
  }
  DWRITE_TEXT_METRICS metrics;
  layout->GetMetrics(&metrics);
  const float stroke = std::max(1.0f, format->GetFontSize() / 17);
  const float left = std::ceil(stroke) + 1;
  const int width = static_cast<int>(
      std::ceil(metrics.widthIncludingTrailingWhitespace + left * 2));
  const int height =
      Px(font_size_ * kRowHeight * (part == kText ? 1 : kSubScale));
  if (!slot.sung.Resize(width, height) || !slot.unsung.Resize(width, height)) {
    return;
  }
  const float top = std::round((height - metrics.height) / 2);
  const RECT bounds = {0, 0, width, height};
  for (auto [surface, color] :
       {std::pair{&slot.unsung, unsung_}, std::pair{&slot.sung, sung_}}) {
    target_->BindDC(surface->dc, &bounds);
    target_->BeginDraw();
    target_->Clear(D2D1::ColorF(0, 0, 0, 0));
    brush_->SetColor(ColorF(color));
    OutlineRenderer renderer(d2d_.Get(), target_.Get(), brush_.Get(),
                             outline_brush_.Get(), stroke_.Get(), stroke);
    layout->Draw(nullptr, &renderer, left, top);
    if (target_->EndDraw() == D2DERR_RECREATE_TARGET) {
      Layout();
      return;
    }
  }
  GdiFlush();
  slot.width = width;
  slot.char_x.resize(text.size() + 1);
  for (UINT32 i = 0; i < text.size(); ++i) {
    float x, y;
    DWRITE_HIT_TEST_METRICS hit;
    layout->HitTestTextPosition(i, FALSE, &x, &y, &hit);
    slot.char_x[i] = left + x;
  }
  slot.char_x[text.size()] = left + metrics.widthIncludingTrailingWhitespace;
}

float DesktopLyrics::FillEdge(const Slot& slot, int64_t position) const {
  if (slot.line < 0 || slot.char_x.empty()) {
    return -1;
  }
  const Line& line = lines_[slot.line];
  const float start = slot.char_x.front();
  const float end = slot.char_x.back();
  if (line.words.empty()) {
    // Same as the player page: a long gap to the next line counts as 6s.
    const int64_t next = static_cast<size_t>(slot.line + 1) < lines_.size()
                             ? lines_[slot.line + 1].time
                             : line.time + 5000;
    const double span =
        std::clamp(static_cast<double>(next - line.time), 800.0, 6000.0);
    const double p = std::clamp((position - line.time) / span, 0.0, 1.0);
    return static_cast<float>(start + (end - start) * p);
  }
  double chars = 0;
  for (const Word& w : line.words) {
    if (position < w.start) {
      break;
    }
    if (position >= w.start + w.duration || w.duration <= 0) {
      chars += w.length;
      continue;
    }
    chars += w.length * static_cast<double>(position - w.start) / w.duration;
    break;
  }
  const double last = static_cast<double>(slot.char_x.size() - 1);
  chars = std::clamp(chars, 0.0, last);
  const size_t i = static_cast<size_t>(chars);
  if (i >= slot.char_x.size() - 1) {
    return end;
  }
  return static_cast<float>(slot.char_x[i] +
                            (slot.char_x[i + 1] - slot.char_x[i]) * (chars - i));
}

int DesktopLyrics::SlotX(const Slot& slot, int fit, float edge,
                         float progress) const {
  const int pad = Px(kPadding);
  const int avail = width_ - pad * 2;
  if (slot.width <= avail) {
    return fit;
  }
  const float overflow = static_cast<float>(slot.width - avail);
  const float offset =
      edge >= 0 ? std::clamp(edge - avail * kScrollAnchor, 0.0f, overflow)
                : overflow * std::clamp(progress, 0.0f, 1.0f);
  return pad - static_cast<int>(std::lround(offset));
}

void DesktopLyrics::DrawSlot(const Slot& slot, int x0, int y0, float edge) {
  if (slot.width == 0) {
    return;
  }
  const int clip_left = Px(kPadding / 3);
  const int clip_right = width_ - clip_left;
  const int from = std::max(0, clip_left - x0);
  const int to = std::min(slot.width, clip_right - x0);
  const float soft = static_cast<float>(Px(kEdgeWidth));
  for (int y = 0; y < slot.sung.height; ++y) {
    const int dy = y0 + y;
    if (dy < 0 || dy >= height_) {
      continue;
    }
    uint32_t* out = frame_.bits + static_cast<size_t>(dy) * width_;
    const uint32_t* unsung = slot.unsung.bits + static_cast<size_t>(y) * slot.width;
    const uint32_t* sung = slot.sung.bits + static_cast<size_t>(y) * slot.width;
    for (int x = from; x < to; ++x) {
      // Share of this pixel the fill has passed, across the soft edge.
      const float t = (edge - (x + 0.5f)) / soft + 0.5f;
      uint32_t src;
      if (t >= 1) {
        src = sung[x];
      } else if (t <= 0) {
        src = unsung[x];
      } else {
        src = Mix(unsung[x], sung[x], static_cast<uint32_t>(t * 256));
      }
      if (src >> 24) {
        out[x0 + x] = Over(src, out[x0 + x]);
      }
    }
  }
}

void DesktopLyrics::DrawToolbar() {
  if (!icon_format_) {
    return;
  }
  for (size_t i = 0; i < buttons_.size(); ++i) {
    const Button& button = buttons_[i];
    const D2D1_RECT_F& r = button.rect;
    std::string name = button.id;
    const bool on = (name == "translation" && translation_) ||
                    (name == "romaji" && romaji_);
    const float fill = static_cast<int>(i) != hot_button_ ? (on ? 0.1f : 0)
                       : pressed_button_ == hot_button_   ? 0.28f
                                                          : 0.16f;
    if (fill > 0) {
      brush_->SetColor(D2D1::ColorF(1, 1, 1, fill));
      const float radius = (r.right - r.left) / 2;
      target_->FillEllipse(
          D2D1::Ellipse(D2D1::Point2F(r.left + radius, r.top + radius), radius,
                        radius),
          brush_.Get());
    }
    if (name == "toggle") {
      name = playing_ ? "pause" : "play";
    }
    const auto glyph = icons_.find(name);
    if (glyph == icons_.end()) {
      continue;
    }
    brush_->SetColor(on ? ColorF(sung_) : D2D1::ColorF(D2D1::ColorF::White));
    target_->DrawText(glyph->second.c_str(),
                      static_cast<UINT32>(glyph->second.size()),
                      icon_format_.Get(), r, brush_.Get());
  }
}

void DesktopLyrics::DrawUnlock() {
  const D2D1_RECT_F& r = unlock_rect_;
  const float radius = (r.right - r.left) / 2;
  brush_->SetColor(D2D1::ColorF(0, 0, 0, unlock_hot_ ? 0.8f : 0.55f));
  target_->FillEllipse(
      D2D1::Ellipse(D2D1::Point2F(r.left + radius, r.top + radius), radius,
                    radius),
      brush_.Get());
  const auto glyph = icons_.find("unlock");
  if (!icon_format_ || glyph == icons_.end()) {
    return;
  }
  brush_->SetColor(D2D1::ColorF(D2D1::ColorF::White));
  target_->DrawText(glyph->second.c_str(),
                    static_cast<UINT32>(glyph->second.size()),
                    icon_format_.Get(), r, brush_.Get());
}

void DesktopLyrics::Render() {
  if (!window_ || !visible_ || !frame_.bits || !target_) {
    return;
  }
  const int64_t position = Position();
  int rows[kSlots] = {kEmpty, kEmpty, kEmpty, kEmpty};
  int active = -1;
  const bool roma = romaji_ && has_roma_;
  const bool trans = translation_ && has_trans_;
  const bool single = single_line_ || roma || trans;
  if (lines_.empty()) {
    rows[0] = kTitle;
  } else if (single) {
    // The current line alone, the first one before it starts.
    const int current = CurrentLine(position);
    const int line = std::max(current, 0);
    rows[0] = line;
    active = current >= 0 ? 0 : -1;
    rows[2] = roma ? line : kEmpty;
    rows[3] = trans ? line : kEmpty;
  } else {
    // Two rows take turns: while one is sung the other shows the next line.
    const int current = CurrentLine(position);
    if (current < 0) {
      rows[0] = 0;
      rows[1] = 1;
    } else {
      active = current % 2;
      rows[active] = current;
      rows[1 - active] = current + 1;
    }
    for (int& row : rows) {
      if (row >= static_cast<int>(lines_.size())) {
        row = kEmpty;
      }
    }
  }
  for (int i = 0; i < kSlots; ++i) {
    if (slots_[i].line != rows[i] || slots_[i].version != version_) {
      RenderSlot(slots_[i], rows[i], i < 2 ? kText : i == 2 ? kRoma : kTrans);
    }
  }
  const float edge = active >= 0 ? FillEdge(slots_[active], position) : -1;
  const bool toolbar = hovered_ && !locked_;
  const int overlay = toolbar                    ? 1
                      : locked_ && locked_hover_ ? 2 + unlock_hot_
                                                 : 0;
  const FrameKey key = {{rows[0], rows[1], rows[2], rows[3]},
                        std::lround(edge * 4),
                        overlay,
                        hot_button_ * 2 + (pressed_button_ == hot_button_),
                        playing_,
                        version_};
  if (last_frame_ == key) {
    return;
  }
  last_frame_ = key;

  const RECT bounds = {0, 0, width_, height_};
  target_->BindDC(frame_.dc, &bounds);
  target_->BeginDraw();
  // Unlocked, the nearly invisible background keeps the whole window under
  // the mouse; layered windows only get clicks on pixels that aren't clear.
  target_->Clear(D2D1::ColorF(0, 0, 0, locked_ ? 0 : 1 / 255.f));
  if (toolbar) {
    brush_->SetColor(D2D1::ColorF(0, 0, 0, 0.55f));
    const float radius = static_cast<float>(Px(kCornerRadius));
    target_->FillRoundedRectangle(
        D2D1::RoundedRect(D2D1::RectF(0, 0, static_cast<float>(width_),
                                      static_cast<float>(height_)),
                          radius, radius),
        brush_.Get());
    DrawToolbar();
  } else if (overlay >= 2) {
    DrawUnlock();
  }
  if (target_->EndDraw() == D2DERR_RECREATE_TARGET) {
    Layout();
    return;
  }
  GdiFlush();

  // Romaji and translation scroll along with the fill of the line above.
  float progress = 0;
  if (edge >= 0 && slots_[0].char_x.size() > 1) {
    const float start = slots_[0].char_x.front();
    const float end = slots_[0].char_x.back();
    progress = (edge - start) / std::max(1.0f, end - start);
  }
  const Align align =
      single && align_ == Align::kStagger ? Align::kCenter : align_;
  const int pad = Px(kPadding);
  const int top = Px(kToolbarHeight);
  const int row_height = Px(font_size_ * kRowHeight);
  const int sub_height = Px(font_size_ * kRowHeight * kSubScale);
  const int y[kSlots] = {top, top + row_height, top + row_height,
                         top + row_height + (roma ? sub_height : 0)};
  for (int i = 0; i < kSlots; ++i) {
    const Slot& slot = slots_[i];
    int fit;
    if (slot.line == kTitle || align == Align::kCenter) {
      fit = (width_ - slot.width) / 2;
    } else if (align == Align::kLeft || (align == Align::kStagger && i == 0)) {
      fit = pad;
    } else if (align == Align::kRight) {
      fit = width_ - pad - slot.width;
    } else {
      // Staggered second row: a little right of the first, so short lines stay
      // close, but never past the right edge.
      fit = std::min(pad + Px(font_size_ * kStaggerIndent),
                     width_ - pad - slot.width);
    }
    const float slot_edge = i == active ? edge : -1;
    DrawSlot(slot, SlotX(slot, fit, slot_edge, i >= 2 ? progress : 0), y[i],
             slot_edge);
  }
  POINT source = {0, 0};
  SIZE size = {width_, height_};
  BLENDFUNCTION blend = {AC_SRC_OVER, 0, 255, AC_SRC_ALPHA};
  UpdateLayeredWindow(window_, nullptr, nullptr, &size, frame_.dc, &source, 0,
                      &blend, ULW_ALPHA);
}

LRESULT CALLBACK DesktopLyrics::WndProc(HWND window, UINT message,
                                        WPARAM wparam, LPARAM lparam) {
  if (message == WM_NCCREATE) {
    const auto* create = reinterpret_cast<const CREATESTRUCT*>(lparam);
    SetWindowLongPtr(window, GWLP_USERDATA,
                     reinterpret_cast<LONG_PTR>(create->lpCreateParams));
  }
  auto* self =
      reinterpret_cast<DesktopLyrics*>(GetWindowLongPtr(window, GWLP_USERDATA));
  if (self && self->window_ == window) {
    if (const auto result = self->HandleMessage(message, wparam, lparam)) {
      return *result;
    }
  }
  return DefWindowProc(window, message, wparam, lparam);
}

std::optional<LRESULT> DesktopLyrics::HandleMessage(UINT message, WPARAM wparam,
                                                    LPARAM lparam) {
  switch (message) {
    case WM_MOUSEACTIVATE:
      return MA_NOACTIVATE;
    case WM_SETCURSOR:
      if (LOWORD(lparam) == HTCLIENT) {
        SetCursor(LoadCursor(
            nullptr, locked_ || hot_button_ >= 0 ? IDC_HAND : IDC_SIZEALL));
        return TRUE;
      }
      break;
    case WM_MOUSEMOVE: {
      if (locked_) {
        return 0;
      }
      if (!hovered_) {
        hovered_ = true;
        TRACKMOUSEEVENT track = {sizeof(track), TME_LEAVE, window_, 0};
        TrackMouseEvent(&track);
      }
      hot_button_ = HitButton(lparam);
      Render();
      return 0;
    }
    case WM_MOUSELEAVE:
      hovered_ = false;
      hot_button_ = -1;
      pressed_button_ = -1;
      Render();
      return 0;
    case WM_LBUTTONDOWN: {
      if (locked_) {
        if (OverUnlock(lparam)) {
          unlock_pressed_ = true;
          SetCapture(window_);
        }
        return 0;
      }
      const int hit = HitButton(lparam);
      if (hit >= 0) {
        pressed_button_ = hit;
        SetCapture(window_);
        Render();
      } else {
        // Moves the window in the system's own drag loop.
        ReleaseCapture();
        SendMessage(window_, WM_NCLBUTTONDOWN, HTCAPTION, 0);
      }
      return 0;
    }
    case WM_LBUTTONUP: {
      if (unlock_pressed_) {
        ReleaseCapture();
        unlock_pressed_ = false;
        if (locked_ && OverUnlock(lparam)) {
          SetLocked(false);
          on_state_();
        }
        return 0;
      }
      if (pressed_button_ < 0) {
        break;
      }
      ReleaseCapture();
      const int pressed = pressed_button_;
      pressed_button_ = -1;
      if (HitButton(lparam) == pressed) {
        Press(buttons_[pressed].id);
      }
      Render();
      return 0;
    }
    case WM_EXITSIZEMOVE: {
      RECT r;
      GetWindowRect(window_, &r);
      position_ = POINT{r.left, r.top};
      on_state_();
      return 0;
    }
    case WM_TIMER:
      if (wparam == kFrameTimer) {
        Render();
        return 0;
      }
      if (wparam == kLockedTimer) {
        PollLocked();
        return 0;
      }
      break;
    case WM_DPICHANGED: {
      dpi_ = HIWORD(wparam);
      const auto* suggested = reinterpret_cast<const RECT*>(lparam);
      Layout();
      position_ = POINT{suggested->left, suggested->top};
      SetWindowPos(window_, nullptr, suggested->left, suggested->top, width_,
                   height_, SWP_NOZORDER | SWP_NOACTIVATE);
      Render();
      return 0;
    }
    case WM_DISPLAYCHANGE: {
      RECT r;
      GetWindowRect(window_, &r);
      Layout();
      MoveTo(r.left, r.top);
      Render();
      return 0;
    }
  }
  return std::nullopt;
}
