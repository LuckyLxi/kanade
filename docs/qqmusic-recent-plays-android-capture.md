# QQ 音乐：Android 端最近播放的各分类

观察日期：2026-11-06（北京时间）。PC 客户端的最近播放只同步歌曲和 MV（见[最近播放抓包](qqmusic-recent-plays-capture.md)），
Android 端「我的 → 最近播放」有 7 个分类：全部、歌曲、专辑、歌单、有声节目、音乐雷达、视频。
在 MuMu 15 中运行官方 Android QQ 音乐 20.09（`QQMusic 20090808`，已登录），用 `scripts/capture-qqmusic-android.mjs --prepare` 经 Fiddler 抓包。
抓包从冷启动开始（12:40:21），之后用 adb 依次点开最近播放页的每个分类（至 12:41:38）。本轮只读，没有播放、上报或删除记录。

## 证据

| 本地材料 | 字节 | SHA-256 |
| --- | --- | --- |
| `qqmusic-recent-plays-android-20261106.saz` | 47536443 | `089544f10df8ff6ad1d687d7e4a15c46c41ddd7ea72226977e3c0ebb3be49a29` |

文件由现有 `.gitignore` 排除。Fiddler 同时作为系统代理，文件中有无关的宿主机流量；Android 请求的公参含 `authst`、Cookie、设备标识，不应提交或公开。
本文不复制 Cookie、`authst`、`sign`、`mask`、设备标识，也不复制真实的播放记录内容；下文示例中的名称和 ID 都是占位。

| 会话 | 时间 | 内容 |
| --- | --- | --- |
| `raw/0136` | 12:40:21.061 | 冷启动批量读取：`type` 1、3、4、5、6、10、12、14、15、18，各一个请求键 |
| `raw/0137`、`0143` | 12:40:21 | 短剧最近播放 `type` 201、202 |
| `raw/0479` | 12:40:31.732 | 歌曲 `type=2`，返回 2500 首 |
| `raw/0480` | 12:40:33.272 | `GetPlayRecentlyCount` |
| `raw/0497`、`0627`、`0843`、`0848`、`0921`、`1032`、`1068`、`1377`、`1382`、`1384` | 12:40:35–12:41:38 | 点开各分类时的增量读取，除 `0843`（全部）外都返回 `-300` |

## 传输

与[专属乐流](qqmusic-feed-column-capture.md)相同：`POST https://u6.y.qq.com/cgi-bin/musics.fcg`，`M-Encoding: m1`，带 `sign` / `mask`；
请求体是 5 字节前缀加 zlib 压缩的 JSON。本轮响应体 `Content-Type: application/octet-stream`、没有 `Content-Encoding`，但正文是 **Brotli** 压缩的 JSON（不是专属乐流那次看到的 zlib）。
解压后歌曲响应为 5552508 字节，传输正文 1332058 字节。

## 读取接口

和 PC 是同一个接口 `music.musicasset.PlayRecentlyRead.GetPlayRecentlyInfo`，用 `type` 区分分类。冷启动时把多个 `type` 合进一个请求，
请求键在方法名后拼上 type（`…GetPlayRecentlyInfo4`、`…GetPlayRecentlyInfo12` 等），`module`/`method` 本身不变。

```json
{
  "type": 3,
  "updateTime": 0,
  "requestCnt": 2500,
  "ext": {
    "bluetooth": "", "recent_play_song_list": "", "jike_select_city_id": "",
    "battery_level": "98", "charging_status": "1", "phone_language": "zh_CN_#Hans",
    "phone_volume": "100", "song_play_status": "0"
  }
}
```

`ext` 是设备状态，后续请求的 `recent_play_song_list` 里还带了一条当前歌曲的 JSON 字符串；是否必填未验证。

响应路径和 PC 一致：`resp[K].data.code` 为业务结果码，`resp[K].data.updateTime` 为同步时间，列表在 `resp[K].data.data.<字段>`。
每个响应都带全部列表字段，只有对应的那个非空。

| `type` | UI 分类 | 列表字段 | 本样本条数 | 每项字段 |
| --- | --- | --- | --- | --- |
| 1 | 全部 | `allItems`（见下） | — | — |
| 2 | 歌曲 | `songList` | 2500 | 与 PC 相同：`track`、`lastTime`、`listenCnt`、`lastPlayDevice` |
| 3 | 专辑 | `albumList` | 60 | `id`、`mid`、`pmid`（封面 mid）、`name`、`singerName`（`/` 连接的字符串）、`num`（歌曲数）、`lastTime`、`index`、`track`（全空的歌曲对象） |
| 4 | 歌单 | `geDanList` | 12 | `id`（歌单 tid）、`name`、`pic`（完整 URL）、`num`、`creater`、`uin`（创建者）、`lastTime`、`index`、`geDanType`、`dirId`、`dirShow` |
| 5 | 音乐雷达 / 电台 | `radioList` | 2 | `id`、`name`、`pic`、`radioType`、`lastTime`、`index`、`singerName`、`pmid`、`num` |
| 6 | 视频 | `mvList` | 20 | 与 PC 相同：`mvInfo`（`vid`、`name`、`cover_pic`、`singers[]`、`video_pay` 等）、`lastTime`、`index` |
| 12 | 有声节目 | `listenBookList` | 6 | `id`、`name`、`pmid`、`track`（最近听的那一集，完整歌曲对象，`track.type=1`）、`lastTime`、`num`、`new_album_right` |
| 10 | 未知 | — | 0 | `nums["10"]=0` |
| 14、15、18 | 未知 | — | — | 冷启动即返回 `data.code=-300` |

- 各列表都已按 `lastTime` 降序排列；`lastTime` 为 Unix 秒。
- UI 的「音乐雷达 1」只显示 `radioList` 中 `radioType=2` 的那一项（猜你喜欢，`id=99`）；另一项 `radioType=3` 没有出现在任何分类里。筛选规则是从这一个样本推断的。
- 页面底部写着「展示该账号下最近播放的 200 个音乐雷达」，其他分类的上限未见提示。
- 「视频」分类还有「腾讯视频 0」子标签，本样本为空，没有看到对应请求。

### `type=1`（全部）

`resp[K].data.data.allItems`：

| 字段 | 内容 |
| --- | --- |
| `commList` | 聚合入口卡片：`{type, title, pic, num, lastTime, index, icon, jumpTo}`。本样本有 `type=2`（已播歌曲，`num=2500`，`lastTime=0`）和 `type=6`（已播视频，`num=20`） |
| `albumList`、`geDanList`、`listenBookList` | 与对应 `type` 的列表结构相同、内容相同（本样本 60 / 12 / 6 条） |
| `radioList`、`singerList`、`zoneList`、`topList`、`liveShowList`、`podcastList`、`roomList` | 本样本为空 |
| `nums` | 各分类计数，键为 type 字符串：`{"2":2500,"3":60,"4":12,"6":20,"10":0,"12":6}`；不含电台 |
| `specialCommList` | 1 项 `{type:16, id, title, pic, lastTime}`，`id` 为一首歌的数字 ID；用途未验证 |
| `filterTypes` | `[5,7,8,9,14,15,17,19]`；猜测是「全部」页要排除的类型，未验证 |
| `abtID` | 实验分组 |

UI 的「全部」页把歌曲、视频合成一张卡片，其余按 `lastTime` 混排并按「昨天 / 更早」分组。

### 增量同步

客户端把上次响应的 `data.updateTime` 作为下次请求的 `updateTime`：

- 没有变化：`data.code=-300`，各列表为空，`updateTime` 原样返回。点开各分类时的 10 次请求中 9 次是这种情况。
- 有变化：返回**整份**列表而不是差量。`raw/0479` 请求 `updateTime=1793901631`，其后只有 4 首新播放，响应仍是完整 2500 首。

所以 `-300` 只能理解为「未变化，用本地缓存」，不是错误。PC 端只抓到 `updateTime=0` 的情况。

## `GetPlayRecentlyCount`

`music.musicasset.PlayRecentlyRead.GetPlayRecentlyCount`，参数 `{"updateTime": <上次的秒级时间>}`。

```json
{"code": 0, "updateTime": 1793939197460395902, "counts": {"<歌曲数字ID>": {"count": 27, "updateTime": 1793620030}}}
```

- 本样本 `counts` 有 3486 项，比歌曲列表多 986 项；歌曲列表里的 2500 首全部在其中，且 `count` 都等于 `listenCnt`。
- 外层 `updateTime` 是纳秒级的 19 位数字，内层为 Unix 秒。

## 短剧

`music.longRadio.LongRadioPlayRecentlyRead.GetPlayRecentlyInfo`，参数 `{"type": 201|202, "updateTime": 0}`，
返回 `data.data.playletList`。本样本两次都是 `data.code=-300`、空列表，UI 中没有对应分类。

## PC 通道重放（2026-11-06）

用 Kanade 现有的 `Core::desktop_private`（PC 公参、`musicu.fcg`、Cookie，无 Sign/Mask）发同样的参数
`{"requestCnt":2500,"type":<t>,"updateTime":0}`，不带 `ext`。测试：`rust/tests/live.rs` 的 `desktop_recent_play_categories`。

| `type` | 结果 |
| --- | --- |
| 2 | `code=0`，2500 首 |
| 1 | `code=0`，专辑 60、歌单 12、有声 6；`nums={"2":2500,"3":60,"4":12,"10":0,"12":6}`，比 Android 少了 `"6"` |
| 3 / 4 / 5 / 6 / 12 | `code=0`，分别 60 / 12 / 2 / 20 / 6 条 |
| 10 | `code=0`，空 |

条数和各分类的 `updateTime` 与 Android 抓包一致，所以 Android 的 `ext` 不是必填，PC 通道可以直接读取所有分类。

登录态：本次重放使用 Android 抓包 `comm` 里的 `qq`/`authst`/`tmeLoginType`（微信登录，`W_X` 开头），
说明 Android 客户端的 musickey 可以直接用在 PC 通道上。10-31 的 HAR 登录态已过期（返回 `1000`）。

## 未验证

- 没有验证 `requestCnt` 对非歌曲分类的作用，也没有验证删除单条或清空记录的接口。
- `type` 10、14、15、18、`filterTypes`、`specialCommList`、`lastPlayDevice` 的含义未知。
