# 猜你喜欢与刷歌模式封面取证（交给 Claude）

观察日期：2026-10-29，北京时间。本轮只查抓包、客户端前端代码并写文档，没有修改应用 UI 或业务代码。

## 已确认的封面来源

| 入口 | 封面来源 | 本次结论 |
| --- | --- | --- |
| 刷歌模式 | 推荐卡片 `cover` | 旧推荐响应中已有非空专辑封面 URL；不同响应的 URL 会变化。 |
| 猜你喜欢 | 客户端 `songInfo.pic`，缺失时由 `songInfo.albummid` 生成 | 推荐卡片 `cover` 为空不代表没有图片；官方首页使用推荐歌曲的专辑封面。 |
| 猜你喜欢卡片背景 | 前端 CSS 的 `bg1` 至 `bg6` 图片 | 按客户端本地小时选背景，不来自推荐卡片的 `cover`。 |

下面的图片地址来自成功响应或保留的客户端 JS/CSS，本轮没有重新下载图片或核验 CDN 的当前状态。
歌曲专辑封面是动态数据，不应把某次抓到的专辑 MID 固定成入口的永久封面。

## 刷歌模式

来源：`qqmusic-recommendations.har`，序号从 0 开始。
`req_1` 对应 `music.recommend.RecommendFeed.get_recommend_feed`。

| HAR 序号 | 字段路径 | 实际值 |
| --- | --- | --- |
| 0 | `req_1.data.v_shelf[0].v_niche[0].v_card[2].title` | 刷歌模式 |
| 0 | 同一卡片 `.cover` | `https://y.gtimg.cn/music/photo_new/T002R150x150M000003JWL9n2yN8LB_3.jpg` |
| 8 | 同一卡片 `.cover` | `https://y.gtimg.cn/music/photo_new/T002R150x150M000003wNMso4LuKcU_7.jpg` |
| 0、8 | 同一卡片 `.miscellany.layer_url` | `https://y.qq.com/music/common/upload/t_cm3_photo_publish/4554682.png` |

该卡片 `type=900`、`subtype=991`、`style=15`，scheme 为
`qqmusic://qq.com/ui/jumpToRadarMode`（此处省略跳转参数）。
卡片下标仅用于定位这份样本，不能固定当作所有响应中的位置。
`layer_url` 是额外图片字段，本轮未验证其在当前客户端中的具体叠加规则，不能直接当作主封面。

另有一个不同用途的“刷歌”入口图标：

```text
来源：qqmusic-recent-plays-sync.har，序号 117
module: music.recommend.RecommendWidget
method: GetPCCommonEntryPoint
路径: response["music.recommend.RecommendWidget.GetPCCommonEntryPoint"].data.Selections[0].Cover
Title: 刷歌
Cover: https://y.qq.com/music/common/upload/ocs/17eefb4d2a7b28d91e7acf9b73760e8b.png
ItemType: 1001
ItemSubType: 10041
EntryType: 1
```

这是快捷入口图标，不等同于推荐卡片中的动态专辑封面。

## 猜你喜欢：动态专辑封面

旧推荐 HAR 序号 0、8 的 `v_shelf[0].v_niche[0].v_card[0]`：

```json
{"title":"猜你喜欢-沉浸刷歌","cover":"","type":700,"subtype":711,"style":6,"jumptype":20001}
```

保留的官方前端 JS 解释了这里为何为空。`qqmusic.har` 序号 1462 的
`/n3/wk_v20/entry//recommend.chunk.bdf2a22fe.js` 中，该卡片的流程是：

1. 挂载时调用客户端桥 `queryRadioSongInfo`，参数包含卡片的 radio id。
2. 监听 `radioStatusChange`，仅处理匹配 radio id 且含有效歌曲 MID 的返回。
3. 使用 `songInfo.pic`；当它为空而 `songInfo.albummid` 非空时，调用 `getAlbumPic(albummid)`。
4. 渲染时将图片交给 `recommend_top__cover_img`，而不是读取该卡片的 `cover`。
5. 歌曲图仍为空时，前端使用 `//y.qq.com/mediastyle//music_v17/src/css/img/extra/default_album.png?max-age=38000`。

这是对已保存 JS 的本地静态检查，没有在本轮监听客户端桥事件；不能声称抓到了某次事件实际返回的 `pic`。

`qqmusic.har` 序号 1466 的 `/n3/wk_v20/entry/index.chunk.6f097f4bb.js` 中，
`getAlbumPic` 对有效专辑 MID 的默认尺寸为 300，生成：

```text
https://y.qq.com/music/photo_new/T002R300x300M000<ALBUM_MID>.jpg?max_age=2592000
```

本轮另抓到了真实取歌请求，来源 `qqmusic-covers-playlist-actions.saz`：

```text
请求 / 响应: raw/066_c.txt / raw/066_s.txt
时间: 2026-10-29 21:50:49.706 +08:00
POST https://u6.y.qq.com/cgi-bin/musics.fcg
module: music.radioProxy.MbTrackRadioSvr
method: get_radio_track
请求键: music.radioProxy.MbTrackRadioSvr.get_radio_track
```

```json
{"id":99,"num":5}
```

HTTP 200，网关及请求业务 `code=0`，返回 `data.tracks` 共 5 首，5 首都有非空 `album.mid`。
同一业务 `data` 内的 `bg_pic_url`、`bg_video_url` 均为空字符串，因此不能依赖它们取得这次的背景图。
取歌结果提供了可生成专辑封面的数据；应用选择哪一首作为入口预览，是接入时需要确定的行为，
不能将 `tracks[0]` 直接宣称为本轮已观察到的官方卡片当前歌曲。

Kanade 已有 `rust/src/qq/parse.rs` 的 `album_cover`，使用
`https://y.gtimg.cn/music/photo_new/T002R300x300M000<ALBUM_MID>.jpg`；可以复用它生成应用封面。
本轮只记录复用点，没有修改图片加载或入口展示方式。

## 猜你喜欢：官方背景图片 URL

来源：`qqmusic.har` 序号 1464 的 `/n3/wk_v20/entry/index.0f49380b3.css`。
JS 使用客户端 `new Date().getHours()` 选主题，区间左闭右开：

| 客户端本地小时 | 类名 | 图片 |
| --- | --- | --- |
| 00–05 | bg1 | [bg1](https://y.qq.com/n3/wk_v20/entry/bg1.0976089ae.png?max_age=6048000) |
| 05–12 | bg2 | [bg2](https://y.qq.com/n3/wk_v20/entry/bg2.4c4f4119e.png?max_age=6048000) |
| 12–14 | bg3 | [bg3](https://y.qq.com/n3/wk_v20/entry/bg3.b4cdff76c.png?max_age=6048000) |
| 14–18 | bg4 | [bg4](https://y.qq.com/n3/wk_v20/entry/bg4.1cd049583.png?max_age=6048000) |
| 18–22 | bg5 | [bg5](https://y.qq.com/n3/wk_v20/entry/bg5.e9edd4020.png?max_age=6048000) |
| 22–24 | bg6 | [bg6](https://y.qq.com/n3/wk_v20/entry/bg6.dab9cba46.png?max_age=6048000) |

05–08 和 08–12 的文案不同，但都用 bg2。这些是卡片背景，歌曲专辑图是另一层图片。
CSS 对背景使用 `background-size: cover`；本文只说明官方资源来源，不要求复现布局、交互或动画。

## 顺带补充：本轮真实刷歌取歌请求

```text
SAZ 请求 / 响应: raw/039_c.txt / raw/039_s.txt
时间: 2026-10-29 21:50:47.648 +08:00
module: music.recommend.TrackRelationServer
method: GetRadarSong
请求键: music.recommend.TrackRelationServer.GetRadarSong
业务参数键: LastToastTime、NeedNum、Page、ReqType
观察值: NeedNum=20、Page=2、ReqType=0；LastToastTime 为客户端携带的时间值。
```

HTTP 200，网关及请求业务 `code=0`，返回 `data.VecSongs` 共 20 首，歌曲对象在每项 `.Track`。
响应还包含 `HasMore`、`TimeStamp`、`Toast` 等字段。这里只观察到这一批，不据此推导完整翻页协议。
两个取歌请求都是 PC `ct="19"`、`cv="2276"`、`patch="118"`，并带 Cookie、Sign、Mask；
没有独立重放，也没有验证应用登录凭据或其他网关的兼容性。

## 来源摘要与验证边界

| 文件 | SHA-256 |
| --- | --- |
| `qqmusic.har` | `585d04f15003d42c6740ebee2e3df8768da9bff59261ad6dfecd0359b0b36cae` |
| `qqmusic-recommendations.har` | `a1e0a393514961c9680fc99064363f4095bb1aa0d29d94e5649c486db74ff4e6` |
| `qqmusic-covers-playlist-actions.saz` | `eb4628ecd18612b037144d8619341c76728da3ee7337d77ae19a286c9a8edf46` |

`recommend.chunk.bdf2a22fe.js` 解码正文为 88924 字节，SHA-256：
`81f209f96ae1ef85b96e7bbbdaad00fa4c90fd37bc6057d2e4c3e73ecac01e7f`。
JS/CSS 的流程与资源定位来自普通本地工具静态检查；没有声称观察到客户端桥的实际执行。
推荐 HAR 序号 0、8 的 REA Evidence ID：
`ev_bbe988f2160729f19f3d56db21fdd45c6e3480a16c378567f791e45f461bcdf2`。

新 SAZ 为 561693 字节，含 103 个会话，已加入本机 Git exclude。凭据、播放曲目及追踪值未复制进文档。
本文完成后检查示例 JSON、来源摘要和文档空白；没有应用代码变更，因此未运行 Flutter/Rust 测试。
