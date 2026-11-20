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
    if (items.isEmpty) return Center(child: Text(l.downloadEmpty));
    final waiting = downloads.waitingForWifi;
    return ListView.builder(
      padding: const EdgeInsets.only(top: 8, bottom: 120),
      itemCount: items.length,
      itemBuilder: (context, i) =>
          _ActiveRow(items[i], waitingForWifi: waiting),
    );
  }

  Widget _done(AppLocalizations l, BuildContext context, List<Song> songs) {
    if (songs.isEmpty) return Center(child: Text(l.downloadedEmpty));
    final scheme = Theme.of(context).colorScheme;
    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 120),
      itemCount: songs.length + 1,
      itemBuilder: (context, i) {
        if (i > 0) return SongTile(songs: songs, index: i - 1);
        return Padding(
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
        _size(d.received),
        if (d.total > BigInt.zero) _size(d.total),
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

String _size(BigInt bytes) {
  const mb = 1024 * 1024;
  final n = bytes.toInt();
  if (n < mb) return '${(n / 1024).toStringAsFixed(0)} KB';
  return '${(n / mb).toStringAsFixed(1)} MB';
}
