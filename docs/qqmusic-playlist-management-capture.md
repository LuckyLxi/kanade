# QQ 音乐重命名与删除歌单抓包（交给 Claude）

## 已确认的接口

2026-10-29，用户在官方 Windows QQ 音乐中操作临时测试歌单，本轮捕获重命名与删除请求。
两项均为 HTTP 200，网关 `code`、请求业务 `code`、业务 `data.retCode` 全部为数字 `0`。
没有从 Kanade 或脚本重放这些写入，也没有修改应用代码或 UI。

来源：项目根目录 `qqmusic-covers-playlist-actions.saz`，561693 字节，103 个会话。
SHA-256：`eb4628ecd18612b037144d8619341c76728da3ee7337d77ae19a286c9a8edf46`。
以下使用 SAZ 内实际文件名，不把文件名编号当作 HAR 的 0 基序号。
原始文件含登录凭据，仅留本地，已加入 `.git/info/exclude`；本文不复制账号、真实歌单编号或名称。

| 功能 | 请求 / 响应 | 北京时间 | module.method |
| --- | --- | --- | --- |
| 重命名歌单 | `raw/072_c.txt` / `raw/072_s.txt` | 21:50:57.386 +08:00 | `music.musicasset.PlaylistBaseWrite.EditPlaylist` |
| 删除歌单 | `raw/081_c.txt` / `raw/081_s.txt` | 21:51:00.665 +08:00 | `music.musicasset.PlaylistBaseWrite.DelPlaylist` |

## 通用传输上下文

```text
POST https://u6.y.qq.com/cgi-bin/musics.fcg
module: music.musicasset.PlaylistBaseWrite
请求键: module + "." + method
```

实际请求的 `Content-Type` 为 `application/x-www-form-urlencoded`，但正文是原始 JSON。
请求包含 `comm` 及上表中的完整请求键；不能把它当作普通表单字段逐项编码。
带 `Cookie`、`Sign`、`Mask` 请求头，不能把旧抓包中的签名固定用于新请求。

观察到的 PC 公参：`ct="19"`、`cv="2276"`、`patch="118"`、`_channelid="20"`、
`_os_version="6.2.9200-2"`、`tmeAppID="qqmusic"`、`tmeLoginType=1`。
样本是微信登录，不能把该登录类型写死用于其他登录方式。
`comm` 还含 `authst`、`uin`、`guid`、`wid`、`psrf_access_token_expiresAt`、
`psrf_qqaccess_token`、`psrf_qqopenid`、`psrf_qqunionid`；未验证哪些是最小必要字段。

## 重命名：EditPlaylist

完整业务参数形状如下；`dirId=123`、名称均为人工示例，不是实际目标：

```json
{
  "bFmtUtf8": true,
  "dirId": 123,
  "dirNewName": "<NEW_PLAYLIST_NAME>",
  "dirShow": 1,
  "mask": 1
}
```

| 字段 | 类型 | 已观察到的用途 / 边界 |
| --- | --- | --- |
| `bFmtUtf8` | boolean | 本次为 true。 |
| `dirId` | number | 账号内目标歌单的目录编号，不是 `tid`。 |
| `dirNewName` | string | 要设置的新名称。 |
| `dirShow` | number | 本次为 1；其他值及其与可见性的关系未验证。 |
| `mask` | number | 本次为 1；其他 bit 的语义未验证。 |

请求结构示例（公参使用占位符，实际还有上文列出的其他公参，不是已验证的精简请求）：

```json
{
  "comm": {
    "ct": "19",
    "cv": "2276",
    "uin": "<CURRENT_MUSICID>",
    "authst": "<CURRENT_MUSICKEY>"
  },
  "music.musicasset.PlaylistBaseWrite.EditPlaylist": {
    "module": "music.musicasset.PlaylistBaseWrite",
    "method": "EditPlaylist",
    "param": {
      "bFmtUtf8": true,
      "dirId": 123,
      "dirNewName": "<NEW_PLAYLIST_NAME>",
      "dirShow": 1,
      "mask": 1
    }
  }
}
```

本样本响应 `data.result.dirId` 与请求目标一致，`data.result.dirName` 与新名称完全一致。
这证明该次官方请求确实成功返回了改名后的目标信息；没有验证空名、重名、超长名或命名审核的失败场景。
`mask` 和 `dirShow` 仅记录观察值，不将其扩展为已经验证的隐私设置功能。

## 删除：DelPlaylist

完整业务参数形状（同样为人工示例）：

```json
{
  "bFmtUtf8": true,
  "dirId": 123,
  "dirName": "<CURRENT_PLAYLIST_NAME>"
}
```

请求键为 `music.musicasset.PlaylistBaseWrite.DelPlaylist`，`module` 相同，`method="DelPlaylist"`。
没有观察到 `tid`、歌曲列表、`dirShow` 或 `mask` 参数。

本次删除的 `dirId` 与前一条重命名请求的 `dirId` 相同，`dirName` 与刚设置的 `dirNewName` 完全相同。
因此名称应来自目标歌单的当前信息，不能继续发送改名前的旧名。
删除响应的 `data.result.dirId` 也与请求目标一致。

这是删除整个歌单的接口，区别于现有删除歌单内歌曲的 `music.musicasset.PlaylistDetailWrite.DelSonglist`。
本轮没有验证删除系统歌单、收藏的他人歌单、恢复歌单，或删除后再次读取列表的行为。

## 两项响应的共同结构

设 `K` 为本次请求的完整请求键，应分别核对：

```text
response.code                -> 本样本 0
response[K].code             -> 本样本 0
response[K].data.retCode     -> 本样本 0
response[K].data.result      -> 目标歌单结果信息
```

不要仅根据 HTTP 200 或 `retCode=0` 忽略外层业务失败。
以下是人工构造的改名响应示例，保留常用字段；不是原始歌单内容：

```json
{
  "code": 0,
  "music.musicasset.PlaylistBaseWrite.EditPlaylist": {
    "code": 0,
    "data": {
      "retCode": 0,
      "msg": "",
      "result": {
        "dirId": 123,
        "dirName": "<NEW_PLAYLIST_NAME>",
        "tid": 456,
        "updateTime": 1700000000
      }
    }
  }
}
```

实际两份 `data` 均还包含 `feedbackURL`、`hit_reason`、`hit_type`、`msg`；
`result` 包含 `bSafetyHitDesc`、`bSafetyHitName`、`dirDesc`、`dirId`、`dirName`、
`dirPicUrl`、`plExtMask`、`resultMask`、`tid`、`updateTime`。
这些字段的完整业务语义未逐项验证。

SAZ 响应保留 HTTP 头，解析前应分离头和正文，并按其 `Content-Encoding` 解压；本轮已完成解码与 JSON 核对。
上述 SAZ 解析为普通本地工具结果，不是 REA Evidence。

## Claude 接入参考与待验证项

- 现有 `rust/src/qq/library.rs` 已从歌单数据保存 `dirId`、`tid` 和名称，可复用目标歌单解析，
  但不能混用目录编号与 `tid`，也不能固定使用本次测试歌单的编号。
- `rust/src/qq/client.rs` 的 `Core::desktop_write` 已有 PC 公参、Cookie、完整请求别名和外层结果码处理，
  `library.rs` 的 `check_write_result` 另行检查 `retCode`，都是可检查的复用点。
  现有通道走 `musicu.fcg`，本次官方请求走 `musics.fcg`，尚未证明两个新方法可以直接复用成功。
- 本轮没有用应用凭据重放、没有验证 Android 上下文，也没有验证 Sign/Mask 的必要性或生成方式。
  其他接口的成功不能替代这两个方法的验证。
- 重命名和删除都是写入，后续应用接入应只在用户明确触发目标操作后提交；本文没有自动执行接口重试或后续写入。

本轮检查了响应三层结果码、改名结果、两次操作的目录关联、示例 JSON、文件摘要及文档空白，
未改变应用代码，因此未运行 Flutter/Rust 测试。抓包结束后已恢复临时路由。
