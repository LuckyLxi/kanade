import 'package:flutter/material.dart';

import '../l10n/l10n_ext.dart';
import '../src/rust/api/music.dart' as api;
import '../src/rust/api/types.dart';
import 'smooth_scroll.dart';
import 'toast.dart';
import 'widgets.dart';

/// 保存成功一次加一，推荐页听到后整页刷新，新选的卡片马上出现。
final foryouSaved = ValueNotifier(0);

/// 自定义推荐页：首页最上面那排卡片显示哪些。设置跟着账号走，和官方手机版是同一份，
/// 只列出 Kanade 首页能显示的项（固定项和歌单卡）；官方的小游戏、网页等其它项保存时保持原样。
class ForyouSettingsPage extends StatefulWidget {
  const ForyouSettingsPage({super.key});

  static Route<void> route() =>
      MaterialPageRoute(builder: (_) => const ForyouSettingsPage());

  @override
  State<ForyouSettingsPage> createState() => _ForyouSettingsPageState();
}

class _ForyouSettingsPageState extends State<ForyouSettingsPage> {
  final _scroll = SmoothScrollController();
  List<ForyouItem>? _items;
  Object? _error;
  var _chosen = <String>{};
  var _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _load() {
    api.getForyouConfig().then(
      (items) {
        if (!mounted) return;
        setState(() {
          _items = items;
          _chosen = {
            for (final i in items)
              if (i.chosen) i.id,
          };
        });
      },
      onError: (Object e) {
        if (mounted) setState(() => _error = e);
      },
    );
  }

  Future<void> _save() async {
    final l = AppLocalizations.of(context);
    setState(() => _saving = true);
    try {
      await api.saveForyouConfig(chosen: _chosen.toList());
      foryouSaved.value++;
      if (!mounted) return;
      showToast(context, l.foryouSaved, kind: ToastKind.success);
      Navigator.of(context).pop();
    } catch (e) {
      if (mounted) {
        showToast(
          context,
          l.foryouSaveFailed(errorText(l, e)),
          kind: ToastKind.error,
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final items = _items;
    final Widget body;
    if (_error != null) {
      body = Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              l.loadFailed(errorText(l, _error!)),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            FilledButton.tonal(
              onPressed: () {
                setState(() => _error = null);
                _load();
              },
              child: Text(l.retry),
            ),
          ],
        ),
      );
    } else if (items == null) {
      body = const PageLoading();
    } else {
      body = ListView(
        controller: _scroll,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Text(
              l.foryouChoose,
              style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
            ),
          ),
          for (final item in items)
            ListTile(
              title: Text(item.title),
              // 猜你喜欢、每日30首固定显示，不能取消
              trailing: item.fixed
                  ? null
                  : Icon(
                      _chosen.contains(item.id)
                          ? Icons.check_circle
                          : Icons.circle_outlined,
                      color: _chosen.contains(item.id)
                          ? scheme.primary
                          : scheme.outline,
                    ),
              onTap: item.fixed
                  ? null
                  : () => setState(
                      () => _chosen.contains(item.id)
                          ? _chosen.remove(item.id)
                          : _chosen.add(item.id),
                    ),
            ),
          const BottomSpacer(),
        ],
      );
    }
    return Scaffold(
      appBar: AppBar(
        title: Text(l.foryouSettings),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: FilledButton(
              onPressed: items == null || _saving ? null : _save,
              child: Text(l.save),
            ),
          ),
        ],
      ),
      body: body,
    );
  }
}
