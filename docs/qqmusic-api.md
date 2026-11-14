# QQ 音乐接口参考

Kanade 用到的 QQ 音乐上游接口，以及它们在 Rust 里的位置。这不是官方文档，只描述当前代码的做法。改接口前先看这里，改完同步更新。

Dart 只调用 [api/music.rs](../rust/src/api/music.rs)，它把请求转给 `rust/src/qq/` 下的实现。下文写的函数名都是 `qq` 模块里的；它们和 Dart 入口的对应关系见文末[Dart 入口](#dart-入口)。

## 目录

- [请求通道](#请求通道)
- [搜索](#搜索)
- [歌曲信息与音质](#歌曲信息与音质)
- [取播放链接](#取播放链接)
- [歌词与高潮片段](#歌词与高潮片段)
- [首页推荐](#首页推荐)
- [榜单](#榜单)
- [歌单](#歌单)
- [最近播放](#最近播放)
- [歌手与专辑](#歌手与专辑)
- [播放页信息页](#播放页信息页)
- [MV](#mv)
- [评论](#评论)
- [用户主页与关注](#用户主页与关注)
- [听歌识曲](#听歌识曲)
- [登录](#登录)
- [缓存](#缓存)
- [错误](#错误)
- [Dart 入口](#dart-入口)

## 请求通道

### 网关

大多数接口是 `POST` 一个 JSON 到统一网关：`musicu.fcg` / `musics.fcg` 只是入口，真正的业务由正文里的 `module` + `method` 决定。旧版 `c.y.qq.com` 的 CGI 用 `GET`，返回 JSON 或 JSONP。

所有通道都在 [client.rs](../rust/src/qq/client.rs)：

| 通道 | 函数 | 地址 | 请求键 | Cookie | 说明 |
| --- | --- | --- | --- | --- | --- |
| 通用 | `musicu` | 先 `u.y.qq.com/cgi-bin/musics.fcg?_=…&sign=…`，失败再 `musicu.fcg` | `req_0` | 已登录就带 | 签名请求出错或业务码非 0 时，原样重发到 `musicu.fcg` |
| 通用 + 覆盖公参 | `musicu_with_comm` | 同上 | `req_0` | 同上 | 把额外字段合并进公参，见下方[公参](#公参) |
| 通用写入 | `musicu_write_with_comm` | `u.y.qq.com/cgi-bin/musicu.fcg` | `req_0` | 必须登录 | 只发一次，不重发 |
| PC 公共 | `desktop_musicu` | `u6.y.qq.com/cgi-bin/musicu.fcg` | `module` 原文 | 不带 | 公参里仍带账号 |
| PC 私有 | `desktop_private` | 同上 | `module.method` | 带 | 读写自己的数据 |
| PC 登录 | `desktop_login` | 同上 | 调用方给 | 不带 | 以未登录的 PC 客户端身份登录或续期 |
| Android 写入 | `mobile_write` | `u.y.qq.com/cgi-bin/musicu.fcg` | `req_0` | 必须登录 | UA `QQMusic 14090008(android 10)`，只发一次 |
| App 授权 | `TmeClient::call`（[login.rs](../rust/src/qq/login.rs)） | 同上 | `req_0` | 显式为空 | 独立的 Android 设备会话，不借用当前账号 |
| 旧 CGI | `get_json` | 各 `c.y.qq.com` / `c6.y.qq.com` 地址 | — | 已登录就带 | `GET`，自动剥掉 JSONP 外壳 |

请求正文形如：

```json
{
  "comm": { "...": "公参" },
  "req_0": { "module": "music.xxx.Yyy", "method": "Zzz", "param": {} }
}
```

PC 通道把 `req_0` 换成 `module` 或 `module.method`，响应里的结果也在同名的键下。下文写的“返回”都相对于这个键下的 `data`；旧 CGI 则相对于原始响应。

请求头要点：

- 通用和 Android 通道：`Content-Type: application/json`，`Referer` / `Origin` 为 `https://y.qq.com`，UA 为 Chrome。
- PC 通道：UA 为 `Mozilla/5.0 (compatible; MSIE 9.0; …)`，`Content-Type` 写的是 `application/x-www-form-urlencoded`，但正文直接是 JSON 字符串，不是表单。

### 公参

| 公参 | 用在哪 | 字段 |
| --- | --- | --- |
| 通用 | 通用通道 | `ct=11`、`cv=v=13020508`、`tmeAppID="qqmusic"`、`format="json"`、`inCharset/outCharset="utf-8"`、`uid=<10 位数字 GUID>`；登录后加 `qq=<musicid>`、`authst=<musickey>`、`tmeLoginType="1"/"2"`（字符串） |
| 内嵌页 `webkit_comm` | 歌手、专辑、评论、电台、用户主页等，合并在通用公参上 | `ct=20`、`cv=2276`、`platform="wk_v17"`、`uin=<musicid 或 "0">`、`g_tk=g_tk_new_20200303=hash33(musickey, 5381)`（未登录为 `5381`）、`needNewCode=1`、`notice=0` |
| Android 推荐 `android_feed_comm` | 首页推荐、专属乐流、自定义推荐页 | 合并 `cv=v="20090808"`、`chid="73387"` |
| Android 版本号 `android_comm` | 360RA 的歌曲信息和取链接 | 合并 `cv=v=14090008` |
| PC | PC 通道 | `ct="19"`、`cv="2276"`、`_channelid="20"`、`_os_version="6.2.9200-2"`、`patch="118"`、`tmeAppID="qqmusic"`、`guid=<32 位大写十六进制>`；登录后加 `uin`、`authst`、`tmeLoginType=1/2`（数字） |
| PC 登录 | `desktop_login` | PC 公参，但 `uin="0"`、`authst=""`、`tmeLoginType=<调用方给>`，另加空的 `psrf_access_token_expiresAt/psrf_qqaccess_token/psrf_qqopenid/psrf_qqunionid` |
| Android 写入 | `mobile_write` | `ct=11`、`cv=v=14090008`、`chid="10003505"`、`tmeAppID`、`tmeLoginType`（字符串）、`qq`、`authst`、`format="json"` |
| App 授权 | `TmeClient` | `ct=11`、`cv=v=14090008`、`chid="10003505"`、`tmeAppID`、`tmeLoginType=2`、`qq="0"`、`authst=""`、`uid`/`sid`（来自 `GetSession`）、`OpenUDID=OpenUDID2=udid=<安装 ID>`；Android 上另加 `os_ver/phonetype/devicelevel/newdevicelevel/rom`，取自系统属性 |

两个设备标识都存在数据库的 kv 表里，生成一次后不再变：`guid`（10 位数字）给通用通道用，`desktop_guid`（32 位十六进制）给 PC 通道用。App 授权用另一个 `mobile_login_device_id`。

未登录时 `Core::uin()` 返回 `"0"`。会话里的 `uin` 存的是 QQ 音乐返回的 `musicid`，不一定等于 QQ 号，可能超出 JavaScript 的安全整数范围，跨语言传递时保持字符串。

### Cookie 与签名

登录后的 Cookie：

```text
uin=<musicid>; qqmusic_uin=<musicid>; qqmusic_key=<musickey>; qm_keyst=<musickey>; tmeLoginType=<1 或 2>
```

微信账号（`login_type=1`）另加 `wxuin=<musicid>`。QQ 账号的 `login_type` 是 `2`。

- `hash33(s, h0)`：逐字符 `h = h + (h << 5) + codepoint`（wrapping），最后取 `h & 0x7fffffff`。`g_tk` 的初值是 `5381`，QQ 扫码的 `ptqrtoken` 初值是 `0`。
- 通用通道 `musics.fcg` 的 `sign` 用的是网页版的 zzc 签名，算法见 [sign.rs](../rust/src/qq/sign.rs)。它是对**实际发送的那串 JSON** 算的，改了字段顺序或空白就要重新签名。
- 官方 PC 客户端请求头里的 `Sign` / `Mask` 是另一套机制，Kanade 没有实现。PC 通道走 `u6.y.qq.com/cgi-bin/musicu.fcg`，这个网关不检查它们。

## 搜索

实现：[music.rs](../rust/src/qq/music.rs) `search`、`hot_search`、`search_suggestions`。

| 功能 | 接口 | 通道 | 参数 | 返回 |
| --- | --- | --- | --- | --- |
| 分类搜索 | `music.search.SearchCgiService.DoSearchForQQMusicDesktop` | PC 公共 | `query`、`search_type`、`num_per_page`、`page_num`（从 1 开始）、`remoteplace`、`searchid`、`grp=1` | `body.<分类>.list`，总数 `meta.sum`，`meta.nextpage > 0` 表示还有下一页（最后一页是 `-1`） |
| 未登录搜歌 | GET `https://c.y.qq.com/soso/fcgi-bin/client_search_cp` | 旧 CGI | `w`、`p`、`n`、`format=json` | `data.song.list`、`data.song.totalnum`；没有 `nextpage`，按总数估算是否还有下一页 |
| 热搜 | `tencent_musicsoso_hotkey.HotkeyService.GetHotkeyForQQMusicPC` | PC 公共 | `search_id=""`、`uin=<musicid 数字，未登录 0>` | `vec_hotkey`（热搜）、`vec_reckey`（登录后的“猜你想搜”），读 `title/query/description`，丢掉空 `query` |
| 联想 | `music.smartboxCgi.SmartBoxCgi.GetSmartBoxResultForPc` | PC 公共 | `num_per_page=4`、`query`、`search_id` | `data.song.song_list`、`data.singer.singer_list`、`data.album.album_list`，读 `name` 和 `singer`；支持拼音和首字母 |

只有“未登录 + 搜歌曲”走旧 CGI，其余情况都走 PC 接口（旧 CGI 没有其他分类）。`searchid` 每次随机生成，37 位大写十六进制。

| `SearchKind` | `search_type` | `remoteplace` | 列表 | 读取的字段 |
| --- | --- | --- | --- | --- |
| `Song` | 0 | `txt.newclient.top` | `body.song.list` | 统一歌曲解析 |
| `Singer` | 1 | `sizer.newclient.singer` | `body.singer.list` | `singerMID/singerName/songNum/albumNum` |
| `Album` | 2 | `sizer.newclient.album` | `body.album.list` | `albumMID/albumName/publicTime`，歌手取 `singer_list[].name` |
| `Playlist` | 3 | `sizer.newclient.playlist` | `body.songlist.list` | `dissid/dissname/imgurl/song_count/listennum/creator.name` |
| `Video` | 4 | `sizer.newclient.mv` | `body.mv.list` | `v_id`（字符串 VID）、`mv_name/mv_pic_url/duration/play_count`；`singer_name` 为空且有 `uploader_nick` 时是用户上传的视频 |
| `Lyric` | 7 | `txt.newclient.top` | `body.song.list` | 歌曲对象。`lyric` / `lyric_hilight` 常为空，歌词在 `content` 里，第一行是“歌名 - 歌手”；取包含关键词的前两行，优先非署名行（“词：xxx”这种） |
| `User` | 8 | `sizer.newclient.users` | `body.user.list` | `encrypt_uin/title/pic/fans_num/diss_num/identify_title`；`iconurl` 是认证角标，不是头像；结果里没有明文账号 |

## 歌曲信息与音质

实现：[quality.rs](../rust/src/qq/quality.rs)。

### 歌曲信息

`music.trackInfo.UniformRuleCtrl.CgiGetTrackInfo` 有两种用法：

| 用途 | 通道 | 参数 | 返回 |
| --- | --- | --- | --- |
| 按数字 ID 补全歌曲（`music::tracks_by_id`） | 通用 | `ids=[id,…]`、`types=[0,…]`，两个数组一样长 | `tracks[]` |
| 取文件信息（`quality_track`） | 登录后 PC 公共，未登录通用 | `ctx=0`、`client=1`、`types=[0]`、`modify_stamp=[0]`、`mids=[mid]` | `tracks[0].file`、`tracks[0].vs` |

推荐卡片、专属乐流、听歌识曲拿到的只有数字 ID，都靠第一种补全。

三种 ID 不能混用：`song.id` 是数字 ID（评论、红心、上报都用它），`song.mid` 是歌曲 MID，`file.media_mid` 是拼文件名用的媒体 MID。`media_mid` 缺失时用歌曲 MID。

### 音质档位与文件名

明文文件名是 `前缀 + media_mid + media_mid + "." + 扩展名`。一首歌有哪些档位，看 `file` 里对应的大小字段是否大于 0。

| `Quality` | 前缀 | 扩展名 | 大小字段 | 说明 |
| --- | --- | --- | --- | --- |
| Dts | DT03 | mp4 | `size_new[9]` | 需要 DTS 解码器 |
| Ra360 | RA04 | mp4 | `size_360ra[3]` | 需要 360RA 解码器；见下文 |
| Master | AI00 | flac | `size_new[0]` | 母带 |
| Atmos | Q000 | flac | `size_new[1]` | 全景声 |
| Atmos71 | Q003 | ogg | `size_new[6]` | |
| Atmos51 | Q001 | flac | `size_new[2]` | |
| Dolby | D004 | mp4 | `size_dolby` | 明文是 AC-4，播放器解不了，只走加密的 `D0M1` |
| Hires | RS01 | flac | `size_hires` | |
| Lossless | F000 | flac | `size_flac` | SQ |
| High | M800 | mp3 | `size_320mp3` | HQ；`size_new[3]`（Ogg320）大于 0 时也列出 |
| Aicodec | TL01 | nac | `size_new[7]` | AI 音质，需要 NAC 解码器，只走加密的 `TLM1` |
| Standard | M500 | mp3 | `size_128mp3` | |
| Low | C400 | m4a | `size_96aac` | |
| Ogg640 / Ogg320 / Ogg192 / Ogg96 | O801 / O800 / O600 / O400 | ogg | `size_new[5]` / `size_new[3]` / `size_192ogg` / `size_96ogg` | 只是编码格式，不在音质菜单里单列 |
| Aac192 / Aac48 | C600 / C200 | m4a | `size_192aac` / `size_48aac` | 同上 |

### 加密文件

登录后，明文拿不到的档位可以用 `music.vkey.GetEVkey.CgiGetEVkey`（PC 公共）取加密文件：

```json
{
  "uin": "<musicid>", "guid": "<desktop_guid>", "ctx": 1,
  "songmid": ["<mid>"], "songtype": [0],
  "filename": ["<加密文件名>"], "musicfile": ["<同格式，ID 用 media_mid>"],
  "checklimit": 0, "downloadfrom": 0, "nettype": "", "referer": "y.qq.com", "scene": 0
}
```

| 档位 | 加密文件名 | 文件名里的 ID | 解密后 |
| --- | --- | --- | --- |
| Master | `AIM0<ID>.mflac` | `track.vs[3]` | FLAC |
| Atmos | `Q0M0<ID>.mflac` | `track.vs[29]` | FLAC |
| Lossless | `F0M0<ID>.mflac` | `file.media_mid` | FLAC |
| High | `O8M0<ID>.mgg` | `file.media_mid` | Ogg |
| Dolby | `D0M1<ID>.mmp4` | `file.media_mid` | MP4（E-AC-3） |
| Dts | `DTM3<ID>.mmp4` | `track.vs[30]` | MP4（DTS-UHD） |
| Aicodec | `TLM1<ID>.mnac` | `track.vs[28]` | NAC |

加密文件名里 ID 只出现一次，和明文不同。`media_mid` 以歌曲信息里的 `file.media_mid` 为准。

返回的 `midurlinfo[]` 按 `filename` 匹配，要求 `result=0`、`purl` 非空、有 `ekey`。`purl` 是完整 https 地址就直接用，否则拼上 `sip` 里第一个 https 地址（都没有就用 `https://isure.stream.qqmusic.qq.com/`）。之后用 `ekey` 下载并解密文件开头，确认容器头对得上才算可用（[encrypted_audio.rs](../rust/src/qq/encrypted_audio.rs)、[qmc.rs](../rust/src/qq/qmc.rs)）。播放时 `SongUrl.ekey` 交给本机中转边下边解密，见 [audio_cache.rs](../rust/src/qq/audio_cache.rs)。

### 360 Reality Audio

`size_360ra` 和 `RA04` 的链接只对 Android 客户端版本号开放；用 PC 或旧版本号请求时，`size_360ra` 是空数组，取链接返回 `104003`。所以 360RA 单独走通用通道加 `android_comm`：

- 文件大小：`CgiGetTrackInfo`（`mids` 写法）读 `tracks[0].file.size_360ra`。
- 链接：`music.vkey.GetVkey.UrlGetVkey`，参数 `guid=<10 位 guid>`、`uin`、`loginflag=1`、`platform="20"`、`ctx=0`、`songmid`、`songtype=[0]`、`filename=["RA04…mp4"]`，再用 `HEAD` 确认 CDN 文件存在。

### 需要本地解码器的音质

DTS:X、360RA、NAC 由播放器以外的解码器先转成 WAV（缓存扩展名为 `wav`），Rust 边解码边写，解出第一段就交给播放器；拖到还没解出的位置时，本机中转会等解码追上。这些解码器只有 Windows x64 和 Android arm64 有，其他平台 `available()` 为 false。

- DTS：解码库由构建者自备，放进 `windows/dts-local/` 或 `android/app/dts-local/`（Android 也可用 `KANADE_DTS_ANDROID_RUNTIME`）。缺解码器时这一档标成 `Unverified`。
- NAC：模型 `android/app/nac-local/7187332.mnn`，或用 `KANADE_NAC_MODEL` 指定，构建时嵌入原生库。
- 360RA：Windows 用 libmpegh（构建时拉取），Android 运行库放 `android/app/ra360-local/` 或用 `KANADE_RA360_ANDROID_RUNTIME`。

源码在 `native/`，由 `windows/CMakeLists.txt` 和 `android/app/build.gradle.kts` 构建，不经过 cargo。

### 音质列表

`song_qualities(mid)` 的步骤：

1. 用歌曲信息里的大小字段列出候选档位（不含上表“只是编码格式”的几项），初始都标成不可用。
2. 登录且有 NAC 解码器、`vs[28]` 非空时，先用 `CgiGetEVkey` 检查 AI 音质。
3. 其余明文档位一次性批量请求 `UrlGetVkey`：登录后只走 PC 公共（带 `ctx=0`）；未登录先走通用 `UrlGetVkey`，没拿全再试 `vkey.GetVkeyServer.CgiGetVkey`。
4. 拿到链接的档位逐个发 `HEAD` 确认 CDN 文件存在，最多 4 个并发。
5. 有 360RA 解码器时单独检查 360RA。
6. 登录后，仍不可用且有加密格式的档位再试 `CgiGetEVkey`。

不可用的原因（`QualityUnavailableReason`）：授权 `result=104003` → `NoPermission`，`104013` → `DeviceRestricted`，其他没链接的 → `NoLink`，`HEAD` 失败 → `FileUnavailable`，请求本身出错 → `VerifyFailed`，缺解码器 → `Unsupported` / `Unverified`。这是 Kanade 自己的解释，不是官方错误码定义。

`Song.vip/has_hq/has_flac` 来自歌曲元数据，只作提示，不代表当前账号真能播。

## 取播放链接

实现：[music.rs](../rust/src/qq/music.rs) `song_url`。

从用户选的音质开始按 `quality::playback_chain` 逐级降档：

| 起始档位 | 降档顺序 |
| --- | --- |
| Master、Hires、Atmos、Dolby、Dts、Ra360 等扩展档位 | 自身 → Lossless → High → Standard → Low |
| Lossless | Lossless → High → Standard → Low |
| High、Ogg320、Ogg640、Aicodec | 自身 → High → Standard → Low |
| Standard、Ogg192、Aac192 | 自身 → Standard → Low |
| Low、Ogg96 | 自身 → Low |
| Aac48 | 只有自身 |

每一档依次尝试：

1. 明文（Dolby、Aicodec、Ra360 跳过）：`music.vkey.GetVkey.UrlGetVkey`。

   ```json
   {
     "guid": "<登录用 desktop_guid，否则 guid>",
     "songmid": ["<mid>"], "songtype": [0],
     "uin": "<musicid 或 0>", "loginflag": 1, "platform": "20",
     "filename": ["M800<media_mid><media_mid>.mp3"],
     "ctx": 0
   }
   ```

   登录后只走 PC 公共并带 `ctx=0`；未登录走通用、不带 `ctx`，失败再试 `vkey.GetVkeyServer.CgiGetVkey`。读 `midurlinfo[0].purl`，要求 `ekey` 为空；地址是 `sip` 里第一个 https 地址加 `purl`（没有 https 就用第一个，`sip` 为空用默认 CDN）。Low / Standard / High / Lossless 以外的档位还要 `HEAD` 一次确认文件存在。
2. 登录后，有加密格式的档位试 `CgiGetEVkey`，见[加密文件](#加密文件)。
3. Ra360 试 Android 版本号的 `UrlGetVkey`，见 [360 Reality Audio](#360-reality-audio)。

所有请求都出错时把原始错误抛出（通常是网络问题）；有响应但没链接时返回 `NoPlayableUrl`。`SongUrl.quality` 是最终拿到的档位，可能比请求的低，界面要显示它而不是请求值。链接有时效，不缓存。

在线音频不直接交给播放器：`stream_audio` 返回本机中转地址，中转边播边把完整文件写进音频缓存，超过上限（`pref:audio_cache_limit_mb`，默认 1024 MB）时按最近播放时间淘汰。

## 歌词与高潮片段

实现：[music.rs](../rust/src/qq/music.rs) `lyric`、`chorus`，解析在 [lyric.rs](../rust/src/qq/lyric.rs)。

歌词主接口：`music.musichallSong.PlayLyricInfo.GetPlayLyricInfo`，通用通道。

```json
{"songMID":"<mid>","songID":42,"trans":1,"roma":0,"crypt":0,"qrc":0}
```

读 `lyric` 和 `trans`，能按 Base64 解成 UTF-8 就解，否则保留原文。主接口出错或歌词为空时改用旧 CGI：

```text
GET https://c.y.qq.com/lyric/fcgi-bin/fcg_query_lyric_new.fcg?songmid=<mid>&format=json&nobase64=1&g_tk=5381
```

读原始响应的 `lyric` / `trans`。按 LRC 时间轴解析并合并翻译，翻译为 `//` 视为没有翻译；没有时间轴的歌词放在 `Lyric.plain`。请求关掉了 QRC，所以没有逐字歌词和罗马音。

高潮片段不用单独请求：歌曲信息（`CgiGetTrackInfo` 的 `ids` 写法，不需要登录）里的 `file.try_begin` / `file.try_end` 就是官方客户端标出的高潮起止，单位毫秒，没有时两个都是 0。`track.vi[4]` / `vi[5]` 是从同一起点开始的 30 秒试听窗口，Kanade 不用。

## 首页推荐

实现：[music.rs](../rust/src/qq/music.rs)。

### 推荐流

`music.recommend.RecommendFeed.get_recommend_feed`，通用通道 + `android_feed_comm`。必须带新版 Android 的版本号，栏目才有能单独刷新的 `refresh_param`，第 2 页之后才有专属乐流。

`recommend_feed` 和官方首页一样取两页，不缓存（官方每次进首页、下拉都重新取）：

| 页 | `param` |
| --- | --- |
| 第 1 页 | `direction=0`、`page=1`、`s_num=0`、`v_cache=[]` |
| 第 2 页 | `direction=1`、`page=2`、`s_num=<第 1 页栏目数>`、`v_cache=<第 1 页栏目 id>` |

两页都带 `v_uniq=[]` 和 `ext={"is_20_style":"1","has_login":"1"/"0"}`。不带 `is_20_style` 时栏目没有 `refresh_param`。

返回结构是 `v_shelf[]`（栏目）→ `v_niche[]` → `v_card[]`（卡片）：

- 栏目标题是 `title_template` 里的 `{String}` 换成 `title_content`。
- 只保留 `type=200` 的歌曲卡和 `type=500` 的歌单卡（“每日30首”这类入口也是歌单卡，副标题是其中一首歌）。节目等其他卡片跳过。
- 歌曲卡只有数字 `id`，所有栏目的歌曲一次性用 `CgiGetTrackInfo` 补全。
- 第 2 页里的栏目 `315` 是专属乐流的第一批，这里丢掉，专属乐流另外取。
- “刷歌模式”入口卡的 `scheme` 形如 `qqmusic://qq.com/ui/jumpToRadarMode?p={"EntranceSongs":[id],…}`，从中取起始歌曲作 `radar_seed`，卡片 `cover` 作 `radar_cover`（可能为空）。

### 单独刷新一个栏目

`refresh_recommend_section(refresh)`：把栏目的 `refresh_param` 原样放进 `param.refresh_info`，其余同第 1 页。服务端只返回这一栏的新内容，标题也可能变。顶上那排（栏目 `301`）和未登录时的栏目 `ModuleID` 为空，不能刷新，`RecommendSection.refresh` 为空字符串。

### 歌单补位

栏目 `271`（「你的歌单补给站」）只发给未登录和 QQ 登录的账号，微信登录没有。没有这一栏时，从歌单广场取一批补在最后，取不到不影响首页：

`music.playlist.PlaylistSquare.GetRecommendWhole`，通用通道，不需要登录。参数 `IsReqHead=false`、`IsReqFeed=true`、`FeedReq={"From":0,"Size":21}`。读 `FeedRsp.List[].Playlist.basic` 的 `tid/title/cover.medium_url/song_cnt/play_cnt/creator.nick`，丢掉 `tid=0` 的项。

### 专属乐流

`feed_column(page, seen)`，需要登录，不缓存。还是 `get_recommend_feed` + `android_feed_comm`：

```json
{
  "direction": 1, "page": "<page + 1>", "s_num": "<page + 1>",
  "v_cache": [], "v_uniq": "<之前各页的 seen>",
  "ext": {"is_20_style":"1","has_login":"1","TwoColPages_proxy":"1","IsTwoColumnFlow_proxy":"1","two_col_page_proxy":"1"}
}
```

推荐流第 1 页没有专属乐流，所以 Kanade 的第 `page` 页对应服务端第 `page + 1` 页。只取栏目 `315` 的卡片：

| 卡片 | 读取 |
| --- | --- |
| `type=200, subtype=0` 单曲 | `card_extra_info.Tracks[0]` 是完整歌曲，标签 `tags[0].Tag` |
| `type=200, subtype=206` 组卡 | `title`，歌曲 ID 在 `card_extra_info.SongList[].ID`，整页一次补全 |
| `type=500` 歌单 | `id/title/cover/cnt` |

每张卡片（包括没显示的）记成 `"<type>_<subtype>_<id>"` 放进 `seen`，下一页通过 `v_uniq` 交回去，避免重复。返回的卡片为空表示没有更多。

### 自定义推荐页

首页最上面那排卡片显示哪些，需要登录，模块 `music.recommend.RecommendWidget`，公参 `android_feed_comm`：

| 操作 | 方法 | 通道 | 参数 |
| --- | --- | --- | --- |
| 读取 | `GetForyouConfigItems` | 通用 | `{"Cmd":"0"}` → `Selections[]` |
| 保存 | `SaveForyouConfigItems` | 通用写入 | `{"Selections": <整张列表>}`，要求返回 `Code=0` |

`ChoseStatus`：`-1` 固定显示，`1` 已勾选，`2` 未勾选。Kanade 只列出固定项和歌单卡（`ItemType=500`），其余是官方 App 的小游戏、网页等。保存时先重新读一次列表，只改 Kanade 列出的项，别的项原样发回，不动手机端的选择。

### 电台与刷歌

| 功能 | 接口 | 通道 | 参数 | 返回 |
| --- | --- | --- | --- | --- |
| 个性电台下一批（猜你喜欢是电台 `99`） | `music.radioProxy.MbTrackRadioSvr.get_radio_track` | 通用 + 内嵌页 | `id`、`num=5`、`from=0`、`scene=0`、`song_ids=[]` | `tracks[]` |
| 刷歌模式（雷达） | `music.recommend.TrackRelationServer.GetRadarSong` | 通用 + 内嵌页 | `Page`（从 1 开始）、`ReqType=0`、`FavSongs=[]`、`EntranceSongs=<radar_seed>` | `VecSongs[].Track` |

两者每次都是新的一批，不缓存。猜你喜欢按设计需要登录，但代码里没有本地拦截，未登录的结果由上游决定。

## 榜单

实现：[music.rs](../rust/src/qq/music.rs) `toplists`、`toplist_detail`。都走通用通道。

| 功能 | 接口 | 参数 | 返回 |
| --- | --- | --- | --- |
| 榜单目录 | `musicToplist.ToplistInfoServer.GetAll` | `{}` | `group[].groupName`、`group[].toplist[]`：`topId/title/period`，封面依次试 `frontPicUrl/headPicUrl/mbFrontPicUrl`，`song[]` 前三首作预览 |
| 榜单详情 | `musicToplist.ToplistInfoServer.GetDetail` | `topId`、`offset=0`、`num=100`、`period` | 元数据在 `data`（`title/intro/period/frontPicUrl`），歌曲在 `songInfoList` |

## 歌单

实现：[music.rs](../rust/src/qq/music.rs)、[library.rs](../rust/src/qq/library.rs)。

### 读取

| 功能 | 接口 | 参数 | 返回 |
| --- | --- | --- | --- |
| 歌单详情 `playlist_detail` | `music.srfDissInfo.aiDissInfo.uniform_get_Dissinfo`，通用 | `disstid=<歌单 ID 数字>`、`enc_host_uin=""`、`tag=1`、`userinfo=1`、`song_begin=0`、`song_num=1000`、`onlysonglist=0`、`orderlist=1` | `dirinfo`（`title/picurl/desc/creator.nick`）、`songlist[]` |
| 自建歌单（含“我喜欢”） | GET `https://c.y.qq.com/rsc/fcgi-bin/fcg_user_created_diss` | `hostuin=<musicid>`、`sin=0`、`size=200`、`format=json` | `data.disslist[]`：`dirid/tid/diss_name/diss_cover/song_cnt/listen_num` |
| 收藏的歌单 | GET `https://c.y.qq.com/fav/fcgi-bin/fcg_get_profile_order_asset.fcg` | `ct=20`、`cid=205360956`、`userid=<musicid>`、`reqtype=3`、`sin=0`、`ein=200`、`format=json` | `data.cdlist[]`：`dissid/dissname/logo/songnum/listennum/nickname` |

- `user_playlists` 合并自建和收藏两个列表，需要登录；收藏列表失败时照样返回自建列表。
- `my_playlists` 只返回自己的歌单（`MyPlaylist`），需要登录，加歌、改名、删除都从这里找目标。
- 歌单详情一次最多 1000 首，自建和收藏各最多 200 个，没有继续翻页。“每日30首”这类歌单因人而异，缓存键里带账号。

**`dir_id` 和 `tid` 是两回事。** `dir_id`（`dirid/dirId`）是歌单在当前账号下的目录编号，写入接口用它；`tid`（也叫 `disstid/dissid`）是歌单本身的 ID，读详情用它。“我喜欢”的 `dir_id` 在每个账号下都是 `201`，但 `tid` 因人而异，要从自建列表里找。普通歌单的编号全部从列表读，不能写死。

“我喜欢”的歌曲 ID（`liked_song_ids`）是先在自建列表里找到 `dir_id=201` 的歌单，再读它的详情，所以也受 1000 首的上限限制。

### 加歌、删歌、红心

模块 `music.musicasset.PlaylistDetailWrite`，加歌 `AddSonglist`，删歌 `DelSonglist`，参数相同，一次一首：

```json
{
  "dirId": 123, "bFmtUtf8": true, "dirName": "<歌单当前名称>", "tid": 456,
  "v_songInfo": [{"songId": 42, "songType": 0}]
}
```

“我喜欢”（红心）走 Android 写入，普通歌单走 PC 私有。目标先从 `my_playlists` 里找，找不到就报错。

### 新建、改名、删除

模块 `music.musicasset.PlaylistBaseWrite`，PC 私有：

| 操作 | 方法 | 参数 |
| --- | --- | --- |
| 新建 `create_playlist` | `AddPlaylist` | `bFmtUtf8=true`、`dirName=<名称>`；名称去掉首尾空白后不能为空。返回 `result.dirId`、`result.tid` 必须都是正整数，另读 `result.dirName/dirPicUrl` |
| 改名 `rename_playlist` | `EditPlaylist` | `bFmtUtf8=true`、`dirId`、`dirNewName=<新名称>`、`dirShow=1`、`mask=1` |
| 删除 `delete_playlist` | `DelPlaylist` | `bFmtUtf8=true`、`dirId`、`dirName=<当前名称>` |

“我喜欢”不能改名或删除，代码里直接拒绝。删除要带当前名称，名称取自 `my_playlists`，可能来自 600 秒的缓存。

所有歌单写入都要求业务 `data.retCode` 明确为数字 `0`，缺了也算失败；只发一次，不重发。成功后清掉该歌单详情和 `my_playlists` 的缓存（新建只清后者）。收藏或取消收藏别人的整个歌单还没实现。

## 最近播放

实现：[history.rs](../rust/src/qq/history.rs)。都需要登录，走 PC 私有。

### 读取

`music.musicasset.PlayRecentlyRead.GetPlayRecentlyInfo`，参数 `{"requestCnt":2500,"type":<类型>,"updateTime":0}`。返回的 `data` 里还有一层 `code`，必须为 `0`，记录在内层 `data` 里：

| `type` | 用途 | 读取 | 转成 |
| --- | --- | --- | --- |
| 2 | 歌曲（`recent_plays`） | `data.songList[].track`，按上游顺序（从新到旧） | `Song`；播放时间、次数、设备不往外传 |
| 1 | 全部 | `data.allItems.albumList` / `geDanList` / `listenBookList` | `AlbumBrief` / `PlaylistBrief` / `RecentBook`（`track` 是上次听的那一集） |
| 6 | 视频 | `data.mvList[].mvInfo` | `VideoBrief`（没有时长和播放量） |
| 5 | 个性电台 | `data.radioList` 里 `radioType=2` 的项（和官方“音乐雷达”一致） | `RecentRadio`，用 `radio_songs(id)` 播放 |

`recent_collections` 并发请求 1、6、5 三种类型。和官方一样一次取 2500 条，不翻页，也不做增量同步或删除。

### 上报播放

`music.musicasset.PlayRecentlyWrite.ReportPlayRecentlyInfo`：

```json
{"data":[{"id":"42","lastTime":1700000000,"listenCnt":1,"type":2}]}
```

`id` 是歌曲数字 ID 的**字符串**，`lastTime` 是 Unix **秒**。要求返回 `data.ret=0`，成功后清掉 `recent_plays` 缓存。这会改云端记录，只在真正开始播放一首歌时调用（`report_play`）。

## 歌手与专辑

实现：[detail.rs](../rust/src/qq/detail.rs)。以下都走通用 + 内嵌页公参。

| 功能 | 接口 | 参数 | 返回 |
| --- | --- | --- | --- |
| 歌手资料 | `music.musichallSinger.SingerInfoInter.GetSingerDetail` | `singer_mids=[mid]`、`pic=1`、`group_singer=1`、`wiki_singer=1`、`ex_singer=1` | `singer_list[0]`：`basic_info.name`、`pic.pic`、`ex_info.desc` |
| 歌手歌曲 | `music.musichallSong.SongListInter.GetSingerSongList` | `singerMid`、`begin`（从 0 开始的偏移）、`num`、`order=1` | `songList[]`、`totalNum` |
| 歌手专辑 | `music.musichallAlbum.AlbumListServer.GetAlbumList` | `singerMid`、`order=1`（按时间）、`num`、`begin` | `albumList[]`、`total` |
| 精选专辑 | `music.musichallAlbum.SelectedAlbumServer.SelectedAlbumList` | `singerMid` | `albumList[]` |
| 视频分类 | `MvService.MvInfoProServer.GetSingerMvTag` | `singermid` | `list[].id/name` |
| 歌手视频 | `MvService.MvInfoProServer.GetSingerMvList` | `singermid`、`tagid`、`start`、`count`、`order`（0 最新，1 最热） | `list[]`（`vid/title/picurl/duration/playcnt`）、`total` |
| 守护信息 | `music.UnifiedHomepage.UnifiedHomepageSrv.GetHomepageIconForMedal` | `SingerMid`、`Uin=<当前 musicid 或 "0">` | `NumButtonList` 里 `ButtonType=9` 的 `ButtonInfo.Title`（如“38万乐迷守护”），原样显示；`cnt` 和这个人数无关 |
| 专辑资料 | `music.musichallAlbum.AlbumInfoServer.GetAlbumDetail` | `albumMid` | `basicInfo`（`albumID/albumName/desc/publishDate`）、`company.name`、`singer.singerList[]` |
| 专辑歌曲 | `music.musichallAlbum.AlbumSongList.GetAlbumSongList` | `albumMid`、`begin=0`、`num=1000`、`order=2` | `songList[]` |

- `singer_detail` 并发取资料、前 30 首歌、前 30 张专辑和精选专辑；之后用 `singer_songs` / `singer_albums` 按偏移翻页。
- 歌手视频的“最热”由上游排序，不能自己按播放量排。换分类或排序后从头加载。
- 专辑列表读 `albumMid/albumName/publishDate/singerName`。专辑评论要用 `basicInfo.albumID`（数字 ID），不是 MID。
- 专辑歌曲一次最多 1000 首，没有继续翻页。

粉丝数走旧 CGI：GET `https://c6.y.qq.com/rsc/fcgi-bin/fcg_order_singer_getnum.fcg`，参数 `singermid`、`utf8=1`、`format=json`，要求 `code` 和 `subcode` 都为 0，读 `num`。`singer_social` 并发取粉丝数、守护信息和关注状态（见[关注](#关注)），不缓存。

封面地址本地拼：

```text
专辑：https://y.gtimg.cn/music/photo_new/T002R300x300M000<专辑 MID>.jpg
歌手：https://y.gtimg.cn/music/photo_new/T001R300x300M000<歌手 MID>.jpg
歌手大图：https://y.gtimg.cn/music/photo_new/T001R800x800M000<歌手 MID>.jpg
```

歌手资料优先用响应里的 `pic.pic`。统一歌曲解析在没有专辑 MID 时用第一位歌手的头像作封面。

## 播放页信息页

实现：[detail.rs](../rust/src/qq/detail.rs) `song_page`、`related_playlists`，[music.rs](../rust/src/qq/music.rs) `similar_songs`。都走通用通道，参数照抄 Android 客户端。

`song_page(id, mid)` 并发请求下面六项。哪一项失败就让那一栏为空，全部失败才报错：

| 栏目 | 接口 | 参数 | 返回 |
| --- | --- | --- | --- |
| 发行日期 | `music.musichallSong.SongInfoServer.GetSongDetail` | `songMid` | `basic.album.pubTime` |
| 标签 | `music.recommend.TrackRelationServer.GetSongLabels` | `songid=<数字 ID>` | `labels[].tagTxt/tagIcon`；`tagTxt` 为空的（官方客户端自己填文字的那种）不显示 |
| AI 解读 | `music.SearchConfig.AiInterpretationSvr.GetAiInterpretation` | `id=<数字 ID 字符串>`、`keyword=""`、`custom_params={"from":"player_leftSlide"}` | `aidirect_list[0].title/content` |
| 相关视频 | `MvService.MvInfoProServer.GetSongRelatedMv` | `songid=<数字 ID 字符串>`、`songtype=1`、`lastmvid=0` | `list[]`：`vid/title/picurl/playcnt/singers[].name`；没有歌手的是用户上传 |
| 相似歌曲 | `music.recommend.TrackRelationServer.GetSimilarSongs` | `songid` | `vecSongNew[0].title_content`（“因为你听了 xx”）、`vecSongNew[0].songs[].track` |
| 相关歌单 | `music.recommend.TrackRelationServer.GetRelatedPlaylist` | `songid` | `vecPlaylistNew[0].playlists[]`：`tid/title/cover/songNum/playCnt/creator`，`hasMore` |

- 相关歌单“换一批”（`related_playlists`）：参数加 `vecPlaylist=<已显示的 tid 数字数组>`、`extra_info={"module":"1"}`，服务端不再返回这些歌单；要求 `retcode=0`。
- 歌曲菜单里的“查找相似歌曲”（`similar_songs`）用同一个 `GetSimilarSongs`，但读的是 `vecSong[].track`，要求 `retcode=0` 且有 `vecSong`，按上游顺序返回。

## MV

实现：[mv.rs](../rust/src/qq/mv.rs) `mv_detail`。两项都走通用通道，并发请求。

| 功能 | 接口 | 参数 | 返回 |
| --- | --- | --- | --- |
| 资料 | `music.video.VideoData.get_video_info_batch` | `vidlist=[vid]`、`required=["play_forbid_reason","cover_pic","name","singers","vid","type","playcnt","pubdate","duration","uploader_nick","desc","code"]` | `data[vid]`；`pubdate` 是 Unix 秒，按北京时间转成日期 |
| 播放地址 | `music.stream.MvUrlProxy.GetMvUrls` | `vids=[vid]`、`request_type=10001`、`addrtype=3`、`format=264` | `data[vid].mp4[]` 中 `code=0` 的条目，从 `freeflow_url[]` / `url[]` 里取第一个 https 地址 |

`filetype` 对应清晰度：`10` → 360P，`20` → 480P，`30` → 720P，`40` → 1080P，其他忽略。同一清晰度只留一条。时长取资料和取流响应里较大的那个。

官方客户端用 `request_type=10003`、`format=265`，只返回相对路径和 HLS 分片，缺 CDN 地址，所以 Kanade 改用 `10001` + H.264，直接拿完整的 MP4 地址。地址有效期 86400 秒，每次打开播放页都重新取。付费 MV 和 `play_forbid_reason≠0` 的情况没处理，没有可用地址时播放页显示无法播放。

VID 是字符串：搜索结果的 `v_id`、歌曲的 `mv.vid`（`mv.id=0` 时也可能有效）、各列表的 `vid`。`Song.mv_vid` 会随播放队列一起保存。

## 评论

实现：[detail.rs](../rust/src/qq/detail.rs) `comment_feed`、`reply_feed`。模块 `music.globalComment.CommentRead`，通用 + 内嵌页公参，参数照抄 Android 客户端。只读，不能发表、删除或点赞。本地不检查登录。

`BizType=1` 是歌曲，`2` 是专辑；`BizId` 是对应数字 ID 的字符串。每页 15 条。

所有评论列表共用的参数：`BizType`、`BizId`、`PageSize=15`、`LastCommentSeqNo`、`PicEnable=1`、`LastTotal`、`LastTotalVer`（第一页 `"0"`，之后是上一页的 `TotalVer`）、`LastRspVer`（第一页的 `RspVer`，后续页的响应里它是空的）、`CmListUIVer=1`、`AudioEnable=1`。

| `CommentSort` | 方法 | 额外参数 |
| --- | --- | --- |
| `Recommend` | `GetRecCommentList` | `RecOffset`、`LastHotScore`、`LastRecScore`、`FromParentCmId=""`、`FromCommentId=""`、`Flag`（第一页 1，之后 0）；后续页另加 `PageNum`、`HashTagID=""`、`CommentIds` |
| `Hot` | `GetHotCommentList` | `PageNum`、`HotType=6`、`WithTop=0`、`LastHotScore`、`LastCommentId`、`HashTagID=""` |
| `Latest` | `GetNewCommentList` | `PageNum`、`LastCommentId`、`SelfSeeEnable=1`、`HashTagID=""` |

`Last*` 都取上一页最后一条评论的对应字段。这些状态由 Rust 打包成 `CommentFeed.cursor`（JSON 字符串），界面取下一页时原样传回，第一页传空字符串。

**推荐列表不是按偏移翻页的。** 第一页响应的 `CommentList.CommentIds` 是后续全部评论的 ID；第 N 页从中按顺序取 15 个放进请求的 `CommentIds`，服务端返回这些评论的正文。未登录时第一页没有 `CommentIds`，推荐只有一页。所以推荐的 `has_more` 看 ID 用完没有，不看 `HasMore`；另外两种看 `CommentList.HasMore == 1`。

回复：`GetReplyCommentList`，参数 `RootCmId`、`PageNum`、`PageSize`（第一页 6，之后 5）、`LastCommentSeqNo`、`LastRankScore`、`RankType=1`、`LastRspVer`、`SelfSeeEnable=1`、`PicEnable=1`、`AudioEnable=1`。回复的 `HasMore` 一直是 1，只有第一页给总数 `CommentList.Total`，所以按“已取条数 < 总数”判断还有没有。

评论总数取顶层 `TotalCmNum`。字段映射：`CmId → id`、`SeqNo → seq_no`、`Nick → nick`、`Avatar → avatar_url`、`Content → content`、`PubTime → time_secs`、`PraiseNum → praise_count`、`ReplyCnt → reply_count`、`RepliedComments[0].Nick → reply_to`、`Pic → pic_url`、`PicSize`（`"宽x高"`）→ `pic_width/pic_height`。正文去掉 `[em]…[/em]` 表情代码，把字面的 `\n` 还原成换行。评论图片的地址不带 Cookie 和参数就能直接下载。

## 用户主页与关注

实现：[user.rs](../rust/src/qq/user.rs)、[social.rs](../rust/src/qq/social.rs)。

### 主页资料

需要登录（未登录时上游返回 `1000`，本地直接返回 `NotLoggedIn`）。用户用 `encrypt_uin`（`euin`）标识，来自用户搜索结果；看自己的主页可以传 musicid。

GET `https://c6.y.qq.com/rsc/fcgi-bin/fcg_get_profile_homepage.fcg`，参数 `userid=<euin>`、`cid=205360838`、`ct=20`、`cv=2276`、`reqfrom=1`、`reqtype=0`、`format=json`、`uin`、`platform=wk_v17`、`g_tk`、`g_tk_new_20200303`。要求 `code` 和 `subcode` 都为 0。

| 读取 | 含义 |
| --- | --- |
| `data.creator.encrypt_uin` | 后续请求用的 euin，缺了就报错 |
| `creator.nick/headpic` | 昵称、头像 |
| `creator.nums.fansnum/follownum` | 粉丝、关注数 |
| `creator.cfinfo.title` | 简介位置显示的认证说明。QQ 音乐不让用户自己写简介，没认证时为空 |
| `creator.isfollow` | 是否已关注 |
| `creator.ishost` | 是否本人；本人不显示关注按钮，也不受隐私限制 |
| `creator.diss_lock` | 自建歌单不公开 |
| `creator.fav_lock` / `islock` | 收藏不公开 |
| `data.mydiss.num` / `mydiss.list` | 公开歌单数和快照 |
| `data.mymusic` | `type=1` 的卡片是“我喜欢”歌单：`id` 是歌单 ID，`num0` 是歌曲数 |

### 公开歌单

`user_playlists(euin, creator, page, page_size)`，`page` 从 0 开始：

1. 不是本人且 `diss_lock=1`：返回空列表，界面显示未公开。
2. `mydiss.list` 的条数等于 `mydiss.num`：资料里已经是完整列表，直接对它分页。有些旧账号在统一主页里只有 about 标签，读 `disc` 会返回空，只能这样拿。
3. 否则用 `music.UnifiedHomepage.UnifiedHomepageSrv.GetHomepageTabDetail`（通用），参数 `uin=<euin>`、`IsQueryTabDetail=1`、`TabID="disc"`、`PageNum`（从 0 开始）、`PageSize`、`Order=0`。读 `DiscTab.List[].Dissid/Title/Picurl/Subtitle` 和 `HasMore`。第一页为空但资料说有歌单时报错，不显示“没有歌单”。

歌曲数从副标题（如“62首    1260.8万次播放 …”）开头解析，播放量不单独给。

### 收藏（我喜欢）

`user_assets(euin, kind, page, page_size)`，`page` 从 0 开始，通用 + 内嵌页公参，不缓存。不是本人且 `fav_lock` 或 `islock` 为 1 时直接返回 `hidden=true`。

| `kind` | 接口 | 参数 | 返回 |
| --- | --- | --- | --- |
| `Song` | `music.srfDissInfo.DissInfo.CgiGetDiss` | `optype=0`、`disstid=<mymusic 里 type=1 的 id>`、`onlysonglist=1`、`song_begin=page*size`、`song_num=size` | `songlist[]`、`hasmore` |
| `Playlist` | `music.musicasset.PlaylistFavRead.GetPlaylistFavInfo_v2` | `uin=<euin>`、`offset`、`size` | `v_list[].tid/name/logo/songnum/nickname`、`hasmore`、`hide` |
| `Album` | `music.musicasset.AlbumFavRead.GetAlbumFavInfo_v2` | `euin`、`offset`、`size` | `v_list[].mid/name/logo/pubtime/v_singer[].name`、`hasmore`、`hide`；`pubtime` 是 Unix 秒 |
| `Video` | `music.musicasset.MVFavRead.getMyFavMV_v2` | `cid=205361447`、`encuin=<euin>`、`support=1`、`num=page*size`、`pagesize=size` | `mvlist[].vid/mv_name/mv_picurl/duration/playcount/singer_name/uploader_nick`、`hasmore` |

- 喜欢的歌曲读的是**目标用户**的“我喜欢”歌单，不是当前账号的。`num0=0` 时返回空；有歌却没有歌单 ID 时报错。
- `Song` 和 `Video` 还要求 `data.code` 和 `data.subcode` 都为 0。
- `hide=true` 表示对方设了隐私，不能当成空收藏。
- 部分旧收藏视频封面为空、时长为 0，仍保留标题和 VID，由界面显示占位图。
- 上传的视频是另一个接口（`fcg_get_my_vedio.fcg`），没有接入。

### 关注

模块 `Concern.ConcernSystemServer`，通用 + 内嵌页公参。

查歌手关注状态（`singer_followed`）：`cgi_qry_concern_status`，参数 `vec_userinfo=[{"usertype":1,"userid":<歌手 MID>}]`、`opertype=5`、`encrypt_singerid=1`，读 `map_singer_status[<MID>] == 1`。未登录时直接返回未关注，不发请求。用户的关注状态在主页资料的 `isfollow` 里。

关注 / 取消关注（`set_followed`）：`cgi_concern_user_v2`，走通用写入。

| 对象 | 参数 |
| --- | --- |
| 歌手 | `opertype=0`（关注）/ `1`（取消）、`userinfo={"usertype":1,"userid":<歌手 MID>}`、`source=0`、`encrypt_singerid=1` |
| 用户 | `opertype=0` / `1`、`userinfo={"usertype":0,"userid":<euin>}` |

要求网关、业务和 `data.code` 都明确为数字 0。只发一次，成功后清掉目标的主页资料缓存。界面在请求期间禁用按钮，成功后才改状态。

## 听歌识曲

实现：[recognize.rs](../rust/src/qq/recognize.rs)。

```text
POST https://c6.y.qq.com/youtu/humming/search?sessionid=<会话 ID>&recognizetype=1&fpType=5
Content-Type: application/x-www-form-urlencoded
正文：录音 PCM 的 Base64
```

录音格式是 8 kHz、16 位小端、单声道 PCM。每次请求都发**从开始录到现在的全部录音**，同一次识别用同一个 `sessionid`，没认出来就继续录再发。

- `ret≠0` 是错误。
- `results[0].lcs > 0` 才算认出来，取 `songlist[0].songid`。录音几乎是底噪时服务端也会返回一串候选，但它们的 `lcs` 都是 0。
- 响应里的歌名等字段是 Base64，不直接用，按 `songid` 走 `CgiGetTrackInfo` 补全歌曲。

## 登录

实现：[login.rs](../rust/src/qq/login.rs)、[mqtt.rs](../rust/src/qq/mqtt.rs)。

登录结果统一从响应里取 `musicid`、`musickey`（兼容 `qm_keyst`），另存续期用的 `refresh_key`、`refresh_token`、`access_token`、`openid`、`expired_at`。到期时间是 `musickeyCreateTime + keyExpiresIn`（`keyExpiresIn` 通常是 259200，即 3 天）；没有 `musickeyCreateTime` 就从现在算，没有 `keyExpiresIn` 记为 0（不知道）。

会话加密后存在数据库 kv 表的 `session` 里（[secret.rs](../rust/src/qq/secret.rs)），旧版本的明文会话在启动时自动转成加密格式。Android 上每次都从数据库读会话，界面进程和播放进程看到的是同一份。

### QQ 扫码

公共参数：`appid=716027609`、`daid=383`、`pt_3rd_aid=100497308`、`u1=https://graph.qq.com/oauth2.0/login_jump`，Referer `https://xui.ptlogin2.qq.com/`。

| 步骤 | 请求 | 要点 |
| --- | --- | --- |
| 1. 二维码 | GET `https://ssl.ptlogin2.qq.com/ptqrshow` | 公共参数加 `e=2&l=M&s=3&d=72&v=4&t=<随机>`；响应是图片，从 Cookie 取 `qrsig` |
| 2. 轮询 | GET `https://ssl.ptlogin2.qq.com/ptqrlogin` | `ptqrtoken=hash33(qrsig, 0)`，Cookie 带 `qrsig`，完整参数见 `poll_qr` |
| 3. 建立 OAuth Cookie | GET `https://ssl.ptlogin2.graph.qq.com/check_sig` | 用成功回调 URL 里的 `uin`、`ptsigx`，拿到 `graph.qq.com` 的 `p_skey` |
| 4. 换 OAuth code | POST 表单 `https://graph.qq.com/oauth2.0/authorize` | `response_type=code`、`client_id=100497308`、`g_tk=hash33(p_skey, 5381)`、`redirect_uri=https://y.qq.com/portal/wx_redirect.html?login_type=1&surl=https://y.qq.com/` 等；不跟随重定向，从 `Location` 取 `code` |
| 5. 换 musickey | `QQConnectLogin.LoginServer.QQLogin`，通用 | `param={"code":"<code>"}`，公参覆盖 `tmeLoginType="2"` |

轮询返回 `ptuiCB('状态', …)`：`66` 等待、`67` 已扫、`65` 过期、`68` 拒绝、`0` 成功（第三个参数是回调 URL），其他把第五个参数当错误信息。

**同一台手机跳转 QQ 登录**（`create_app_qr`）：步骤 1 改成公共参数加 `s=8&e=0&type=1&t=<随机>`，响应是 `ptui_qrcode_CB({"ec":0,"qrcode":"<跳转地址>"})`，没有图片。必须带 `type=1`，否则 QQ 报“登录失败(73)”。之后的轮询和扫码一样。

### 微信扫码

| 步骤 | 请求 | 要点 |
| --- | --- | --- |
| 1. 二维码页 | GET `https://open.weixin.qq.com/connect/qrconnect` | `appid=wx48db31d50e334801`、`redirect_uri=https://y.qq.com/portal/wx_redirect.html?login_type=2&surl=https://y.qq.com/`、`response_type=code`、`scope=snsapi_login`、`state=STATE`、`href=<QQ 音乐的弹窗样式>`；从页面里找 `/connect/qrcode/<UUID>` 或 `uuid=<UUID>` |
| 2. 二维码图片 | GET `https://open.weixin.qq.com/connect/qrcode/<UUID>` | UUID 放在 `QrCode.qrsig` |
| 3. 长轮询 | GET `https://lp.open.weixin.qq.com/connect/l/qrconnect` | `uuid`、`_=<毫秒时间>`；服务端最长挂起约 25 秒，超时设 35 秒 |
| 4. 换 musickey | `music.login.LoginServer.Login`，通用 | `param={"code":"<wx_code>","strAppid":"wx48db31d50e334801"}`，公参覆盖 `tmeLoginType="1"` |

轮询返回 `window.wx_errcode=…;window.wx_code='…';`：`408` 等待、`404` 已扫、`403` 拒绝、`402` 过期、`405` 且 `wx_code` 非空为成功。

微信账号的 musickey 以 `W_X` 开头。

### QQ 音乐 App 授权

在手机 QQ 音乐里打开授权页确认登录。整个流程用一个独立的 `TmeClient`，`GetSession`、二维码和最终换票都用同一组 `uid/sid`。

1. `music.getSession.session.GetSession`，参数 `{"uid":"","vkey":0,"caller":0}`，保存 `session.uid` / `session.sid`。
2. `music.login.LoginServer.CreateQRCode`，这一步公参覆盖 `ct=23`、`cv=0`。`param` 写要登录的客户端：Windows 上是 `{"tmeAppID":"qqmusic","ct":19,"cv":2276}`（PC 身份），其他平台是 `{"tmeAppID":"qqmusic","ct":11,"cv":14090008}`（Android 身份）。返回 `qrcodeID` 和带 `base64,` 前缀的 `qrcode` 图片。
3. 连 `wss://mu.y.qq.com/ws/handshake`（子协议 `mqtt`，MQTT 5），订阅 `management.qrcode_login/<qrcodeID>`。收到 SUBACK 后才把二维码和授权入口 `https://y.qq.com/m/client/qr_code_login/authorize.html?qrcode_id=<qrcodeID>` 交给界面，避免用户确认时还没订阅上。订阅最多等 15 秒。
   - CONNECT：认证方法 `pass`，User Properties `tmeAppID=qqmusic`、`business=management`、`hashTag=<qrcodeID>`、`clientTag=management.user`、`userID=<qrcodeID>`。keep alive 初始 45 秒，服务器给了新值就用新值，按一半周期发心跳。服务器用 `0x9C` / `0x9D` 重定向时跟过去。
   - SUBSCRIBE：User Properties `authorization=tmelogin`、`pubsub=unicast`。
4. 推送的 User Property `type`：`scanned` 已扫、`canceled` 拒绝、`timeout` 过期、`loginFailed` 失败、`cookies` 授权成功。后台最多等 120 秒。
5. `cookies` 消息里的 `cookies.qqmusic_uin.value` 和 `cookies.qqmusic_key.value` 只是临时凭证，再调一次 `music.login.LoginServer.Login` 换正式 musickey，参数 `musicid=<临时账号，数字>`、`qrCodeID`、`token=<临时 key>`，`tmeLoginType=6`。Windows 走 PC 登录通道（登录设备管理里显示为 Windows PC），其他平台用同一个 `TmeClient`（显示为 Android）。

结果不能靠轮询 `CheckQRCode` 拿（授权后它仍返回 `40000`）。`poll_login_qr(QqMusic, …)` 读的是本地记下的推送状态，终态读一次就清掉，找不到按过期处理。

这种登录记 `tme=true`；Android 身份还会把整套 `TmeClient.comm` 存进会话的 `login_comm`，退出时要用。账号类型跟随手机 QQ 音乐当前的登录方式（QQ 或微信）。

### Cookie 登录与用户资料

`login_with_cookie`：账号依次取 `uin`、`qqmusic_uin`、`wxuin` 中第一个非空的，去掉开头的 `o` 和 `0`；密钥依次取 `qm_keyst`、`qqmusic_key`。缺了就返回 `InvalidCookie`。musickey 以 `W_X` 开头算微信，否则算 QQ。Cookie 登录没有到期时间和续期凭证。

登录后用 GET `https://c.y.qq.com/rsc/fcgi-bin/fcg_get_profile_homepage.fcg`（`format=json`、`cid=205360838`、`userid=<musicid>`、`reqfrom=1`）读 `data.creator.nick/headpic` 作昵称和头像。这一步失败不影响登录，昵称为空时显示 musicid。所以 Cookie 登录成功不代表凭据一定能调私有接口。

QQ 和微信扫码在换 musickey 前会先清掉旧会话；App 授权只在换票成功后才替换旧会话。

### 自动退出

凭据失效时，需要登录的接口返回业务码 `1000`，不附说明，也不区分是过期、被挤下线还是在设备管理里被删除。公开接口会忽略失效的凭据照常返回。

流程：

1. 任何 Dart 入口拿到 `1000` 时，`api_error()` 调 `suspect_session()`，在后台复核。只有注册了 `watch_session_end` 的界面进程会复核，Android 播放进程不会。
2. 复核用 PC 私有的 `GetPlayRecentlyInfo`（`requestCnt=1`、`type=2`）。快到期（不到 1 天）或不知道到期时间且能续期的，先续期再复核；没提前续期而复核被拒时也续一次再复核。
3. 仍是 `1000` 且期间没换账号：清掉会话和接口缓存，推送原因：已过到期时间为 `Expired`，到期前被拒为 `Revoked`，不知道到期时间为 `Unknown`。

启动时 `check_session()` 也会复核一次。

### 续期

`refresh_session()`，参数照抄官方 PC 客户端。`musicid` 必须是**数字**，传字符串返回 `10006`。

| 账号 | 条件 | 通道与请求键 | `param` |
| --- | --- | --- | --- |
| App 授权（`tme`）的微信账号 | 有 `refresh_key` | PC 登录，请求键 `WXLoginByToken`，`tmeLoginType=1` | `access_token=""`、`deviceName="L"`、`deviceType="Widnows"`（原文拼写）、`expired_in=0`、`forceRefreshToken=0`、`musicid`、`musickey`、`onlyNeedAccessToken=0`、`openid=""`、`refresh_key`、`refresh_token`（可以为空）、`strAppid="wx48db31d50e334801"` |
| 网页 QQ 扫码 | 有 `refresh_key`、`refresh_token`、`access_token` | PC 登录，请求键 `music.login.LoginServer.Login`，`tmeLoginType=2` | `access_token`、`appid=100497308`、`deviceName="L"`、`deviceType="Widnows"`、`expired_in=<登录响应的 expired_at>`、`forceRefreshToken=0`、`musicid`、`musickey`、`onlyNeedAccessToken=0`、`openid`、`refresh_key`、`refresh_token` |
| 网页微信扫码 | 有 `refresh_key`、`refresh_token` | 通用 `music.login.LoginServer.Login`，公参覆盖 `tmeLoginType` | `musicid`、`musickey`、`refresh_key`、`refresh_token`、`strAppid="wx48db31d50e334801"` |

- App 授权登录只给 `refresh_key`，没有 `refresh_token`。这时如果走网页微信那一行的写法，服务端返回 `1000`，**而且当前 musickey 会跟着失效**。必须用第一行带 `deviceName` 等字段的写法，第一次续期的响应会补发 `refresh_token`。
- App 授权的 QQ 账号还没验证过，不续期。Cookie 登录和旧版本保存的会话缺少续期凭证，要重新登录一次。
- 续期返回新 musickey，旧的通常仍能用一段时间。续期期间退出或换了账号，结果直接丢掉。

### 退出

`logout()` 先通知服务器下线这台设备，再删本地会话。通知最多等 5 秒，失败也照常退出。

- Windows 上的 App 授权登录：PC 私有 `music.login.LoginServer.Logout`，`param={}`。
- Android 身份的 App 授权登录（有 `login_comm`）：用 `TmeClient` 和登录时存下的那套公参（换上当前 `qq`/`authst`/`tmeLoginType`），`param={"dummy":0,"scene":"user_logout"}`。必须带上登录时 `GetSession` 给的 `uid/sid`，设备才会从登录设备管理里消失；只发 `{}` 虽然返回 `code=0`，但设备不删、旧 key 照样能用。
- 其他：Android 写入 `music.login.LoginServer.Logout`，`param={}`。旧版本保存的 Android 身份会话没有 `login_comm`，退出时删不掉设备，重新登录一次后就可以。

## 缓存

`Core::cached` 把**原始 JSON** 缓存在 SQLite 里，所以改了解析逻辑也不会读到旧结构。缓存键都加了当前账号前缀，未登录为 `0`。过期就重新请求，不会拿过期数据当网络失败的兜底。

| 数据 | 有效期 |
| --- | --- |
| 搜索、热搜、联想、歌曲文件信息（含 360RA）、歌单详情、自建歌单列表、用户主页资料、用户公开歌单分页 | 600 秒 |
| 榜单详情 | 1800 秒 |
| 榜单目录、歌手资料及歌曲 / 专辑分页、专辑详情、MV 资料 | 3600 秒 |
| 最近播放歌曲、最近播放其他分类 | 300 秒 |
| 歌词、高潮片段 | 7 天 |

不缓存：首页推荐和栏目刷新、专属乐流、自定义推荐页、歌单补位、电台、刷歌、`user_playlists` 的合并结果、播放链接和音质授权、MV 播放地址、评论和回复、播放页信息页、相似歌曲、歌手粉丝 / 守护 / 关注状态、歌手视频、用户收藏、听歌识曲。

写入后清缓存：

- 歌单加删歌、改名、删除 → 该歌单详情和 `my_playlists`；新建 → `my_playlists`。
- 上报播放 → `recent_plays`。
- 关注 / 取消关注 → 目标的主页资料。
- 自动退出 → 全部接口缓存。

`clear_cache()` 清掉全部接口缓存，不会退出登录，也不删音频缓存。

## 错误

### 结果码检查

HTTP 200 不代表成功。各通道的检查力度不同：

| 通道 / 接口 | 检查 |
| --- | --- |
| 通用 | 业务 `code` 必须为 0；不单独检查外层网关的 `code` |
| PC 公共 / 私有 / 登录 | 外层 `code` 有且非 0 时失败（缺失不算失败）；业务 `code` 必须为 0 |
| 通用写入、Android 写入、App 授权 | 外层和业务 `code` 都必须明确为数字 0 |
| 旧 CGI | 只检查 HTTP 状态和 JSON 解析；需要时由调用处再检查 |

在此之上，各接口还会再检查：

| 接口 | 额外检查 |
| --- | --- |
| 歌单写入 | `retCode=0`（必须有） |
| 最近播放读取 / 上报 | 内层 `code=0` / `ret=0` |
| 关注写入 | `data.code=0`（必须有，且是数字） |
| 歌手粉丝数、用户主页资料 | `code=0` 且 `subcode=0` |
| 用户收藏的歌曲和视频 | `data.code=0` 且 `data.subcode=0` |
| 相似歌曲、相关歌单换一批 | `retcode=0` |
| 保存自定义推荐页 | `Code=0` |
| 听歌识曲 | `ret=0` |

`ServerError.code` 在部分路径下会被格式化成 `Some(1000)` 这种样子，`ApiError::is_auth_rejected` 两种写法都认。

除了 `1000`，不要擅自把其他数字（如 `2000`、`80105`）定义成某个唯一原因。写请求超时时结果不确定，专用写通道不会自动重发，应先读回状态再决定。

### ApiError

定义在 [api/error.rs](../rust/src/api/error.rs)：`NotLoggedIn`、`NoPlayableUrl`、`UnsupportedFormat`、`UnverifiedFormat`、`LoginFailed{detail}`、`InvalidCookie{missing}`、`ServerError{api,code}`、`BadResponse{detail}`、`Network{detail}`、`Internal{detail}`。

内部用 anyhow，以 `bail!(ApiError::…)` / `.context(ApiError::…)` 抛出；到 Dart 边界由 `api_error()` 统一转换（错误链里找到 `ApiError` 就用它，否则 reqwest 错误转 `Network`，JSON 错误转 `BadResponse`，其余转 `Internal`），界面文案由 Dart 翻译。新加的 Dart 入口也要 `.map_err(api_error)`，这样 `1000` 才会触发登录复核。

普通请求超时 15 秒；微信长轮询 35 秒；音频中转连接 15 秒、读取 30 秒。

## Dart 入口

[api/music.rs](../rust/src/api/music.rs) 里和上游接口有关的入口。缓存、偏好、音频中转、版本更新等本地功能也在这个文件，不列在这里。

| 功能 | 入口 | 返回 |
| --- | --- | --- |
| 搜索 | `search(keyword, kind, page, page_size)` / `get_hot_search()` / `get_search_suggestions(query)` | `SearchResult` / `HotSearch` / `Vec<SearchSuggestion>` |
| 播放 | `get_song_url(mid, media_mid, quality)` / `get_song_qualities(mid)` | `SongUrl` / `Vec<QualityOption>` |
| 歌词、高潮 | `get_lyric(mid, id)` / `get_song_chorus(id)` | `Lyric` / `Option<ChorusRange>` |
| 榜单 | `get_toplists()` / `get_toplist_detail(top_id, period)` | `Vec<TopListGroup>` / `TopListDetail` |
| 首页 | `get_recommend_feed()` / `refresh_recommend_section(refresh)` / `get_feed_column(page, seen)` | `RecommendFeed` / `RecommendSection` / `FeedColumnPage` |
| 自定义推荐页 | `get_foryou_config()` / `save_foryou_config(chosen)` | `Vec<ForyouItem>` / 空 |
| 电台、刷歌 | `get_guess_you_like()` / `get_radio_songs(id)` / `get_radar_songs(seed, page)` | `Vec<Song>` |
| 歌单读取 | `get_playlist_detail(id)` / `get_user_playlists()` / `get_my_playlists()` / `get_liked_song_ids()` | `PlaylistDetail` / `Vec<PlaylistBrief>` / `Vec<MyPlaylist>` / `Vec<i64>` |
| 歌单写入 | `set_song_liked(song_id, liked)` / `add_song_to_playlist(dir_id, song_id)` / `remove_song_from_playlist(dir_id, song_id)` / `create_playlist(name)` / `rename_playlist(dir_id, name)` / `delete_playlist(dir_id)` | 新建返回 `MyPlaylist`，其余为空 |
| 最近播放 | `get_recent_plays()` / `get_recent_collections()` / `report_play(song_id)` | `Vec<Song>` / `RecentCollections` / 空 |
| 歌手 | `get_singer_detail(mid)` / `get_singer_songs(mid, begin, num)` / `get_singer_albums(mid, begin, num)` / `get_singer_social(mid)` / `get_singer_video_tags(mid)` / `get_singer_videos(mid, name, tag, order, begin, num)` | `SingerDetail` / `Vec<Song>` / `Vec<AlbumBrief>` / `SingerSocial` / `Vec<VideoTag>` / `SingerVideoPage` |
| 专辑 | `get_album_detail(mid)` | `AlbumDetail` |
| 播放页信息页 | `get_song_page(song_id, song_mid)` / `get_related_playlists(song_id, exclude)` / `get_similar_songs(song_id)` | `SongPage` / `RelatedPlaylists` / `Vec<Song>` |
| MV | `get_mv_detail(vid)` | `MvDetail` |
| 评论 | `get_comment_feed(target, id, sort, cursor)` / `get_reply_feed(root_id, cursor)` | `CommentFeed` |
| 用户 | `get_user_profile(euin)` / `get_user_public_playlists(euin, creator, page, page_size)` / `get_user_assets(euin, kind, page, page_size)` | `UserProfile` / `UserPlaylistPage` / `UserAssetPage` |
| 关注 | `set_singer_followed(mid, followed)` / `set_user_followed(euin, followed)` | 空 |
| 听歌识曲 | `recognize_song(session_id, pcm)` | `Option<Song>` |
| 登录 | `create_login_qr(kind)` / `create_qq_app_login()` / `poll_login_qr(kind, qrsig)` / `login_with_cookie(cookie)` | `QrCode` / `QrCode` / `QrStatus` / `UserInfo` |
| 登录态 | `current_user()` / `check_session()` / `watch_session_end(sink)` / `logout()` | `Option<UserInfo>` / 空 / `SessionEndReason` 流 / 空 |

数据结构见 [api/types.rs](../rust/src/api/types.rs)。`QrCode.qrsig` 在三种登录里分别是 `qrsig`、微信 UUID、`qrcodeID`。`UserInfo` 不含密钥。统一歌曲解析（[parse.rs](../rust/src/qq/parse.rs) `song`）兼容 `songInfo` / `data` 包装和旧接口的字段名，没有 MID 的歌曲会被丢掉，所以返回条数可能比上游少。
