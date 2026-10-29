# QQ 音乐最近播放接口抓包（交给 Claude 接入）

## 结论

已抓到官方 Windows 客户端实际使用的最近播放读取接口：

```text
POST https://u6.y.qq.com/cgi-bin/musics.fcg?pcachetime=<动态值>
module: music.musicasset.PlayRecentlyRead
method: GetPlayRecentlyInfo
请求键: music.musicasset.PlayRecentlyRead.GetPlayRecentlyInfo
```

歌曲使用 `type=2`，本次成功返回 2500 条；MV 使用 `type=6`，成功返回 15 条。
两份响应的网关 `code`、请求业务 `code`、业务 `data.code` 均为数字 `0`。
歌曲数据完整保存在 SAZ 中；HAR 因导出大小限制省略了歌曲响应正文。

本轮只抓包、核对并写本文档，没有实现 Kanade 功能，没有改 UI，也没有重放请求。

## 证据位置

观察日期：2026-10-29，北京时间。HAR 序号从 **0** 开始；SAZ 使用归档内实际文件名。

| 文件 | 大小 / 记录数 | SHA-256 |
| --- | --- | --- |
| `qqmusic-recent-plays.har` | 887448 字节，36 条 | `5541a71ab071e8004208543a05ea4df9474bf6e2c3691c0e2728585c1dd1f03d` |
| `qqmusic-recent-plays-sync.har` | 5070935 字节，239 条 | `2d247db96dc743df5e9097a15a147ba5f066fb0413f76abe0ee43b9e2398877a` |
| `qqmusic-recent-plays-sync.saz` | 4590230 字节 | `ba79707a5e576bf3b10f9268e53d4945309d682e4cf0700d6b28a2a73472f29d` |

文件均在项目根目录。原始文件含登录凭据和其他应用流量，仅供本地定点读取；不要提交仓库或整份贴进对话。
HAR 已被现有 `.gitignore` 排除，新增 SAZ 已加入本机 `.git/info/exclude`。
本文未复制 Cookie、账号、令牌、Sign/Mask 值或真实播放列表内容。

第一轮在已打开的客户端切换最近播放，没有捕获读取请求。第二轮在抓包期间退出并重启客户端后捕获：

| 功能 | HAR 序号 | SAZ 请求 / 响应 | 请求时间 |
| --- | --- | --- | --- |
| 最近播放 MV | 205 | `raw/206_c.txt` / `raw/206_s.txt` | 21:17:57.808 +08:00 |
| 最近播放歌曲 | 206 | `raw/207_c.txt` / `raw/207_s.txt` | 21:17:57.808 +08:00 |

这说明本样本在启动阶段进行了记录同步；不能据此认定每次进入页面都会联网。
HAR 的 REA 核对 Evidence ID：`ev_6821504537142e9f4e40327ef2a41ad02485008da2987693de52bb22e1b30b96`。
SAZ 的解压、Brotli 解码与完整歌曲统计使用普通本地工具完成，不属于该 REA Evidence。

## 请求参数

歌曲请求的完整业务参数：

```json
{"requestCnt":2500,"type":2,"updateTime":0}
```

MV 请求的完整业务参数：

```json
{"requestCnt":2500,"type":6,"updateTime":0}
```

| 参数 | 抓到的类型与值 | 可以确认的含义 / 边界 |
| --- | --- | --- |
| `requestCnt` | number，2500 | 本次歌曲实际返回 2500 条。其他取值、最大值、是否存在更多历史记录均未验证。 |
| `type` | number，2 / 6 | 2 的响应填充 `songList`；6 的响应填充 `mvList`。其他枚举未验证。 |
| `updateTime` | number，0 | 本次初始同步传 0；响应也包含该字段。增量同步、翻页语义未验证。 |

未观察到 `page`、`begin`、`offset` 参数，也没有捕获后续页请求。
不能把响应的 `updateTime` 直接当作向前翻页游标；是否可用它增量同步需要另行验证。
2500 条恰好等于请求数量，也不足以证明已经拿到账号全部历史。

请求结构示例（凭据均为占位符，部分公参省略；不是已验证的最小可运行请求）：

```json
{
  "comm": {
    "_channelid": "20",
    "_os_version": "6.2.9200-2",
    "authst": "<CURRENT_MUSICKEY>",
    "ct": "19",
    "cv": "2276",
    "guid": "<DESKTOP_GUID>",
    "patch": "118",
    "tmeAppID": "qqmusic",
    "tmeLoginType": 1,
    "uin": "<CURRENT_MUSICID>"
  },
  "music.musicasset.PlayRecentlyRead.GetPlayRecentlyInfo": {
    "module": "music.musicasset.PlayRecentlyRead",
    "method": "GetPlayRecentlyInfo",
    "param": {
      "requestCnt": 2500,
      "type": 2,
      "updateTime": 0
    }
  }
}
```

实际 `comm` 还包含 `psrf_access_token_expiresAt`（number）、`psrf_qqaccess_token`、
`psrf_qqopenid`、`psrf_qqunionid`、`wid`（均为 string）。本样本是微信登录，
`tmeLoginType=1`；不能把它固定用于所有登录方式。`ct`、`cv` 在此处是字符串。
这些是观察到的公参，不代表每项都已证实必填。

实际请求有 `Cookie`、`Sign`、`Mask` 请求头，User-Agent 为：

```text
Mozilla/5.0 (compatible; MSIE 9.0; Windows NT 6.1; WOW64; Trident/5.0)
```

虽然 `Content-Type` 是 `application/x-www-form-urlencoded`，SAZ 中请求正文实际是原始 JSON，
不是把 `comm` 等字段编码成普通表单。Fiddler 的 HAR 将其放进 `postData.params` 的参数名中；
解析原始 HAR 时不能只查 `postData.text`。

## 歌曲响应

设 `K = "music.musicasset.PlayRecentlyRead.GetPlayRecentlyInfo"`，原始响应路径为：

```text
response.code                       -> 网关结果码
response[K].code                    -> 请求业务结果码
response[K].data.code               -> 最近播放业务结果码
response[K].data.type               -> 本次为 2
response[K].data.updateTime         -> 服务端同步时间值
response[K].data.data.songList      -> 最近播放歌曲数组
```

注意业务 `data` 内还有一层 `data`。以下是人工构造的结构示例，ID、时间、歌曲内容均非实际记录：

```json
{
  "code": 0,
  "music.musicasset.PlayRecentlyRead.GetPlayRecentlyInfo": {
    "code": 0,
    "data": {
      "type": 2,
      "code": 0,
      "updateTime": 1700000000,
      "data": {
        "songList": [
          {
            "track": {
              "id": 123456,
              "type": 0,
              "mid": "<SONG_MID>",
              "name": "<SONG_NAME>",
              "title": "<SONG_TITLE>",
              "singer": [{"mid": "<SINGER_MID>", "name": "<SINGER_NAME>"}],
              "album": {"mid": "<ALBUM_MID>", "name": "<ALBUM_NAME>"},
              "interval": 200,
              "file": {"media_mid": "<MEDIA_MID>"}
            },
            "lastTime": 1700000000,
            "listenCnt": 1,
            "lastPlayDevice": 0
          }
        ]
      }
    }
  }
}
```

| 每条记录字段 | 类型 | 观察结果 |
| --- | --- | --- |
| `track` | object | 完整歌曲对象，含 `id`、`mid`、`name`、`title`、`subtitle`、`singer`、`album`、`interval`、`file`、`pay`、`action` 等。 |
| `lastTime` | number | 最近播放时间。本次均为 10 位时间值，按 Unix 秒理解；转换成 Dart 毫秒时间时应乘 1000。 |
| `listenCnt` | number | 播放次数字段，本次均为整数；统计周期和累计规则未验证。 |
| `lastPlayDevice` | number | 本次所有记录均为 0；设备枚举含义未验证，不能据此映射成 Windows 或手机。 |

完整样本核对结果：2500 条记录、2500 个不同 `track.id`，所有记录都有 `track.id` 和 `track.mid`；
数组已按 `lastTime` 非递增排列。该结果是样本事实，不是跨账号、跨版本的协议保证。

MV 列表路径为 `response[K].data.data.mvList`，每项有 `mvInfo`、`lastTime`、`index`。
`mvInfo` 包含 `vid`、`sid`、`name`、`cover_pic`、`singers`、`video_pay` 等。
外层还存在 `allItems`、`albumList`、`geDanList`、`radioList` 等字段；歌曲请求不应将
`allItems.specialCommList` 当作歌曲数组。

## HAR 缺正文的处理

歌曲 HAR 序号 206 的 `response.content` 没有 `text`，其 `comment` 明确为：

```text
Body length exceeded fiddler.importexport.HTTPArchiveJSON.MaxTextBodyLength, so body was omitted.
```

因此这不是空歌曲列表，也不是接口失败。完整响应在 SAZ 的 `raw/207_s.txt`：
先分离 HTTP 头和正文，再按 `Content-Encoding: br` 解码。解码后是 **5551565 字节** JSON，
传输正文为 1328808 字节。MV 的解码正文为 12751 字节。
本轮已实际完成这两份正文的解码、JSON 解析和三层结果码核对。

## 已有的上报证据（与读取分开）

旧文件 `qqmusic-player-actions.har` 序号 54 另有：

```text
module: music.musicasset.PlayRecentlyWrite
method: ReportPlayRecentlyInfo
param.data[]: {id: string, lastTime: number, listenCnt: number, type: number}
```

该旧样本 `type=2`、`listenCnt=1`，`id` 为数字字符串；`lastTime` 是与请求时间相差约一秒的
10 位 Unix 秒时间值。响应网关 `code=0`、请求业务 `code=0`、`data.ret=0`，
并返回 `data.timeList[]`（`type`、`updateTime`、`lastUpdateTime`、`code`）。
这只证明官方客户端存在上报调用；本轮没有重放上报，也没有验证应用的上报时机或去重规则。

## Claude 接入时的复用点与未验证项

- `rust/src/qq/parse.rs` 的 `parse::song` 可解析 `track` 内的歌曲结构；应传入 `item["track"]`，
  不能直接把整个最近播放条目交给 `parse::songs`。时间、次数、设备字段位于 `track` 外，需要另外保留。
- 现有 `rust/src/qq/client.rs` 有 PC 公参及 `Core::desktop_musicu`。它使用的是 `musicu.fcg`，
  请求别名为 module，且默认不附带 Cookie；与本次官方抓到的 musics 请求并不完全相同。
  可以作为复用候选，但本文没有验证这个接口能否直接通过该封装调用成功。
- 本轮没有独立重放，因此未验证 `musicu.fcg` 替代网关、Sign/Mask 的必要性、最小 Cookie、公参裁剪、
  Android 登录凭据的兼容性、QQ 登录、未登录状态以及失效凭据的返回行为。
- 没有验证 `requestCnt` 的其他值、2500 条之后的数据、增量同步或删除接口。
- 后续联网验证应先做只读读取；实现播放上报或删除记录属于另一项写入功能。

本轮没有应用代码变更，因此未运行 Flutter/Rust 测试。文档交付检查包括原始文件摘要、完整响应 JSON、
结果码、条目统计、示例 JSON 语法、Markdown 空白和凭据排除检查。
