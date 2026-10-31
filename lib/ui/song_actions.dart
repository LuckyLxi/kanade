import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../auth/auth_controller.dart';
import '../data/data_ext.dart';
import '../l10n/l10n_ext.dart';
import '../library/library_controller.dart';
import '../player/player_controller.dart';
import '../src/rust/api/types.dart';
import 'album_page.dart';
import 'comments_page.dart';
import 'sheet.dart';
import 'singer_page.dart';
import 'smooth_scroll.dart';
import 'toast.dart';
import 'widgets.dart';

bool _requireLogin(BuildContext context) {
  if (context.read<AuthController>().loggedIn) return true;
  showToast(context, AppLocalizations.of(context).loginRequired);
  return false;
}

Future<void> toggleLike(BuildContext context, Song song) async {
  if (!_requireLogin(context)) return;
  final l = AppLocalizations.of(context);
  try {
    final liked = await context.read<LibraryController>().toggleLike(song);
    if (context.mounted) {
      showToast(context, liked ? l.liked : l.unliked, kind: liked ? ToastKind.liked : ToastKind.info);
    }
  } catch (e) {
    if (context.mounted) showToast(context, l.actionFailed(errorText(l, e)), kind: ToastKind.error);
  }
}

Future<void> addToPlaylist(BuildContext context, Song song) async {
  if (!_requireLogin(context)) return;
  final l = AppLocalizations.of(context);
  final library = context.read<LibraryController>();
  final picked = await showKanadeSheet<MyPlaylist>(
    context: context,
    builder: (_) => _PlaylistPicker(load: library.myPlaylists),
  );
  if (picked == null || !context.mounted) return;
  try {
    await library.addToPlaylist(picked, song);
    if (context.mounted) showToast(context, l.addedToPlaylist(picked.name), kind: ToastKind.success);
  } catch (e) {
    if (context.mounted) showToast(context, l.actionFailed(errorText(l, e)), kind: ToastKind.error);
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

/// 从自己的歌单删歌，成功返回 true。
Future<bool> removeFromPlaylist(BuildContext context, MyPlaylist playlist, Song song) async {
  if (!_requireLogin(context)) return false;
  final l = AppLocalizations.of(context);
  try {
    await context.read<LibraryController>().removeFromPlaylist(playlist, song);
    if (context.mounted) showToast(context, l.removedFromPlaylist(playlist.name), kind: ToastKind.success);
    return true;
  } catch (e) {
    if (context.mounted) showToast(context, l.actionFailed(errorText(l, e)), kind: ToastKind.error);
    return false;
  }
}

void openSinger(BuildContext context, Song song) {
  final singers = song.singers.where((s) => s.mid.isNotEmpty).toList();
  if (singers.length == 1) {
    Navigator.of(context).push(SingerPage.route(singers.first.mid, singers.first.name));
    return;
  }
  showKanadeSheet<void>(
    context: context,
    builder: (sheet) => SheetGroup(
      children: [
        for (final s in singers)
          SheetRow(
            leading: const Icon(Icons.person_outline_rounded),
            title: s.name,
            chevron: true,
            onTap: () {
              Navigator.pop(sheet);
              Navigator.of(context).push(SingerPage.route(s.mid, s.name));
            },
          ),
      ],
    ),
  );
}

/// 歌曲的更多操作：下一首播放、红心、加入歌单、评论放在上面一排，歌手、专辑在下面。
/// 在自己的歌单里打开时传入 [onRemove]，多出“从歌单中删除”。
Future<void> showSongActions(BuildContext context, Song song, {VoidCallback? onRemove}) {
  final l = AppLocalizations.of(context);
  return showKanadeSheet<void>(
    context: context,
    builder: (sheet) {
      final liked = sheet.watch<LibraryController>().isLiked(song);
      // 正在放的这首（比如从播放页打开）没必要“下一首播放”
      final isCurrent = sheet.select<PlayerController, bool>((p) => p.current?.mid == song.mid);
      // 先关掉面板，再用外层 context 执行，面板关闭后 sheet 就失效了
      void run(void Function() action) {
        Navigator.pop(sheet);
        action();
      }

      final hasSinger = song.singers.any((s) => s.mid.isNotEmpty);
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SheetHeader(
            leading: Cover(song.coverUrl, size: 48, radius: 10),
            title: song.name,
            subtitle: singerNames(song),
          ),
          SheetQuickActions(
            children: [
              if (!isCurrent)
                SheetQuickAction(
                  icon: Icons.queue_play_next_rounded,
                  label: l.playNext,
                  onTap: () => run(() => playNext(context, song)),
                ),
              SheetQuickAction(
                icon: liked ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                iconColor: liked ? Theme.of(sheet).colorScheme.primary : null,
                label: liked ? l.likedShort : l.likeShort,
                onTap: () => run(() => toggleLike(context, song)),
              ),
              SheetQuickAction(
                icon: Icons.playlist_add_rounded,
                label: l.addToPlaylist,
                onTap: () => run(() => addToPlaylist(context, song)),
              ),
              SheetQuickAction(
                icon: Icons.chat_bubble_outline_rounded,
                label: l.comments,
                onTap: () => run(() => Navigator.of(context).push(CommentsPage.song(song))),
              ),
            ],
          ),
          if (hasSinger || song.albumMid.isNotEmpty || onRemove != null)
            SheetGroup(
              children: [
                if (hasSinger)
                  SheetRow(
                    leading: const Icon(Icons.person_outline_rounded),
                    title: l.singerNamed(singerNames(song)),
                    chevron: true,
                    onTap: () => run(() => openSinger(context, song)),
                  ),
                if (song.albumMid.isNotEmpty)
                  SheetRow(
                    leading: const Icon(Icons.album_outlined),
                    title: l.albumNamed(song.albumName),
                    chevron: true,
                    onTap: () => run(() => Navigator.of(context).push(AlbumPage.route(song.albumMid, song.albumName))),
                  ),
                if (onRemove != null)
                  SheetRow(
                    leading: const Icon(Icons.playlist_remove_rounded),
                    title: l.removeFromPlaylist,
                    destructive: true,
                    onTap: () => run(onRemove),
                  ),
              ],
            ),
        ],
      );
    },
  );
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

  Widget _placeholder(Widget child) => SizedBox(height: 140, child: Center(child: child));

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
                return _placeholder(Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(l.loadFailed(errorText(l, snap.error!)), textAlign: TextAlign.center),
                    const SizedBox(height: 12),
                    FilledButton.tonal(onPressed: () => setState(() => _future = widget.load()), child: Text(l.retry)),
                  ],
                ));
              }
              final lists = snap.data;
              if (lists == null) return _placeholder(const CircularProgressIndicator());
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
