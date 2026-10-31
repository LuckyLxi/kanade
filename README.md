# Kanade

一个用 Flutter + Rust 写的 QQ 音乐第三方客户端（个人学习用途）。

- **Flutter**：界面，以及基于 media_kit（libmpv）的音频播放
- **Rust**（通过 flutter_rust_bridge 2.12）：网络请求、`zzc` 签名、登录、SQLite 缓存、歌词解析

QQ 音乐上游接口的请求方式、参数、返回路径及验证边界见 [接口参考](docs/qqmusic-api.md)。

## 功能

| 功能 | 状态 |
| --- | --- |
| 推荐歌单、排行榜 | ✅ 不登录也能用 |
| 分类搜索 | ✅ 歌曲、歌手、专辑、歌单、视频、歌词、用户七类，均支持分页；未登录时歌曲沿用旧接口，其余用 PC 搜索 |
| MV | ✅ 360P–1080P 可切换，Windows 上已验证播放；付费 MV 未验证 |
| 用户主页 | ✅ 资料和公开歌单（分页），从用户搜索进入 |
| 在线播放 | ✅ 登录后使用 PC 取链接接口，未登录沿用原实现；音质按选定档位逐级降级 |
| 音质菜单 | ✅ 按当前歌曲的 QQ 音质信息和账号实际可播放性动态生成 |
| 歌词 + 翻译 | ✅ 当前行高亮，点击某行跳转到对应时间 |
| QQ / 微信扫码登录 | ⚠️ 已实现，二维码和轮询已验证，扫码后的流程需要真实账号验证 |
| QQ 音乐 App 授权登录 | ⚠️ Android 会话、二维码和 MQTT 订阅已验证，最终凭证交换待真实授权验证 |
| Cookie 登录（备用） | ⚠️ 已实现，需要真实账号验证 |
| 我的歌单（创建的 + 收藏的） | ⚠️ 已实现，需要登录后验证 |

能播放哪些歌，取决于你账号本身的权限。未登录时会员歌曲拿不到播放链接，播放器会自动跳过。
本项目只请求官方提供的普通音频格式，不处理任何加密格式。

PC 搜索和取播放链接使用 `ct=19`、`cv=2276`、独立的持久化 32 位 GUID。
搜索方法为 `music.search.SearchCgiService.DoSearchForQQMusicDesktop`，请求结构来自官方客户端抓包，
通过客户端内置的 `https://u6.y.qq.com/cgi-bin/musicu.fcg` 网关发送。
PC 匿名搜索复现不稳定，因此未登录时保留原接口，登录后使用 PC 接口。
本次回归中，原未登录 `client_search_cp` 接口直接请求也返回 HTTP 500，当前可用性未通过验证。
取链接方法为客户端 DLL 中的 `music.vkey.GetVkey.UrlGetVkey`，已用普通歌曲验证音频读取。
抓包中实际使用的 `musics.fcg` 携带另一套 `Sign` / `Mask` 请求头，其生成算法尚未实现。
当前完成搜索和取播放链接迁移，歌词、歌单和登录仍使用原有实现。
本地 HAR 包含登录凭据，应用运行时不依赖它；PC 冒烟测试通过 `QQMUSIC_TEST_HAR` 显式指定该文件，
只把登录态放入测试进程的内存数据库。

QQ 音乐 App 授权流程对照 [YAQMC 使用的 qm-api-rs](https://github.com/YAQMC/qm-api-rs/blob/bab630d44901f80cae47dd0f09314950d0028e23/src/modules/login.rs)：
先申请 Android `uid/sid`，二维码申请与临时凭证交换使用同一会话和客户端版本；
MQTT 订阅成功后才提供授权入口，凭证交换失败时保留原登录态。未使用随机 QIMEI 代替服务端设备凭据。

音质菜单读取 QQ 返回的歌曲文件信息，仅列出文件大小大于零的已识别档位，再批量获取当前账号的
播放授权，并通过 CDN HEAD 请求核验文件是否可访问。主菜单按母带、Hi-Res、臻品音质、无损、
高品质、标准、流畅等音质档位展示，不把额外的 AAC / OGG 编码和码率单独列成音质档位；
名称和格式编码使用本地映射，歌曲实际提供哪些档位由接口数据决定。
菜单只显示当前歌曲实际可播放的档位；无权限、文件不可用、播放器不支持或未通过播放验证的档位不显示。
菜单在切歌及登录状态变化后刷新。

## 目录结构

```
rust/src/
  api/            # 暴露给 Dart 的接口（frb 只扫描这里）
    music.rs      #   函数
    types.rs      #   数据结构
  qq/             # 具体实现
    client.rs     #   reqwest 客户端、musicu 请求、登录态、缓存封装
    sign.rs       #   musics.fcg 签名、hash33
    store.rs      #   SQLite（缓存表 + kv 表）
    music.rs      #   搜索 / 播放链接 / 歌词 / 榜单 / 歌单
    login.rs      #   QQ / 微信扫码 → musickey
    parse.rs      #   JSON → 结构体
    lyric.rs      #   LRC 解析和翻译合并
rust/tests/live.rs  # 调用真实接口的冒烟测试
lib/
  main.dart
  player/player_controller.dart   # 播放队列、media_kit
  auth/auth_controller.dart
  ui/                             # 各个页面
```

## 开发

```bash
# 改了 rust/src/api 下的代码后重新生成绑定
flutter_rust_bridge_codegen generate

# 改了 lib/l10n/*.arb 后重新生成多语言代码（flutter run / pub get 也会自动生成）
flutter gen-l10n

# 运行
flutter run -d windows
flutter run -d <android 设备>

# 已开启 Fiddler（8888）和 FlClash TUN 时，抓 Windows 客户端推荐页，3 分钟后恢复路由
node scripts/capture-qqmusic-fiddler.mjs --capture --recommendations

# 抓播放器关联的歌手、评论、专辑、红心和添加歌单操作，5 分钟后恢复路由
node scripts/capture-qqmusic-fiddler.mjs --capture --player

# Rust 单元测试 / 真实接口冒烟测试
cd rust
cargo test --lib
# PC 测试先设置 QQMUSIC_TEST_HAR 为本地登录抓包的绝对路径
cargo test --test live desktop_ -- --ignored --test-threads=1
cargo test --test live -- --ignored --nocapture --test-threads=1
```

数据（缓存和登录态）保存在 `getApplicationSupportDirectory()/kanade.db`，登录凭据是明文存储的。

## 待做

- Android 后台播放和通知栏控制（audio_service）
- 歌手账号主页的歌曲 / 专辑标签
- 收藏 / 取消收藏、把歌加进歌单
- 逐字歌词（QRC）
