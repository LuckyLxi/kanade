# QQ 音乐 Windows 播放器关联操作抓包

来源：`qqmusic-player-actions.har`，389 条记录，6,549,159 字节。
SHA-256：`8f96270f7bea23fb326037ba28ec894836eab2c6a512b81595dcbbdbac25c122`。
观察日期：2026-10-29（北京时间）。下文序号从 0 开始。
未复制 Cookie、登录公参值、账号标识、歌单名称、评论内容或签名值；未重放写请求。

## 五类功能的实际接口

| 功能 | HAR 序号 / 请求键 | module.method | 已观察到的结果 |
| --- | --- | --- | --- |
| 歌手资料 | 12 / req_0 | music.musichallSinger.SingerInfoInter.GetSingerDetail | singer_list 返回 1 位歌手 |
| 歌手歌曲 | 12 / req_1；21 / req_0 | music.musichallSong.SongListInter.GetSingerSongList | 分别返回 10 首、30 首 |
| 歌手专辑列表 | 12 / req_2；25 / req_0 | music.musichallAlbum.AlbumListServer.GetAlbumList | 各返回 10 张专辑 |
| 最新评论 | 28、31；45 | music.globalComment.CommentRead.GetNewCommentList | 返回非空评论列表 |
| 热门评论 | 28、31；45 | music.globalComment.CommentRead.GetHotCommentList | 请求成功，本样本的列表为空 |
| 评论回复 | 32、33、34 / req_1 | music.globalComment.CommentRead.GetReplyCommentList | 观察到 PageNum 0、1、2 的请求 |
| 专辑详情 | 36 / req_1 | music.musichallAlbum.AlbumInfoServer.GetAlbumDetail | 返回 basicInfo、company、singer、extra |
| 专辑歌曲 | 36 / req_2 | music.musichallAlbum.AlbumSongList.GetAlbumSongList | 返回 21 首歌曲 |
| 歌曲红心添加 | 58 | music.musicasset.PlaylistDetailWrite.AddSonglist | dirId=201，retCode=0 |
| 歌曲红心取消 | 59 | music.musicasset.PlaylistDetailWrite.DelSonglist | dirId=201，retCode=0 |
| 添加到普通歌单 | 61 | music.musicasset.PlaylistDetailWrite.AddSonglist | 本样本 dirId=1，retCode=0 |

表中各请求均为 HTTP 200，网关 code 与请求业务 code 均为 0。
红心及添加歌单进一步核对了 `data.retCode=0`；评论进一步核对了 `data.SubCode=0`。

## 请求与返回结构

- 歌手详情参数：`singer_mids`、`pic`、`group_singer`、`wiki_singer`、`ex_singer`。
- 歌手歌曲参数：`singerMid`、`begin`、`num`、`order`。
- 歌手专辑列表参数：`singerMid`、`order`、`num`、`begin`。
- 专辑详情参数：`albumMid`；专辑歌曲参数另含 `begin`、`num`、`order`。
- 评论以 `BizType` 和 `BizId` 定位对象：本次歌曲为 BizType=1，专辑为 BizType=2。
- 最新评论观察到 PageNum=0、PageSize=25、WithHot=1；热门评论观察到
  PageNum=0、PageSize=15、HotType=2。主评论列表的后续页请求未出现在本样本中。
- 回复参数包含 `RootCmId`、`LastCommentSeqNo`、`PageSize`、`LastRankScore`、
  `RankType`、`PicEnable`、`PageNum`。RankType 在样本中也有变化，不能把返回差异全部归因于翻页。
- 评论主路径为 `data.CommentList.Comments`；另有 `CommentList2`，各含
  `HasMore`、`Total`、`NextOffset`、`ListType`、`CommentIds`。

## 红心与添加歌单

本次歌曲红心操作对应向 dirId=201 的系统歌单添加、移除歌曲。
普通歌单添加复用 AddSonglist；不能把样本的普通歌单 dirId=1 固定用于其他账号或歌单。

两种写入方法的参数键一致：

```text
bFmtUtf8: true
dirId: 目标目录编号
dirName: 目标目录名称
tid: 目标歌单标识（数值型）
v_songInfo: [{ songId: 歌曲数字编号, songType: 0 }]
```

响应 `data.result` 为更新后的歌单信息，包含 dirId、tid、songlist、updateTime 等。
本次未看到从普通测试歌单移除歌曲的独立请求；DelSonglist 的已观察成功对象是系统歌单。
后续实现独立写操作时应核对实际目标歌单，并在用户触发操作后才发送。

## 客户端参数差异与其他观察

- 歌手、评论、专辑详情使用客户端内嵌页面上下文 `ct=20`。
- 红心与添加歌单使用原生客户端上下文 `ct="19"`、`cv="2276"`。
- 两组均访问客户端网关；不能假定它们共用完整公参、鉴权方式或请求别名。
- 额外观察到歌手精选专辑、相似歌手、MV 列表和评论操作接口。
  序号 35 的 `GlobalComment.GlobalCommentWriteServer.UpdateHotComment` 成功返回 code=0、subcode=0；
  它针对评论，不能与歌曲红心操作混用。

## 核对方式与边界

以上来自对原始 HAR 的本地 JSON 核对，未重放其中的写请求，尚未接入 Kanade 界面。
REA 的严格 HAR 校验因序号 260 的 `request.queryString[0].name` 类型不合规而未通过，
没有生成有效的 REA Evidence ID；原始 HAR 未被修改。这不影响直接核对上述明确的 JSON 业务记录。
抓包可证明这些请求与响应存在，不能据此宣称所有后续页、排序组合和其他账号的写操作均已验证。

## Android 收藏／加歌的 2000 排查

2026-10-29 用 `music.vipcgi.VipBannerCgi.QueryVipBanner` 做了只读对照：
同一套 PC 公参、Cookie、`module.method` 请求键，发到无 Sign/Mask 的 `musics.fcg` 时，
全局及业务 code 均为 2000；发到 `u6.y.qq.com/cgi-bin/musicu.fcg` 时均为 0。
因此应用的 `desktop_write` 改用 musicu 网关，保留 PC 公参、请求别名和 Cookie。
没有保存或复用 HAR 中的 Sign/Mask，也没有自动重试写操作。

另外，写响应必须明确包含数字型 `retCode=0` 才报告成功；缺失结果码不再被当作 0。
只读传输回归测试通过。收藏和添加歌单的真实写入仍需在新版 Android App 中由用户触发复测。

## Windows 红心仍报 80105 的后续修正

用户后续在 Windows 上确认普通歌单添加成功，但系统「我喜欢」添加返回业务码 80105。
这证明不能把普通歌单的成功直接推广到系统收藏目录。

参考 [simple-music 的实测记录](https://github.com/Yyyangshenghao/simple-music/blob/master/docs/qq-music-api.md#28-2026-10-16-红心签名加密协议修复)，
仅将 dirId=201 的 AddSonglist / DelSonglist 分流到 `zzc` 签名、`ag-1` 加密的 musics 通道。
采用网页公参 ct=24、cv=4747474、platform=yqq.json，以及当前登录态的 Cookie、authst 和 g_tk。
201 的请求参数只带 dirId 与 v_songInfo；普通歌单继续使用已经成功的 PC musicu 路径与完整歌单参数。
每次请求随机生成 12 字节 IV，AES-128-GCM 加密与签名使用同一份 JSON；响应先按协议解码，
再检查全局 code、业务 code、retCode。单次提交，不自动重发或回退明文。

本次已通过跨语言加密测试向量、业务失败不能被 retCode=0 掩盖的回归测试，
并分别用只读接口验证普通 PC 和签名加密通道。尚待用户在新版 Windows 程序中验证真实红心操作。

后续用户在该 Windows 测试版对《赴每一程未知 (I.R.I.S cover)》复测，红心仍返回 80105；
不能将此处的签名通道修正记为已解决。官方 `get_song_detail_yqq` 返回该曲 ID=634598738、
MID=004Ytrah01J9gS、type=0；当前微信登录态与原抓包属于同一账号，但 musickey 已变化。
用当前通道查询该账号 3 首已收藏歌曲，均正确返回已收藏；加入 tmeLoginType 后查询结果不变。
因此只读身份识别和加密解码通过，仍不能据此证明写入权限或完整写请求正确。
正在补抓同一首歌在官方 Windows 客户端中的成功红心请求；未自动重放收藏写请求。

## Kanade 接入情况（2026-10-29）

- 歌手页、专辑页、评论（热门 + 最新 + 回复）：`rust/src/qq/detail.rs`，用内嵌页公参 `ct=20`。
  联网核对：歌手 002mYUgi0lXd76 返回 160 首歌、10 张专辑；歌曲 1401475 的最新评论第 0、1 页
  各 25 条且无重复；一条 68 条回复的评论，回复第 0、1 页各 10 条且无重复。
  主评论后续页按 `PageNum` 递增并传上一页最后一条的 `SeqNo` 作为 `LastCommentSeqNo`。
- 红心与加入歌单：`rust/src/qq/library.rs`，用原生公参 `ct="19"`，按抓包发往
  `musics.fcg?pcachetime=`，请求键为 `module.method`。目标歌单的 `dirId`/`tid`/名称从
  `fcg_user_created_diss` 的 `dirid`、`tid`、`diss_name` 读取（已只读核对能找到 dirid=201），不写死。
- 写请求只在用户点击按钮后发送；开发时未实际发出过写请求。
