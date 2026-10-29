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
class _RadioRow extends StatelessWidget {
  const _RadioRow(this.feed);

  final RecommendFeed feed;

  Future<void> _start(BuildContext context, Future<List<Song>> Function() fetch) async {
    final l = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await context.read<PlayerController>().playRadio(fetch);
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(l.radioFailed(errorText(l, e)))));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final loggedIn = context.watch<AuthController>().loggedIn;
    if (!loggedIn && feed.radarSeed.isEmpty) return const SliverToBoxAdapter();
    var page = 0;
    final scheme = Theme.of(context).colorScheme;
    // 深灰实心胶囊，抗色只给图标
    final style = FilledButton.styleFrom(
      backgroundColor: scheme.surfaceContainerHigh,
      foregroundColor: scheme.onSurface,
      iconColor: scheme.primary,
      textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
    );
    return SliverPadding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      sliver: SliverToBoxAdapter(
        child: Wrap(
          spacing: 10,
          runSpacing: 8,
          children: [
            if (loggedIn)
              FilledButton.icon(
                style: style,
                icon: const Icon(Icons.favorite_outline),
                label: Text(l.radioGuessYouLike),
                onPressed: () => _start(context, api.getGuessYouLike),
              ),
            if (feed.radarSeed.isNotEmpty)
              FilledButton.icon(
                style: style,
                icon: const Icon(Icons.radar),
                label: Text(l.radioRadar),
                // 每次点击从第 1 批开始，之后续取依次往后翻
                onPressed: () {
                  page = 0;
                  _start(context, () => api.getRadarSongs(seed: feed.radarSeed, page: ++page));
                },
              ),
          ],
        ),
      ),
    );
  }
}
