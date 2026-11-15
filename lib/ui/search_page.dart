import 'dart:async';
import 'dart:convert';

import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../l10n/l10n_ext.dart';
import '../player/player_controller.dart';
import '../src/rust/api/music.dart' as api;
import '../src/rust/api/types.dart';
import 'album_page.dart';
import 'keyed_route.dart';
import 'mv_page.dart';
import 'recognize_sheet.dart';
import 'video_tile.dart';
import 'singer_page.dart';
import 'sliding_segments.dart';
import 'smooth_scroll.dart';
import 'song_list_page.dart';
import 'toast.dart';
import 'user_page.dart';
import 'song_tile.dart';
import 'widgets.dart';

class SearchPage extends StatefulWidget {
  const SearchPage({super.key});

  @override
  State<SearchPage> createState() => _SearchPageState();
}

/// 一个分类已经加载的结果；只有和分类对应的列表有内容。
class _Results {
  List<Song> songs = [];
  List<String> lyricSnippets = [];
  List<SingerBrief> singers = [];
  List<AlbumBrief> albums = [];
  List<PlaylistBrief> playlists = [];
  List<VideoBrief> videos = [];
  List<UserBrief> users = [];
  List<List<String>> songTags = [];
  List<SearchDirect> direct = [];
  List<String> related = [];

  /// 综合页第一页的歌曲数；之后翻页来的是放在最下面的“更多单曲”。
  int leadSongs = 0;
  int page = 0;
  int total = 0;
  bool hasMore = true;
  bool loading = false;
  Object? error;

  /// 跟着结果走，切换分类再切回来不会重播入场动画。
  final stagger = EntranceStagger.list();

  int get length =>
      songs.length +
      singers.length +
      albums.length +
      playlists.length +
      videos.length +
      users.length +
      direct.length;

  /// 每次换成新列表：歌曲列表会交给播放队列，不能在原列表上追加。
  void add(SearchResult r) {
    page++;
    total = r.total;
    hasMore = r.hasMore;
    songs = [...songs, ...r.songs];
    lyricSnippets = [...lyricSnippets, ...r.lyricSnippets];
    singers = [...singers, ...r.singers];
    albums = [...albums, ...r.albums];
    playlists = [...playlists, ...r.playlists];
    videos = [...videos, ...r.videos];
    users = [...users, ...r.users];
    songTags = [...songTags, ...r.songTags];
    direct = [...direct, ...r.direct];
    related = [...related, ...r.related];
    if (page == 1) leadSongs = songs.length;
  }
}

class _SearchPageState extends State<SearchPage> {
  static const _pageSize = 30;
  static const _historyKey = 'search_history';
  static const _historyMax = 20;

  final _controller = TextEditingController();
  final _hotScroll = SmoothScrollController();
  final _suggestScroll = SmoothScrollController();
  final _scrolls = {
    for (final k in SearchKind.values) k: SmoothScrollController(),
  };
  String _keyword = '';
  SearchKind _kind = SearchKind.all;
  final _results = <SearchKind, _Results>{};

  HotSearch? _hot;
  Object? _hotError;
  int _board = 0;
  List<String> _history = _readHistory();

  /// 正在输入（还没回车）时显示联想，而不是上一次的搜索结果。
  bool _typing = false;
  List<SearchSuggestion> _suggestions = [];
  Timer? _debounce;

  _Results get _current => _results.putIfAbsent(_kind, _Results.new);

  static List<String> _readHistory() {
    final raw = api.getPref(key: _historyKey);
    if (raw == null) return [];
    return (jsonDecode(raw) as List).cast<String>();
  }

  void _saveHistory(List<String> history) {
    setState(() => _history = history);
    api.setPref(key: _historyKey, value: jsonEncode(history));
  }

  @override
  void initState() {
    super.initState();
    _loadHot();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    _hotScroll.dispose();
    _suggestScroll.dispose();
    for (final c in _scrolls.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _loadHot() async {
    try {
      final hot = await api.getHotSearch();
      if (mounted) setState(() => _hot = hot);
    } catch (e) {
      if (mounted) setState(() => _hotError = e);
    }
  }

  void _onChanged(String text) {
    _debounce?.cancel();
    setState(() {
      _typing = true;
      if (text.trim().isEmpty) _suggestions = [];
    });
    final query = text.trim();
    if (query.isEmpty) return;
    _debounce = Timer(const Duration(milliseconds: 250), () async {
      try {
        final list = await api.getSearchSuggestions(query: query);
        // 只保留和输入框当前内容对应的结果，丢弃过期的请求
        if (mounted && _typing && _controller.text.trim() == query) {
          setState(() => _suggestions = list);
        }
      } catch (_) {
        // 联想失败不影响直接回车搜索
      }
    });
  }

  void _clear() {
    _debounce?.cancel();
    setState(() {
      _controller.clear();
      _typing = false;
      _suggestions = [];
      _keyword = '';
      _results.clear();
    });
  }

  bool get _showingSuggestions => _typing && _controller.text.trim().isNotEmpty;

  /// 返回键：联想退回上次的结果，结果退回热搜。
  void _back() {
    if (_showingSuggestions && _keyword.isNotEmpty) {
      _debounce?.cancel();
      FocusManager.instance.primaryFocus?.unfocus();
      setState(() {
        _controller.text = _keyword;
        _typing = false;
        _suggestions = [];
      });
    } else {
      _clear();
    }
  }

  /// 点联想或热搜词：填进输入框并直接搜索。
  void _searchFor(String keyword) {
    _controller.text = keyword;
    _search(keyword);
  }

  /// 换关键词时保留当前分类，和官方客户端一样。
  Future<void> _search(String keyword) async {
    keyword = keyword.trim();
    if (keyword.isEmpty) return;
    _debounce?.cancel();
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      _typing = false;
      _keyword = keyword;
      _results.clear();
    });
    _saveHistory(
      [
        keyword,
        ..._history.where((h) => h != keyword),
      ].take(_historyMax).toList(),
    );
    await _loadMore();
  }

  void _selectKind(SearchKind kind) {
    if (kind == _kind) return;
    setState(() => _kind = kind);
    if (_current.page == 0) _loadMore();
  }

  Future<void> _loadMore() async {
    final kind = _kind;
    final r = _current;
    if (r.loading || _keyword.isEmpty || !r.hasMore || r.error != null) return;
    final keyword = _keyword;
    setState(() => r.loading = true);
    try {
      final page = await api.search(
        keyword: keyword,
        kind: kind,
        page: r.page + 1,
        pageSize: _pageSize,
      );
      // 等待期间换了关键词，这份结果已经被清掉了
      if (!mounted || keyword != _keyword || _results[kind] != r) return;
      setState(() => r.add(page));
    } catch (e) {
      if (mounted) setState(() => r.error = e);
    } finally {
      if (mounted) setState(() => r.loading = false);
    }
  }

  void _retry() {
    setState(() => _current.error = null);
    _loadMore();
  }

  Future<void> _playSinger(String mid) async {
    final l = AppLocalizations.of(context);
    final player = context.read<PlayerController>();
    try {
      final songs = await api.getSingerSongs(mid: mid, begin: 0, num: 50);
      if (songs.isNotEmpty) await player.playList(songs, 0);
    } catch (e) {
      if (mounted) {
        showToast(
          context,
          l.loadFailed(errorText(l, e)),
          kind: ToastKind.error,
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    return PopScope(
      canPop: !_showingSuggestions && _keyword.isEmpty,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _back();
      },
      child: Scaffold(
        appBar: AppBar(
          toolbarHeight: 64,
          titleSpacing: 16,
          title: Row(
            children: [
              Expanded(
                child: SearchBar(
                  controller: _controller,
                  hintText: l.searchHint,
                  leading: Icon(Icons.search, color: scheme.onSurfaceVariant),
                  elevation: const WidgetStatePropertyAll(0),
                  backgroundColor: WidgetStatePropertyAll(
                    scheme.surfaceContainerHigh,
                  ),
                  side: WidgetStateProperty.resolveWith(
                    (states) => states.contains(WidgetState.focused)
                        ? BorderSide(color: scheme.outline)
                        : BorderSide.none,
                  ),
                  constraints: const BoxConstraints(minHeight: 48),
                  padding: const WidgetStatePropertyAll(
                    EdgeInsetsDirectional.only(start: 16, end: 6),
                  ),
                  textStyle: const WidgetStatePropertyAll(
                    TextStyle(fontSize: 15),
                  ),
                  onSubmitted: _search,
                  trailing: [
                    if (_controller.text.isNotEmpty)
                      _RoundButton(
                        icon: Icons.close_rounded,
                        size: 36,
                        iconSize: 16,
                        color: scheme.surfaceContainerHighest,
                        onPressed: _clear,
                      ),
                  ],
                  onChanged: _onChanged,
                ),
              ),
              if (_controller.text.isEmpty) ...[
                const SizedBox(width: 10),
                _RoundButton(
                  icon: Icons.mic_none_rounded,
                  tooltip: l.recognizeSong,
                  size: 48,
                  iconSize: 22,
                  color: scheme.surfaceContainerHigh,
                  onPressed: () => showRecognizeSheet(context),
                ),
              ],
            ],
          ),
        ),
        body: _body(l),
      ),
    );
  }

  Widget _body(AppLocalizations l) {
    if (_showingSuggestions) {
      return _suggestionList(l);
    }
    if (_keyword.isEmpty) {
      return _hotView(l);
    }
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
          child: SlidingSegments(
            labels: [for (final k in SearchKind.values) _kindLabel(l, k)],
            selected: _kind.index,
            onSelect: (i) => _selectKind(SearchKind.values[i]),
          ),
        ),
        Expanded(child: _resultView(l)),
      ],
    );
  }

  String _kindLabel(AppLocalizations l, SearchKind kind) => switch (kind) {
    SearchKind.all => l.searchKindAll,
    SearchKind.song => l.searchKindSong,
    SearchKind.singer => l.searchKindSinger,
    SearchKind.album => l.searchKindAlbum,
    SearchKind.playlist => l.searchKindPlaylist,
    SearchKind.video => l.searchKindVideo,
    SearchKind.lyric => l.searchKindLyric,
    SearchKind.user => l.searchKindUser,
  };

  Widget _resultView(AppLocalizations l) {
    final r = _current;
    if (r.length == 0) {
      if (r.error != null) {
        return Center(
          child: TextButton(
            onPressed: _retry,
            child: Text(
              l.searchFailed(errorText(l, r.error!)),
              textAlign: TextAlign.center,
            ),
          ),
        );
      }
      return Center(
        child: r.loading || r.page == 0
            ? const PageLoading()
            : Text(l.searchNoResults),
      );
    }
    final rows = _kind == SearchKind.all ? _allRows(l, r) : null;
    final count = rows?.length ?? r.length;
    return NotificationListener<ScrollNotification>(
      onNotification: (n) {
        // 综合页里横向滚动的歌单不算
        if (n.metrics.axis == Axis.vertical && n.metrics.extentAfter < 400) {
          _loadMore();
        }
        return false;
      },
      child: CustomScrollView(
        key: ValueKey(_kind),
        controller: _scrolls[_kind],
        slivers: [
          SliverList.builder(
            itemCount: count,
            // 结果只往后追加，按序号对得上
            itemBuilder: (context, i) => Entrance(
              delay: r.stagger.delay(i),
              child: rows?[i] ?? _item(l, r, i),
            ),
          ),
          // 放在列表外面，新的一页插进来时它还是同一个，才能淡出
          SliverToBoxAdapter(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              child: _footer(l, r),
            ),
          ),
        ],
      ),
    );
  }

  /// 综合页：直达卡片、单曲、各分类一小段、相关搜索，翻页来的歌放在最后。
  List<Widget> _allRows(AppLocalizations l, _Results r) {
    final lead = r.leadSongs;
    Widget song(int i) =>
        SongTile(songs: r.songs, index: i, tags: r.songTags[i]);
    return [
      for (final d in r.direct) _directCard(l, d),
      if (lead > 0) _moreTitle(l, SearchKind.song),
      for (var i = 0; i < lead; i++) song(i),
      if (r.singers.isNotEmpty) _moreTitle(l, SearchKind.singer),
      for (final s in r.singers) _singerTile(l, s),
      if (r.playlists.isNotEmpty) ...[
        _moreTitle(l, SearchKind.playlist),
        _playlistRow(l, r.playlists),
      ],
      if (r.albums.isNotEmpty) _moreTitle(l, SearchKind.album),
      for (final a in r.albums) AlbumTile(a),
      if (r.videos.isNotEmpty) _moreTitle(l, SearchKind.video),
      for (final v in r.videos) VideoTile(v),
      if (r.related.isNotEmpty) ...[
        _sectionTitle(l.searchRelated),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final w in r.related)
                _KeywordChip(w, outlined: true, onTap: () => _searchFor(w)),
            ],
          ),
        ),
      ],
      if (r.songs.length > lead) _sectionTitle(l.searchMoreSongs),
      for (var i = lead; i < r.songs.length; i++) song(i),
    ];
  }

  /// 综合页的分段标题，点了切到对应分类。
  Widget _moreTitle(AppLocalizations l, SearchKind kind) {
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    return InkWell(
      onTap: () => _selectKind(kind),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 20, 12, 6),
        child: Row(
          children: [
            Expanded(
              child: Text(
                _kindLabel(l, kind),
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            Text(l.seeAll, style: TextStyle(fontSize: 12, color: muted)),
            Icon(Icons.chevron_right, size: 16, color: muted),
          ],
        ),
      ),
    );
  }

  Widget _playlistRow(AppLocalizations l, List<PlaylistBrief> list) {
    return SizedBox(
      height: 180,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: list.length,
        separatorBuilder: (_, _) => const SizedBox(width: 12),
        itemBuilder: (context, i) {
          final p = list[i];
          return SizedBox(
            width: 124,
            child: PlaylistCard(
              title: p.title,
              coverUrl: p.coverUrl,
              badge: p.playCount > BigInt.zero
                  ? '▶ ${formatCount(l, p.playCount.toInt())}'
                  : null,
              onTap: () =>
                  openPage(context, SongListPage.playlist(p.id, p.title)),
            ),
          );
        },
      ),
    );
  }

  Widget _directCard(AppLocalizations l, SearchDirect d) {
    final scheme = Theme.of(context).colorScheme;
    final singer = d.kind == SearchDirectKind.singer;
    // 歌手卡片的标题是“歌手: 周杰伦”
    final name = singer
        ? d.title.replaceFirst(RegExp(r'^[^:：]*[:：]\s*'), '')
        : d.title;
    final subtitle = [d.tag, d.subtitle].where((x) => x.isNotEmpty).join(' · ');
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      child: Material(
        color: scheme.surfaceContainer,
        borderRadius: BorderRadius.circular(22),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () {
            switch (d.kind) {
              case SearchDirectKind.singer:
                openPage(context, SingerPage.route(d.id, name));
              case SearchDirectKind.playlist:
                openPage(context, SongListPage.playlist(d.id, d.title));
              case SearchDirectKind.album:
                openPage(context, AlbumPage.route(d.id, d.title));
              case SearchDirectKind.video:
                Navigator.of(context).push(MvPage.route(d.id, d.title));
            }
          },
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                Cover(d.coverUrl, size: 64, radius: singer ? 32 : 14),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      if (subtitle.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          subtitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12,
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                if (singer) ...[
                  const SizedBox(width: 8),
                  _RoundButton(
                    icon: Icons.play_arrow_rounded,
                    tooltip: l.play,
                    size: 44,
                    iconSize: 24,
                    color: scheme.primary,
                    iconColor: scheme.onPrimary,
                    onPressed: () => _playSinger(d.id),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _singerTile(AppLocalizations l, SingerBrief s) => ListTile(
    leading: Cover(s.avatarUrl, size: 52, radius: 26),
    title: Text(
      s.name,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
    ),
    subtitle: Text(l.singerStats(s.songCount, s.albumCount)),
    onTap: () => openPage(context, SingerPage.route(s.mid, s.name)),
  );

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
        if (p.playCount > BigInt.zero)
          '▶ ${formatCount(l, p.playCount.toInt())}',
      ].join(' · '),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    ),
    onTap: () => openPage(context, SongListPage.playlist(p.id, p.title)),
  );

  Widget _footer(AppLocalizations l, _Results r) {
    if (r.error != null) {
      return ListTile(
        key: const ValueKey('error'),
        title: Text(
          l.loadFailed(errorText(l, r.error!)),
          textAlign: TextAlign.center,
        ),
        onTap: _retry,
      );
    }
    final songs = _kind == SearchKind.song || _kind == SearchKind.lyric;
    return Padding(
      key: ValueKey(r.loading),
      padding: const EdgeInsets.all(16),
      child: Center(
        child: r.loading
            ? const BouncingDots()
            // 综合页上游不给总数
            : _kind == SearchKind.all
            ? null
            : Text(
                songs ? l.searchTotal(r.total) : l.searchTotalItems(r.total),
              ),
      ),
    );
  }

  Widget _item(AppLocalizations l, _Results r, int i) {
    switch (_kind) {
      case SearchKind.all:
        throw StateError('综合页由 _allRows 生成');
      case SearchKind.song:
        return SongTile(songs: r.songs, index: i, tags: r.songTags[i]);
      case SearchKind.lyric:
        return _LyricTile(
          songs: r.songs,
          index: i,
          snippet: r.lyricSnippets[i],
          keyword: _keyword,
        );
      case SearchKind.singer:
        return _singerTile(l, r.singers[i]);
      case SearchKind.album:
        return AlbumTile(r.albums[i]);
      case SearchKind.playlist:
        return _playlistTile(l, r.playlists[i]);
      case SearchKind.video:
        return VideoTile(r.videos[i]);
      case SearchKind.user:
        final u = r.users[i];
        return ListTile(
          leading: Cover(u.avatarUrl, size: 52, radius: 26),
          title: Text(
            u.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
          ),
          subtitle: Text(
            u.description.isNotEmpty
                ? u.description
                // 歌手账号没有歌单标签，不显示“歌单 0”
                : u.playlistCount > 0
                ? l.userBriefStats(
                    formatCount(l, u.fansCount.toInt()),
                    u.playlistCount,
                  )
                : l.userFans(formatCount(l, u.fansCount.toInt())),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          onTap: () => openPage(context, UserPage.route(u.euin, u.name)),
        );
    }
  }

  Widget _suggestionList(AppLocalizations l) {
    final scheme = Theme.of(context).colorScheme;
    final query = _controller.text.trim();
    return ListView(
      controller: _suggestScroll,
      padding: EdgeInsets.only(
        top: 8,
        bottom: MediaQuery.paddingOf(context).bottom + 16,
      ),
      children: [
        for (final s in _suggestions)
          if (s.kind == SuggestionKind.singer)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Material(
                color: scheme.surfaceContainer,
                borderRadius: BorderRadius.circular(20),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: () =>
                      openPage(context, SingerPage.route(s.mid, s.title)),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Row(
                      children: [
                        Cover(s.coverUrl, size: 52, radius: 26),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                s.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                l.searchKindSinger,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: scheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Icon(
                          Icons.chevron_right,
                          color: scheme.onSurfaceVariant,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            )
          else
            InkWell(
              onTap: () => _searchFor(s.title),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 16, 0),
                child: SizedBox(
                  height: 52,
                  child: Row(
                    children: [
                      Icon(
                        Icons.search,
                        size: 18,
                        color: scheme.onSurfaceVariant.withValues(alpha: 0.6),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Text.rich(
                          _highlight(
                            s.title,
                            query,
                            TextStyle(color: scheme.onSurfaceVariant),
                            TextStyle(
                              color: scheme.onSurface,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 15),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
      ],
    );
  }

  Widget _hotView(AppLocalizations l) {
    final hot = _hot;
    final scheme = Theme.of(context).colorScheme;
    final board = hot == null || hot.boards.isEmpty
        ? null
        : hot.boards[_board.clamp(0, hot.boards.length - 1)];
    return ListView(
      controller: _hotScroll,
      // 自己指定 padding 会盖掉 ListView 自动加的底部留白，要把玻璃条的高度算进去
      padding: EdgeInsets.only(
        bottom: MediaQuery.paddingOf(context).bottom + 16,
      ),
      children: [
        if (_history.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 8, 4),
            child: Row(
              children: [
                Expanded(child: _label(l.searchHistory)),
                IconButton(
                  tooltip: l.searchHistoryClear,
                  iconSize: 18,
                  color: scheme.onSurfaceVariant,
                  onPressed: () => _saveHistory([]),
                  icon: const Icon(Icons.delete_outline_rounded),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: _HistoryChips(_history, onTap: _searchFor),
          ),
        ],
        if (hot == null)
          Padding(
            padding: const EdgeInsets.only(top: 120),
            // 热搜加载失败时退回原来的提示，不影响搜索
            child: _hotError != null
                ? Center(child: Text(l.searchPrompt))
                : const PageLoading(),
          ),
        if (hot != null && hot.recommended.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 24, 16, 12),
            child: _label(l.searchRecommended),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final k in hot.recommended.take(12))
                  _KeywordChip(
                    k.title,
                    outlined: true,
                    onTap: () => _searchFor(k.query),
                  ),
              ],
            ),
          ),
        ],
        if (hot != null && board != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 28, 16, 8),
            child: SlidingSegments(
              labels: [for (final b in hot.boards) b.name],
              selected: hot.boards.indexOf(board),
              onSelect: (i) => setState(() => _board = i),
            ),
          ),
        for (final (i, k) in (board?.keywords ?? const <HotKeyword>[]).indexed)
          InkWell(
            onTap: () => _searchFor(k.query),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: SizedBox(
                height: 46,
                child: Row(
                  children: [
                    SizedBox(
                      width: 22,
                      child: Text(
                        '${i + 1}',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                          fontFeatures: const [FontFeature.tabularFigures()],
                          color: i < 3
                              ? scheme.onSurface
                              : scheme.onSurfaceVariant.withValues(alpha: 0.6),
                        ),
                      ),
                    ),
                    const SizedBox(width: 14),
                    // 标题最多占 3/4、说明最多 1/4 并靠右，窗口再窄也只是省略
                    Flexible(
                      flex: 3,
                      fit: FlexFit.tight,
                      child: Text(
                        k.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 15),
                      ),
                    ),
                    if (k.description.isNotEmpty)
                      Flexible(
                        child: Padding(
                          padding: const EdgeInsets.only(left: 8),
                          child: Text(
                            k.description,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.end,
                            style: TextStyle(
                              fontSize: 12,
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _label(String text) => Text(
    text,
    style: TextStyle(
      fontSize: 13,
      letterSpacing: 0.5,
      color: Theme.of(context).colorScheme.onSurfaceVariant,
    ),
  );

  Widget _sectionTitle(String text) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
    child: Text(
      text,
      style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
    ),
  );
}

/// [text] 里第一次出现的 [keyword]（不分大小写）用 [hit]，其余用 [base]。
TextSpan _highlight(
  String text,
  String keyword,
  TextStyle base,
  TextStyle hit,
) {
  final at = keyword.isEmpty
      ? -1
      : text.toLowerCase().indexOf(keyword.toLowerCase());
  if (at < 0) return TextSpan(text: text, style: base);
  final end = at + keyword.length;
  return TextSpan(
    style: base,
    children: [
      TextSpan(text: text.substring(0, at)),
      TextSpan(text: text.substring(at, end), style: hit),
      TextSpan(text: text.substring(end)),
    ],
  );
}

class _RoundButton extends StatelessWidget {
  const _RoundButton({
    required this.icon,
    required this.size,
    required this.iconSize,
    required this.color,
    required this.onPressed,
    this.iconColor,
    this.tooltip,
  });

  final IconData icon;
  final double size;
  final double iconSize;
  final Color color;
  final Color? iconColor;
  final String? tooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final button = Material(
      color: color,
      shape: const CircleBorder(),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onPressed,
        child: SizedBox.square(
          dimension: size,
          child: Icon(icon, size: iconSize, color: iconColor),
        ),
      ),
    );
    return tooltip == null ? button : Tooltip(message: tooltip, child: button);
  }
}

/// 搜索词胶囊。描边的是推荐词，实底的是最近搜索。
class _KeywordChip extends StatelessWidget {
  const _KeywordChip(
    this.text, {
    super.key,
    required this.onTap,
    this.outlined = false,
  });

  static const height = 34.0;
  static const padding = 14.0;
  static const style = TextStyle(fontSize: 13);

  final String text;
  final bool outlined;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: outlined ? Colors.transparent : scheme.surfaceContainer,
      shape: StadiumBorder(
        side: outlined
            ? BorderSide(color: scheme.surfaceContainerHighest)
            : BorderSide.none,
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: padding),
          child: SizedBox(
            height: height,
            child: Center(
              widthFactor: 1,
              child: Text(
                text,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: style.copyWith(color: scheme.onSurface),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 最近搜索：超过一行时只显示第一行，行尾一个展开按钮；展开后按钮挪到最后变成收起。
class _HistoryChips extends StatefulWidget {
  const _HistoryChips(this.history, {required this.onTap});

  final List<String> history;
  final ValueChanged<String> onTap;

  @override
  State<_HistoryChips> createState() => _HistoryChipsState();
}

class _HistoryChipsState extends State<_HistoryChips> {
  static const _spacing = 8.0;
  static const _toggleWidth = _KeywordChip.height;
  static const _duration = Duration(milliseconds: 260);

  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final scaler = MediaQuery.textScalerOf(context);
    final dir = Directionality.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxWidth = constraints.maxWidth;
        final widths = [
          for (final h in widget.history)
            ((TextPainter(
                      text: TextSpan(text: h, style: _KeywordChip.style),
                      textDirection: dir,
                      textScaler: scaler,
                      maxLines: 1,
                    )..layout()).width.ceilToDouble() +
                    _KeywordChip.padding * 2)
                .clamp(0.0, maxWidth),
        ];
        // 不带按钮时第一行放得下几个
        int fit(double reserve) {
          var x = 0.0;
          for (final (i, w) in widths.indexed) {
            final next = x == 0 ? w : x + _spacing + w;
            if (next > maxWidth - reserve) return i;
            x = next;
          }
          return widths.length;
        }

        final overflow = fit(0) < widths.length;
        // 收起时按钮放在第一行最后，后面的照样排在下面，只是被裁掉
        final firstRow = overflow ? fit(_toggleWidth + _spacing) : 0;
        final toggle = Tooltip(
          message: _expanded ? l.showLess : l.showMore,
          child: Material(
            color: scheme.surfaceContainer,
            shape: const CircleBorder(),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: () => setState(() => _expanded = !_expanded),
              child: SizedBox.square(
                dimension: _toggleWidth,
                child: AnimatedRotation(
                  turns: _expanded ? 0.5 : 0,
                  duration: _duration,
                  curve: Curves.easeOutCubic,
                  child: Icon(
                    Icons.keyboard_arrow_down_rounded,
                    size: 20,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
            ),
          ),
        );
        final chips = [
          for (final h in widget.history)
            _KeywordChip(h, key: ValueKey(h), onTap: () => widget.onTap(h)),
        ];
        // 收起时 Wrap 只给一行高，下面几行溢出不裁；外面按动画中的高度裁，收起才是慢慢盖住而不是一下消失
        return ClipRect(
          child: AnimatedSize(
            duration: _duration,
            curve: Curves.easeOutCubic,
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: overflow && !_expanded
                    ? _KeywordChip.height
                    : double.infinity,
              ),
              child: Wrap(
                spacing: _spacing,
                runSpacing: _spacing,
                children: [
                  if (!overflow)
                    ...chips
                  else if (_expanded) ...[
                    ...chips,
                    toggle,
                  ] else ...[
                    ...chips.take(firstRow),
                    toggle,
                    ...chips.skip(firstRow),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// 歌词结果：一张卡片里是歌曲行，下面是命中的歌词，搜的词加亮。
class _LyricTile extends StatelessWidget {
  const _LyricTile({
    required this.songs,
    required this.index,
    required this.snippet,
    required this.keyword,
  });

  final List<Song> songs;
  final int index;
  final String snippet;
  final String keyword;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      child: Material(
        color: scheme.surfaceContainer,
        borderRadius: BorderRadius.circular(18),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SongTile(songs: songs, index: index),
            if (snippet.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
                child: Text.rich(
                  _highlight(
                    snippet,
                    keyword,
                    TextStyle(color: scheme.onSurfaceVariant),
                    TextStyle(
                      color: scheme.onSurface,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 13, height: 1.5),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
