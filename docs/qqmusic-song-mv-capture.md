# QQ 音乐：从歌曲进入 MV、查找相似歌曲

观察日期：2026-10-31（北京时间）。用户在官方 Windows QQ 音乐中操作，
通过已开启的 FlClash TUN 与 Fiddler 抓包；本文所用请求发生在 23:02:32 至 23:02:49。
仅被动观察、离线解码，没有重放请求或改动 Kanade 的业务代码、UI、交互和动画。

## 证据

从 Fiddler 的本地 `dump.saz` 中筛选 QQ 音乐 `musics.fcg/musicu.fcg` 会话，
保留所选会话原始请求、响应与元数据成员，另派生解压响应正文的 HAR，共 18 条记录。
本次保存的是筛选后的会话包，不是完整 Fiddler 会话导出。
HAR 的 `_sazRequestFile/_sazResponseFile` 对应 SAZ 成员，时间来自 `ClientBeginRequest`；
`time/timings` 为占位值，不用于推断耗时。

| 本地材料 | 字节 | SHA-256 |
| --- | --- | --- |
| `qqmusic-song-mv-20261031.saz` | 86010 | `807d8ca4cdafda8947496d7da12ac1ec4bd89eb489b50a52f77bf98405479e87` |
| `qqmusic-song-mv-20261031.har` | 262688 | `42c9be0dcbcf07033656858eebccea4f18326b169917437e77a5c293887f3dfe` |

两份本地文件由现有 `.gitignore` 排除，含当前会话凭据，不应提交或公开。
本文不复制 Cookie、登录公参值、Sign/Mask、设备 GUID、鉴权媒体路径。
下文 HAR 序号从 0 开始。

REA 离线核对 HAR 0、3、4、7、8，Evidence ID：
`ev_9dda38cdad72a1142183f2021eefc6e4c006a76ec2af7175ee48122d43df8307`。
相似歌曲 HAR 10 的 Evidence ID：
`ev_c165523f09a6627cd7b55701baa41dcb7f88dbdc3c7064ca9d6dbbe8f2fff0a8`。
证据来自保留文件，不能据此声称完成了独立联网重放或所有客户端入口验证。

## 歌曲 → MV 的关联来源

本轮观察到的链路：歌曲搜索结果中的 `song.mv.vid` → MV 详情 → MV 取流。
从搜索返回至取流之间，没有看到另一次以歌曲 ID 换取 VID 的请求。

HAR 0 / `raw/112_c.txt`：

```json
{
  "music.search.SearchCgiService": {
    "module": "music.search.SearchCgiService",
    "method": "DoSearchForQQMusicDesktop",
    "param": {
      "grp": 1,
      "num_per_page": 40,
      "page_num": 1,
      "query": "鸣潮",
      "remoteplace": "sizer.newclient.song",
      "search_type": 0,
      "searchid": "<GENERATED_SEARCH_ID>"
    }
  }
}
```

关联字段路径：
`response["music.search.SearchCgiService"].data.body.song.list[].mv.vid`。
本轮 HTTP 200、网关 `code=0`、业务 `code=0`、业务 `data.code=0`。

| 歌曲 | 歌曲 ID / MID | `mv.id` | `mv.vid` | `mv.vt` |
| --- | --- | --- | --- | --- |
| Turning Around (余烬重燃) | `667137632` / `002uVqdJ0unvAk` | 2396894 | `0029LB4H4RaS6j` | 0 |
| 心月辞·长相望 | `726206595` / `000bjZqH448qnK` | 0 | `012FcL2B0wkgvf` | 1 |
| Daisy Crown (日文版) | `563448542` / `002BdEeK2Mr2Kd` | 0 | `012g4cWp0eGgFH` | 1 |
| 赴每一程未知 (I.R.I.S cover) | `634598738` / `004Ytrah01J9gS` | 0 | 空字符串 | 0 |

40 条歌曲中有 23 条的 `mv.vid` 非空，其中 15 条的 `mv.id=0`。
因此不能用 `mv.id > 0` 作为是否存在视频关联的条件；后续接口使用字符串 VID。
`mv.vid` 非空也不代表必定有播放权限，仍需检查详情和取流结果。
`vt` 在本包有 0/1 两种值，未单独验证其完整语义。

本次点击的是 Turning Around，后续单视频详情和取流都使用 `0029LB4H4RaS6j`，
与该歌曲搜索结果一致。其他歌曲行只证明关联字段的返回，未逐首播放。

## 点击歌曲 MV 后的请求

| 功能 | HAR / SAZ 请求 | 请求键 | module.method |
| --- | --- | --- | --- |
| 单视频详情 | 3 / `raw/150_c.txt` | `GetMVStreamInfo` | `music.video.VideoData.get_video_info_batch` |
| 批量视频资料 | 4 / `raw/151_c.txt` | `get_video_info_batch` | `music.video.VideoData.get_video_info_batch` |
| MV 取流 | 7 / `raw/156_c.txt` | `GetMvUrls` | `music.stream.MvUrlProxy.GetMvUrls` |
| 视频相关推荐 | 8 / `raw/166_c.txt` | `rec_video_byvid` | `video.VideoLogicServer.rec_video_byvid` |

这些请求 HTTP 200、网关及业务 `code=0`。
单视频详情参数是 `vidlist=["0029LB4H4RaS6j"]` 和 `required` 字段列表，
返回路径为 `response.GetMVStreamInfo.data[VID]`。
视频名为「《鸣潮》二周年潮声庆典纪念动画 | Turning Around 余烬重燃」，
`sid=2396894`、条目 `code=0`、`play_forbid_reason=0`、`duration=141`。
MV 时长不等于歌曲时长（该曲 `interval=247`），应读取视频详情自己的时长。

本轮取流业务参数：

```json
{
  "filetype": 40,
  "format": 265,
  "guid": "<CURRENT_DEVICE_GUID>",
  "maxFiletype": 60,
  "request_type": 10003,
  "testCdn": 1,
  "vids": ["0029LB4H4RaS6j"]
}
```

返回 `response.GetMvUrls.data[VID].mp4[]/hls[]`。
MP4 的 filetype 10/20/30/40 条目 `code=0`，`url/freeflow_url` 数组为空，
`urlPath` 非空；其他占位条目出现 `code=2000`，不能仅检查外层成功码。
完整播放地址的既有实现与验证见 [API 文档的 MV 部分](qqmusic-api.md#mv)。
本轮未独立请求媒体文件，不新增“完整播放验证成功”的结论。

## 查找相似歌曲

已捕获用户此次操作。HAR 10 / `raw/199_c.txt`，23:02:46.2178667：

```json
{
  "music.recommend.TrackRelationServer.GetSimilarSongs": {
    "module": "music.recommend.TrackRelationServer",
    "method": "GetSimilarSongs",
    "param": {
      "songid": 667137632
    }
  }
}
```

`songid` 使用歌曲数字 ID，本包为 JSON 数字；不传 songmid 或视频 VID。
这条与上述 MV 对应同一首 Turning Around。
HTTP 200、网关 `code=0`、业务 `code=0`，进一步检查 `data.retcode=0`、`data.msg=""`。

响应路径相对于 `response["music.recommend.TrackRelationServer.GetSimilarSongs"].data`：

| 字段 | 本次结果 |
| --- | --- |
| `vecSong[].track` | 3 首歌曲，使用常规歌曲结构，包含 id、mid、singer、album、mv、interval、file、pay 等 |
| `vecSong[].tf/abt/trace` | 推荐附加字段；不用于歌曲主键 |
| `songTagInfoList[]` | 1 条标签，含 id、tag、link、tagid、from_type；按歌曲 id 关联 |
| `vecSongNew` | null；不能将其作为本包的歌曲列表来源 |

返回顺序为：

1. Turning Around (余烬重燃) (伴奏)：`667137593` / `002TF0od1Y9sDT`。
2. 愿戴荣光坠入天渊：`571288678` / `0034QXzv2ptMdw`。
3. 远航星的告别：`639372873` / `0038W0WD0TlByu`。

第二首附带「昨日热播」标签，`tagid=3040`、`from_type=9`。
列表包装在 `track` 中，接入时应将 `track` 交给现有歌曲解析器。
本次仅一个输入歌曲样本，没有分页参数，不推断固定返回数量、空结果或其他歌曲的表现。

## 传输上下文与项目状态

上述业务请求统一为 `POST https://u6.y.qq.com/cgi-bin/musics.fcg`（另带动态 `pcachetime`）。
Content-Type 为 `application/x-www-form-urlencoded`，正文实际为 JSON；
原生 PC 公参 `ct="19"`、`cv="2276"`、`patch="118"`，带当前 Cookie、Sign/Mask。
示例省略了这些公参与请求头，不能直接作为已验证的完整独立调用。

当前 `rust/src/qq/parse.rs` 的 `song()` 与 `rust/src/api/types.rs` 的 `Song`
未保留歌曲 `mv.vid`；已有 `mv.rs` 接口则接收 VID。
因此后续接入歌曲 MV 入口可保留上游 `mv.vid` 后复用现有 MV 详情与播放逻辑。
本次没有修改业务数据结构、UI 或交互，也未实现相似歌曲功能。

保留包还包含用户正常播放触发的歌词、音频取流及播放上报，未重放这些请求。
已恢复临时 FlClash 路由，TUN 保持开启。

校验通过：`git diff --check`、文档 JSON 示例与本地链接、SAZ 成员与 HAR 对应关系、
文件摘要、歌曲 VID 在详情与取流请求间的一致性、相似歌曲三层结果码和实际列表。
本文仅新增抓包记录并补充 API 文档，未修改 Dart/Rust，因此未运行应用测试。

## 后续软件接入（2026-10-31）

用户随后明确要求把两个按钮放进歌曲长按 / 更多按钮的弹窗。
在上述抓包基础上，现已为 `Song` 增加 `mv_vid` 并由统一歌曲解析器读取，
播放队列保存和恢复时保留该字段；旧队列缺少字段时按空 VID 兼容。
弹窗中 VID 非空的歌曲显示「观看 MV」，打开现有 `MvPage`。
「查找相似歌曲」调用 `get_similar_songs(song_id)`，检查 `retcode` 后提取 `vecSong[].track`，
在现有 `SongListPage` 中展示并播放；沿用加载、失败重试和空列表禁用播放的处理。
修正共用 `AsyncView` 重试回调返回 Future 导致的断言，未更改弹窗样式和动画。

验证：`flutter analyze --no-pub` 与 `cargo clippy --lib --tests -- -D warnings` 通过。
3 条 Rust 针对性测试、5 条新弹窗测试及 13 条既有播放队列 / 音源测试通过。
只读联网测试 `desktop_song_mv_and_similar_songs` 经应用后端取得 4 档 MV 播放流及 3 首相似歌曲；
本次测试未重新下载媒体文件或验证新增视频播放时长。
测试使用内存登录态，不更改应用登录数据库；针对 Fiddler 系统代理的证书干扰，
只在测试子进程对 QQ 音乐域名设置 `NO_PROXY`，保持 TLS 证书校验。
`flutter build windows --release --no-pub` 构建通过，产物位于 `build/windows/x64/runner/Release/`。
