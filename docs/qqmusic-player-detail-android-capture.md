# QQ 音乐：Android 播放页右滑的歌曲信息页

观察日期：2026-11-09（北京时间）。Android 官方 QQ 音乐 20.09（`QQMusic 20090808`，已登录）的播放页顶部有三个页面圆点，
中间是播放页，手指从左往右滑会进入左侧的「歌曲信息页」。PC 客户端没有这一页。
在 MuMu 15 中用 `scripts/capture-qqmusic-android.mjs --prepare` 经 Fiddler 抓包。本轮只读，只点过一次「相关歌单 · 换一批」。

## 证据

| 本地材料 | 字节 | SHA-256 |
| --- | --- | --- |
| `qqmusic-player-detail-android-20261109.saz` | 5734922 | `00b419ee2e82ba18ea3b63edcbe8c068642e9f6a529877e6f42738bb68621dc6` |
| `qqmusic-player-detail-video-android-20261109.saz` | 19334661 | `797dd7f47fcb4195a2d4b2901bc2f43abe8cb766ffcbfdd72c9ec63e58f44b99` |

两个文件都由现有 `.gitignore` 排除。请求公参含 `authst`、`wxrefresh_token`、Cookie 和设备标识，不应提交或公开；本文不复制这些值。

| 文件 / 会话 | 时间 | 内容 |
| --- | --- | --- |
| 第一份 `raw/726` | 01:10:33.622 | 右滑进入《Lost Soul》（`songid=663019890`）信息页，一个请求合并 15 个接口 |
| 第一份 `raw/724` | 01:10:33.607 | 同时单独发出的 `music.sociality.KolWorksTag.SongProducer` |
| 第一份 `raw/811` | 01:11:25.706 | 点「相关歌单 · 换一批」 |
| 第二份 `raw/0110` | 01:13:22.064 | 切到下一首《Picture of You》后，信息页的同一合并请求 |
| 第二份 `…getVideoListBySongidForPlayPage` | 01:15–01:17 | 播放页的视频入口请求，含《月声尽，心灯明》（`songid=728834042`） |

## 传输

与[专属乐流](qqmusic-feed-column-capture.md)、[Android 最近播放](qqmusic-recent-plays-android-capture.md)相同：
`POST https://u6.y.qq.com/cgi-bin/musics.fcg`，`M-Encoding: m1`，带 `sign` / `mask`，请求体 5 字节前缀加 zlib 压缩的 JSON。
同时发出的 `musicw.fcg` 请求（`mlive.recommend.MliveRecommendExternalFlowSvr.PlayPageRecommend`，直播推荐）是 JCE 二进制，本轮没有解析。

请求时机：手指滑到左页时才发出，不是在打开播放页时预取（01:10:32.5 滑动，01:10:33.6 发出）。
往下滚动不再发新请求，整页数据都来自这一次合并请求。

## 合并请求

请求键等于 `module.method`。参数中的 `extra_info` / `ext` 和[最近播放](qqmusic-recent-plays-android-capture.md)一样是设备状态
（电量、音量、`recent_play_song_list` 等），是否必填未验证。AI 解读的参数带 `custom_params.from = "player_leftSlide"`。

| 接口 | 参数 | 页面上的栏目 | 《Lost Soul》的结果 |
| --- | --- | --- | --- |
| `music.musichallSong.SongInfoServer.GetSongDetail` | `{"songMid"}` | 标题、发行日期、「歌曲详情」链接 | `basic.name`、`basic.album.{mid,name,pubTime}`、`basic.jumpURL`（百科 H5 页） |
| `music.recommend.TrackRelationServer.GetSongLabels` | `{"songid", "ext"}` | 「85人在听」等标签行 | 见下文 |
| `music.SearchConfig.AiInterpretationSvr.GetAiInterpretation` | `{"id": "<songid 字符串>", "keyword": "", "custom_params": {"from": "player_leftSlide"}}` | 「问元宝」AI 解读 | `aidirect_list[0].{title, content, scheme}` |
| `music.artistMedal.ArtistMedalEntrySrv.GetSongMedalEntry` | `{"SongID"}` | 歌曲成就勋章 | `Title`、`MoreScheme`，`MedalList[].{Title, SubTitle, PicURL, UnlockStatus, CreateTime}` |
| `music.recommend.TrackRelationServer.GetSimilarSongs` | `{"songid", "extra_info"}` | 听「歌手」的也在听 | `vecSongNew[0].songs` 15 首（页面只显示 3 首），标题模板 `title_template` + `title_content` |
| `music.recommend.TrackRelationServer.GetRelatedPlaylist` | `{"songid", "extra_info"}` | 相关歌单推荐 | `vecPlaylistNew[0].playlists` 7 个，`hasMore=1` |
| `MvService.MvInfoProServer.GetSongRelatedMv` | `{"songid": "<字符串>", "songtype": 1, "lastmvid": 0}` | 精选视频（推断，见下文） | `list: []`，页面没有这一栏 |
| `music.video.TencentVideoQuery.GetVideoListBySongId` | `{"songId", "songType": 1}` | 相关影视（推断） | `list: null` |
| `music.musichallSong.OtherVersionServer.GetRecommedRank` | `{"version": 0}` | 栏目顺序 | 见下文 |
| `music.musichallSong.OtherVersionServer.GetOtherVersionSongs` | `{"songID", "songMid", "sin": 0}` | 其他版本 | `versionList: []` |
| `music.longRadio.recommend.getSongRelateLongRadioAlbum` | `{"songid", "fversion": 1, "load_more": 0}` | 节目推荐 | `albumList: null` |
| `music.mir.SheetMusicSvr.GetMoreSheetMusic` | `{"songMid", "scoreType": -1}` | 相关曲谱 | `code=10007`，无曲谱 |
| `music.superSound.EffectRecommend.GetPlaypageRecTab` | `{"songID", "singerIDs"}` | 歌手音效 | 全空 |
| `music.medalHall.MedalRecommendSrv.GetMedalRecEntrance` | `{"SongID", "From": 1, "Singers"}` | 勋章入口 | `Enable=false` |
| `music.osu.OsuTrackSvr.GetPlaypageRecommendTab` | `{"trackId"}` | 弹一弹（音游） | `enabled=1`，其余为空 |

空结果的模块不显示对应栏目。《Lost Soul》页面从上到下是：标题信息、标签行、AI 解读、成就勋章、也在听、相关歌单。

### 栏目顺序

`GetRecommedRank.recMods` 是 26 个 `{id, title, subid}`，按顺序为：

单曲详情 10000、歌曲标签 10020、在听 10017、相关信息 10016、歌曲参数 10014、音乐人活动标签 10015、歌手音效 10024、AI 10025、
成就勋章 10026、勋章 10023、弹一弹 10018、相似单曲 10003、相关歌单 10004、直播推荐 10022、**相关视频 10007**、节目推荐 10021、
其他版本 10001、相关艺人 10011、相关专辑 10012、相关节目 10010、相关曲谱 10019、相关阅读 10005、广告 10006、相关影视 10013，
最后又出现一次相似单曲（`subid=1`）和相关歌单（`subid=1`）。两首样本的顺序相同。

### 标签行

`GetSongLabels.labels[]`：`{id, tagTxt, tagIcon, tagUrl, tagType, species}`。

| 样本 | `tagType` / `species` / `tagTxt` |
| --- | --- |
| Lost Soul | `24/3/""`（图标）、`23/5/"85人在听"`、`31/1/"87%的人听完"`、`9/1/"本周热播"`、`1000/7/""` |
| Picture of You | `24/3/""`、`23/5/"32人在听"`、`1/1/"#Pop"`、`28/1/"\"暖暖的透气感音色\""`、`9/1/"收藏10w+"`、`1000/7/""` |

带 `tagUrl` 的标签跳到 `qqmusic://qq.com/ui/similarSongs?p={"songid","tagid","tagName"}`。`tagTxt` 为空的两项页面上不显示文字，
用途未验证。Picture of You 页面上还有「制作：King Henry/Steven Martinez」和「44.1kHz 16bit」两项，
它们不在这个合并请求里（`GetSongDetail.songAuthor` 全空），来源没有查清。

### AI 解读

`GetAiInterpretation` 的结果在 `data.aidirect_list[0]`：

| 字段 | 内容 |
| --- | --- |
| `title` | 解读标题，如「《Lost Soul》两分钟装下刷视频的怅惘」 |
| `content` | 完整正文（样本 345 字），页面按 `custom_info.line_cnt`（`"3"`）截成 3 行，末尾显示「…」 |
| `custom_info.word_speed` | `"10"`，用途未验证 |
| `docid` | `143007511_music_explain_v13` |
| `scheme` | 跳转元宝对话：`qqmusic://qq.com/ui/aiAssistantQuery?p=…`，`p` 里的 `sendMessage` 是标题、`openNewSession="1"` |

Kanade 只需要 `title` 和 `content`，不接入元宝对话（那等于转发官方的 AI 服务）。
空结果时 `aidirect_list` 的形状未见到；无签名、未登录能否取到也未验证。

### 也在听 / 相关歌单

- `GetSimilarSongs.vecSongNew[0].songs[]` 每项 `{track, tf, abt, trace}`，`track` 是常规歌曲对象；
  `songTagInfoList[]` 是这些歌曲的小标签（`{id: songid, tag: "本周热播", link, tagid, from_type}`）。
  旧字段 `vecSong` 只有 3 首。
- `GetRelatedPlaylist.vecPlaylistNew[0].playlists[]`：`{tid, songNum, cover, title, creator, playCnt}`，`playCnt` 是字符串。
  旧字段 `vecPlaylist` 为空。

「换一批」（`raw/811`）只请求 `GetRelatedPlaylist`，在参数里加上 `vecPlaylist`，值是当前已显示的 tid 数组，`extra_info.module` 为 `"1"`；
返回 6 个不重复的新歌单，`hasMore` 仍为 1。

## 精选视频

用户反馈部分歌曲在这页会多一栏「精选视频」，例如《月声尽，心灯明》（`songid=728834042`）。在 MuMu 中打不开这首歌的播放页（见下文），
所以**没有抓到这首歌信息页的官方请求，也没有在模拟器里看到这一栏的实际样子**。

可以确定的部分：

- 同一首歌的播放页视频入口 `music.video.VideoSong.getVideoListBySongidForPlayPage`（`{"song_id", "song_type": 0, "from": 33, ...}`）
  返回一条视频：`vid=010Sz9DR1a8FZ9`，标题「《月声尽，心灯明》全曲翻唱（cover：鸣潮先约电台）@…」。
- 本机匿名、不签名请求 `https://u.y.qq.com/cgi-bin/musicu.fcg`（`comm: {ct: 24, cv: 0, format: "json"}`）：
  - `MvService.MvInfoProServer.GetSongRelatedMv`，`{"songid": "728834042", "songtype": 1, "lastmvid": 0}`，
    返回同一个 `vid`：`{hasmore: 0, list: [{mvid: 52772404, vid, title, picurl, playcnt, singers: []}]}`。
  - `music.video.TencentVideoQuery.GetVideoListBySongId` 返回 `list: null`。
  - 换成《晴天》（`97773`）：`GetSongRelatedMv` 返回 3 条官方 MV / 演唱会视频，`hasmore=1`；把 `lastmvid` 设为上一页最后一项的 `mvid`，
    返回下一条，`hasmore` 仍为 1。`GetVideoListBySongId` 返回的是腾讯视频影视剧条目（`{id, title, secondTitle, hzCover, vtCover, ...}`），
    对应「相关影视」。

由此推断「精选视频」就是 `recMods` 里的「相关视频 10007」，数据来自 `GetSongRelatedMv`。如果要确认标题文案、显示条数和点击行为，
需要在真机上看一次这首歌的信息页。

## MuMu 中的闪退

《月声尽，心灯明》《Summer Solstice》一打开播放页，App 就在主进程的 `MediaCodec_loop` 线程 SIGSEGV 退出
（`libstagefright.so` 的 `MediaCodec::setState`）；Lost Soul、Picture of You 正常。

- 播放进程是单独的 `com.tencent.qqmusic:QQPlayerService`，主进程崩溃时它还活着，崩的时候也没有在播放，所以不是音频解码的问题。
  把在线音质从 HQ（ogg）改成标准、关闭「播放页动态封面」、更换 MuMu 渲染器，都没有解决。
- 推测是播放页对带视频的歌曲做了视频解码，仅在模拟器（x86_64 上跑 arm64 App）里出问题。真机上是否正常、具体是哪个视频组件，都未验证。
- 测试结束后已把音质和动态封面改回 HQ / 开启。

## 未验证

- 精选视频栏的标题、条数、排序和跳转，以及它是否只用 `GetSongRelatedMv`。
- 「制作」「44.1kHz 16bit」两项的数据来源。
- `extra_info` 设备状态字段是否必填；不签名、不登录调用这些接口的稳定性（本轮只验证了上述两个视频接口）。
- `musicw.fcg` 直播推荐的 JCE 内容。
