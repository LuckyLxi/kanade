import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../data/data_ext.dart';
import '../l10n/l10n_ext.dart';
import '../player/player_controller.dart';
import '../src/rust/api/types.dart';
import 'download_actions.dart';
import 'glass.dart';
import 'song_actions.dart';
import 'toast.dart';
import 'widgets.dart';

/// 多选：勾几首歌，一起下一首播放、加入歌单、加红心（在“我喜欢”里是取消红心）或下载。
class SongSelectPage extends StatefulWidget {
  const SongSelectPage(this.songs, {this.unlike = false, super.key});

  final List<Song> songs;

  /// 从“我喜欢”进来时红心按钮改成取消喜欢。
  final bool unlike;

  static Route<void> route(List<Song> songs, {bool unlike = false}) =>
      MaterialPageRoute(builder: (_) => SongSelectPage(songs, unlike: unlike));

  @override
  State<SongSelectPage> createState() => _SongSelectPageState();
}

class _SongSelectPageState extends State<SongSelectPage> {
  final _picked = <int>{};

  List<Song> get _songs => [
    for (var i = 0; i < widget.songs.length; i++)
      if (_picked.contains(i)) widget.songs[i],
  ];

  /// 操作完成后退出多选。
  Future<void> _run(Future<bool> Function(List<Song>) action) async {
    if (await action(_songs) && mounted) Navigator.of(context).pop();
  }

  Future<bool> _playNext(List<Song> songs) async {
    final l = AppLocalizations.of(context);
    final player = context.read<PlayerController>();
    if (player.current == null) {
      await player.playList(songs, 0);
      return true;
    }
    // 倒着插到当前这首后面，播放顺序和勾选的顺序一样
    for (final s in songs.reversed) {
      player.playNext(s);
    }
    showToast(context, l.queuedNext, kind: ToastKind.success);
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final top = MediaQuery.paddingOf(context).top;
    final all = _picked.length == widget.songs.length;
    final enabled = _picked.isNotEmpty;
    return GlassBackScaffold(
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 左边让出浮着的玻璃返回钮
          Padding(
            padding: EdgeInsets.fromLTRB(76, top + 8, 8, 4),
            child: SizedBox(
              height: 44,
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      l.selectedCount(_picked.length),
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: () => setState(() {
                      all
                          ? _picked.clear()
                          : _picked.addAll([
                              for (var i = 0; i < widget.songs.length; i++) i,
                            ]);
                    }),
                    child: Text(all ? l.selectNone : l.selectAll),
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            child: ListView.builder(
              itemCount: widget.songs.length,
              itemBuilder: (context, i) {
                final s = widget.songs[i];
                final picked = _picked.contains(i);
                void toggle() =>
                    setState(() => picked ? _picked.remove(i) : _picked.add(i));
                return ListTile(
                  onTap: toggle,
                  leading: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Checkbox(value: picked, onChanged: (_) => toggle()),
                      const SizedBox(width: 4),
                      Cover(s.coverUrl, size: 44, radius: 8),
                    ],
                  ),
                  title: Text(
                    s.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text(
                    singerNames(s),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                );
              },
            ),
          ),
          Material(
            color: scheme.surfaceContainer,
            child: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  children: [
                    _Action(
                      icon: Icons.queue_play_next_rounded,
                      label: l.playNext,
                      onTap: enabled ? () => _run(_playNext) : null,
                    ),
                    _Action(
                      icon: Icons.playlist_add_rounded,
                      label: l.addToPlaylist,
                      onTap: enabled
                          ? () => _run((s) => addSongsToPlaylist(context, s))
                          : null,
                    ),
                    if (widget.unlike)
                      _Action(
                        icon: Icons.heart_broken_rounded,
                        label: l.unlike,
                        onTap: enabled
                            ? () => _run((s) => unlikeSongs(context, s))
                            : null,
                      )
                    else
                      _Action(
                        icon: Icons.favorite_border_rounded,
                        label: l.likeShort,
                        onTap: enabled
                            ? () => _run((s) => likeSongs(context, s))
                            : null,
                      ),
                    _Action(
                      icon: Icons.download_rounded,
                      label: l.download,
                      onTap: enabled
                          ? () => _run((s) => downloadSongs(context, s))
                          : null,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Action extends StatelessWidget {
  const _Action({required this.icon, required this.label, this.onTap});

  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = onTap == null
        ? scheme.onSurface.withValues(alpha: 0.38)
        : scheme.onSurface;
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: color),
              const SizedBox(height: 4),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 12, color: color),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
