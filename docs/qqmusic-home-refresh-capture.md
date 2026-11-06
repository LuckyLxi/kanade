# QQ 音乐：首页整页刷新与单栏刷新

观察日期：2026-11-06（北京时间）。MuMu 15 中的官方 Android QQ 音乐 20.09（`QQMusic 20090808`，已登录），
用 `scripts/capture-qqmusic-android.mjs --prepare` 经 Fiddler 抓包，结束后 `--restore`。操作由 adb 驱动，依次是：

1. 13:41:52 强制停止后冷启动；
2. 13:42:16 点「听「…」的也在听」右侧的刷新按钮；
3. 13:42:21 点「热门节目，听点不一样的」右侧的刷新按钮；
4. 13:42:35 在首页下拉刷新。

## 证据

| 本地材料 | 字节 | SHA-256 |
| --- | --- | --- |
| `qqmusic-home-refresh-20261106.saz` | 11737527 | `4a6e27393d010db4ad4059e56f946162e72bd2ab53576911ad96ede7796abbd0` |
| `qqmusic-home-sections-20261106.saz` | 24711638 | `0eb689b53c33aa591ca429952d586d36340b12de4397797387d97654474091d3` |

文件由现有 `.gitignore` 排除。Fiddler 同时作为系统代理，文件里有大量无关的宿主机流量；Android 请求的公参含 `authst`、Cookie、设备标识，不应提交或公开。
本文不复制 Cookie、`authst`、`sign`、`mask`、设备标识。首页请求为 `raw/482`（冷启动）、`851`、`864`（单栏刷新）、`908`（下拉）。

传输与 `docs/qqmusic-feed-column-capture.md` 相同（`u6.y.qq.com/cgi-bin/musics.fcg`，请求体 5 字节前缀加 zlib），
但这一轮的响应体是 **brotli** 压缩，不是 zlib；请求头一样，没有看到协商字段。

## 请求

四次都是 `music.recommend.RecommendFeed.get_recommend_feed`。

冷启动和下拉刷新完全一样，就是重新取第 1 页：

```json
{"direction": 0, "page": 1, "s_num": 0, "client_time": 1793943718, "v_cache": ["301", "207", "272"], "ext": {"is_20_style": "1", "has_login": "1", …}}
```

单栏刷新在同样的第 1 页请求上加 `refresh_info`，即上一次响应里该栏目的 `refresh_param`；`ext` 另多一个 `module_list`（当前页面上各栏目的 `ModuleID`）：

```json
{
  "refresh_info": {
    "ModuleID": "minister@2@10731", "Page": 1, "ShelfID": "207", "LayoutTrace": "",
    "LayoutSeq": "8:1793943719#0:3#recforyou@0@0,minister@2@10731,podcast@1@0",
    "ExtraInfo": {"refresh_param": "new", "abt": "…", "layout_seq": "…", "layout_trace": "…", "moduleID": "…", "tjreport": "21_67", "type": "207", …}
  },
  "direction": 0, "page": 1, "s_num": 0, "v_cache": ["301", "207", "272"],
  "ext": {"module_list": "minister@2@10731,podcast@1@0", …}
}
```

官方往 `ExtraInfo` 里补了栏目上的 `abt`、`tjreport`、`trace` 等统计字段；实测原样带回 `refresh_param` 就够（见下）。

## 响应

| 请求 | 栏目 |
| --- | --- |
| 冷启动 / 下拉 | `301`「Hi {昵称} 今日为你推荐」（每日30首、猜你喜欢等入口，`refresh_param` 的 `ModuleID` 为空）、`207` 歌曲 36 首、`272` 有声节目 18 个 |
| 刷新 207 | 只有 `207`，标题也换了（「听「eufonius」的也在听」→「「Chinatsu」，这是你的宝藏好歌」，`ModuleID` 从 `minister@2@10731` 变为 `minister@5@liked_songs`） |
| 刷新 272 | 只有 `272`，18 个新节目 |

每次响应里栏目都带新的 `refresh_param`，下次刷新用新的。下拉后各栏的内容和主题都变了。

## 第 2 页：另外两个歌曲栏目

14:25 又抓了一轮（`qqmusic-home-sections-20261106.saz`，同样不提交）：冷启动后连续上滑。官方首页一共有三个歌曲栏目，
第 1 页（`raw/1060`）只有 301、207、272，上滑时第 2 页（`raw/1391`）才带来另外两个 207 和专属乐流的第一批：

```json
{"direction": 1, "page": 2, "s_num": 3, "v_cache": ["301", "207", "272"], "v_uniq": [], "ext": {"is_20_style": "1", "has_login": "1", …}}
```

- `v_cache` 是第 1 页的栏目 id，`s_num` 是已经显示的栏目数；`ext` 里没有专属乐流翻页用的 `TwoColPages_proxy` 等字段。
- 返回 207「听「…」的也在听」、207「「昵称」，这是你的惊喜好歌」、315「「昵称」的专属乐流」（8 张卡）。两个 207 都带 `refresh_param`（`Page` 为 2）。
- 第 3、4 页（`raw/1420`、`1498`）只有 315，`v_cache` 加上 315，`s_num` 为 6、7。

Kanade 用同样的参数请求第 2 页，也拿到两个歌曲栏目；把它们的 `refresh_param` 放进第 1 页请求的 `refresh_info`，同样只返回这一栏的新内容。
刷新偶尔返回空标题（`title_template` 为 `{String}`、`title_content` 为空），界面用默认标题。

## Kanade 实测

用 Kanade 登录态的数据库副本，直接请求 `musicu.fcg` 的明文 JSON：

| 公参 | 结果 |
| --- | --- |
| PC 内嵌页 `ct=20`（Kanade 原来的首页） | 栏目 301、207、272、271，`refresh_param` 全部为空；带 `refresh_info` 时服务端忽略，仍返回整页，但每次请求所有栏目内容都换新 |
| Android `cv=v=20090808`、`chid=73387`，`ext` 带 `is_20_style`、`has_login` | 栏目 301、207、272，207 和 272 有 `refresh_param`；原样带回后只返回该栏的新内容 |
| 同上，不带 `ext` | 栏目相同，但 `refresh_param` 全部为空 |
| 同上，未登录（`has_login=0`） | 栏目更多（301、207、302、271、207、272、276、114），`refresh_param` 全部为空 |

Kanade 的首页改用 Android 公参（`qq::music::recommend_feed`），每次进 App、整页刷新都重新请求、不缓存；
能单独刷新的栏目（`ModuleID` 不为空）把 `refresh_param` 交给界面，刷新时原样带回（`refresh_recommend_section`）。
登录后的栏目组合每次不同：多数是 301、207、272，有时有 271「你的歌单补给站」（这时它也带 `refresh_param`）；272 是有声节目，Kanade 本来就不显示。
用 `integration_test/home_refresh_test.dart` 在 Windows 版里实测了顶部刷新键、歌曲栏刷新、专属乐流刷新，三者都换了内容；两次冷启动的首页内容也不同。

专属乐流（315）的刷新没有用 `refresh_info`：Kanade 从专栏第 1 页重新取，把之前看过的卡片都放进 `v_uniq`，实测返回的 8 张全是新卡。
