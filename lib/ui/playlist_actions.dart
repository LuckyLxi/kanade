import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/data_ext.dart';
import '../l10n/l10n_ext.dart';
import '../library/library_controller.dart';
import '../src/rust/api/types.dart';
import 'sheet.dart';
import 'toast.dart';
import 'widgets.dart';

/// 歌单菜单做了什么，详情页据此改标题或退出。
sealed class PlaylistEdit {}

class PlaylistRenamed extends PlaylistEdit {
  PlaylistRenamed(this.name);

  final String name;
}

class PlaylistDeleted extends PlaylistEdit {}

/// “我喜欢”不能改名也不能删。
bool canEditPlaylist(MyPlaylist? p) => p != null && !isLikedPlaylist(p);

/// 自建歌单的更多操作：重命名、删除。没有改动时返回 null。
Future<PlaylistEdit?> showPlaylistActions(BuildContext context, MyPlaylist playlist) async {
  final l = AppLocalizations.of(context);
  final action = await showKanadeSheet<String>(
    context: context,
    builder: (sheet) => Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SheetHeader(
          leading: Cover(playlist.coverUrl, size: 48, radius: 10),
          title: playlist.name,
          subtitle: l.songCount(playlist.songCount),
        ),
        SheetGroup(
          children: [
            SheetRow(
              leading: const Icon(Icons.edit_outlined),
              title: l.renamePlaylist,
              onTap: () => Navigator.pop(sheet, 'rename'),
            ),
            SheetRow(
              leading: const Icon(Icons.delete_outline_rounded),
              title: l.deletePlaylist,
              destructive: true,
              onTap: () => Navigator.pop(sheet, 'delete'),
            ),
          ],
        ),
      ],
    ),
  );
  if (!context.mounted) return null;
  return switch (action) {
    'rename' => _rename(context, playlist),
    'delete' => _delete(context, playlist),
    _ => null,
  };
}

Future<PlaylistEdit?> _rename(BuildContext context, MyPlaylist playlist) async {
  final l = AppLocalizations.of(context);
  final library = context.read<LibraryController>();
  final name = await _playlistName(context, l.renamePlaylist, initial: playlist.name);
  if (name == null || name == playlist.name || !context.mounted) return null;
  try {
    await library.renamePlaylist(playlist, name);
    if (context.mounted) showToast(context, l.playlistRenamed, kind: ToastKind.success);
    return PlaylistRenamed(name);
  } catch (e) {
    if (context.mounted) showToast(context, l.actionFailed(errorText(l, e)), kind: ToastKind.error);
    return null;
  }
}

Future<PlaylistEdit?> _delete(BuildContext context, MyPlaylist playlist) async {
  final l = AppLocalizations.of(context);
  final library = context.read<LibraryController>();
  final ok = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      content: Text(l.deletePlaylistConfirm(playlist.name)),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(false), child: Text(l.cancel)),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.error),
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(l.delete),
        ),
      ],
    ),
  );
  if (ok != true || !context.mounted) return null;
  try {
    await library.deletePlaylist(playlist);
    if (context.mounted) showToast(context, l.playlistDeleted, kind: ToastKind.success);
    return PlaylistDeleted();
  } catch (e) {
    if (context.mounted) showToast(context, l.actionFailed(errorText(l, e)), kind: ToastKind.error);
    return null;
  }
}

Future<String?> _playlistName(BuildContext context, String title, {String initial = ''}) => showDialog<String>(
  context: context,
  builder: (_) => _PlaylistNameDialog(title: title, initial: initial),
);

class _PlaylistNameDialog extends StatefulWidget {
  const _PlaylistNameDialog({required this.title, required this.initial});

  final String title;
  final String initial;

  @override
  State<_PlaylistNameDialog> createState() => _PlaylistNameDialogState();
}

class _PlaylistNameDialogState extends State<_PlaylistNameDialog> {
  late final _controller = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final value = _controller.text.trim();
    if (value.isNotEmpty) Navigator.of(context).pop(value);
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(widget.title),
      content: TextField(
        controller: _controller,
        autofocus: true,
        maxLength: 40,
        decoration: InputDecoration(hintText: l.playlistNameHint),
        onSubmitted: (_) => _submit(),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: Text(l.cancel)),
        ValueListenableBuilder(
          valueListenable: _controller,
          builder: (_, value, _) =>
              FilledButton(onPressed: value.text.trim().isEmpty ? null : _submit, child: Text(l.ok)),
        ),
      ],
    );
  }
}

Future<MyPlaylist?> createPlaylist(BuildContext context) async {
  final l = AppLocalizations.of(context);
  final library = context.read<LibraryController>();
  final name = await _playlistName(context, l.createPlaylist);
  if (name == null || !context.mounted) return null;
  try {
    final playlist = await library.createPlaylist(name);
    if (context.mounted) showToast(context, l.playlistCreated, kind: ToastKind.success);
    return playlist;
  } catch (e) {
    if (context.mounted) showToast(context, l.actionFailed(errorText(l, e)), kind: ToastKind.error);
    return null;
  }
}
