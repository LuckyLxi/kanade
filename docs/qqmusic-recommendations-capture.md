# QQ 音乐 Windows 推荐页抓包核对

来源：本地 `qqmusic-recommendations.har`，共 42 条记录。
SHA-256：`a1e0a393514961c9680fc99064363f4095bb1aa0d29d94e5649c486db74ff4e6`。
本轮推荐请求时间为 2026-10-28 23:53:47 至 23:54:18（北京时间）。
文件另含当日 18:27 至 18:28 的旧搜索等记录，不能当作本轮推荐请求。
下文序号均从 0 开始；未复制 Cookie、账号标识、鉴权参数值或追踪字段值。

## 已确认的接口

这些推荐页请求均发往 `https://u6.y.qq.com/cgi-bin/musics.fcg`，对应请求与业务响应成功。

| HAR 序号 / 请求键 | module.method | 实际返回内容 |
| --- | --- | --- |
| 0、8、13 / req_1 | music.recommend.RecommendFeed.get_recommend_feed | 个性推荐首页区块及下一页区块 |
| 5 / req_1 | music.musicHall.MusicHallPlatformSvr.GetFocus | 焦点图轮播，12 张卡片 |
| 5 / req_2 | playlist.HotRecommendServer.get_new_hot_recommend | 推荐歌单模块，modules 长度为 2 |
| 5 / req_3 | newsong.NewSongServer.get_new_song_info | 新歌数据，songlist 长度为 60 |
| 5 / req_4 | music.longRadio.recommend.GetPCHotRecommend | 热门节目数据，Shelfs 长度为 1 |
| 5 / req_5 | music.area.CategoryArea.getCategoryAreaInCategoryPlaylist | 分类专区 |

## 个性推荐数据结构

主路径为 `req_1.data.v_shelf[].v_niche[].v_card[]`。
区块标题由 `title_template` 与 `title_content` 组合，卡片中包含 `title`、`subtitle`、
`cover`、`type`、`subtype`、`jumptype`、`id`、`miscellany` 等字段。

- 序号 0、8：首页各有 4 个区块。顶部包含 7 张入口卡片，包括猜你喜欢、每日30首、刷歌模式、
  AI 伴听、百万收藏、新歌推荐及杜比专区。
- 同一页另有 36 张个性推荐歌曲卡片、8 张节目卡片及 12 张歌单卡片。
- 序号 13：下一页有 12 张推荐歌单卡片，以及另一个含 36 张歌曲卡片的推荐区块。

已观察到的翻页参数：

```json
{"direction":0,"page":1,"v_cache":[],"v_uniq":[],"s_num":0}
{"direction":1,"page":2,"v_cache":[],"v_uniq":[],"s_num":4}
```

## 客户端上下文

这是 Windows 客户端内嵌推荐页所用的上下文：`ct=20`、`cv=2276`、`platform=wk_v17`。
请求同时使用 Cookie 和 `uin`、`uid`、`guid`、`g_tk`、`g_tk_new_20200303` 等公参。
它与原生搜索请求的 `ct=19` 配置不同，接入时不能直接假定共用搜索请求的完整公参。
本次仅检查保留的成功请求，未验证签名生成、独立重放或未登录行为。

## 仍缺少的证据

每日30首、猜你喜欢、刷歌模式目前确认的是首页入口；这些入口卡片的
`card_extra_info.SongList` 与 `Tracks` 均为空。本文件未找到它们进入详情后的完整列表或续取请求。
36 首首页个性推荐歌曲不能当作每日30首。

若下一步要实现这些入口的完整功能，需要补抓点击卡片标题进入后的详情请求，
以及猜你喜欢播放后的续取请求；仅刷新首页不足以确认这些接口。

## 猜你喜欢与刷歌模式的独立接口验证

2026-10-29，对照 [YAQMC 使用的 qm-api-rs 推荐模块](https://github.com/YAQMC/qm-api-rs/blob/bab630d44901f80cae47dd0f09314950d0028e23/src/modules/recommend.rs)，
使用原 HAR 的 Cookie、公参及 User-Agent，另行向 `https://u6.y.qq.com/cgi-bin/musicu.fcg`
发起了两次取歌请求。此处是独立的在线验证，不是原 HAR 中已观察到的调用。

| 功能 | module.method | 参数 | 验证结果 |
| --- | --- | --- | --- |
| 猜你喜欢 | music.radioProxy.MbTrackRadioSvr.get_radio_track | id=99、num=5、from=0、scene=0、song_ids=[] | HTTP 200，全局和业务 code 均为 0，tracks 返回 5 首 |
| 刷歌／雷达 | music.recommend.TrackRelationServer.GetRadarSong | Page=1、ReqType=0、FavSongs=[]、EntranceSongs 使用入口给出的歌曲 | HTTP 200，全局和业务 code 均为 0，VecSongs 返回 11 首 |

原始刷歌入口跳转为 `qqmusic://qq.com/ui/jumpToRadarMode`，携带 Page、ReqType、EntranceSongs，
其中 Page 为字符串 "1"，ReqType 为字符串 "0"，EntranceSongs 含 1 首入口歌曲。
上述在线验证使用数字型 Page=1、ReqType=0。

接入歌曲模型时，猜你喜欢读取 `data.tracks`，雷达读取 `data.VecSongs[].Track`。
它们适合按批次加入播放队列；后续翻页、去重、跳过和反馈行为尚未在本轮验证，
不能据这两次成功取歌就宣称已复现官方客户端的完整刷歌行为。

## 取证说明

REA CLI 对原 HAR 的序号 0、5、8、13 进行了离线核对，Evidence ID 为
`ev_7b7fe12eeae6e855753496b949345d1be2b6175855f951ea39da9ad494d875f0`。
离线记录能证明文件中存在这些请求与响应，不能独立证明页面点击顺序、实际发起进程或线上可重放性；
进程与路由观察来自本轮 FlClash 连接记录，不是 HAR 自身的进程归因。
