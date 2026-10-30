import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../data/data_ext.dart';
import '../l10n/l10n_ext.dart';
import '../src/rust/api/music.dart' as api;
import '../src/rust/api/types.dart';
import 'smooth_scroll.dart';

typedef CommentLoader = Future<CommentPage> Function(int page, String lastSeqNo);

/// 评论列表：第一页先列热门评论，再列最新评论，滚到底继续加载。
class CommentsPage extends StatelessWidget {
  const CommentsPage({super.key, required this.title, required this.load});

  final String title;
  final CommentLoader load;

  static Route<void> song(Song s) => MaterialPageRoute(
        builder: (_) => CommentsPage(
          title: s.name,
          load: (page, last) => api.getComments(target: CommentTarget.song, id: s.id, page: page, lastSeqNo: last),
        ),
      );

  static Route<void> album(AlbumDetail a) => MaterialPageRoute(
        builder: (_) => CommentsPage(
          title: a.name,
          load: (page, last) => api.getComments(target: CommentTarget.album, id: a.id, page: page, lastSeqNo: last),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text('${l.comments} · $title', overflow: TextOverflow.ellipsis)),
      body: _CommentList(load: load, showHot: true),
    );
  }
}

class _CommentList extends StatefulWidget {
  const _CommentList({required this.load, this.showHot = false, this.controller});

  final CommentLoader load;
  final bool showHot;
  final ScrollController? controller;

  @override
  State<_CommentList> createState() => _CommentListState();
}

class _CommentListState extends State<_CommentList> {
  final List<Comment> _hot = [];
  final List<Comment> _latest = [];
  int _page = 0;
  int _total = 0;
  bool _hasMore = true;
  bool _loading = false;
  Object? _error;

  /// 回复面板会传进它自己的 controller（拖动面板用），否则用自己的。
  final _scroll = SmoothScrollController();

  @override
  void initState() {
    super.initState();
    _more();
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _more() async {
    if (_loading || !_hasMore) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final p = await widget.load(_page, _latest.isEmpty ? '' : _latest.last.seqNo);
      if (!mounted) return;
      setState(() {
        if (_page == 0) {
          _hot.addAll(p.hot);
          _total = p.total;
        }
        // 防止翻页游标不准时出现重复
        final seen = _latest.map((c) => c.id).toSet();
        final fresh = p.latest.where((c) => seen.add(c.id)).toList();
        _latest.addAll(fresh);
        _page++;
        _hasMore = p.hasMore && fresh.isNotEmpty;
      });
    } catch (e) {
      if (mounted) setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final rows = <Widget>[
      if (widget.showHot && _hot.isNotEmpty) ...[
        _Section(l.hotComments),
        for (final c in _hot) CommentTile(c),
      ],
      if (_latest.isNotEmpty) ...[
        if (widget.showHot) _Section('${l.latestComments} · ${l.commentTotal(_total)}'),
        for (final c in _latest) CommentTile(c),
      ],
    ];
    Widget footer;
    if (_error != null) {
      footer = Center(
        child: TextButton(onPressed: _more, child: Text(l.loadFailed(errorText(l, _error!)), textAlign: TextAlign.center)),
      );
    } else if (_loading) {
      footer = const Padding(padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator()));
    } else if (rows.isEmpty) {
      footer = Padding(padding: const EdgeInsets.all(32), child: Center(child: Text(l.noComments, style: text.bodyMedium)));
    } else {
      footer = const SizedBox(height: 24);
    }
    return NotificationListener<ScrollNotification>(
      onNotification: (n) {
        if (n.metrics.extentAfter < 400 && _error == null) _more();
        return false;
      },
      child: ListView(controller: widget.controller ?? _scroll, children: [...rows, footer]),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section(this.title);

  final String title;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
        child: Text(title, style: Theme.of(context).textTheme.titleSmall),
      );
}

class CommentTile extends StatelessWidget {
  const CommentTile(this.c, {super.key});

  final Comment c;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final time = DateFormat.yMd(l.localeName).add_Hm().format(DateTime.fromMillisecondsSinceEpoch(c.timeSecs.toInt() * 1000));
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 18,
            backgroundImage: c.avatarUrl.isEmpty ? null : NetworkImage(httpsUrl(c.avatarUrl)),
            child: c.avatarUrl.isEmpty ? const Icon(Icons.person, size: 18) : null,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(c.nick, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13)),
                    ),
                    if (c.praiseCount > 0) ...[
                      Icon(Icons.thumb_up_alt_outlined, size: 14, color: scheme.onSurfaceVariant),
                      const SizedBox(width: 4),
                      Text(formatCount(l, c.praiseCount), style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
                    ],
                  ],
                ),
                const SizedBox(height: 4),
                Text.rich(TextSpan(children: [
                  if (c.replyTo.isNotEmpty) TextSpan(text: l.replyTo(c.replyTo), style: TextStyle(color: scheme.primary)),
                  TextSpan(text: c.content),
                ])),
                const SizedBox(height: 4),
                Text(time, style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant)),
                if (c.replyCount > 0)
                  TextButton(
                    style: TextButton.styleFrom(padding: EdgeInsets.zero, visualDensity: VisualDensity.compact),
                    onPressed: () => _showReplies(context, c),
                    child: Text(l.viewReplies(c.replyCount)),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

void _showReplies(BuildContext context, Comment root) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (_) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.7,
      maxChildSize: 0.95,
      builder: (context, controller) => Column(
        children: [
          CommentTile(Comment(
            id: root.id,
            seqNo: root.seqNo,
            nick: root.nick,
            avatarUrl: root.avatarUrl,
            content: root.content,
            timeSecs: root.timeSecs,
            praiseCount: root.praiseCount,
            // 面板顶部的原评论不再显示“查看回复”
            replyCount: 0,
            replyTo: root.replyTo,
          )),
          const Divider(height: 1),
          Expanded(
            child: _CommentList(
              controller: controller,
              load: (page, last) => api.getCommentReplies(rootId: root.id, page: page, lastSeqNo: last),
            ),
          ),
        ],
      ),
    ),
  );
}
