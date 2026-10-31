# QQ 音乐 Windows 分类搜索与 MV 抓包

观察日期：2026-10-31（北京时间）。用户在官方 Windows QQ 音乐中操作，
通过 FlClash TUN 将 QQMusic / QQMusicExternal / qmbrowser 的 QQ 音乐 API 流量送入本机 Fiddler。
本轮相关请求时间：19:26:38 至 19:27:09。仅抓包与本地解码，未重放请求，未接入 Kanade UI。

## 证据来源

| 本地材料 | 内容 | SHA-256 |
| --- | --- | --- |
| `qqmusic-search-mv-20261031.saz` | Fiddler 保存的 139 个会话，617125 字节 | `44ac28caaf07f1f56c6ff36857fd044a0f2ddd5e3f407630d72cd63b03057108` |
| `qqmusic-search-mv-20261031.har` | 从 SAZ 提取的 18 条相关只读 API 记录，472994 字节；响应已解压 | `3058a82b0af76293d475ef737e7cb80bceee8bdd3dbeaeb2d27ea195fd9ae19a` |

HAR 不是 Fiddler 的直接导出。每条的 `_sazRequestFile` / `_sazResponseFile`
指向原始 SAZ 成员，时间来自对应 `_m.xml` 的 `ClientBeginRequest`。
原始 SAZ 未修改；两个文件均由现有 `qqmusic*.saz` / `qqmusic*.har` 规则排除在 Git 之外。
下文 HAR 序号从 0 开始，SAZ 文件编号直接使用成员名。
本文不复制 Cookie、账号标识、登录公参值、Sign / Mask、vkey 或带鉴权的媒体路径。

REA CLI 已离线检查派生 HAR 的全部 18 条记录，Evidence ID：
`ev_beb749c6ef719f772fa1f101c0cd8a4aba373ad31e3a5e2ecc8857d219ee79bf`。
REA 证明的是保留文件中的请求与响应；客户端操作由用户完成，进程与转发链来自 FlClash 连接日志。

## 七类搜索

统一使用 `music.search.SearchCgiService.DoSearchForQQMusicDesktop`，
请求键为 `music.search.SearchCgiService`。这轮关键词为「鸣潮」。
以下响应的 HTTP 状态、网关 `code`、业务 `code`、业务 `data.code` 都成功（200 / 0 / 0 / 0）。

| 分类 | HAR / SAZ 请求 | search_type | remoteplace | page_num / num_per_page | 返回路径 / 实际条数 | meta.sum |
| --- | --- | --- | --- | --- | --- | --- |
| 歌曲 | 7 / `raw/026_c.txt` | 0 | `sizer.newclient.song` | 1 / 40 | `body.song.list` / 40 | 1000 |
| 视频 | 2 / `raw/010_c.txt` | 4 | `sizer.newclient.mv` | 1 / 56 | `body.mv.list` / 56 | 443 |
| 专辑 | 3 / `raw/012_c.txt` | 2 | `sizer.newclient.album` | 1 / 30 | `body.album.list` / 30 | 251 |
| 歌单 | 4 / `raw/014_c.txt` | 3 | `sizer.newclient.playlist` | 0 / 21 | `body.songlist.list` / 21 | 300 |
| 歌词 | 1 / `raw/008_c.txt` | 7 | `txt.newclient.top` | 1 / 10 | `body.song.list` / 10 | 1000 |
| 歌手 | 5 / `raw/016_c.txt` | 1 | `sizer.newclient.singer` | 1 / 28 | `body.singer.list` / 19 | 19 |
| 用户 | 6 / `raw/018_c.txt` | 8 | `sizer.newclient.users` | 1 / 30 | `body.user.list` / 31 | 401 |

表中路径相对于业务 `data`，例如视频为
`response["music.search.SearchCgiService"].data.body.mv.list`。
`grp=1`，`searchid` 为 37 位大写十六进制字符串；这组分类请求复用了同一个搜索 ID。
每页数量为官方客户端本次布局的实测值，不能视为接口固定限制。

视频请求业务体：

```json
{
  "music.search.SearchCgiService": {
    "module": "music.search.SearchCgiService",
    "method": "DoSearchForQQMusicDesktop",
    "param": {
      "grp": 1,
      "num_per_page": 56,
      "page_num": 1,
      "query": "鸣潮",
      "remoteplace": "sizer.newclient.mv",
      "search_type": 4,
      "searchid": "<GENERATED_SEARCH_ID>"
    }
  }
}
```

实际请求另含登录与设备 `comm`；不能只发送上面这个业务片段就宣称复现成功。

需要保留的差异：

- 歌词搜索仍返回歌曲对象，额外有 `lyric` / `lyric_hilight` 等字段；不是整首歌词下载接口。
- 歌单请求出现 `page_num=0`，但响应 `meta.curpage=1`；其他分类本轮请求为 1。
  尚未抓到歌单第二页，不能直接将歌曲分页规则套用给歌单。
- 视频返回 `meta.nextpage=2`，本包没有第二页视频搜索请求，翻页尚未实证。
- 用户实际返回 31 条，超过请求的 30 条。不能仅凭列表长度等于 page size 判断是否还有下一页。
- 歌手返回 `meta.nextpage=-1`；其余本轮分类为 2。
  总数应按业务需求区分 `meta.sum` 与 `meta.estimate_sum`，两者本轮有不一致。

视频列表关键字段：`v_id`（字符串 VID）、`mv_id`、`mv_name`、`mv_pic_url`、
`duration`、`play_count`、`singer_list`、`singerMID`、`singer_name`、`pay`、`notplay`、`video_switch`。
另含上传者与视频类型字段。不能把视频搜索中的全部对象都假定为官方 MV，
也不能用 `mv_id` 替代后续接口需要的字符串 VID。

其他分类的主要定位字段：专辑 `albumMID` / `albumID`，歌单 `dissid`，
歌手 `singerMID` / `singerID`；用户返回账号与展示字段，本文不保留其值。

## MV 详情、播放地址与清晰度切换

| 功能 | HAR / SAZ 请求 | 请求键 | module.method |
| --- | --- | --- | --- |
| MV 元数据 | 8、15 / `raw/034_c.txt`、`raw/102_c.txt` | `GetMVStreamInfo` | `music.video.VideoData.get_video_info_batch` |
| MV 取流 | 9、16 / `raw/038_c.txt`、`raw/104_c.txt` | `GetMvUrls` | `music.stream.MvUrlProxy.GetMvUrls` |
| 关联推荐 | 10–13、17 / `raw/040_c.txt`、`raw/045_c.txt`、`raw/049_c.txt`、`raw/053_c.txt`、`raw/108_c.txt` | `rec_video_byvid` | `video.VideoLogicServer.rec_video_byvid` |
| MV 评论 | 14 / `raw/077_c.txt` | `req_0`、`req_1` | `music.globalComment.CommentRead.GetNewCommentList` / `GetHotCommentList` |

元数据参数为 `vidlist: ["<VID>"]` 和 `required: [...]`，响应按 VID 索引：
`response.GetMVStreamInfo.data[VID]`。返回 `name`、`cover_pic`、`singers`、
`duration`、`playcnt`、`pubdate`、`play_forbid_reason`、`pay_info`、`video_pay`、
`filesize`、`filesize_v2` 等。样本时长为 169 秒，条目 `code=0`、`play_forbid_reason=0`。
`filesize_v2` 按 `mp4` / `mp4_h265` / `hls` / `hls_h265` 分组，元素含 `fmt` / `fs` 等，
部分元素为全零占位，不能将所有数组元素视为可用画质。

首次取流参数：

```json
{
  "filetype": 10,
  "format": 265,
  "guid": "<CURRENT_DEVICE_GUID>",
  "maxFiletype": 60,
  "request_type": 10003,
  "testCdn": 1,
  "vids": ["<VID>"]
}
```

用户切换清晰度后，对同一 VID 再次请求，`filetype` 变为 `40`，上述其他字段未变。
本轮没有记录界面清晰度标签与编码参数的逐项对应，不能据此直接命名为某个分辨率。

返回对象为 `response.GetMvUrls.data[VID]`，含 `mp4[]`、`hls[]`、`duration`、`svp_flag`。
每个流条目有独立 `code`、`filetype`、`format`、`newFileType`、`expire`、`fileSize`、
`url`、`freeflow_url`、`comm_url`、`urlPath`、`m3u8` 等字段。

- 两次请求均 HTTP 200，网关及业务 `code=0`；但流条目并非全部成功。
  `filetype=10/20/30/40` 的条目 `code=0`，其他占位条目在本样本为 2000。
- MP4 成功条目的 `urlPath` 非空，是相对媒体路径；`url` / `freeflow_url` / `comm_url` 数组均为空。
  不能只取 `mp4[0].url[0]`，也不能把相对路径直接当成完整播放 URL。
- HLS 中仅当前请求 `filetype` 对应条目的 `m3u8` 非空，内容为带 17 个相对分片路径的
  `#EXTM3U` 播放列表。两次分别命中 10 与 40。
- 样本 `expire=86400`。路径中含动态鉴权信息，不能把本次返回路径硬编码或发布到文档。
- 本轮未包含 CDN 调度请求或媒体文件响应；仍缺少当前会话的 CDN 基址与实际媒体下载验证。
  这份包确认了元数据、取流和清晰度参数，尚不足以宣称已完成独立 MV 播放。

关联推荐参数为 `vid`、`support=1`、`required` 字段列表；五次业务成功，但本样本 `data.list` 均为空。
评论使用 `BizType=5`、`BizId=VID`。最新 / 热门请求 `PageNum=0`，`PageSize` 分别 25 / 15，
业务 `data.SubCode=0`，分别返回 6 / 0 条主评论。本轮未重放播放上报或其他写请求。

## 传输上下文与后续接入边界

本轮上表请求均为 `POST https://u6.y.qq.com/cgi-bin/musics.fcg`，
`Content-Type: application/x-www-form-urlencoded`，正文实际为 JSON 字符串。
响应包含 Brotli 压缩，需要按响应头解码后再解析。

原生搜索与 MV 请求带 Cookie、原生 `Sign` / `Mask`，使用字符串型 `ct="19"`、`cv="2276"`、
`patch="118"`。MV 评论来自 qmbrowser 内嵌页，使用数字型 `ct=20`、`cv=2276`、
`platform="wk_v17"`，本次没有原生 Sign / Mask 请求头。
不能把既有应用的无原生签名 `musicu.fcg` 通道与这次实抓的 `musics.fcg` 视为已验证等价。
本轮没有独立重放、未登录调用、其他账号、付费 MV 或完整分辨率映射验证。

可复用抓包入口：

```powershell
node scripts/capture-qqmusic-fiddler.mjs --check --search
node scripts/capture-qqmusic-fiddler.mjs --capture --search
```

搜索模式复用已有扩展进程 / 域名规则，持续 300 秒，并在结束时恢复原路由与代理选择。
它不自动操作客户端，也不自动保存 Fiddler 会话。本轮已保存会话并恢复临时路由。
脚本通过 `node --check` 和准备检查；文档与脚本通过 `git diff --check`。
本轮不涉及 Dart / Rust 业务实现，因此未运行应用测试。
