import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:provider/provider.dart';

import '../data/data_ext.dart';
import '../l10n/l10n_ext.dart';
import '../player/player_controller.dart';
import '../src/rust/api/music.dart' as api;
import '../src/rust/api/types.dart';
import 'keyed_route.dart';
import 'singer_page.dart';
import 'widgets.dart';

/// MV 播放页：上面是 16:9 播放器（自带进度条和全屏），下面是清晰度和资料。
/// 打开时暂停正在放的歌，离开时不自动恢复。
class MvPage extends StatelessWidget {
  const MvPage({super.key, required this.vid, required this.title});

  final String vid;
  final String title;

  static Route<void> route(String vid, String title) => MaterialPageRoute(builder: (_) => MvPage(vid: vid, title: title));

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis)),
      body: AsyncView<MvDetail>(
        load: () => api.getMvDetail(vid: vid),
        builder: (context, d) => _Body(d),
      ),
    );
  }
}

class _Body extends StatefulWidget {
  const _Body(this.d);

  final MvDetail d;

  @override
  State<_Body> createState() => _BodyState();
}

class _BodyState extends State<_Body> {
  /// 默认 720P：比 1080P 省流量，手机和窗口里都够清楚。
  static const _defaultHeight = 720;

  final _player = Player(configuration: const PlayerConfiguration(title: 'Kanade MV'));
  late final _controller = VideoController(_player);
  MvStream? _stream;

  @override
  void initState() {
    super.initState();
    final streams = widget.d.streams;
    if (streams.isEmpty) return;
    context.read<PlayerController>().pause();
    _play(streams.lastWhere((s) => s.height <= _defaultHeight, orElse: () => streams.first), Duration.zero);
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  void _play(MvStream stream, Duration start) {
    setState(() => _stream = stream);
    _player.open(Media(stream.url, start: start));
  }

  /// 换清晰度时从当前位置接着放。
  void _switch(MvStream stream) {
    if (stream == _stream) return;
    _play(stream, _player.state.position);
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final d = widget.d;
    return ListView(
      children: [
        AspectRatio(
          aspectRatio: 16 / 9,
          child: _stream == null
              ? Stack(
                  fit: StackFit.expand,
                  children: [
                    Cover(d.coverUrl, radius: 0),
                    ColoredBox(
                      color: Colors.black54,
                      child: Center(child: Text(l.mvUnavailable, style: const TextStyle(color: Colors.white))),
                    ),
                  ],
                )
              : Video(controller: _controller),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
          child: Text(d.name, style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800)),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
          child: Text(
            [
              if (d.uploader.isNotEmpty) d.uploader,
              if (d.playCount > BigInt.zero) '▶ ${formatCount(l, d.playCount.toInt())}',
              if (d.publishDate.isNotEmpty) d.publishDate,
            ].join(' · '),
            style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
          ),
        ),
        if (d.streams.length > 1)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final s in d.streams)
                  Pill(label: '${s.height}P', selected: s == _stream, onTap: () => _switch(s)),
              ],
            ),
          ),
        if (d.singers.isNotEmpty) ...[
          const SizedBox(height: 8),
          for (final s in d.singers)
            ListTile(
              leading: ClipOval(child: Cover(singerAvatar(s.mid), size: 40, radius: 0)),
              title: Text(s.name),
              trailing: const Icon(Icons.chevron_right),
              onTap: s.mid.isEmpty ? null : () => openPage(context, SingerPage.route(s.mid, s.name)),
            ),
        ],
        if (d.description.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Text(d.description, style: TextStyle(fontSize: 13, height: 1.6, color: scheme.onSurfaceVariant)),
          ),
        const BottomSpacer(),
      ],
    );
  }
}
