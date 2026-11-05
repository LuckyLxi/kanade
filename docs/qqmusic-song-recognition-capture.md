# QQ 音乐：听歌识曲

观察日期：2026-11-06（北京时间）。PC 客户端没有识曲入口，改在 MuMu 15（Android 15，root）
中运行从用户手机导出的官方 Android QQ 音乐 20.09（`QQMusic 20090808`，仅 arm64-v8a），
用 `scripts/capture-qqmusic-android.mjs --prepare` 经 Fiddler 抓包。识曲请求发生在 00:12:27 至 00:12:38，
电脑外放歌曲、模拟器使用宿主机默认麦克风收音。

## 证据

| 本地材料 | 字节 | SHA-256 |
| --- | --- | --- |
| `qqmusic-song-recognition-20261106.saz` | 827133 | `1e77b835ecb4ad9ac6da3470d9b6e48c6a6abca8160696a556eac18807b58aca` |

本地文件由现有 `.gitignore` 排除。Fiddler 当时同时作为系统代理，文件中还有与 QQ 音乐无关的宿主机流量和会话 Cookie，不应提交或公开。
本文不复制 Cookie、`uid`、`sign`、`mask`。识曲相关会话为 `raw/05` 至 `raw/16`。

## 请求

```
POST https://c6.y.qq.com/youtu/humming/search?sessionid=<毫秒时间戳>&recognizetype=1&fpType=<5|3>
Content-Type: application/x-www-form-urlencoded
```

正文不是表单，而是录音的 base64 文本：

- 8000 Hz、16 位小端有符号、单声道 PCM，无 WAV 头。
  依据：相邻 `fpType=5` 请求约 1 秒增长 16192 字节；未签名重放返回 `req_length="12.144"`，正好对应 194304 / 2 / 8000。
- 同一 `sessionid` 下累计上传：每次都发送从开始到当前的全部录音，后一次是前一次的前缀扩展（已逐字节核对 13 → 16）。
- `fpType=5` 在录音 1、2、3 秒时各发一次，之后约每 3 秒一次（6、9、12 秒）；
  从约 6 秒起，每次 `fpType=5` 前约 40 毫秒另发一次 `fpType=3`，正文是同一录音、短 704 字节的前缀。本轮认出歌曲的是 `fpType=5`。
  `fpType=3` 的服务端算法未验证。

官方客户端额外带 `Cookie`、`uid`、`sign`、`mask`、`SOURCE: spr_qqmusic_android`、`x-sign-data-type: json`。

## 响应

未命中（录音 1 至 9 秒）：

```json
{"session_id":"…","fpType":5,"ret":0,"code":0,"subcode":-7,"message":"not_match"}
```

`subcode` 在 1、2 秒录音时为 `-7`，3 秒起为 `-1`；两者含义未验证，实现上都视为继续录音。

命中（`raw/16`，约 12 秒录音）：顶层 `results`、`songlist`、`songtj`、`youtuinfo`、`ext`。
`results[0]` 有 `id`、`offset`（命中位置，秒，字符串）、`inlier`、`type="music"`；
`songlist[0]` 是常规歌曲对象（`id`、`mid`、`name`、`singer`、`album`、`file`、`pay` 等）。

## 无签名重放

用 `raw/16` 的正文重新发起请求，只带 `Content-Type`，不带 Cookie、`uid`、`sign`、`mask`、`SOURCE`，并使用新的 `sessionid`：
返回 HTTP 200，成功识别出同一首歌（`songid=556513371`、`songmid=003iAr9X0S6fJp`）。`raw/05`（约 1 秒）重放仍为 `not_match`。

无签名时响应形状不同：

- 顶层 `req_length`、`results`、`ret`、`session_id`、`status=1`、`songlist`。
- `songlist[0]` 使用旧字段名：`songid`、`songmid`、`songname`、`singerid`、`singermid`、`singername`、`albumid`、`albummid`、`albumname`、`playtime` 等。
- 其中 `songname`、`singername`、`albumname` 是 UTF-8 的 base64；`songmid` 等 mid 是明文。

只重放了这一段录音，没有验证频率限制、录音上限，也没有验证无签名通道是否长期可用。

## 底噪误判（2026-11-06 Kanade 实测）

Windows 麦克风没听到音乐时（每秒 RMS 约 43，约 -57 dBFS），无签名通道在约 8 秒后也会返回命中，三次分别给出三首不同的歌。
误判响应的 `results` 有 6 个候选，`inlier=15`、`lcs=0`，`offset` 都相同；
上面真正命中的那次只有 1 个候选，`inlier=36`、`lcs=100`。Kanade 因此只接受 `results[0].lcs > 0` 的结果。
`lcs` 的确切含义未知。

## 不经麦克风的样本验证（2026-11-06）

从 Kanade 本地歌曲缓存取 3 首歌（`003HfR8139FNqB`、`003KHkP23qtKsA`、`003nMqWr1Ea0KV`），各在 30 秒、90 秒处截 12 秒，
用 ffmpeg 转成 8 kHz 单声道 s16le，再派生两种变体：叠加同等响度高斯噪声（SNR 0 dB）；
把音乐压到 RMS 300 再叠加 RMS 43 的底噪。另生成 3 段只有 RMS 43 高斯噪声的 12 秒样本。
每个样本按 App 的节奏（1、2、3、6、9、12 秒的累计前缀）用同一 `sessionid` 无签名上传：

- 18 个歌曲样本全部认对：17 个在 3 秒时命中，SNR 0 dB 的一个在 6 秒时命中；每次命中都只有 1 个候选、`lcs=100`，`inlier` 随时长增长（3 秒约 10–36，12 秒约 25–131）。
- 3 段纯噪声样本在每个时间点都返回 `not_match`。合成噪声没有复现上面真实麦克风底噪的误判。
- 经 `recognize_song`（Rust）用 6 秒前缀复测 6 个歌曲样本和 3 段噪声，结果一致。
