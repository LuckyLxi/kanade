import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../auth/auth_controller.dart';
import '../data/data_ext.dart';
import '../l10n/l10n_ext.dart';
import '../library/library_controller.dart';
import '../player/player_controller.dart';
import '../src/rust/api/music.dart' as api;
import '../src/rust/api/types.dart';
import 'sheet.dart';
import 'smooth_scroll.dart';
import 'toast.dart';
import 'widgets.dart';

bool _requireLogin(BuildContext context) {
  if (context.read<AuthController>().loggedIn) return true;
  showToast(context, AppLocalizations.of(context).loginRequired);
  return false;
}

/// 本地歌没有 QQ 音乐的歌曲 id，红心、歌单、评论都用不了；去掉后一首不剩时提示。
List<Song> onlineSongs(BuildContext context, List<Song> songs) {
  final online = songs.where((s) => !isLocalSong(s)).toList();
  if (online.isEmpty && songs.isNotEmpty) {
    showToast(context, AppLocalizations.of(context).localSongUnsupported);
  }
  return online;
}

Future<void> toggleLike(BuildContext context, Song song) async {
  if (onlineSongs(context, [song]).isEmpty) return;
  if (!_requireLogin(context)) return;
  final l = AppLocalizations.of(context);
  try {
    final liked = await context.read<LibraryController>().toggleLike(song);
    if (context.mounted) {
      showToast(
        context,
        liked ? l.liked : l.unliked,
        kind: liked ? ToastKind.liked : ToastKind.info,
      );
    }
  } catch (e) {
    if (context.mounted) {
      showToast(
        context,
        l.actionFailed(errorText(l, e)),
        kind: ToastKind.error,
      );
    }
  }
}

Future<void> addToPlaylist(BuildContext context, Song song) =>
    addSongsToPlaylist(context, [song]);

/// 选一个歌单，把这些歌逐首加进去；全部加完返回 true。
Future<bool> addSongsToPlaylist(BuildContext context, List<Song> songs) async {
  songs = onlineSongs(context, songs);
  if (songs.isEmpty || !_requireLogin(context)) return false;
  final l = AppLocalizations.of(context);
  final library = context.read<LibraryController>();
  final picked = await showKanadeSheet<MyPlaylist>(
    context: context,
    builder: (_) => _PlaylistPicker(load: library.myPlaylists),
  );
  if (picked == null || !context.mounted) return false;
  try {
    for (final song in songs) {
      await library.addToPlaylist(picked, song);
    }
    if (context.mounted) {
      showToast(
        context,
        l.addedToPlaylist(picked.name),
        kind: ToastKind.success,
      );
    }
    return true;
  } catch (e) {
    if (context.mounted) {
      showToast(
        context,
        l.actionFailed(errorText(l, e)),
        kind: ToastKind.error,
      );
    }
    return false;
  }
}

/// 多选里的「喜欢」：还没加红心的逐首加上，已经喜欢的不动。
Future<bool> likeSongs(BuildContext context, List<Song> songs) async {
  songs = onlineSongs(context, songs);
  if (songs.isEmpty || !_requireLogin(context)) return false;
  final l = AppLocalizations.of(context);
  final library = context.read<LibraryController>();
  try {
    for (final song in songs) {
      if (!library.isLiked(song)) await library.toggleLike(song);
    }
    if (context.mounted) showToast(context, l.liked, kind: ToastKind.liked);
    return true;
  } catch (e) {
    if (context.mounted) {
      showToast(
        context,
        l.actionFailed(errorText(l, e)),
        kind: ToastKind.error,
      );
    }
    return false;
  }
}

/// 逐首取消红心，跳过本来就没喜欢的；全部完成返回 true。
Future<bool> unlikeSongs(BuildContext context, List<Song> songs) async {
  songs = onlineSongs(context, songs);
  if (songs.isEmpty || !_requireLogin(context)) return false;
  final l = AppLocalizations.of(context);
  final library = context.read<LibraryController>();
  try {
    for (final song in songs) {
      if (library.isLiked(song)) await library.toggleLike(song);
    }
    if (context.mounted) showToast(context, l.unliked);
    return true;
  } catch (e) {
    if (context.mounted) {
      showToast(
        context,
        l.actionFailed(errorText(l, e)),
        kind: ToastKind.error,
      );
    }
    return false;
  }
}

void playNext(BuildContext context, Song song) {
  final l = AppLocalizations.of(context);
  switch (context.read<PlayerController>().playNext(song)) {
    case PlayNextResult.queued:
      showToast(context, l.queuedNext, kind: ToastKind.success);
    case PlayNextResult.current:
      showToast(context, l.alreadyPlaying);
    case PlayNextResult.started:
      break;
  }
}

/// 每次不喜欢成功加一，开着的不喜欢列表据此刷新。
final dislikesRevision = ValueNotifier(0);

/// 选不喜欢这首歌还是其中一位歌手；正在放的歌受影响时切到下一首。
Future<void> dislikeSong(BuildContext context, Song song) async {
  if (onlineSongs(context, [song]).isEmpty || !_requireLogin(context)) return;
  final l = AppLocalizations.of(context);
  final singers = song.singers.where((s) => s.mid.isNotEmpty).toList();
  final picked = await showKanadeSheet<Object>(
    context: context,
    builder: (sheet) => Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SheetHeader(title: l.dislikeChoose),
        SheetGroup(
          children: [
            SheetRow(
              leading: Cover(song.coverUrl, size: 32, radius: 8),
              title: l.dislikeSong(song.name),
              onTap: () => Navigator.pop(sheet, song),
            ),
            for (final s in singers)
              SheetRow(
                leading: Cover(singerAvatar(s.mid), size: 32, radius: 16),
                title: l.dislikeSinger(s.name),
                onTap: () => Navigator.pop(sheet, s),
              ),
          ],
        ),
      ],
    ),
  );
  if (picked == null || !context.mounted) return;
  final player = context.read<PlayerController>();
  final singer = picked is Singer ? picked : null;
  try {
    if (singer == null) {
      await api.dislikeSong(songId: song.id, name: song.name);
    } else {
      await api.dislikeSinger(mid: singer.mid, name: singer.name);
    }
    dislikesRevision.value++;
    if (context.mounted) {
      showToast(
        context,
        singer == null ? l.dislikedSong : l.dislikedSinger,
        kind: ToastKind.success,
      );
    }
    final current = player.current;
    if (current != null &&
        (singer == null
            ? current.mid == song.mid
            : current.singers.any((s) => s.mid == singer.mid))) {
      await player.next();
    }
  } catch (e) {
    if (context.mounted) {
      showToast(
        context,
        l.actionFailed(errorText(l, e)),
        kind: ToastKind.error,
      );
    }
  }
}

/// 从自己的歌单删歌，成功返回 true。
Future<bool> removeFromPlaylist(
  BuildContext context,
  MyPlaylist playlist,
  Song song,
) async {
  if (!_requireLogin(context)) return false;
  final l = AppLocalizations.of(context);
  try {
    await context.read<LibraryController>().removeFromPlaylist(playlist, song);
    if (context.mounted) {
      showToast(
        context,
        l.removedFromPlaylist(playlist.name),
        kind: ToastKind.success,
      );
    }
    return true;
  } catch (e) {
    if (context.mounted) {
      showToast(
        context,
        l.actionFailed(errorText(l, e)),
        kind: ToastKind.error,
      );
    }
    return false;
  }
}

/// 选一个自己的歌单。加载中和出错时只占一小块，免得卡片先撑满再缩回去。
class _PlaylistPicker extends StatefulWidget {
  const _PlaylistPicker({required this.load});

  final Future<List<MyPlaylist>> Function() load;

  @override
  State<_PlaylistPicker> createState() => _PlaylistPickerState();
}

class _PlaylistPickerState extends State<_PlaylistPicker> {
  late Future<List<MyPlaylist>> _future = widget.load();

  Widget _placeholder(Widget child) =>
      SizedBox(height: 140, child: Center(child: child));

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SheetHeader(title: l.addToPlaylist),
        Flexible(
          child: FutureBuilder<List<MyPlaylist>>(
            future: _future,
            builder: (context, snap) {
              if (snap.hasError) {
                return _placeholder(
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        l.loadFailed(errorText(l, snap.error!)),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 12),
                      FilledButton.tonal(
                        onPressed: () =>
                            setState(() => _future = widget.load()),
                        child: Text(l.retry),
                      ),
                    ],
                  ),
                );
              }
              final lists = snap.data;
              if (lists == null) {
                return _placeholder(const CircularProgressIndicator());
              }
              if (lists.isEmpty) return _placeholder(Text(l.noMyPlaylists));
              // 歌单多的时候会很长，滚轮也要平滑
              return SmoothScroll(
                builder: (_, scroll) => SheetGroup(
                  controller: scroll,
                  children: [
                    for (final p in lists)
                      SheetRow(
                        leading: Cover(p.coverUrl, size: 40),
                        title: p.name,
                        subtitle: l.songCount(p.songCount),
                        onTap: () => Navigator.pop(context, p),
                      ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
