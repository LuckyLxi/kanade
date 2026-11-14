# QQ 音乐：Android 端首页歌单推荐与歌单广场

观察日期：2026-11-14（北京时间）。MuMu 15 中的官方 Android QQ 音乐 20.09（`QQMusic 20090808`），
用 `scripts/capture-qqmusic-android.mjs --prepare` 经 Fiddler 抓包，操作由 adb 驱动，只读。

问题来源：手机版首页有一栏「你的歌单补给站」，微信登录的账号没有，未登录和 QQ 登录有。

## 证据

| 本地材料 | 字节 | SHA-256 |
| --- | --- | --- |
| `qqmusic-playlist-rec-android-20261114.saz` | 21854938 | `c4ba295d244a4e995ea48b08d101ac91808eef2def74363c3955ae87bce2e7ad` |

文件由 `.gitignore` 排除。请求公参含 Cookie 和设备标识，本文不复制这些值。

本轮为了拿到未登录状态，先用 root 把 `/data/data/com.tencent.qqmusic` 和 `/data/user_de/0/com.tencent.qqmusic` 整份 tar 备份，
再清空这两个目录启动 App（没有点「退出登录」，避免服务端注销会话），抓完后还原备份并补回 SELinux 类别，
微信登录状态恢复正常。

对照：同日先在微信登录状态（`comm.tmeLoginType=2`）下抓了一次冷启动，首页 `get_recommend_feed` 只返回
`301`（今日为你推荐）、`114`（排行榜）、`302`、`272`（有声）四个栏目，没有歌单栏目。这份对照没有单独保存。

| 会话 | 操作 |
| --- | --- |
| `raw/0113` | 未登录冷启动，首页第 1 页（`tmeLoginType=0`） |
| `raw/0254`、`0372`、`0486`… | 首页往下滑的第 2 页起，只有至臻专辑（`279`） |
| `raw/0851` | 点「你的歌单补给站」标题进入「分类歌单」页 |
| `raw/1222` | 分类歌单页往下滑，第 3 批（`From=42`） |

## 首页栏目：就是 `get_recommend_feed` 里的一个 shelf

不是独立接口。「你的歌单补给站」是 `music.recommend.RecommendFeed.get_recommend_feed` 第 1 页里 `id=271` 的栏目，
和 Kanade 现在用的首页请求（`rust/src/qq/music.rs` `recommend_feed`，同样的 Android 20.09 公参）是同一个接口。
未登录时第 1 页的栏目顺序：

| shelf `id` | 标题 | 卡片 |
| --- | --- | --- |
| 301 | hi 今日为你打造 | 入口卡（猜你喜欢、每日30首、百万收藏…） |
| 207 | 听「G.E.M.邓紫棋」的也在听 | 歌曲（type 200） |
| 302 | （空） | type -1 占位 |
| 272 | 热门节目，听点不一样的 | 节目（type 400） |
| 276 | 为你精选的AI歌单 | 9 个歌单，type 500 / subtype 2001 |
| 114 | 排行榜 | type 1000 |
| 207 | 大家都在听 | 歌曲 |
| **271** | **你的歌单补给站** | **12 个歌单，type 500 / subtype 0** |

`271` 的 `extra_info.moduleID` 是 `playlist@135@0`，`276` 是 `algotorial@0@0`。

歌单卡字段（type 500）：`id` 是歌单 tid（如 `9722878332`），能直接给 `get_playlist_detail`；`title`、`cover`、
`cnt`（播放数）、`jumptype=10014`；`miscellany.cnt_content`（“169.5W 播放”）、`fav_cnt`、`rcmdtemplate`（“8141人收藏”）；
`tags[].Tag` 是封面左下角的角标（“互动歌单”“累计收藏破1w”“Pop”）。`276` 的 AI 歌单卡另有
`card_extra_info.PlaylistExt[]`（`LayerTitle`、`LayerClassifyTitle` 等封面图层）和 `scheme`（`qqmusic://qq.com/ui/gedan?...`）。

Kanade 的 `recommend_section` 已经保留 type 500 卡片，所以只要服务端返回 `271`，Kanade 首页就会显示这一栏。
微信登录看不到，是服务端没下发这一栏，不是客户端过滤；只抓了一个微信账号，不能断定所有微信账号都这样。
QQ 登录有这一栏是用户在真机上观察到的，本轮没有用 QQ 账号抓包。

## 「更多」：歌单广场 `music.playlist.PlaylistSquare`

`271` 的 `more.scheme` 打开 RN 页面「分类歌单」（Playlists）。页面首屏一次合并请求（`raw/0851`，ct=11）：

| 请求键 | module.method | 参数 |
| --- | --- | --- |
| `tab` | `music.playlist.PlaylistSquare.GetSquareTab` | `From=0`、`Size=8` |
| `gedan` | `music.playlist.PlaylistSquare.GetRecommendWhole` | `IsReqHead=true`、`IsReqFeed=true`、`FeedReq={From:0,Size:21,styleMode:1}` |
| `abt` | `tme_di.abtest.MusicABTest.get_strategy` | 与内容无关 |

往下滑时只发 `GetRecommendWhole`，`IsReqHead=false`、`IsReqResGrade=true`、`FeedReq={From:42,Size:21}`（`raw/1222`）。

- `GetSquareTab`：`data.List[]` 为顶部标签，`TagName/TagType/TagID`：推荐 1/-1、互动歌单 3/3903、AI歌单 5/9527、说唱 3/42、
  国风 3/3420、私藏 3/3419、流行 3/3152、摇滚 3/41。
- `GetRecommendWhole`：`data.HeadRsp.List[]` 是顶部「编辑推荐」轮播（本样本 5 个），`data.FeedRsp.List[]` 是下方三列网格，
  另有 `FeedRsp.HasMore`、`FeedRsp.FromLimit`（400）。每项 `Playlist.basic` 含 `tid`、`title`、`desc`、
  `cover.medium_url`、`creator.nick`、`play_cnt`、`fav_cnt`、`song_cnt`、`v_tag[]`；`WhereFrom` 为“干预”等来源说明。

本轮同时出现 `music.playlist.AiPlCategory.get_ai_category_content`（`category_id=9527`、`last_id`、`size=12`，ct=23 带 `sign`），
对应「AI歌单」分类；不是点击触发的页面请求，可能是 H5 预加载，未进一步确认。

## 通用通道重放（2026-11-14）

不带 Cookie、不签名，向 `https://u.y.qq.com/cgi-bin/musicu.fcg` 发 `comm={ct:24,cv:0}`：

- `GetSquareTab` + `GetRecommendWhole` 全局和业务 code 均为 0，返回 8 个标签、5 个轮播、21 个歌单。
- `From=0/21/42` 各返回 21 个不同的歌单，翻页有效。`HasMore` 只有 `From=0` 时为 `true`，之后都是 `false`，
  所以不能靠 `HasMore` 判断结束，可参考 `FromLimit=400`。
- `comm.ct=11, cv=20090808` 结果相同。

也就是说，歌单广场不依赖登录状态。想让微信登录的账号也看到歌单推荐，可以用这个接口，不用依赖首页 `271` 栏目。
其他标签（`TagType=3` 分类、`TagType=5` AI）的取数请求本轮没有抓到。
