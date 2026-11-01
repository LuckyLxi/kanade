> 本项目仅供个人学习和技术交流，与腾讯 / QQ 音乐没有任何关系。
> 所有音乐内容的版权归各自权利人所有；能播放哪些歌完全取决于你自己账号的权限。
> 本项目只请求官方提供的普通音频格式，**不破解、不处理任何加密格式**。

<p align="center">
  <img src="docs/screenshots/desktop.png" width="90%">
</p>
<p align="center">
  <img src="docs/screenshots/desktop-player.png" width="90%">
</p>
<p align="center">
  <img src="docs/screenshots/discover.jpg" width="22%">
  <img src="docs/screenshots/playlist.jpg" width="22%">
  <img src="docs/screenshots/player.jpg" width="22%">
  <img src="docs/screenshots/lyrics.jpg" width="22%">
</p>

## 功能

**发现**
- 推荐页：个性化推荐歌单和歌曲、新歌首发
- 排行榜

**搜索**
- 热搜榜、猜你想搜，搜索联想

**播放**
- 列表循环、单曲循环、随机播放，播放队列，下一首播放
- 音质菜单只显示这首歌在你账号下**真正能播**的档位
- 歌词和翻译：当前行高亮，点某一行就跳到那里；播放器左滑切到歌词
- 查看MV

**账号**
- 我喜欢、最近播放、我的歌单（创建的和收藏的）
- 新建、重命名、删除歌单，把歌加进歌单或从歌单删掉

**歌手、专辑、用户**
- 歌手页：精选、歌曲、专辑、视频、详情，关注
- 用户页：公开的歌单、收藏、我喜欢，关注
- 歌曲评论

上游接口的请求方式、参数、返回结构以及哪些地方已验证 / 未验证，见 [接口参考](docs/qqmusic-api.md)。

### 运行

需要先安装 [Flutter](https://flutter.dev) 和 [Rust](https://rustup.rs)

```bash
git clone https://github.com/LuckyLxi/kanade.git
cd kanade
flutter pub get
flutter run -d windows
```

## 许可证

本项目采用 [GNU General Public License v3.0](LICENSE)（GPL-3.0-only）。第三方代码保留各自的许可证和版权声明。

## 致谢

- [flutter_rust_bridge](https://github.com/fzyzcjy/flutter_rust_bridge)
- [media_kit](https://github.com/media-kit/media-kit)
- [liquid_glass_widgets](https://pub.dev/packages/liquid_glass_widgets)
- [smtc_windows](https://pub.dev/packages/smtc_windows)
- [audio_service](https://pub.dev/packages/audio_service)
- QQ 音乐 App 授权登录流程参考了 [YAQMC/qm-api-rs](https://github.com/YAQMC/qm-api-rs)
