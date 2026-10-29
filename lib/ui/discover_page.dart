import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../auth/auth_controller.dart';
import '../l10n/l10n_ext.dart';
import '../player/player_controller.dart';
import '../src/rust/api/music.dart' as api;
import '../src/rust/api/types.dart';
import 'song_list_page.dart';
import 'widgets.dart';

class DiscoverPage extends StatelessWidget {
  const DiscoverPage({super.key});

  /// 每个歌曲区块在首页只露出几首，其余点“查看全部”。
  static const _previewSongs = 6;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    // 不要大标题：底部导航已经说明了在哪一页
    return Scaffold(
      body: AsyncView<(RecommendFeed, List<Song>, List<TopListGroup>)>(
        load: () async {
          // 三个请求并行发出
          final feed = api.getRecommendFeed();
          final newSongs = api.getNewSongs();
          final toplists = api.getToplists();
          return (await feed, await newSongs, await toplists);
        },
        builder: (context, data) {
          final (feed, newSongs, groups) = data;
          return CustomScrollView(
            slivers: [
              SliverToBoxAdapter(child: SizedBox(height: MediaQuery.paddingOf(context).top + 4)),
              _RadioRow(feed),
              for (final section in feed.sections) ...[
                if (section.playlists.isNotEmpty) ...[
                  _Header(section.title.isEmpty ? l.recommendedPlaylists : section.title),
                  _PlaylistRow(section.playlists),
                ],
                if (section.songs.isNotEmpty)
                  ..._songSection(context, section.title.isEmpty ? l.recommendedSongs : section.title, section.songs),
              ],
              if (newSongs.isNotEmpty) ..._songSection(context, l.newSongs, newSongs),
              for (final g in groups) ...[
                _Header(g.name),
                SliverList.builder(itemCount: g.lists.length, itemBuilder: (_, i) => _TopListTile(g.lists[i])),
              ],
              const SliverToBoxAdapter(child: BottomSpacer()),
            ],
          );
        },
      ),
    );
  }

  List<Widget> _songSection(BuildContext context, String title, List<Song> songs) {
    final l = AppLocalizations.of(context);
    final shown = songs.length > _previewSongs ? _previewSongs : songs.length;
    void viewAll() => Navigator.of(context).push(SongListPage.songs(title, songs));
    return [
      _Header(title, onMore: songs.length > shown ? viewAll : null),
      // 点某一首时把整个区块作为播放列表
      SliverList.builder(
        itemCount: shown,
        itemBuilder: (_, i) => SongTile(songs: songs, index: i),
      ),
      if (songs.length > shown)
        SliverToBoxAdapter(
          child: Align(
            alignment: Alignment.centerLeft,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: TextButton(onPressed: viewAll, child: Text(l.viewAllSongs(songs.length))),
            ),
          ),
        ),
    ];
  }
}

/// 横向滚动的一排歌单卡片（含“每日30首”等入口）。
class _PlaylistRow extends StatelessWidget {
  const _PlaylistRow(this.playlists);

  final List<PlaylistBrief> playlists;

  @override
  Widget build(BuildContext context) => SliverToBoxAdapter(
    child: SizedBox(
      height: 186,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: playlists.length,
        separatorBuilder: (_, _) => const SizedBox(width: 12),
        itemBuilder: (context, i) {
          final p = playlists[i];
          return SizedBox(
            width: 124,
            child: PlaylistCard(
              title: p.title,
              coverUrl: p.coverUrl,
              badge: p.playCount > BigInt.zero
                  ? '▶ ${formatCount(AppLocalizations.of(context), p.playCount.toInt())}'
                  : null,
              onTap: () => Navigator.of(context).push(SongListPage.playlist(p.id, p.title)),
            ),
          );
        },
      ),
    ),
  );
}

class _Header extends StatelessWidget {
  const _Header(this.text, {this.onMore});

  final String text;
  final VoidCallback? onMore;

  @override
  Widget build(BuildContext context) => SliverToBoxAdapter(child: SectionHeader(text, onMore: onMore));
}

class _TopListTile extends StatelessWidget {
  const _TopListTile(this.t);

  final TopList t;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      leading: Cover(t.coverUrl, size: 64, radius: 12),
      title: Text(t.title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final (i, s) in t.preview.indexed) Text('${i + 1}. $s', maxLines: 1, overflow: TextOverflow.ellipsis),
        ],
      ),
      onTap: () => Navigator.of(context).push(SongListPage.toplist(t.topId, t.period, t.title)),
    );
  }
}

/// 猜你喜欢（需要登录）和刷歌模式（需要推荐页给出起始歌曲）两个电台入口。
/// 猜你喜欢先预取一批，用第一首的专辑图当封面，点开就从这批放起；刷歌用入口卡给的封面。
class _RadioRow extends StatefulWidget {
  const _RadioRow(this.feed);

  final RecommendFeed feed;

  @override
  State<_RadioRow> createState() => _RadioRowState();
}

class _RadioRowState extends State<_RadioRow> {
  /// 预取的猜你喜欢下一批；没登录或已经用掉时为 null。
  Future<List<Song>>? _guess;
  List<Song> _guessShown = const [];

  void _prefetchGuess() {
    final f = api.getGuessYouLike();
    _guess = f;
    f.then((songs) {
      if (mounted && _guess == f) setState(() => _guessShown = songs);
    }, onError: (_) {
      // 预取失败只是没有封面，点击时会再取
    });
  }

  Future<void> _start(Future<List<Song>> Function() fetch, {Future<List<Song>>? first}) async {
    final l = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final player = context.read<PlayerController>();
    try {
      final batch = await first?.then<List<Song>?>((s) => s.isEmpty ? null : s, onError: (_) => null);
      await player.playRadio(fetch, first: batch);
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(l.radioFailed(errorText(l, e)))));
    }
  }

  void _startGuess() {
    final first = _guess;
    // 这批交给播放器了，封面换成下一批
    _guessShown = const [];
    _prefetchGuess();
    _start(api.getGuessYouLike, first: first);
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final feed = widget.feed;
    final loggedIn = context.watch<AuthController>().loggedIn;
    if (loggedIn && _guess == null) _prefetchGuess();
    if (!loggedIn && _guess != null) {
      _guess = null;
      _guessShown = const [];
    }
    if (!loggedIn && feed.radarSeed.isEmpty) return const SliverToBoxAdapter();
    var page = 0;
    final next = _guessShown.firstOrNull;
    return SliverPadding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      sliver: SliverToBoxAdapter(
        child: Align(
          alignment: Alignment.centerLeft,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Row(
              children: [
                if (loggedIn)
                  Expanded(
                    child: _RadioCard(
                      icon: Icons.favorite,
                      title: l.radioGuessYouLike,
                      subtitle: next?.name,
                      coverUrl: next?.coverUrl ?? '',
                      onTap: _startGuess,
                    ),
                  ),
                if (loggedIn && feed.radarSeed.isNotEmpty) const SizedBox(width: 10),
                if (feed.radarSeed.isNotEmpty)
                  Expanded(
                    child: _RadioCard(
                      icon: Icons.radar,
                      title: l.radioRadar,
                      coverUrl: feed.radarCover,
                      // 每次点击从第 1 批开始，之后续取依次往后翻
                      onTap: () {
                        page = 0;
                        _start(() => api.getRadarSongs(seed: feed.radarSeed, page: ++page));
                      },
                    ),
                  ),
                // 只有一张时也保持半宽
                if (!loggedIn || feed.radarSeed.isEmpty) ...[const SizedBox(width: 10), const Spacer()],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 电台入口：左边专辑封面（右下角压一个抗色图标），右边标题和接下来那首歌。
class _RadioCard extends StatelessWidget {
  const _RadioCard({required this.icon, required this.title, this.subtitle, required this.coverUrl, required this.onTap});

  final IconData icon;
  final String title;
  final String? subtitle;
  final String coverUrl;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surfaceContainerHigh,
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Row(
            children: [
              SizedBox.square(
                dimension: 56,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Cover(coverUrl, size: 56, radius: 12),
                    Positioned(
                      right: -4,
                      bottom: -4,
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color: scheme.primary,
                          shape: BoxShape.circle,
                          border: Border.all(color: scheme.surfaceContainerHigh, width: 2),
                        ),
                        child: Icon(icon, size: 13, color: scheme.onPrimary),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        subtitle!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
