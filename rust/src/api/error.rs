//! 返回给 Dart 的错误码。界面文案由 Dart 侧按语言翻译，`detail` 只放技术信息。
//! Display / From 等实现在 crate::qq::error，避免 frb 扫描。

#[derive(Debug, Clone)]
pub enum ApiError {
    NotLoggedIn,
    /// 所有音质都拿不到播放链接（可能需要登录或会员）。
    NoPlayableUrl,
    /// 播放器暂不支持此格式。
    UnsupportedFormat,
    /// 暂未通过播放验证的格式。
    UnverifiedFormat,
    LoginFailed { detail: String },
    /// Cookie 里缺少必需的字段。
    InvalidCookie { missing: String },
    /// 接口返回了非零错误码。
    ServerError { api: String, code: String },
    /// 响应无法解析或缺少字段。
    BadResponse { detail: String },
    Network { detail: String },
    Internal { detail: String },
}
