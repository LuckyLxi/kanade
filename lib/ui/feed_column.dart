import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_rust_bridge/flutter_rust_bridge.dart' show Int64List;
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';
import 'package:provider/provider.dart';

import '../auth/auth_controller.dart';
import '../data/data_ext.dart';
import '../l10n/l10n_ext.dart';
import '../player/player_controller.dart';
import '../src/rust/api/music.dart' as api;
import '../src/rust/api/types.dart';
import 'keyed_route.dart';
import 'song_list_page.dart';
import 'toast.dart';
import 'widgets.dart';

/// 推荐页最下面的「昵称」的专属乐流：两列（窗口宽时更多列）瀑布流，滑到底自动加载下一页。
/// 只有登录后才有数据；换账号时重新从第一页开始。
class FeedColumn extends StatelessWidget {
  const FeedColumn({super.key});

  @override
  Widget build(BuildContext context) {
    final user = context.select<AuthController, UserInfo?>((a) => a.user);
    if (user == null) return const SliverToBoxAdapter(child: SizedBox.shrink());
    return _FeedColumn(key: ValueKey(user.uin), nickname: user.nickname);
  }
}

class _FeedColumn extends StatefulWidget {
  const _FeedColumn({super.key, required this.nickname});

  final String nickname;

  @override
  State<_FeedColumn> createState() => _FeedColumnState();
}

class _FeedColumnState extends State<_FeedColumn> {
  /// 卡片最窄这么宽，窗口宽时多排几列。
  static const _minCardWidth = 200.0;

  final _cards = <FeedCard>[];
  final _seen = <String>[];
  var _page = 0;
  var _hasMore = true;
  var _loading = false;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _loadMore();
  }

  Future<void> _loadMore() async {
    if (_loading || !_hasMore || _error != null) return;
    setState(() => _loading = true);
    try {
      final page = await api.getFeedColumn(page: _page + 1, seen: _seen);
      if (!mounted) return;
      setState(() {
        _page++;
        _seen.addAll(page.seen);
        _cards.addAll(page.cards);
        _hasMore = page.cards.isNotEmpty;
      });
    } catch (e) {
      if (mounted) setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _retry() {
    setState(() => _error = null);
    _loadMore();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    // 第一页没取到卡片就整块不显示，不留一个空标题
    if (_cards.isEmpty && !_loading && _error == null) {
      return const SliverToBoxAdapter(child: SizedBox.shrink());
    }
    return SliverMainAxisGroup(
      slivers: [
        SliverToBoxAdapter(
          child: SectionHeader(l.feedColumnTitle(widget.nickname)),
        ),
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          sliver: SliverLayoutBuilder(
            builder: (context, constraints) => SliverMasonryGrid.count(
              crossAxisCount: (constraints.crossAxisExtent / _minCardWidth)
                  .floor()
                  .clamp(2, 6),
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              childCount: _cards.length,
              itemBuilder: (context, i) {
                // 快滑到底时取下一页；不能在 build 里 setState，放到这一帧之后
                if (i >= _cards.length - 4) scheduleMicrotask(_loadMore);
                return _Card(_cards[i]);
              },
            ),
          ),
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Center(
              child: _error != null
                  ? TextButton(
                      onPressed: _retry,
                      child: Text(
                        l.loadFailed(errorText(l, _error!)),
                        textAlign: TextAlign.center,
                      ),
                    )
                  : _loading
                  ? const CircularProgressIndicator()
                  : const SizedBox.shrink(),
            ),
          ),
        ),
      ],
    );
  }
}

/// 从这首歌开始刷歌，和官方点卡片的行为一样；续取时播放器会跳过已经在队列里的歌。
Future<void> _radioFrom(BuildContext context, Song song) async {
  final l = AppLocalizations.of(context);
  final overlay = Overlay.of(context, rootOverlay: true);
  var page = 0;
  try {
    await context.read<PlayerController>().playRadio(
      () =>
          api.getRadarSongs(seed: Int64List.fromList([song.id]), page: ++page),
      first: [song],
    );
  } catch (e) {
    Toast.show(overlay, l.radioFailed(errorText(l, e)), kind: ToastKind.error);
  }
}

class _Card extends StatelessWidget {
  const _Card(this.card);

  final FeedCard card;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final muted = TextStyle(fontSize: 12, color: scheme.onSurfaceVariant);
    final title = text.bodyMedium?.copyWith(fontWeight: FontWeight.w600);
    final child = switch (card.kind) {
      FeedCardKind.song => _CoverCard(
        cover: card.songs.first.coverUrl,
        onTap: () => _radioFrom(context, card.songs.first),
        children: [
          Text(
            card.songs.first.name,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: title,
          ),
          const SizedBox(height: 2),
          Text(
            singerNames(card.songs.first),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: muted,
          ),
          if (card.tag.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              card.tag,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: muted,
            ),
          ],
        ],
      ),
      FeedCardKind.playlist => _CoverCard(
        cover: card.playlist!.coverUrl,
        onTap: () => openPage(
          context,
          SongListPage.playlist(card.playlist!.id, card.playlist!.title),
        ),
        children: [
          Text(
            card.playlist!.title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: title,
          ),
          if (card.playlist!.playCount > BigInt.zero) ...[
            const SizedBox(height: 2),
            Text(
              '▶ ${formatCount(AppLocalizations.of(context), card.playlist!.playCount.toInt())}',
              style: muted,
            ),
          ],
        ],
      ),
      FeedCardKind.group => Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              card.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: title,
            ),
            const SizedBox(height: 6),
            for (final song in card.songs)
              InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: () => _radioFrom(context, song),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Row(
                    children: [
                      Cover(song.coverUrl, size: 44),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              song.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: text.bodySmall?.copyWith(
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            Text(
                              singerNames(song),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: muted,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    };
    return Material(
      color: scheme.surfaceContainer,
      borderRadius: BorderRadius.circular(14),
      clipBehavior: Clip.antiAlias,
      child: child,
    );
  }
}

/// 上面方形大封面、下面几行字的卡片，整张可点。
class _CoverCard extends StatelessWidget {
  const _CoverCard({
    required this.cover,
    required this.onTap,
    required this.children,
  });

  final String cover;
  final VoidCallback onTap;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AspectRatio(aspectRatio: 1, child: Cover(cover, radius: 0)),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: children,
          ),
        ),
      ],
    ),
  );
}
