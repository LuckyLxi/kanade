import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../auth/auth_controller.dart';
import '../data/data_ext.dart';
import '../download/download_controller.dart';
import '../l10n/l10n_ext.dart';
import '../library/library_controller.dart';
import '../player/player_controller.dart';
import '../src/rust/api/music.dart' as api;
import '../src/rust/api/types.dart';
import 'album_page.dart';
import 'comments_page.dart';
import 'download_actions.dart';
import 'follow_button.dart';
import 'lyric_options_sheet.dart';
import 'mv_page.dart';
import 'player_bar_page.dart';
import 'sheet.dart';
import 'singer_page.dart';
import 'song_actions.dart';
import 'song_list_page.dart';
import 'widgets.dart';

void openSinger(BuildContext context, Song song) {
  final singers = song.singers.where((s) => s.mid.isNotEmpty).toList();
  if (singers.length == 1) {
    pushFromPlayer(
      context,
      SingerPage.route(singers.first.mid, singers.first.name),
    );
    return;
  }
  showKanadeSheet<void>(
    context: context,
    builder: (sheet) => SheetGroup(
      children: [
        for (final s in singers)
          SheetRow(
            leading: Cover(singerAvatar(s.mid), size: 32, radius: 16),
            title: s.name,
            trailing: _SingerFollow(s.mid),
            chevron: true,
            onTap: () {
              Navigator.pop(sheet);
              pushFromPlayer(context, SingerPage.route(s.mid, s.name));
            },
          ),
      ],
    ),
  );
}

/// 歌曲的更多操作：上排快捷操作，下方为 MV、相似歌曲、歌手和专辑。
/// 在自己的歌单里打开时传入 [onRemove]，多出“从歌单中删除”；从播放页打开时 [lyricOptions] 多出歌词显示设置。
Future<void> showSongActions(
  BuildContext context,
  Song song, {
  VoidCallback? onRemove,
  bool lyricOptions = false,
}) {
  final l = AppLocalizations.of(context);
  // 本地歌没有 QQ 音乐的歌曲 id，只留播放队列和删除
  final local = isLocalSong(song);
  // 拿不到评论数就不显示
  final commentTotal = local
      ? Future<int?>.value()
      : api
            .getSongCommentCount(id: song.id)
            .then<int?>((n) => n, onError: (_) => null);
  return showKanadeSheet<void>(
    context: context,
    builder: (sheet) {
      final liked = sheet.watch<LibraryController>().isLiked(song);
      final downloads = sheet.watch<DownloadController>();
      final download = downloads.item(song.mid);
      // 正在放的这首（比如从播放页打开）没必要“下一首播放”
      final isCurrent = sheet.select<PlayerController, bool>(
        (p) => p.current?.mid == song.mid,
      );
      // 先关掉面板，再用外层 context 执行，面板关闭后 sheet 就失效了
      void run(void Function() action) {
        Navigator.pop(sheet);
        action();
      }

      final scheme = Theme.of(sheet).colorScheme;
      final singers = song.singers.where((s) => s.mid.isNotEmpty).toList();
      Widget label(String text) => Text(
        text,
        style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
      );
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SheetHeader(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
            leading: Cover(song.coverUrl, size: 56, radius: 12),
            title: song.name,
            subtitle: [
              singerNames(song),
              if (song.albumName.isNotEmpty) song.albumName,
            ].join(' · '),
            trailing: local
                ? null
                : _LikeButton(
                    liked: liked,
                    tooltip: liked ? l.likedShort : l.likeShort,
                    onTap: () => run(() => toggleLike(context, song)),
                  ),
          ),
          SheetPills(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
            children: [
              if (!isCurrent)
                SheetPill(
                  icon: Icons.queue_play_next_rounded,
                  label: l.playNext,
                  onTap: () => run(() => playNext(context, song)),
                ),
              if (!local)
                SheetPill(
                  icon: Icons.playlist_add_rounded,
                  label: l.addToPlaylist,
                  onTap: () => run(() => addToPlaylist(context, song)),
                ),
            ],
          ),
          Divider(
            height: 9,
            thickness: 0.5,
            indent: 14,
            endIndent: 14,
            color: scheme.outlineVariant,
          ),
          if (!local) ...[
            SheetRow(
              leading: Icon(
                download?.state == DownloadState.done
                    ? Icons.download_done_rounded
                    : Icons.download_rounded,
              ),
              title: download == null
                  ? l.download
                  : downloadStateText(l, download.state),
              trailing: download == null
                  ? null
                  : download.state == DownloadState.running
                  ? ValueListenableBuilder(
                      valueListenable: downloads.live(download),
                      builder: (_, d, _) => label(downloadProgressText(d)),
                    )
                  : label(qualityLabel(l, download.quality)),
              onTap: () => run(
                () => download == null
                    ? downloadSong(context, song)
                    : showDownloadActions(context, song, download),
              ),
            ),
            SheetRow(
              leading: const Icon(Icons.chat_bubble_outline_rounded),
              title: l.comments,
              trailing: FutureBuilder(
                future: commentTotal,
                builder: (_, snap) => switch (snap.data) {
                  final n? when n > 0 => label(formatCount(l, n)),
                  _ => const SizedBox.shrink(),
                },
              ),
              onTap: () => run(
                () => Navigator.of(context).push(CommentsPage.song(song)),
              ),
            ),
          ],
          if (lyricOptions)
            SheetRow(
              leading: const Icon(Icons.lyrics_outlined),
              title: l.lyricOptions,
              chevron: true,
              onTap: () => run(() => showLyricOptions(context)),
            ),
          if (song.mvVid.isNotEmpty)
            SheetRow(
              leading: const Icon(Icons.music_video_rounded),
              title: l.watchMv,
              onTap: () => run(
                () =>
                    Navigator.of(context)
                        .push(MvPage.route(song.mvVid, song.name)),
              ),
            ),
          if (!local)
            SheetRow(
              leading: const Icon(Icons.manage_search_rounded),
              title: l.findSimilarSongs,
              onTap: () => run(
                () => pushFromPlayer(
                  context,
                  SongListPage.similar(song, l.similarSongsTitle(song.name)),
                ),
              ),
            ),
          if (singers.isNotEmpty)
            SheetRow(
              // 多位歌手时没有哪张头像能代表全部
              leading: singers.length == 1
                  ? Cover(singerAvatar(singers.first.mid), size: 22, radius: 11)
                  : const Icon(Icons.person_outline_rounded),
              title: singerNames(song),
              trailing: label(l.singerLabel),
              onTap: () => run(() => openSinger(context, song)),
            ),
          if (song.albumMid.isNotEmpty)
            SheetRow(
              leading: Cover(song.coverUrl, size: 22, radius: 5),
              title: song.albumName,
              trailing: label(l.albumLabel),
              onTap: () => run(
                () => pushFromPlayer(
                  context,
                  AlbumPage.route(song.albumMid, song.albumName),
                ),
              ),
            ),
          if (!local)
            SheetRow(
              leading: const Icon(Icons.heart_broken_outlined),
              title: l.dislike,
              onTap: () => run(() => dislikeSong(context, song)),
            ),
          if (onRemove != null)
            SheetRow(
              leading: const Icon(Icons.playlist_remove_rounded),
              title: l.removeFromPlaylist,
              destructive: true,
              onTap: () => run(onRemove),
            ),
          if (download?.state == DownloadState.done)
            SheetRow(
              leading: const Icon(Icons.delete_outline_rounded),
              title: l.deleteDownloadedSong,
              destructive: true,
              onTap: () => run(() => confirmDeleteDownload(context, song)),
            ),
        ],
      );
    },
  );
}

class _LikeButton extends StatelessWidget {
  const _LikeButton({
    required this.liked,
    required this.tooltip,
    required this.onTap,
  });

  final bool liked;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (_, group) = sheetColors(scheme);
    return Tooltip(
      message: tooltip,
      child: Material(
        color: liked ? scheme.primaryContainer : group,
        shape: const CircleBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: SizedBox.square(
            dimension: 40,
            child: Icon(
              liked ? Icons.favorite_rounded : Icons.favorite_border_rounded,
              size: 22,
              color: liked ? scheme.onPrimaryContainer : scheme.onSurface,
            ),
          ),
        ),
      ),
    );
  }
}

/// 多位歌手面板里每行右边的关注按钮。播放页已经提前取过关注状态，一般打开就有。
class _SingerFollow extends StatefulWidget {
  const _SingerFollow(this.mid);

  final String mid;

  @override
  State<_SingerFollow> createState() => _SingerFollowState();
}

class _SingerFollowState extends State<_SingerFollow> {
  late final _account = context.read<AuthController>().user?.uin;
  late final _social = SingerSocials.get(widget.mid, _account);
  bool? _followed;

  @override
  Widget build(BuildContext context) => FutureBuilder<SingerSocial>(
    future: _social,
    initialData: SingerSocials.peek(widget.mid, _account),
    builder: (context, snap) {
      if (snap.hasError) return const SizedBox.shrink();
      final social = snap.data;
      // 还在取时先占着位置，回来时歌手名不会被挤窄
      return Padding(
        padding: const EdgeInsets.only(left: 8, right: 4),
        child: IgnorePointer(
          ignoring: social == null,
          child: AnimatedOpacity(
            opacity: social == null ? 0 : 1,
            duration: const Duration(milliseconds: 200),
            child: SizedBox(
              height: 32,
              child: FollowButton(
                followed: _followed ?? social?.followed ?? false,
                onChanged: (value) async {
                  await api.setSingerFollowed(mid: widget.mid, followed: value);
                  SingerSocials.setFollowed(widget.mid, _account, value);
                  if (mounted) setState(() => _followed = value);
                },
              ),
            ),
          ),
        ),
      );
    },
  );
}
