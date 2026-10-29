import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../auth/auth_controller.dart';
import '../data/data_ext.dart';
import '../l10n/l10n_ext.dart';
import '../library/library_controller.dart';
import '../src/rust/api/types.dart';
import 'album_page.dart';
import 'comments_page.dart';
import 'singer_page.dart';
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
    if (context.mounted) showToast(context, liked ? l.liked : l.unliked);
  } catch (e) {
    if (context.mounted) showToast(context, l.actionFailed(errorText(l, e)));
  }
}

Future<void> addToPlaylist(BuildContext context, Song song) async {
  if (!_requireLogin(context)) return;
  final l = AppLocalizations.of(context);
  final library = context.read<LibraryController>();
  final picked = await showModalBottomSheet<MyPlaylist>(
    context: context,
    builder: (_) => SafeArea(
      child: AsyncView<List<MyPlaylist>>(
        load: library.myPlaylists,
        builder: (context, lists) => lists.isEmpty
            ? Center(child: Text(l.noMyPlaylists))
            : ListView(
                shrinkWrap: true,
                children: [
                  ListTile(title: Text(l.addToPlaylist, style: Theme.of(context).textTheme.titleMedium)),
                  for (final p in lists)
                    ListTile(
                      leading: Cover(p.coverUrl, size: 40),
                      title: Text(p.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                      subtitle: Text(l.songCount(p.songCount)),
                      onTap: () => Navigator.pop(context, p),
                    ),
                ],
              ),
      ),
    ),
  );
  if (picked == null || !context.mounted) return;
  try {
    await library.addToPlaylist(picked, song);
    if (context.mounted) showToast(context, l.addedToPlaylist(picked.name));
  } catch (e) {
    if (context.mounted) showToast(context, l.actionFailed(errorText(l, e)));
  }
}

/// 从自己的歌单删歌，成功返回 true。
Future<bool> removeFromPlaylist(BuildContext context, MyPlaylist playlist, Song song) async {
  if (!_requireLogin(context)) return false;
  final l = AppLocalizations.of(context);
  try {
    await context.read<LibraryController>().removeFromPlaylist(playlist, song);
    if (context.mounted) showToast(context, l.removedFromPlaylist(playlist.name));
    return true;
  } catch (e) {
    if (context.mounted) showToast(context, l.actionFailed(errorText(l, e)));
    return false;
  }
}

void openSinger(BuildContext context, Song song) {
  final singers = song.singers.where((s) => s.mid.isNotEmpty).toList();
  if (singers.length == 1) {
    Navigator.of(context).push(SingerPage.route(singers.first.mid, singers.first.name));
    return;
  }
  showModalBottomSheet<void>(
    context: context,
    builder: (sheet) => SafeArea(
      child: ListView(
        shrinkWrap: true,
        children: [
          for (final s in singers)
            ListTile(
              leading: const Icon(Icons.person_outline),
              title: Text(s.name),
              onTap: () {
                Navigator.pop(sheet);
                Navigator.of(context).push(SingerPage.route(s.mid, s.name));
              },
            ),
        ],
      ),
    ),
  );
}

/// 歌曲的更多操作：红心、加入歌单、评论、歌手、专辑。
/// 在自己的歌单里打开时传入 [onRemove]，多出“从歌单中删除”。
Future<void> showSongActions(BuildContext context, Song song, {VoidCallback? onRemove}) {
  final l = AppLocalizations.of(context);
  return showModalBottomSheet<void>(
    context: context,
    builder: (sheet) {
      final liked = sheet.watch<LibraryController>().isLiked(song);
      // 先关掉面板，再用外层 context 执行，面板关闭后 sheet 就失效了
      void run(void Function() action) {
        Navigator.pop(sheet);
        action();
      }

      return SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            ListTile(
              leading: Cover(song.coverUrl, size: 44, radius: 6),
              title: Text(song.name, maxLines: 1, overflow: TextOverflow.ellipsis),
              subtitle: Text(singerNames(song), maxLines: 1, overflow: TextOverflow.ellipsis),
            ),
            const Divider(height: 1),
            ListTile(
              leading: Icon(liked ? Icons.favorite : Icons.favorite_border, color: liked ? Colors.red : null),
              title: Text(liked ? l.unlike : l.like),
              onTap: () => run(() => toggleLike(context, song)),
            ),
            ListTile(
              leading: const Icon(Icons.playlist_add),
              title: Text(l.addToPlaylist),
              onTap: () => run(() => addToPlaylist(context, song)),
            ),
            if (onRemove != null)
              ListTile(
                leading: const Icon(Icons.playlist_remove),
                title: Text(l.removeFromPlaylist),
                onTap: () => run(onRemove),
              ),
            ListTile(
              leading: const Icon(Icons.comment_outlined),
              title: Text(l.comments),
              onTap: () => run(() => Navigator.of(context).push(CommentsPage.song(song))),
            ),
            if (song.singers.any((s) => s.mid.isNotEmpty))
              ListTile(
                leading: const Icon(Icons.person_outline),
                title: Text(l.singerNamed(singerNames(song)), maxLines: 1, overflow: TextOverflow.ellipsis),
                onTap: () => run(() => openSinger(context, song)),
              ),
            if (song.albumMid.isNotEmpty)
              ListTile(
                leading: const Icon(Icons.album_outlined),
                title: Text(l.albumNamed(song.albumName), maxLines: 1, overflow: TextOverflow.ellipsis),
                onTap: () => run(() => Navigator.of(context).push(AlbumPage.route(song.albumMid, song.albumName))),
              ),
          ],
        ),
      );
    },
  );
}
