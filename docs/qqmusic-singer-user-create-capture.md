# QQ 音乐歌手主页、关注、新建歌单与用户主页抓包

观察日期：2026-10-31（北京时间）。代码基线：`820b61d`。
本轮只抓包和整理，未修改业务代码、UI、交互或动画，未独立重放任何 QQ 音乐业务请求。
用户审核本记录后再决定接入内容。

## 本次抓到了什么

歌手样本为「鸣潮先约电台」。用户记录的界面显示为粉丝 **33.9 万**、**38 万乐迷守护**。

| 用户要求 | 抓到的内容 | 核对结果与缺项 |
| --- | --- | --- |
| 歌手主页精选 | 歌手资料、首批歌曲与专辑、精选专辑、相似歌手、视频预览 | 批量请求成功；精选专辑有 2 张。精选页由多个接口组成 |
| 歌手视频 | 分类标签、分类列表、排序参数切换 | 全部 17 条、官方版 16 条、动画版 1 条；未出现 `start>0` 的分页请求 |
| 关注歌手 | 查询关注状态、关注、取消关注 | 歌手两次写操作的网关、业务与内层结果码均为 0 |
| 粉丝数 | 歌手关注人数 CGI | 返回精确值 `339101`，对应界面的 33.9 万 |
| 乐迷守护 | 主页守护按钮文案、勋章入口及详情相关读取 | 返回 `38万乐迷守护`；**未确认精确人数的独立数值字段** |
| 新建歌单 | `PlaylistBaseWrite.AddPlaylist` | `retCode=0`，返回新目录 `dirId` 与歌单 `tid`；没有自动重放或删除测试歌单 |
| 用户主页 | 他人资料、公开自建歌单、上传视频、收藏歌单 / 专辑 / MV、关注用户 | 抓到非空自建歌单样本（5 个）；收藏与上传视频本次样本为空。自己的主页未获得独立的新响应 |

这张表是当前证据范围，不代表所有账号、隐私设置、后续页或独立客户端调用都已验证。

## 文件与取证范围

临时 FlClash 规则将 QQMusic / QQMusicExternal / qmbrowser 的 `y.qq.com` 域及既有指定 API IP
送入本机 Fiddler。抓包窗口 20:34:00 至 20:39:00，派生 HAR 中的 API 请求发生于
20:34:40.501 至 20:37:01.504。

| 本地文件 | 内容 | SHA-256 |
| --- | --- | --- |
| `qqmusic-singer-user-create-20261031-2034.saz` | Fiddler 原始归档，1451 个会话，4191325 字节 | `0f6978c2a0d7f795114b9df1599fefb1057ba425e688a4316d934804aad0dbd3` |
| `qqmusic-singer-user-create-20261031-2034.har` | 按本轮时间和 QQ 音乐 CGI 路径筛选的 105 条请求，1022696 字节 | `76d177d34812e7c18968f54ae40ec4dcb2b16c7277aac7961d3d380061e4c86e` |

HAR 是从 SAZ 本地提取的派生材料，包含业务读写及部分附带请求，并非 105 个不同接口。
每项 `_sazRequestFile` / `_sazResponseFile` 指向原始成员，时间来自对应 `_m.xml`。
响应先按 HTTP 头解压；不能无损转成 UTF-8 的响应在 HAR 中使用标准 Base64 编码保存。
原始 SAZ 未修改。两类抓包文件均被现有 Git 忽略规则排除，仅留本地。

下文 HAR 序号从 0 开始，SAZ 编号按实际文件名引用。
不复制 Cookie、登录公参、签名、普通用户账号、真实测试歌单名称或其编号。

REA CLI 已离线核对 HAR 的 105 条记录，Evidence ID：
`ev_37b1fe4a040cb1dcdaa9d8a681f410b6ac0b5790e430802e9f1276102d8d4b9d`。
REA 检查的是保留文件；页面操作由用户完成，进程归因与转发链来自 FlClash 连接观察。

## 歌手精选页

HAR 11 / `raw/0120_c.txt` 为一次八项批量请求，HAR 88 / `raw/0914_c.txt` 再次观察到同一组合。
响应文件分别为 `raw/0120_s.txt` / `raw/0914_s.txt`。

| 请求键 | module.method | 业务参数 | 业务 data 返回路径 |
| --- | --- | --- | --- |
| `req_0` | `music.musichallSinger.SingerInfoInter.GetSingerDetail` | `singer_mids=[MID]`、`pic=1`、`group_singer=1`、`wiki_singer=1`、`ex_singer=1` | `singer_list[]`；`basic_info` / `pic` / `ex_info` 等 |
| `req_1` | `music.musichallSong.SongListInter.GetSingerSongList` | `singerMid`、`begin=0`、`num=10`、`order=1` | `songList[]`、`totalNum` |
| `req_2` | `music.musichallAlbum.AlbumListServer.GetAlbumList` | `singerMid`、`begin=0`、`num=30`、`order=1` | `albumList[]`、`total` |
| `req_3` | `music.musichallAlbum.SelectedAlbumServer.SelectedAlbumList` | `singerMid` | `albumList[]`；本次 2 张 |
| `req_4` | `Concern.ConcernSystemServer.cgi_qry_concern_status` | 见关注部分 | `map_singer_status`、`map_user_status` |
| `req_5` | `music.SimilarSingerSvr.GetSimilarSingerList` | `singerMid`、`num=6` | `singerlist`（本样本为 null） |
| `req_6` | `MvService.MvInfoProServer.GetSingerMvList` | `singerid`、`singermid`、`tagid=0`、`start=0`、`count=6`、`order=1` | `list[]`（6 条）、`total=17` |
| `req_7` | `music.sociality.KolFansVIPAccount.Singer2PkgUinStr` | `SingerMIDs=[MID]` | `SingerMID2PkgUin` / `SingerMID2EncUin` 等映射 |

两次 HTTP 均为 200，网关及上述八项业务 `code` 均为 0。
精选专辑元素含 `albumMid`、`albumName`、`albumTranName`、`publishDate`、`albumPmid`。
不能把精选页整体理解成一个名叫“精选”的单独接口。

## 歌手视频分类与排序

模块：`MvService.MvInfoProServer`。

| HAR / SAZ 请求 | 方法与参数差异 | 实际返回 |
| --- | --- | --- |
| 45 / `raw/0339_c.txt`，`req_0` | `GetSingerMvTag`，`singermid` | `list=[{id:0,name:"全部"},{id:1,name:"官方版"},{id:11,name:"动画版"}]` |
| 45 / `raw/0339_c.txt`，`req_1` | `GetSingerMvList`，`tagid=0,start=0,count=40,order=0` | `list` 17 条，`total=17` |
| 46 / `raw/0345_c.txt` | 同上，`tagid=1` | 16 条，`total=16` |
| 47 / `raw/0357_c.txt` | 同上，`tagid=11` | 1 条，`total=1` |
| 48 / `raw/0360_c.txt` | 动画版，`order=1` | 1 条 |
| 49、50 / `raw/0371_c.txt`、`raw/0374_c.txt` | `order=0`；分别动画版、全部 | 1 条、17 条 |

列表请求还包含 `singermid`，视频页请求没有精选预览中的数字 `singerid`。
返回字段为 `vid`、`mvid`、`title`、`picurl`、`duration`、`playcnt`、`pubdate`、`type`、
`icon_type`、`picformat`。这里使用 `vid` / `title`，与搜索视频的 `v_id` / `mv_name` 不同。

全部请求 HTTP 200、网关及业务 `code=0`。样本中 `order=0` 的全部 / 官方版按 `pubdate` 倒序；
`order=1` 只在单条动画版列表及精选预览中出现，尚不足以确认完整排序语义。
标签来自响应，不能将本歌手的三个标签固定用于其他歌手。此样本总量小于 40，未验证后续偏移。

## 关注歌手、关注用户

### 查询歌手状态

HAR 11、88 的 `req_4`：`Concern.ConcernSystemServer.cgi_qry_concern_status`。
业务参数形状：

```json
{
  "vec_userinfo": [{ "usertype": 1, "userid": "<SINGER_MID>" }],
  "opertype": 5,
  "encrypt_singerid": 1
}
```

本轮 `map_singer_status` 按歌手 MID 索引，返回值为 0。
第一次查询发生在关注前，第二次发生在关注、取消关注后，均为未关注状态。

### 关注与取消

模块及方法：`Concern.ConcernSystemServer.cgi_concern_user_v2`，请求键为 `req_0`。

| 对象 | HAR / SAZ 请求 | 参数与结果 |
| --- | --- | --- |
| 歌手关注 / 取消 | 23、24 / `raw/0166_c.txt`、`raw/0185_c.txt` | `opertype=0/1`，`source=0`，`encrypt_singerid=1`；`userinfo.usertype=1`，`userid=歌手 MID` |
| 用户关注 / 取消，样本 A | 65、66 / `raw/0502_c.txt`、`raw/0514_c.txt` | `opertype=0/1`；`userinfo.usertype=0`，`userid=对应主页的 encrypt_uin` |
| 用户关注 / 取消，样本 B | 76、77 / `raw/0601_c.txt`、`raw/0612_c.txt` | 同上，目标对应另一个主页 |

用户写请求中没有歌手请求的 `source` / `encrypt_singerid` 字段。
六条写请求均为 HTTP 200、网关 `code=0`、`req_0.code=0`，并核对 `req_0.data.code=0`。
业务 `data` 还含 `safety`，不能只凭 HTTP 200 报告关注成功。
本轮用户亲自在官方客户端执行并恢复操作，没有脚本重放。

## 粉丝数与乐迷守护

### 粉丝数：精确数字

HAR 15、92 / `raw/0130_c.txt`、`raw/0928_c.txt`：

```text
GET https://c6.y.qq.com/rsc/fcgi-bin/fcg_order_singer_getnum.fcg
```

关键查询参数为 `singermid`、`utf8=1`、`rnd`，另带内嵌页公共参数及登录上下文。
实际返回外层 `code=0`、`subcode=0`、`num=339101`、`status=0`、`blogflag=0`。
界面 33.9 万与 `num` 相符，后续实现应保留原始计数，展示时再格式化。

### 守护：已确认展示文案，未确认精确数字

HAR 19、95 / `raw/0136_c.txt`、`raw/0932_c.txt`，`req_0`：

```text
music.UnifiedHomepage.UnifiedHomepageSrv.GetHomepageIconForMedal
param: { SingerMid: <SINGER_MID>, Uin: <CURRENT_LOGIN_UIN> }
```

本次 `Uin` 为字符串，与请求 `comm.uin` 相同，不能替换成歌手映射出的账号。
HTTP 200、网关和业务 `code=0`。响应中：

- `data.NumButtonList[]` 的 `ButtonType=9` 条目，其 `ButtonInfo.Title` 为 `38万乐迷守护`。
- 同条目的 `ButtonInfo.Jump` 提供跳转信息，`ExtraInfo.medalId` 提供对应勋章标识。
- **`data.cnt=0`，不能用它代替 38 万守护人数，也不能将展示文案还原成精确 380000 人。**
- 同时抓到的 `music.lvz.MusicianGoodsSvr.GetMusicianMonthConf` 返回 `Ret=0`，但 `FansNum=""`。
  这个字段本轮不能作为守护人数来源。

打开守护详情后，原始包 `raw/0239_c.txt` 为
`i2.y.qq.com/n3/medal_collection/pages/medal_collection_v3/star_detail.html` 页面请求。
还抓到了 `music.medalHall` 下的排行、任务、常伴之心、弹窗、横幅等读取，以及勋章皮肤读取。
这些附带请求不全部等于守护人数接口；HAR 27 的 `GetWatchAdPickOneModule` 业务码为 **44005**，
不能描述为守护详情的所有接口均成功。

HAR 44 / `raw/0288_c.txt` 是 `encoding=ag-1` 的加密横幅请求。
按项目已有 `sign.rs` 常量本地解码后，方法为 `music.medalHall.MedalBannerSrv.GetBannerList`，
参数键 `BizType/Pos/Ext`，网关及业务 `code=0`；不是节目取歌请求。
这一解码结论来自本地分析，REA 对该 HAR 项保留的是编码后的传输内容。

## 新建歌单

HAR 0 / `raw/0037_c.txt`、`raw/0037_s.txt`，时间 20:34:40.501。

```text
POST https://u6.y.qq.com/cgi-bin/musics.fcg
请求键：music.musicasset.PlaylistBaseWrite.AddPlaylist
module：music.musicasset.PlaylistBaseWrite
method：AddPlaylist
```

完整业务参数仅有：

```json
{ "bFmtUtf8": true, "dirName": "<NEW_PLAYLIST_NAME>" }
```

实际请求另有完整 PC `comm`、Cookie、Sign / Mask；不能把这个片段当作已验证的独立请求。
HTTP 200、网关及业务 `code=0`，进一步核对业务 `data.retCode=0`。
返回 `data.result` 包含 `dirId`、`tid`、`dirName`、`dirDesc`、`dirPicUrl`、`updateTime`、
`plExtMask`、`resultMask`、`bSafetyHitName`、`bSafetyHitDesc`。
后续重命名 / 删除需要目录 `dirId`，读取歌单通常使用 `tid`，两者不能混用。

这个接口负责新建目录；不是已有的 `AddSonglist` 加歌接口。
本轮只观察用户创建一个空测试歌单，未验证同名、非法名称、私密可见性、创建后加歌或其他错误分支。

## 用户主页

### 官方 Windows 本轮使用旧 CGI

HAR 58、70、82、101 / `raw/0445_c.txt`、`raw/0554_c.txt`、`raw/0859_c.txt`、`raw/1174_c.txt`：

```text
GET https://c6.y.qq.com/rsc/fcgi-bin/fcg_get_profile_homepage.fcg
```

关键查询参数为 `userid=<目标用户标识>`、`cid=205360838`、`ct=20`、`cv=2276`、
`reqfrom=1`、`reqtype=0`，另有 `uin`、`g_tk` 等公共参数和 Cookie。
本轮目标用户与请求账号不同，返回 `data.creator.ishost=0`，不把这些响应标成自己的主页。

四条均 HTTP 200、外层 `code=0/subcode=0`。主要结构：

| 字段 | 含义与本次样本 |
| --- | --- |
| `data.creator.nick/headpic/uin/encrypt_uin` | 昵称、头像、账号与加密账号；保留标识类型，本文不复制其值 |
| `data.creator.isfollow` | 关注状态 |
| `data.creator.nums.fansnum/follownum` | 用户粉丝与总关注计数；另有 `followusernum/followsingernum` |
| `data.creator.islock/buy_lock/fav_lock/diss_lock` | 主页及不同资产的隐私字段，不能仅靠空数组判断为“没有内容” |
| `data.mydiss.num/list[]` | 公开自建歌单；HAR 70 返回 5 个，含 `dissid/dirid/title/picurl/subtitle/isshow/dir_show` |
| `data.mymusic[]` | 喜欢、评论、已购音乐、那年今日等卡片；卡片因用户而异 |
| `data.video`、`data.myarticle`、`data.myradio` | 视频、文章、主播电台入口与列表，本次主播电台 `totalcnt=0` |

当前项目已有的其他用户页走 `GetHomepageHeader/GetHomepageTabDetail`，
本轮官方 PC 的旧 CGI 是另一条实抓链路，不据此替换现有实现。

### 上传视频与收藏资产

| 功能 | HAR / SAZ 请求 | 参数与返回 |
| --- | --- | --- |
| 上传视频 | 59、72、84、103 / `raw/0455_c.txt`、`raw/0571_c.txt`、`raw/0865_c.txt`、`raw/1181_c.txt` | GET `https://c6.y.qq.com/rsc/fcgi-bin/fcg_get_my_vedio.fcg`（原接口拼写为 vedio）；`userid,reqtype=1,cid=205361746,sin=0,pagesize=25`；返回 `video.num/hasmore/list` |
| 收藏歌单 | 61 / `raw/0473_c.txt` | `music.musicasset.PlaylistFavRead.GetPlaylistFavInfo_v2`；`uin,offset=0,size=50`；返回 `v_list,total,hasmore,hide` |
| 收藏专辑 | 62 / `raw/0476_c.txt` | `music.musicasset.AlbumFavRead.GetAlbumFavInfo_v2`；`euin,offset=0,size=50`；返回 `v_list,total,hasmore,hide` |
| 收藏 MV | 63 / `raw/0487_c.txt` | `music.musicasset.MVFavRead.getMyFavMV_v2`；`cid=205361447,encuin,support=1,num=0,pagesize=50`；返回 `mvlist,total,hasmore` |

上述请求 HTTP 及业务结果成功，但本次列表均为空；还没有非空收藏元素及后续页证据。
`uin` / `euin` / `encuin` 的参数名不能仅凭名字推断其明文或加密语义，接入前要对照具体响应来源。
用户关注操作已在上节单独核对：本轮 `userinfo.userid` 与对应主页 `creator.encrypt_uin` 一致。

## 传输差异与验证

歌手内嵌页及关注请求：`POST https://u6.y.qq.com/cgi-bin/musics.fcg`，
正文为 JSON，`Content-Type: application/x-www-form-urlencoded`；公参 `ct=20`、`cv=2276`、
`platform="wk_v17"`，带 Cookie，本次无原生 Sign / Mask 请求头。

新建歌单为原生 PC 请求，同网关与正文形式，但 `ct="19"`、`cv="2276"`、`patch="118"`，
携带原生 Sign / Mask。创建歌单请求别名为完整 `module.method`，内嵌页多使用 `req_0` 等别名。
这些上下文不能不经验证直接混用。

检查原始 SAZ 与派生 HAR 的成员、解码正文、请求时间、记录总数和 SHA-256；
核对本记录涉及的业务结果码、列表长度与计数字段。凭据排除、文档空白和链接检查均已通过。
临时路由与原代理选择已恢复，TUN 保持开启。仅新增本记录，不改业务源码；未运行应用测试。
