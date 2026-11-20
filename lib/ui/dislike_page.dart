import 'package:material_ui/material_ui.dart';

import '../l10n/l10n_ext.dart';
import '../src/rust/api/music.dart' as api;
import '../src/rust/api/types.dart';
import 'sliding_segments.dart';
import 'smooth_scroll.dart';
import 'song_actions.dart';
import 'toast.dart';
import 'widgets.dart';

/// 不喜欢的歌曲和歌手，和官方 App 的黑名单是同一份。
class DislikePage extends StatefulWidget {
  const DislikePage({super.key});

  static Route<void> route() =>
      MaterialPageRoute(builder: (_) => const DislikePage());

  @override
  State<DislikePage> createState() => _DislikePageState();
}

class _DislikePageState extends State<DislikePage> {
  static const _kinds = [DislikeKind.song, DislikeKind.singer];

  final _scroll = SmoothScrollController();
  var _tab = 0;
  final _items = <DislikeKind, List<DislikeItem>>{};
  final _errors = <DislikeKind, Object>{};
  final _cancelling = <String>{};

  @override
  void initState() {
    super.initState();
    _reload();
    dislikesRevision.addListener(_reload);
  }

  @override
  void dispose() {
    dislikesRevision.removeListener(_reload);
    _scroll.dispose();
    super.dispose();
  }

  void _reload() => _kinds.forEach(_load);

  void _load(DislikeKind kind) {
    api
        .getDislikes(kind: kind)
        .then(
          (items) {
            if (mounted) {
              setState(() {
                _items[kind] = items;
                _errors.remove(kind);
              });
            }
          },
          onError: (Object e) {
            if (mounted) setState(() => _errors[kind] = e);
          },
        );
  }

  Future<void> _cancel(DislikeKind kind, DislikeItem item) async {
    final l = AppLocalizations.of(context);
    setState(() => _cancelling.add(item.id));
    try {
      await api.cancelDislike(kind: kind, id: item.id);
      if (!mounted) return;
      setState(() => _items[kind]?.remove(item));
      showToast(context, l.dislikeCancelled, kind: ToastKind.success);
    } catch (e) {
      if (mounted) {
        showToast(
          context,
          l.actionFailed(errorText(l, e)),
          kind: ToastKind.error,
        );
      }
    } finally {
      if (mounted) setState(() => _cancelling.remove(item.id));
    }
  }

  Widget _list(AppLocalizations l, DislikeKind kind) {
    final error = _errors[kind];
    if (error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              l.loadFailed(errorText(l, error)),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            FilledButton.tonal(
              onPressed: () {
                setState(() => _errors.remove(kind));
                _load(kind);
              },
              child: Text(l.retry),
            ),
          ],
        ),
      );
    }
    final items = _items[kind];
    if (items == null) return const PageLoading();
    if (items.isEmpty) {
      return Center(
        child: Text(
          kind == DislikeKind.song
              ? l.dislikeSongsEmpty
              : l.dislikeSingersEmpty,
        ),
      );
    }
    final scheme = Theme.of(context).colorScheme;
    return ListView(
      controller: _scroll,
      padding: const EdgeInsets.only(top: 8),
      children: [
        for (final item in items)
          ListTile(
            key: ValueKey(item.id),
            leading: item.imageUrl.isEmpty
                ? SizedBox.square(
                    dimension: 40,
                    child: Icon(
                      Icons.music_note_rounded,
                      color: scheme.onSurfaceVariant,
                    ),
                  )
                : Cover(item.imageUrl, size: 40, radius: 20),
            title: Text(
              item.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            trailing: TextButton(
              onPressed: _cancelling.contains(item.id)
                  ? null
                  : () => _cancel(kind, item),
              child: Text(l.dislikeCancel),
            ),
          ),
        const BottomSpacer(),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l.dislikeList)),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: SlidingSegments(
              labels: [l.tabSongs, l.searchKindSinger],
              selected: _tab,
              onSelect: (i) => setState(() => _tab = i),
            ),
          ),
          Expanded(child: _list(l, _kinds[_tab])),
        ],
      ),
    );
  }
}
