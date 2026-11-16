import 'dart:math';

import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../l10n/l10n_ext.dart';
import '../player/player_controller.dart';
import '../src/rust/api/music.dart' as api;
import '../src/rust/api/types.dart';
import 'glass.dart';
import 'keyed_route.dart';
import 'singer_page.dart';
import 'sliding_segments.dart';
import 'smooth_scroll.dart';
import 'song_list_page.dart';
import 'song_tile.dart';
import 'toast.dart';
import 'video_tile.dart';
import 'widgets.dart';

enum _Kind { song, album, playlist, video, book, radar }

/// 云端最近播放：顶上一直有搜索框，下面一条分段切换歌曲、专辑、歌单、视频、有声、雷达。
class RecentPage extends StatefulWidget {
  const RecentPage({super.key});

  static Route<void> route() =>
      MaterialPageRoute(builder: (_) => const RecentPage());

  @override
  State<RecentPage> createState() => _RecentPageState();
}

class _RecentPageState extends State<RecentPage> {
  _Kind _kind = _Kind.song;
  final _query = TextEditingController();

  late final Future<List<Song>> _songs = api.getRecentPlays();
  late final Future<RecentCollections> _collections = api
      .getRecentCollections();

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  bool _matches(Iterable<String> fields) {
    final q = _query.text.trim().toLowerCase();
    return q.isEmpty || fields.any((f) => f.toLowerCase().contains(q));
  }

  bool get _filtering => _query.text.trim().isNotEmpty;

  String _label(AppLocalizations l, _Kind kind) => switch (kind) {
    _Kind.song => l.searchKindSong,
    _Kind.album => l.searchKindAlbum,
    _Kind.playlist => l.searchKindPlaylist,
    _Kind.video => l.searchKindVideo,
    _Kind.book => l.recentKindAudiobook,
    _Kind.radar => l.recentKindRadar,
  };

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final top = MediaQuery.paddingOf(context).top;
    return GlassBackScaffold(
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 左边让出浮着的玻璃返回钮
          Padding(
            padding: EdgeInsets.fromLTRB(76, top + 8, 16, 0),
            child: SizedBox(height: 44, child: _searchField(l)),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
            child: SlidingSegments(
              labels: [for (final k in _Kind.values) _label(l, k)],
              selected: _kind.index,
              onSelect: (i) => setState(() => _kind = _Kind.values[i]),
            ),
          ),
          Expanded(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              switchInCurve: Curves.easeOut,
              switchOutCurve: Curves.easeIn,
              child: KeyedSubtree(
                key: ValueKey(_kind),
                child: _kind == _Kind.song
                    ? AsyncView<List<Song>>(
                        key: ValueKey(_songs),
                        load: () => _songs,
                        builder: (context, songs) => _songsView(l, songs),
                      )
                    : AsyncView<RecentCollections>(
                        key: ValueKey(_collections),
                        load: () => _collections,
                        builder: (context, c) => _list(l, _items(l, c)),
                      ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _searchField(AppLocalizations l) {
    final scheme = Theme.of(context).colorScheme;
    return TextField(
      controller: _query,
      onChanged: (_) => setState(() {}),
      style: const TextStyle(fontSize: 15),
      textAlignVertical: TextAlignVertical.center,
      decoration: InputDecoration(
        hintText: l.recentSearchHint,
        filled: true,
        fillColor: scheme.surfaceContainer,
        contentPadding: EdgeInsets.zero,
        prefixIcon: Icon(
          Icons.search_rounded,
          size: 20,
          color: scheme.onSurfaceVariant,
        ),
        suffixIcon: _query.text.isEmpty
            ? null
            : IconButton(
                tooltip: l.cancel,
                icon: const Icon(Icons.close_rounded, size: 18),
                color: scheme.onSurfaceVariant,
                onPressed: () => setState(_query.clear),
              ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(999),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }

  Widget _songsView(AppLocalizations l, List<Song> songs) {
    if (songs.isEmpty) return Center(child: Text(l.noItems));
    final shown = [
      for (final s in songs)
        if (_matches([s.name, for (final e in s.singers) e.name])) s,
    ];
    final scheme = Theme.of(context).colorScheme;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 8, 8),
          child: Row(
            children: [
              _PressScale(
                child: IconButton(
                  tooltip: l.playAll(shown.length),
                  style: IconButton.styleFrom(
                    fixedSize: const Size(44, 44),
                    backgroundColor: scheme.primaryContainer,
                    foregroundColor: scheme.onPrimaryContainer,
                    disabledBackgroundColor: scheme.surfaceContainerHigh,
                  ),
                  onPressed: shown.isEmpty
                      ? null
                      : () =>
                            context.read<PlayerController>().playList(shown, 0),
                  icon: const Icon(Icons.play_arrow_rounded, size: 26),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l.playAllTitle,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${l.songCount(shown.length)} · ${l.recentNewestFirst}',
                      style: TextStyle(
                        fontSize: 12,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              _PressScale(
                child: IconButton(
                  tooltip: l.shufflePlay,
                  onPressed: shown.isEmpty
                      ? null
                      : () {
                          final p = context.read<PlayerController>();
                          p.setMode(PlayMode.shuffle);
                          p.playList(shown, Random().nextInt(shown.length));
                        },
                  icon: const Icon(Icons.shuffle_rounded),
                ),
              ),
            ],
          ),
        ),
        const Divider(indent: 16, endIndent: 16),
        Expanded(
          child: shown.isEmpty
              ? Center(child: Text(l.searchNoResults))
              : SmoothScroll(
                  builder: (context, scroll) => ListView.builder(
                    controller: scroll,
                    keyboardDismissBehavior:
                        ScrollViewKeyboardDismissBehavior.onDrag,
                    padding: const EdgeInsets.only(top: 4),
                    itemCount: shown.length + 1,
                    itemBuilder: (context, i) => i == shown.length
                        ? const BottomSpacer()
                        : SongTile(songs: shown, index: i),
                  ),
                ),
        ),
      ],
    );
  }

  Widget _list(AppLocalizations l, List<Widget Function()> items) {
    if (items.isEmpty) {
      return Center(child: Text(_filtering ? l.searchNoResults : l.noItems));
    }
    return SmoothScroll(
      builder: (context, scroll) => ListView.builder(
        key: ValueKey(_kind),
        controller: scroll,
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        padding: const EdgeInsets.only(top: 8),
        itemCount: items.length + 1,
        itemBuilder: (context, i) =>
            i == items.length ? const BottomSpacer() : items[i](),
      ),
    );
  }

  /// 和首页的猜你喜欢一样当电台放，快放完时自动续取下一批。
  Future<void> _playRadio(AppLocalizations l, int id) async {
    final overlay = Overlay.of(context, rootOverlay: true);
    try {
      await context.read<PlayerController>().playRadio(RadioSource.station(id));
    } catch (e) {
      Toast.show(
        overlay,
        l.radioFailed(errorText(l, e)),
        kind: ToastKind.error,
      );
    }
  }

  List<Widget Function()> _items(AppLocalizations l, RecentCollections c) =>
      switch (_kind) {
        _Kind.album => [
          for (final a in c.albums)
            if (_matches([a.name, a.singerName])) () => AlbumTile(a),
        ],
        _Kind.playlist => [
          for (final p in c.playlists)
            if (_matches([p.title, p.creator])) () => _playlistTile(l, p),
        ],
        _Kind.video => [
          for (final v in c.videos)
            if (_matches([v.name, v.creator])) () => VideoTile(v),
        ],
        _Kind.book => [
          for (final b in c.books)
            if (_matches([b.name, if (b.episode != null) b.episode!.name]))
              () => _bookTile(b),
        ],
        _Kind.radar => [
          for (final r in c.radios)
            if (_matches([r.name])) () => _radioTile(l, r),
        ],
        _Kind.song => throw StateError('songs use _songsView'),
      };

  Widget _playlistTile(AppLocalizations l, PlaylistBrief p) => ListTile(
    leading: Cover(p.coverUrl, size: 52, radius: 12),
    title: Text(
      p.title,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
    ),
    subtitle: Text(
      [
        l.songCount(p.songCount),
        if (p.creator.isNotEmpty) p.creator,
      ].join(' · '),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    ),
    onTap: () => openPage(context, SongListPage.playlist(p.id, p.title)),
  );

  Widget _bookTile(RecentBook b) {
    final episode = b.episode;
    return ListTile(
      leading: Cover(b.coverUrl, size: 52, radius: 12),
      title: Text(
        b.name,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
      ),
      subtitle: episode == null
          ? null
          : Text(episode.name, maxLines: 1, overflow: TextOverflow.ellipsis),
      // 播放上次听到的那一集
      onTap: episode == null
          ? null
          : () => context.read<PlayerController>().playList([episode], 0),
    );
  }

  Widget _radioTile(AppLocalizations l, RecentRadio r) => ListTile(
    leading: Cover(r.coverUrl, size: 52, radius: 12),
    title: Text(
      r.name,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
    ),
    onTap: () => _playRadio(l, r.id),
  );
}

/// 按下时缩一点，松手回弹；只听指针，不和按钮自己的点击抢手势。
class _PressScale extends StatefulWidget {
  const _PressScale({required this.child});

  final Widget child;

  @override
  State<_PressScale> createState() => _PressScaleState();
}

class _PressScaleState extends State<_PressScale> {
  bool _down = false;

  void _set(bool down) {
    if (_down != down) setState(() => _down = down);
  }

  @override
  Widget build(BuildContext context) => Listener(
    onPointerDown: (_) => _set(true),
    onPointerUp: (_) => _set(false),
    onPointerCancel: (_) => _set(false),
    child: AnimatedScale(
      scale: _down ? 0.86 : 1,
      duration: Duration(milliseconds: _down ? 90 : 320),
      curve: _down ? Curves.easeOut : Curves.easeOutBack,
      child: widget.child,
    ),
  );
}
