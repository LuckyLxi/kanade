import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../data/data_ext.dart';
import '../download/download_controller.dart';
import '../l10n/l10n_ext.dart';
import '../player/player_controller.dart';
import '../src/rust/api/types.dart';
import 'download_actions.dart';
import 'glass.dart';
import 'sliding_segments.dart';
import 'song_tile.dart';
import 'widgets.dart';

/// 下载管理：「下载中」能暂停、继续、重试、取消，「已下载」直接播放。
class DownloadsPage extends StatefulWidget {
  const DownloadsPage({super.key});

  static Route<void> route() =>
      MaterialPageRoute(builder: (_) => const DownloadsPage());

  @override
  State<DownloadsPage> createState() => _DownloadsPageState();
}

class _DownloadsPageState extends State<DownloadsPage> {
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final top = MediaQuery.paddingOf(context).top;
    final downloads = context.watch<DownloadController>();
    final active = [
      for (final d in downloads.items)
        if (d.state != DownloadState.done) d,
    ];
    // 新下好的在前
    final done = [
      for (final d in downloads.items.toList().reversed)
        if (d.state == DownloadState.done) d.song,
    ];
    final running = active.any(
      (d) =>
          d.state == DownloadState.running || d.state == DownloadState.queued,
    );
    return GlassBackScaffold(
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 左边让出浮着的玻璃返回钮
          Padding(
            padding: EdgeInsets.fromLTRB(76, top + 8, 8, 0),
            child: SizedBox(
              height: 44,
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      l.download,
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  if (_tab == 0 && active.isNotEmpty)
                    TextButton(
                      onPressed: () {
                        final mids = [for (final d in active) d.song.mid];
                        running
                            ? downloads.pause(mids)
                            : downloads.resume(mids);
                      },
                      child: Text(
                        running ? l.downloadPauseAll : l.downloadResumeAll,
                      ),
                    ),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
            child: SlidingSegments(
              labels: [
                '${l.downloading} ${active.length}',
                '${l.downloaded} ${done.length}',
              ],
              selected: _tab,
              onSelect: (i) => setState(() => _tab = i),
            ),
          ),
          Expanded(
            child: _tab == 0
                ? _active(l, downloads, active)
                : _done(l, context, done),
          ),
        ],
      ),
    );
  }

  Widget _active(
    AppLocalizations l,
    DownloadController downloads,
    List<DownloadItem> items,
  ) {
    final waiting = downloads.waitingForWifi;
    return _RemovalList<DownloadItem>(
      items: items,
      keyOf: (d) => d.song.mid,
      empty: Center(child: Text(l.downloadEmpty)),
      padding: const EdgeInsets.only(top: 8, bottom: 120),
      itemBuilder: (items, i) {
        final item = items[i];
        return ValueListenableBuilder(
          valueListenable: downloads.live(item),
          // 状态变了列表会整个重建；正在淡出的行停在移出前的样子
          builder: (_, d, _) => _ActiveRow(
            d.state == item.state ? d : item,
            waitingForWifi: waiting,
          ),
        );
      },
    );
  }

  Widget _done(AppLocalizations l, BuildContext context, List<Song> songs) {
    final scheme = Theme.of(context).colorScheme;
    return _RemovalList<Song>(
      items: songs,
      keyOf: (s) => s.mid,
      empty: Center(child: Text(l.downloadedEmpty)),
      padding: const EdgeInsets.only(bottom: 120),
      itemBuilder: (songs, i) => SongTile(songs: songs, index: i),
      header: songs.isEmpty
          ? null
          : Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 8, 4),
              child: Row(
                children: [
                  IconButton(
                    tooltip: l.playAll(songs.length),
                    style: IconButton.styleFrom(
                      fixedSize: const Size(44, 44),
                      backgroundColor: scheme.primaryContainer,
                      foregroundColor: scheme.onPrimaryContainer,
                    ),
                    onPressed: () =>
                        context.read<PlayerController>().playList(songs, 0),
                    icon: const Icon(Icons.play_arrow_rounded, size: 26),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      '${l.playAllTitle} · ${l.songCount(songs.length)}',
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}

/// 列表里少了的行先淡出、收起高度再拿掉，下面的行跟着往上移。新增的行直接出现。
class _RemovalList<T> extends StatefulWidget {
  const _RemovalList({
    required this.items,
    required this.keyOf,
    required this.itemBuilder,
    required this.empty,
    required this.padding,
    this.header,
  });

  final List<T> items;
  final Object Function(T item) keyOf;
  final Widget Function(List<T> items, int index) itemBuilder;
  final Widget empty;
  final EdgeInsets padding;
  final Widget? header;

  @override
  State<_RemovalList<T>> createState() => _RemovalListState<T>();
}

class _Row {
  _Row(this.key);

  final Object key;

  /// 正在移出时冻结的旧行和它的动画。
  Widget? leaving;
  AnimationController? controller;
  CurvedAnimation? animation;

  void dispose() {
    animation?.dispose();
    controller?.dispose();
  }
}

class _RemovalListState<T> extends State<_RemovalList<T>>
    with TickerProviderStateMixin {
  late var _rows = [for (final t in widget.items) _Row(widget.keyOf(t))];

  /// 列表删空后头部也没了，最后几行收起前先留着旧的，不然它们会一下跳上去。
  Widget? _lastHeader;

  @override
  void didUpdateWidget(_RemovalList<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.header == null && oldWidget.header != null) {
      _lastHeader = IgnorePointer(child: oldWidget.header);
    } else if (widget.header != null) {
      _lastHeader = null;
    }
    final items = widget.items;
    final keys = [for (final t in items) widget.keyOf(t)];
    final keySet = keys.toSet();
    final oldIndex = {
      for (var i = 0; i < oldWidget.items.length; i++)
        oldWidget.keyOf(oldWidget.items[i]): i,
    };
    final next = <_Row>[];
    final placed = <Object>{};
    var j = 0;
    void place(int i) {
      next.add(_Row(keys[i]));
      placed.add(keys[i]);
    }

    // 按新列表的顺序排，正在移出的行留在原来的位置
    for (final r in _rows) {
      if (!keySet.contains(r.key)) {
        if (r.controller == null) _leave(r, oldWidget, oldIndex[r.key]!);
        next.add(r);
        continue;
      }
      if (r.controller != null) {
        // 移出途中又加回来了，按新的行放
        r.dispose();
        continue;
      }
      if (placed.contains(r.key)) continue;
      while (keys[j] != r.key) {
        if (!placed.contains(keys[j])) place(j);
        j++;
      }
      place(j++);
    }
    for (; j < keys.length; j++) {
      if (!placed.contains(keys[j])) place(j);
    }
    _rows = next;
  }

  void _leave(_Row r, _RemovalList<T> old, int index) {
    final c = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 280),
      value: 1,
    );
    r
      ..leaving = old.itemBuilder(old.items, index)
      ..controller = c
      ..animation = CurvedAnimation(parent: c, curve: Curves.easeInOutCubic);
    c.reverse().whenComplete(() {
      if (!mounted || !_rows.contains(r)) return;
      setState(() => _rows.remove(r));
      r.dispose();
    });
  }

  @override
  void dispose() {
    for (final r in _rows) {
      r.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_rows.isEmpty) return widget.empty;
    final header = widget.header ?? _lastHeader;
    final offset = header == null ? 0 : 1;
    final index = {
      for (var i = 0; i < widget.items.length; i++)
        widget.keyOf(widget.items[i]): i,
    };
    return ListView.builder(
      padding: widget.padding,
      itemCount: _rows.length + offset,
      findChildIndexCallback: (key) {
        final i = _rows.indexWhere((r) => ValueKey(r.key) == key);
        return i < 0 ? null : i + offset;
      },
      itemBuilder: (context, i) {
        if (i < offset) return header!;
        final r = _rows[i - offset];
        final animation = r.animation;
        return KeyedSubtree(
          key: ValueKey(r.key),
          child: animation == null
              ? widget.itemBuilder(widget.items, index[r.key]!)
              : IgnorePointer(
                  child: SizeTransition(
                    sizeFactor: animation,
                    alignment: Alignment.topCenter,
                    child: FadeTransition(opacity: animation, child: r.leaving),
                  ),
                ),
        );
      },
    );
  }
}

class _ActiveRow extends StatelessWidget {
  const _ActiveRow(this.d, {required this.waitingForWifi});

  final DownloadItem d;
  final bool waitingForWifi;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final downloads = context.read<DownloadController>();
    final mid = d.song.mid;
    final error = d.error;
    final status = switch (d.state) {
      DownloadState.queued when waitingForWifi => l.downloadWaitingWifi,
      DownloadState.queued => l.downloadQueued,
      DownloadState.running => [
        formatBytes(d.received.toInt()),
        if (d.total > BigInt.zero) formatBytes(d.total.toInt()),
      ].join(' / '),
      DownloadState.paused => l.downloadPaused,
      DownloadState.failed => [
        l.downloadFailed,
        if (error != null) errorText(l, error),
      ].join(' · '),
      DownloadState.done => l.downloaded,
    };
    final progress = d.total > BigInt.zero
        ? (d.received.toDouble() / d.total.toDouble()).clamp(0.0, 1.0)
        : null;
    final (icon, tooltip, action) = switch (d.state) {
      DownloadState.queued || DownloadState.running => (
        Icons.pause_rounded,
        l.downloadPause,
        () => downloads.pause([mid]),
      ),
      DownloadState.paused => (
        Icons.play_arrow_rounded,
        l.downloadResume,
        () => downloads.resume([mid]),
      ),
      _ => (
        Icons.refresh_rounded,
        l.downloadRetry,
        () => downloads.resume([mid]),
      ),
    };
    return ListTile(
      leading: Cover(d.song.coverUrl, size: 48, radius: 10),
      title: Text(d.song.name, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${singerNames(d.song)} · ${qualityLabel(l, d.quality)}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 4),
          if (d.state == DownloadState.running ||
              (d.state == DownloadState.paused && progress != null))
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: LinearProgressIndicator(
                value: progress,
                minHeight: 3,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          Text(
            status,
            maxLines: d.state == DownloadState.failed ? 4 : 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 12,
              color: d.state == DownloadState.failed
                  ? scheme.error
                  : scheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(tooltip: tooltip, icon: Icon(icon), onPressed: action),
          IconButton(
            tooltip: l.cancelDownload,
            icon: const Icon(Icons.close_rounded),
            onPressed: () => confirmDeleteDownload(context, d.song),
          ),
        ],
      ),
    );
  }
}
