# QQ 音乐：首页「{昵称}」的专属乐流

观察日期：2026-11-06（北京时间）。PC 客户端首页没有这个栏目，改在 MuMu 15 中运行官方 Android QQ 音乐 20.09（`QQMusic 20090808`，已登录），
用 `scripts/capture-qqmusic-android.mjs --prepare` 经 Fiddler 抓包。请求发生在 01:59:44 至 02:00:50。
操作由 adb 驱动：点栏目右侧刷新按钮，再连续上滑加载更多。

上滑时有几次被识别成点击：02:00:08 打开了一个歌单详情页，02:00:14 起播放了一首歌，
02:00:31 向账号最近播放上报了一次（`music.musicasset.PlayRecentlyWrite.ReportPlayRecentlyInfo`）。
这些请求不属于专栏，下文不分析；本轮没有出现红心、收藏、关注等写操作。

## 证据

| 本地材料 | 字节 | SHA-256 |
| --- | --- | --- |
| `qqmusic-feed-column-20261106.saz` | 39587904 | `362dd969d468c33ffe8aa7753f299bbb4c83c95357ad9559bdfded11c240cfec` |

文件由现有 `.gitignore` 排除。Fiddler 同时作为系统代理，文件中有无关的宿主机流量；Android 请求的公参含 `authst`、Cookie、设备标识，不应提交或公开。
本文不复制 Cookie、`authst`、`sign`、`mask`、设备标识。专栏请求为 `raw/006`（刷新）和 `raw/036`、`072`、`115`、`149`（翻页）。

## 官方客户端的传输

```
POST https://u6.y.qq.com/cgi-bin/musics.fcg
User-Agent: QQMusic 20090808(android 15)
M-Encoding: m1
x-sign-data-type: json
sign / mask: 有
```

- 请求体：5 字节前缀后接 zlib 压缩的 JSON（`{"comm":{…},"<module>.<method>":{"module","method","param"}}`）。
- 响应体：zlib 压缩的 JSON（以 `78 01` 开头）。
- 同一通道里另有一类请求和响应是 JCE/TARS 二进制（响应以 `0c13000001a1` 开头），本轮见到的是歌单预取
  `music.srfDissInfo.UgcPreDissInfo.CgiGetDiss`、VIP 横幅、直播推荐等，与专栏无关。
- 公参：`ct="11"`、`cv=v="20090808"`、`chid="73387"`、`tmeAppID="qqmusic"`、`os_ver="15"`、`gzip="1"`，另有登录与设备字段。

## 接口

`music.recommend.RecommendFeed.get_recommend_feed`，和 Kanade 现有首页推荐是同一个接口，参数和公参不同。

刷新专栏（`raw/006`）：

```json
{
  "direction": 1, "page": 2, "s_num": 7, "client_time": 1793901450,
  "v_cache": ["301", "207", "272", "315"],
  "refresh_info": {"ModuleID": "waterfall@1@0", "Page": 2, "ShelfID": "315", "LayoutTrace": "", "LayoutSeq": "…", "ExtraInfo": {…}},
  "ext": {"is_20_style": "1", "has_login": "1", "module_list": "minister@27@favo_songs,podcast@1@0,minister@2@21045,minister@28@recent_songs,waterfall@1@0", …}
}
```

`refresh_info` 就是上一次响应里该栏目的 `refresh_param`，原样带回。

翻页（`raw/036` 起）：

```json
{
  "direction": 1, "page": 4, "s_num": 7, "client_time": 1793901588,
  "v_cache": ["301", "207", "272", "315"],
  "v_uniq": ["200_0_680172", "500_0_2968769538", "200_206_639372873", …],
  "ext": {"is_20_style": "1", "TwoColPages_proxy": "1", "IsTwoColumnFlow_proxy": "1", "two_col_page_proxy": "1", …}
}
```

- `page` 每次加 1；`s_num` 在本轮依次为 7、8、9、10。
- `v_uniq` 是已经展示过的卡片，格式 `{type}_{subtype}_{id}`，每翻一页多 8 个（16、24、32、40）。
- `ext` 里还有电量、蓝牙、时区、最近播放列表等客户端状态，没有验证哪些是必需的。

## 响应

`data.v_shelf` 只有一个栏目：`id="315"`、`style=4`。首次出现（刷新响应）时
`title_template="「{String}」的专属乐流"`、`title_content` 是昵称；之后的翻页响应标题为空。
栏目带 `refresh_param`（同上）、`more`、`style_detail.is_big` 等字段；`data` 另有 `load_mark`、`d_num`、`prompt`、`msg`，本轮都是 0 或空。

卡片在 `v_shelf[0].v_niche[0].v_card`，每页 8 张。5 个响应共 40 张，只有三种：

| 卡片 | type / subtype / style | 数量 | 内容 |
| --- | --- | --- | --- |
| 单曲 | 200 / 0 / 301 | 20 | `title` 歌名、`subtitle` 歌手、`cover` 专辑图；`card_extra_info.Tracks[0]` 是完整歌曲对象（含 `mid`、`file.media_mid`、`singer`、`album`）；`tags[0].Tag` 是一句评论标签，如“男女对唱，把失眠的拉扯唱成对话”，`Link` 跳到评论 |
| 三首一组 | 200 / 206 / 304 | 10 | `title` 是分组名，如“重温曾经你最爱听的歌”“「Make Me Complete」相似发现”；`card_extra_info.SongList` 3 项（`ID`、`MID`、`Name`、`SingerName`、`Cover`），`Tracks` 只有第一首的完整对象 |
| 歌单 | 500 / 0 / 302 | 10 | `id` 歌单 ID、`title`、`cover`、`cnt` 播放数；`miscellany.cnt_content` 如“10.4W 播放” |

单曲卡和组卡的 `scheme` 是 `qqmusic://qq.com/media/playRecommendRadar?p={"TraceArray":[id],"EntranceSongs":[id]}`，
即点击后以这首歌为起点进入刷歌模式，与 Kanade 已有的 `radar_songs` 入口格式相同。

## Kanade 可用性实测

用 Kanade 登录态的数据库副本，不经签名、直接请求 `https://u.y.qq.com/cgi-bin/musicu.fcg` 的明文 JSON：

| 公参 | ext | 第 1 页栏目 | 第 2、3 页栏目 |
| --- | --- | --- | --- |
| 现有首页（PC 内嵌页 `ct=20`） | 无 | 301、207、272、271 | 205、207（无 315） |
| 现有 Android 写入通道（`cv=14090008`） | 无 | 301、207、272 | 308、276、273、207、114、205 等（无 315） |
| 同上 | 首页 / 翻页 ext | 301、207、272 | 同上（无 315） |
| Android `ct=11`、`cv=v=20090808`、`chid=73387` | 首页 / 翻页 ext | 301、207、272 | 只有 315，各 8 张卡，类型排布与官方一致，8 张里 6 张带 `Tracks` |

结论：不需要 `musics.fcg` 的签名和压缩；关键是 `cv=20090808` 的 Android 公参，第 1 页之后的翻页才返回专栏。
Kanade 的实现（`qq::music::feed_column`）在此基础上去掉了首页第 1 页：直接从服务端第 2 页开始请求，`v_cache` 为空数组，
`v_uniq` 传之前各页卡片。实测连续 4 页各 8 张卡、互不重复；组卡按 `SongList` 的 ID 用 `CgiGetTrackInfo` 补全后都是 3 首。
没有单独验证 `ext` 是否必需、未登录时的行为，也没有验证刷新请求（`refresh_info`）。
