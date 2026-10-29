import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:gal/gal.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../auth/auth_controller.dart';
import '../l10n/l10n_ext.dart';
import '../library/library_controller.dart';
import '../src/rust/api/music.dart' as api;
import '../src/rust/api/error.dart';
import '../src/rust/api/types.dart';
import 'playlist_actions.dart';
import 'settings_page.dart';
import 'song_list_page.dart';
import 'widgets.dart';

class MinePage extends StatelessWidget {
  const MinePage({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthController>();
    final user = auth.user;
    final l = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    // 不要“我的”大标题，右上角只留设置
    return Scaffold(
      appBar: AppBar(
        actions: [
          IconButton(
            tooltip: l.settings,
            style: IconButton.styleFrom(backgroundColor: scheme.surfaceContainerHigh),
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => Navigator.of(context).push(SettingsPage.route()),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: user == null ? const _LoggedOut() : _LoggedIn(user, key: ValueKey(user.uin)),
    );
  }
}

class _LoggedOut extends StatelessWidget {
  const _LoggedOut();

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.account_circle_outlined, size: 72),
            const SizedBox(height: 12),
            Text(l.loginPrompt, textAlign: TextAlign.center),
            const SizedBox(height: 20),
            Wrap(
              spacing: 12,
              runSpacing: 8,
              alignment: WrapAlignment.center,
              children: [
                FilledButton.icon(
                  icon: const Icon(Icons.qr_code),
                  label: Text(l.loginQq),
                  onPressed: () => showDialog(
                    context: context,
                    builder: (_) => const QrLoginDialog(kind: LoginKind.qq),
                  ),
                ),
                FilledButton.tonalIcon(
                  icon: const Icon(Icons.qr_code_2),
                  label: Text(l.loginWechat),
                  onPressed: () => showDialog(
                    context: context,
                    builder: (_) => const QrLoginDialog(kind: LoginKind.wechat),
                  ),
                ),
                FilledButton.tonalIcon(
                  icon: const Icon(Icons.music_note),
                  label: Text(l.loginQqMusic),
                  onPressed: () => showDialog(
                    context: context,
                    builder: (_) => const QrLoginDialog(kind: LoginKind.qqMusic),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () => showDialog(context: context, builder: (_) => const CookieLoginDialog()),
              child: Text(l.loginCookie),
            ),
          ],
        ),
      ),
    );
  }
}

class _LoggedIn extends StatefulWidget {
  const _LoggedIn(this.user, {super.key});

  final UserInfo user;

  @override
  State<_LoggedIn> createState() => _LoggedInState();
}

/// 全部歌单（含收藏的），以及自建歌单按 tid 查到的可写信息。
typedef _Playlists = (List<PlaylistBrief>, Map<String, MyPlaylist>);

/// 自建歌单的可写信息拿不到时，只是没有改名/删除入口，列表照常显示。
Future<_Playlists> _loadPlaylists(LibraryController library) async {
  final own = library.myPlaylists().then((l) => {for (final p in l) p.tid.toString(): p}, onError: (_) => <String, MyPlaylist>{});
  final all = await api.getUserPlaylists();
  return (all, await own);
}

class _LoggedInState extends State<_LoggedIn> {
  /// false：自己创建的；true：收藏别人的。
  bool _collected = false;

  bool _isCreated(PlaylistBrief p) => p.creator.isEmpty || p.creator == widget.user.nickname;

  /// “我喜欢”是 dirId 201 的那个自建歌单，点开时才去取它的 id。
  Future<void> _openLiked() async {
    final l = AppLocalizations.of(context);
    final nav = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final liked = (await context.read<LibraryController>().myPlaylists()).where((p) => p.dirId == 201).firstOrNull;
      if (liked != null) nav.push(SongListPage.playlist(liked.tid.toString(), liked.name));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(l.loadFailed(errorText(l, e)))));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final user = widget.user;
    final likedCount = context.select<LibraryController, int>((c) => c.likedCount);
    final playlistsVersion = context.select<LibraryController, int>((c) => c.playlistsVersion);
    return ListView(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(2),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: scheme.primary, width: 2),
                ),
                child: CircleAvatar(
                  radius: 27,
                  backgroundColor: scheme.surfaceContainerHigh,
                  backgroundImage: user.avatarUrl.isEmpty ? null : NetworkImage(user.avatarUrl),
                  child: user.avatarUrl.isEmpty ? const Icon(Icons.person) : null,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      user.nickname,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 2),
                    Text('ID ${user.uin}', style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
                  ],
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              Expanded(
                child: _QuickTile(
                  icon: Icon(Icons.favorite, color: scheme.primary),
                  label: l.likedSongs,
                  trailing: likedCount > 0 ? '$likedCount' : null,
                  onTap: _openLiked,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _QuickTile(
                  icon: const Icon(Icons.history),
                  label: l.recentPlays,
                  onTap: () => Navigator.of(context).push(SongListPage.recent(l.recentPlays)),
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
          child: Row(
            children: [
              Expanded(
                child: Text(l.myPlaylists, style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w700)),
              ),
              _Pill(label: l.playlistsCreated, selected: !_collected, onTap: () => setState(() => _collected = false)),
              const SizedBox(width: 6),
              _Pill(label: l.playlistsCollected, selected: _collected, onTap: () => setState(() => _collected = true)),
            ],
          ),
        ),
        AsyncView<_Playlists>(
          // 改名、删除、加删歌之后重新加载
          key: ValueKey(playlistsVersion),
          load: () => _loadPlaylists(context.read<LibraryController>()),
          builder: (context, data) {
            final (all, own) = data;
            final lists = all.where((p) => _isCreated(p) != _collected).toList();
            if (lists.isEmpty) {
              return Padding(
                padding: const EdgeInsets.all(32),
                child: Center(
                  child: Text(l.noPlaylists, style: TextStyle(color: scheme.onSurfaceVariant)),
                ),
              );
            }
            return Column(
              children: [
                for (final p in lists)
                  ListTile(
                    leading: Cover(p.coverUrl, size: 52, radius: 12),
                    title: Text(
                      p.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                    ),
                    subtitle: Text(
                      [if (p.songCount > 0) l.songCount(p.songCount), if (!_isCreated(p)) p.creator].join(' · '),
                    ),
                    trailing: canEditPlaylist(own[p.id])
                        ? IconButton(
                            tooltip: l.more,
                            icon: Icon(Icons.more_vert, color: scheme.onSurfaceVariant),
                            onPressed: () => showPlaylistActions(context, own[p.id]!),
                          )
                        : Icon(Icons.chevron_right, color: scheme.onSurfaceVariant),
                    onTap: () => Navigator.of(context).push(SongListPage.playlist(p.id, p.title)),
                    onLongPress: canEditPlaylist(own[p.id]) ? () => showPlaylistActions(context, own[p.id]!) : null,
                  ),
              ],
            );
          },
        ),
        // ListView 自己会加上玻璃条盖住的底部 padding
        const SizedBox(height: 16),
      ],
    );
  }
}

/// “我喜欢 / 最近播放”这种大号入口卡片。onTap 为空时显示成暂不可用。
class _QuickTile extends StatelessWidget {
  const _QuickTile({required this.icon, required this.label, this.trailing, required this.onTap});

  final Widget icon;
  final String label;
  final String? trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Opacity(
      opacity: onTap == null ? 0.45 : 1,
      child: Material(
        color: scheme.surfaceContainerHigh,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: scheme.outlineVariant),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: SizedBox(
            height: 92,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  icon,
                  Row(
                    children: [
                      Expanded(
                        child: Text(label, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                      ),
                      if (trailing != null)
                        Text(
                          trailing!,
                          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: scheme.onSurfaceVariant),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 选中是白底黑字，没选中是描边。
class _Pill extends StatelessWidget {
  const _Pill({required this.label, required this.selected, required this.onTap});

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: selected ? scheme.secondaryContainer : Colors.transparent,
      shape: StadiumBorder(side: selected ? BorderSide.none : BorderSide(color: scheme.outlineVariant)),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
              color: selected ? scheme.onSecondaryContainer : scheme.onSurfaceVariant,
            ),
          ),
        ),
      ),
    );
  }
}

class QrLoginDialog extends StatefulWidget {
  const QrLoginDialog({super.key, required this.kind});

  final LoginKind kind;

  @override
  State<QrLoginDialog> createState() => _QrLoginDialogState();
}

const _appLogin = MethodChannel('kanade/app_login');

enum _QrState { loading, loadFailed, waiting, scanned, expired, refused, failed }

class _QrLoginDialogState extends State<QrLoginDialog> {
  QrCode? _qr;
  _QrState _state = _QrState.loading;
  Object? _error;
  bool _expired = false;
  Timer? _timer;
  bool _polling = false;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _refresh() async {
    _timer?.cancel();
    setState(() {
      _qr = null;
      _expired = false;
      _state = _QrState.loading;
    });
    try {
      final qr = await api.createLoginQr(kind: widget.kind);
      if (!mounted) return;
      setState(() {
        _qr = qr;
        _state = _QrState.waiting;
      });
      _timer = Timer.periodic(const Duration(seconds: 2), (_) => _poll());
    } catch (e) {
      if (mounted) {
        setState(() {
          _state = _QrState.loadFailed;
          _error = e;
        });
      }
    }
  }

  Future<void> _poll() async {
    final qr = _qr;
    if (qr == null || _polling) return;
    _polling = true;
    try {
      final s = await api.pollLoginQr(kind: widget.kind, qrsig: qr.qrsig);
      if (!mounted) return;
      switch (s) {
        case QrStatus_Waiting():
          break;
        case QrStatus_Scanned():
          setState(() => _state = _QrState.scanned);
        case QrStatus_Expired():
          _timer?.cancel();
          setState(() {
            _expired = true;
            _state = _QrState.expired;
          });
        case QrStatus_Refused():
          _timer?.cancel();
          setState(() {
            _expired = true;
            _state = _QrState.refused;
          });
        case QrStatus_Success(:final user):
          _timer?.cancel();
          context.read<AuthController>().onLoggedIn(user);
          Navigator.of(context).pop();
      }
    } catch (e) {
      _timer?.cancel();
      if (mounted) {
        setState(() {
          _expired = true;
          _state = _QrState.failed;
          _error = e;
        });
      }
    } finally {
      _polling = false;
    }
  }

  String _status(AppLocalizations l) {
    return switch (_state) {
      _QrState.loading => l.qrLoading,
      _QrState.loadFailed => l.qrFailed(errorText(l, _error!)),
      _QrState.waiting => switch (widget.kind) {
        LoginKind.qq => l.qrScanHintQq,
        LoginKind.wechat => l.qrScanHintWechat,
        LoginKind.qqMusic => l.qrScanHintQqMusic,
      },
      _QrState.scanned => l.qrScanned,
      _QrState.expired => l.qrExpired,
      _QrState.refused => l.qrRefused,
      // LoginFailed 的文案本身就带“登录失败”
      _QrState.failed =>
        _error is ApiError_LoginFailed ? errorText(l, _error!) : l.errorLoginFailed(errorText(l, _error!)),
    };
  }

  void _toast(String text) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

  /// 申请一张跳转专用票据交给手机 QQ（等同于用 QQ 扫了码），确认后 QQ 通过 schemacallback 切回本 App，
  /// 登录结果仍由现有的 ptqrlogin 轮询拿到。
  Future<void> _openQq() async {
    final old = _qr;
    if (old == null) return;
    final QrCode ticket;
    try {
      ticket = await api.createQqAppLogin();
    } catch (e) {
      if (mounted) _toast(AppLocalizations.of(context).qrFailed(errorText(AppLocalizations.of(context), e)));
      return;
    }
    if (!mounted) return;
    // 之后轮询跳转票据；画面上的二维码保留，但已不再被轮询
    setState(() => _qr = QrCode(image: old.image, qrsig: ticket.qrsig, url: ticket.url));
    final target = Uri.parse(
      'wtloginmqq://ptlogin/qlogin?qrcode=${Uri.encodeComponent(ticket.url)}'
      '&schemacallback=${Uri.encodeComponent('kanade-auth://authorize/qq')}',
    );
    if (!await _launch(target, 'com.tencent.mobileqq') && mounted) {
      _toast(AppLocalizations.of(context).qrQqNotInstalled);
    }
  }

  /// 在 QQ 音乐内打开二维码对应的授权页（等同于用 QQ 音乐扫了码），点“登录”后轮询即可拿到 App 当前账号。
  Future<void> _openQqMusic() async {
    final url = _qr?.url ?? '';
    if (url.isEmpty) return;
    final target = Uri.parse('qqmusic://qq.com/ui/openUrl?p=${Uri.encodeComponent(jsonEncode({'url': url}))}');
    if (!await _launch(target, 'com.tencent.qqmusic') && mounted) {
      _toast(AppLocalizations.of(context).qrQqMusicNotInstalled);
    }
  }

  /// 安卓上必须指定包名打开，见 MainActivity。
  Future<bool> _launch(Uri target, String package) async {
    try {
      return defaultTargetPlatform == TargetPlatform.android
          ? await _appLogin.invokeMethod<bool>('open', {'url': target.toString(), 'package': package}) ?? false
          : await launchUrl(target, mode: LaunchMode.externalApplication);
    } catch (_) {
      return false;
    }
  }

  Future<void> _saveImage() async {
    final qr = _qr;
    if (qr == null) return;
    final l = AppLocalizations.of(context);
    try {
      await Gal.putImageBytes(qr.image, name: 'kanade_login_${DateTime.now().millisecondsSinceEpoch}');
      if (mounted) _toast(l.qrSavedQq);
    } catch (e) {
      if (mounted) _toast(l.qrSaveFailed('$e'));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final mobile =
        !kIsWeb && (defaultTargetPlatform == TargetPlatform.android || defaultTargetPlatform == TargetPlatform.iOS);
    final ready = _qr != null && !_expired;
    return AlertDialog(
      title: Text(switch (widget.kind) {
        LoginKind.qq => l.loginQq,
        LoginKind.wechat => l.loginWechat,
        LoginKind.qqMusic => l.loginQqMusic,
      }),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 200,
            height: 200,
            child: _qr == null
                ? const Center(child: CircularProgressIndicator())
                : Opacity(
                    opacity: _expired ? 0.2 : 1,
                    child: Image.memory(_qr!.image, filterQuality: FilterQuality.none, fit: BoxFit.contain),
                  ),
          ),
          const SizedBox(height: 12),
          Text(_status(l), textAlign: TextAlign.center),
          if (mobile && ready) ...[
            const SizedBox(height: 12),
            ...switch (widget.kind) {
              LoginKind.qq => [
                FilledButton.icon(onPressed: _openQq, icon: const Icon(Icons.open_in_new), label: Text(l.qrOpenQq)),
                TextButton.icon(onPressed: _saveImage, icon: const Icon(Icons.save_alt), label: Text(l.qrSaveImage)),
              ],
              LoginKind.qqMusic => [
                FilledButton.icon(
                  onPressed: _openQqMusic,
                  icon: const Icon(Icons.open_in_new),
                  label: Text(l.qrOpenQqMusic),
                ),
              ],
              // 微信拒绝识别相册里的登录码，本机没有办法完成
              LoginKind.wechat => [
                Text(
                  l.qrWechatSameDeviceTip,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            },
          ],
        ],
      ),
      actions: [
        if (_expired) TextButton(onPressed: _refresh, child: Text(l.qrRefresh)),
        TextButton(onPressed: () => Navigator.of(context).pop(), child: Text(l.cancel)),
      ],
    );
  }
}

class CookieLoginDialog extends StatefulWidget {
  const CookieLoginDialog({super.key});

  @override
  State<CookieLoginDialog> createState() => _CookieLoginDialogState();
}

class _CookieLoginDialogState extends State<CookieLoginDialog> {
  final _controller = TextEditingController();
  bool _busy = false;
  Object? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await context.read<AuthController>().loginWithCookie(_controller.text);
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(l.cookieLoginTitle),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l.cookieLoginHint),
            const SizedBox(height: 12),
            TextField(
              controller: _controller,
              maxLines: 4,
              decoration: InputDecoration(
                border: const OutlineInputBorder(),
                errorText: _error == null ? null : errorText(l, _error!),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: Text(l.cancel)),
        FilledButton(onPressed: _busy ? null : _submit, child: Text(l.login)),
      ],
    );
  }
}
