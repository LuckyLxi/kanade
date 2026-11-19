import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../download/download_controller.dart';
import '../l10n/l10n_ext.dart';
import '../src/rust/api/music.dart' as api;
import '../src/rust/api/types.dart';
import 'kanade_dialog.dart';
import 'sheet.dart';
import 'toast.dart';

/// 能选的音质，按官方顺序从免费到 SVIP 排列；缺解码器的档位不显示。设置里的默认音质也用它。
final selectableQualities = [
  Quality.low,
  Quality.standard,
  Quality.aicodec,
  Quality.high,
  Quality.lossless,
  Quality.hires,
  Quality.dolby,
  Quality.atmos51,
  Quality.atmos71,
  Quality.atmos,
  Quality.master,
  Quality.ra360,
  Quality.dts,
].where((q) => api.qualitySupported(quality: q)).toList();

Future<void> downloadSong(BuildContext context, Song song) =>
    downloadSongs(context, [song]);

/// 选个音质下载。一首时只列这首有的音质；多首时列全部档位，哪首没有就自动降一档。
/// 加入了下载返回 true。
Future<bool> downloadSongs(BuildContext context, List<Song> songs) async {
  final l = AppLocalizations.of(context);
  final downloads = context.read<DownloadController>();
  final single = songs.length == 1 ? songs.first : null;
  final q = await showKanadeSheet<Quality>(
    context: context,
    builder: (_) => _QualityPicker(
      subtitle: single?.name ?? l.downloadBatchHint(songs.length),
      load: single == null
          ? () async => selectableQualities
          : () async => [
              for (final o in await api.getSongQualities(mid: single.mid))
                if (o.available) o.quality,
            ],
    ),
  );
  if (q == null) return false;
  await downloads.download(songs, q);
  if (context.mounted) showToast(context, l.downloadAdded);
  return true;
}

/// 「更多」里的下载状态一行显示什么。
String downloadStateText(AppLocalizations l, DownloadState s) => switch (s) {
  DownloadState.queued => l.downloadQueued,
  DownloadState.running => l.downloading,
  DownloadState.paused => l.downloadPaused,
  DownloadState.failed => l.downloadFailed,
  DownloadState.done => l.downloaded,
};

String downloadProgressText(DownloadItem d) => d.total > BigInt.zero
    ? '${(d.received * BigInt.from(100) ~/ d.total).toInt()}%'
    : '';

/// 已经在下载列表里的歌：重下、重试或删掉。
Future<void> showDownloadActions(
  BuildContext context,
  Song song,
  DownloadItem d,
) {
  final l = AppLocalizations.of(context);
  final downloads = context.read<DownloadController>();
  return showKanadeSheet<void>(
    context: context,
    builder: (sheet) {
      void run(void Function() action) {
        Navigator.pop(sheet);
        action();
      }

      final error = d.error;
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SheetHeader(
            title: song.name,
            subtitle: [
              downloadStateText(l, d.state),
              qualityLabel(l, d.quality),
              if (d.state == DownloadState.failed && error != null)
                errorText(l, error),
            ].join(' · '),
          ),
          SheetGroup(
            children: [
              if (d.state == DownloadState.done)
                SheetRow(
                  leading: const Icon(Icons.high_quality_outlined),
                  title: l.downloadOtherQuality,
                  onTap: () => run(() => downloadSong(context, song)),
                ),
              if (d.state == DownloadState.failed)
                SheetRow(
                  leading: const Icon(Icons.refresh_rounded),
                  title: l.downloadRetry,
                  onTap: () => run(() => downloads.download([song], d.quality)),
                ),
              SheetRow(
                leading: const Icon(Icons.delete_outline_rounded),
                title: d.state == DownloadState.done
                    ? l.deleteDownload
                    : l.cancelDownload,
                destructive: true,
                onTap: () => run(() {
                  if (d.state == DownloadState.done) {
                    confirmDeleteDownload(context, song);
                  } else {
                    downloads.remove(song.mid);
                  }
                }),
              ),
            ],
          ),
        ],
      );
    },
  );
}

/// 删掉下好的文件和歌词，先问一次。
Future<void> confirmDeleteDownload(BuildContext context, Song song) async {
  final l = AppLocalizations.of(context);
  final downloads = context.read<DownloadController>();
  final ok = await showKanadeDialog<bool>(
    context,
    builder: (context) => KanadeDialog(
      icon: Icons.delete_outline_rounded,
      danger: true,
      title: l.deleteDownload,
      message: l.deleteDownloadConfirm(song.name),
      actions: [
        KanadeDialogAction(
          label: l.delete,
          primary: true,
          danger: true,
          onPressed: () => Navigator.of(context).pop(true),
        ),
        KanadeDialogAction(
          label: l.cancel,
          onPressed: () => Navigator.of(context).pop(false),
        ),
      ],
    ),
  );
  if (ok != true) return;
  await downloads.remove(song.mid);
  if (context.mounted) {
    showToast(context, l.downloadDeleted, kind: ToastKind.success);
  }
}

class _QualityPicker extends StatefulWidget {
  const _QualityPicker({required this.subtitle, required this.load});

  final String subtitle;
  final Future<List<Quality>> Function() load;

  @override
  State<_QualityPicker> createState() => _QualityPickerState();
}

class _QualityPickerState extends State<_QualityPicker> {
  late Future<List<Quality>> _options = widget.load();

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SheetHeader(title: l.downloadQuality, subtitle: widget.subtitle),
        FutureBuilder(
          future: _options,
          builder: (context, snap) {
            if (snap.hasError) {
              return SheetGroup(
                children: [
                  SheetRow(
                    leading: const Icon(Icons.refresh_rounded),
                    title: l.qualityFailedRetry,
                    subtitle: errorText(l, snap.error!),
                    onTap: () => setState(() => _options = widget.load()),
                  ),
                ],
              );
            }
            final options = snap.data;
            if (options == null) {
              return const Padding(
                padding: EdgeInsets.symmetric(vertical: 32),
                child: Center(child: CircularProgressIndicator()),
              );
            }
            if (options.isEmpty) {
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: Text(
                  l.qualityNoneForSong,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: scheme.onSurfaceVariant),
                ),
              );
            }
            return Flexible(
              child: SingleChildScrollView(
                child: SheetGroup(
                  children: [
                    for (final q in options)
                      SheetRow(
                        leading: const Icon(Icons.graphic_eq_rounded),
                        title: qualityLabel(l, q),
                        subtitle: savesAsWav(q) ? l.downloadWavHint : null,
                        onTap: () => Navigator.pop(context, q),
                      ),
                  ],
                ),
              ),
            );
          },
        ),
      ],
    );
  }
}
