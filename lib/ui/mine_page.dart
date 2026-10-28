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
import '../src/rust/api/music.dart' as api;
import '../settings/locale_controller.dart';
import '../src/rust/api/error.dart';
import '../src/rust/api/types.dart';
import 'song_list_page.dart';
import 'widgets.dart';

class MinePage extends StatelessWidget {
  const MinePage({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthController>();
    final user = auth.user;
    final l = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(l.tabMine),
        actions: [
          const _LanguageMenu(),
          if (user != null)
            IconButton(tooltip: l.logout, icon: const Icon(Icons.logout), onPressed: auth.logout),
        ],
      ),
      body: user == null ? const _LoggedOut() : _LoggedIn(user, key: ValueKey(user.uin)),
    );
  }
}

/// 语言选择：跟随系统 / 各语言用自己的名字显示。
class _LanguageMenu extends StatelessWidget {
  const _LanguageMenu();

  static const _names = {'zh': '简体中文', 'en': 'English'};

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final controller = context.watch<LocaleController>();
    // PopupMenuButton 的 value 不能为 null，用空字符串表示跟随系统
    return PopupMenuButton<String>(
      tooltip: l.language,
      icon: const Icon(Icons.translate),
      initialValue: controller.locale?.languageCode ?? '',
      onSelected: (v) => controller.setLocale(v.isEmpty ? null : Locale(v)),
      itemBuilder: (_) => [
        PopupMenuItem(value: '', child: Text(l.languageSystem)),
        for (final locale in AppLocalizations.supportedLocales)
          PopupMenuItem(
            value: locale.languageCode,
            child: Text(_names[locale.languageCode] ?? locale.languageCode),
          ),
      ],
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
                  onPressed: () => showDialog(context: context, builder: (_) => const QrLoginDialog(kind: LoginKind.qq)),
                ),
                FilledButton.tonalIcon(
                  icon: const Icon(Icons.qr_code_2),
                  label: Text(l.loginWechat),
                  onPressed: () => showDialog(context: context, builder: (_) => const QrLoginDialog(kind: LoginKind.wechat)),
                ),
                FilledButton.tonalIcon(
                  icon: const Icon(Icons.music_note),
                  label: Text(l.loginQqMusic),
                  onPressed: () => showDialog(context: context, builder: (_) => const QrLoginDialog(kind: LoginKind.qqMusic)),
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

class _LoggedIn extends StatelessWidget {
  const _LoggedIn(this.user, {super.key});

  final UserInfo user;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Column(
      children: [
        ListTile(
          leading: CircleAvatar(
            backgroundImage: user.avatarUrl.isEmpty ? null : NetworkImage(user.avatarUrl),
            child: user.avatarUrl.isEmpty ? const Icon(Icons.person) : null,
          ),
          title: Text(user.nickname),
          subtitle: Text('ID ${user.uin}'),
        ),
        const Divider(height: 1),
        Expanded(
          child: AsyncView<List<PlaylistBrief>>(
            load: api.getUserPlaylists,
            builder: (context, lists) => lists.isEmpty
                ? Center(child: Text(l.noPlaylists))
                : ListView.builder(
                    itemCount: lists.length,
                    itemBuilder: (context, i) {
                      final p = lists[i];
                      return ListTile(
                        leading: Cover(p.coverUrl, size: 48),
                        title: Text(p.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                        subtitle: Text([
                          if (p.songCount > 0) l.songCount(p.songCount),
                          if (p.creator.isNotEmpty && p.creator != user.nickname) p.creator,
                        ].join(' · ')),
                        onTap: () => Navigator.of(context).push(SongListPage.playlist(p.id, p.title)),
                      );
                    },
                  ),
          ),
        ),
      ],
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
      _QrState.failed => _error is ApiError_LoginFailed
          ? errorText(l, _error!)
          : l.errorLoginFailed(errorText(l, _error!)),
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
    final mobile = !kIsWeb && (defaultTargetPlatform == TargetPlatform.android || defaultTargetPlatform == TargetPlatform.iOS);
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
                  FilledButton.icon(onPressed: _openQqMusic, icon: const Icon(Icons.open_in_new), label: Text(l.qrOpenQqMusic)),
                ],
              // 微信拒绝识别相册里的登录码，本机没有办法完成
              LoginKind.wechat => [
                  Text(l.qrWechatSameDeviceTip, textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodySmall),
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
