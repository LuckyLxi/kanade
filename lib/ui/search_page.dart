import 'dart:async';

import 'package:flutter/material.dart';

import '../l10n/l10n_ext.dart';
import '../src/rust/api/music.dart' as api;
import '../src/rust/api/types.dart';
import 'widgets.dart';

class SearchPage extends StatefulWidget {
  const SearchPage({super.key});

  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  static const _pageSize = 30;

  final _controller = TextEditingController();
  final _scroll = ScrollController();
  String _keyword = '';
  List<Song> _songs = [];
  int _page = 0;
  int _total = 0;
  bool _loading = false;
  Object? _error;

  HotSearch? _hot;
  Object? _hotError;

  /// 正在输入（还没回车）时显示联想，而不是上一次的搜索结果。
  bool _typing = false;
  List<SearchSuggestion> _suggestions = [];
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(() {
      if (_scroll.position.extentAfter < 400) _loadMore();
    });
    _loadHot();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    _scroll.dispose();
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
        if (mounted && _typing && _controller.text.trim() == query) setState(() => _suggestions = list);
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
      _songs = [];
      _error = null;
    });
  }

  /// 点联想或热搜词：填进输入框并直接搜索。
  void _searchFor(String keyword) {
    _controller.text = keyword;
    _search(keyword);
  }

  Future<void> _search(String keyword) async {
    keyword = keyword.trim();
    if (keyword.isEmpty) return;
    _debounce?.cancel();
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      _typing = false;
      _keyword = keyword;
      _songs = [];
      _page = 0;
      _total = 0;
      _error = null;
    });
    await _loadMore();
  }

  Future<void> _loadMore() async {
    if (_loading || _keyword.isEmpty || (_page > 0 && _songs.length >= _total)) return;
    final keyword = _keyword;
    setState(() => _loading = true);
    try {
      final r = await api.searchSongs(keyword: keyword, page: _page + 1, pageSize: _pageSize);
      if (keyword != _keyword) return;
      setState(() {
        _page++;
        _total = r.songs.isEmpty ? _songs.length : r.total;
        _songs = [..._songs, ...r.songs];
      });
    } catch (e) {
      setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(
        title: SearchBar(
          controller: _controller,
          hintText: l.searchHint,
          leading: const Icon(Icons.search),
          elevation: const WidgetStatePropertyAll(0),
          onSubmitted: _search,
          trailing: [
            if (_controller.text.isNotEmpty) IconButton(icon: const Icon(Icons.clear), onPressed: _clear),
          ],
          onChanged: _onChanged,
        ),
      ),
      body: _body(l),
    );
  }

  Widget _body(AppLocalizations l) {
    if (_typing && _controller.text.trim().isNotEmpty) {
      return _suggestionList();
    }
    if (_keyword.isEmpty) {
      return _hotView(l);
    }
    if (_error != null && _songs.isEmpty) {
      return Center(child: Text(l.searchFailed(errorText(l, _error!))));
    }
    if (_songs.isEmpty) {
      return Center(child: _loading ? const CircularProgressIndicator() : Text(l.searchNoResults));
    }
    return ListView.builder(
      controller: _scroll,
      itemCount: _songs.length + 1,
      itemBuilder: (_, i) {
        if (i == _songs.length) {
          return Padding(
            padding: const EdgeInsets.all(16),
            child: Center(
              child: _loading ? const CircularProgressIndicator() : Text(l.searchTotal(_total)),
            ),
          );
        }
        return SongTile(songs: _songs, index: i);
      },
    );
  }

  Widget _suggestionList() {
    return ListView(
      children: [
        for (final s in _suggestions)
          ListTile(
            leading: Icon(switch (s.kind) {
              SuggestionKind.song => Icons.music_note_outlined,
              SuggestionKind.singer => Icons.person_outline,
              SuggestionKind.album => Icons.album_outlined,
            }),
            title: Text(s.title, maxLines: 1, overflow: TextOverflow.ellipsis),
            subtitle: s.subtitle.isEmpty ? null : Text(s.subtitle, maxLines: 1, overflow: TextOverflow.ellipsis),
            // 歌曲/专辑带上歌手名一起搜，结果更准
            onTap: () => _searchFor(s.subtitle.isEmpty ? s.title : '${s.title} ${s.subtitle}'),
          ),
      ],
    );
  }

  Widget _hotView(AppLocalizations l) {
    final hot = _hot;
    if (hot == null) {
      // 热搜加载失败时退回原来的提示，不影响搜索
      return Center(child: _hotError != null ? Text(l.searchPrompt) : const CircularProgressIndicator());
    }
    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.only(bottom: 16),
      children: [
        if (hot.recommended.isNotEmpty) ...[
          _sectionTitle(l.searchRecommended),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final k in hot.recommended.take(12))
                  ActionChip(label: Text(k.title), onPressed: () => _searchFor(k.query)),
              ],
            ),
          ),
        ],
        if (hot.hot.isNotEmpty) _sectionTitle(l.searchHot),
        for (final (i, k) in hot.hot.indexed)
          ListTile(
            dense: true,
            leading: SizedBox(
              width: 28,
              child: Text(
                '${i + 1}',
                textAlign: TextAlign.center,
                style: theme.textTheme.titleMedium?.copyWith(
                  color: i < 3 ? theme.colorScheme.primary : theme.colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            title: Text(k.title, maxLines: 1, overflow: TextOverflow.ellipsis),
            trailing: k.description.isEmpty
                ? null
                : Text(k.description, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
            onTap: () => _searchFor(k.query),
          ),
      ],
    );
  }

  Widget _sectionTitle(String text) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
        child: Text(text, style: Theme.of(context).textTheme.titleMedium),
      );
}
