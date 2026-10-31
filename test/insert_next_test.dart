import 'package:flutter_test/flutter_test.dart';
import 'package:kanade/player/player_controller.dart';
import 'package:kanade/src/rust/api/types.dart';

Song _song(String mid) => Song(
  id: 0,
  mid: mid,
  name: mid,
  singers: const [],
  albumMid: '',
  albumName: '',
  durationSecs: 200,
  mediaMid: mid,
  coverUrl: '',
  vip: false,
  hasHq: false,
  hasFlac: false,
);

List<String> _mids(List<Song> q) => [for (final s in q) s.mid];

void main() {
  final queue = [_song('a'), _song('b'), _song('c'), _song('d')];

  test('新歌插在当前这首后面', () {
    final (q, i) = insertNext(queue, 1, _song('x'));
    expect(_mids(q), ['a', 'b', 'x', 'c', 'd']);
    expect(i, 1);
  });

  test('后点的先放', () {
    var (q, i) = insertNext(queue, 0, _song('x'));
    (q, i) = insertNext(q, i, _song('y'));
    expect(_mids(q), ['a', 'y', 'x', 'b', 'c', 'd']);
  });

  test('已在当前歌前面的歌挪过来，当前下标跟着前移', () {
    final (q, i) = insertNext(queue, 2, _song('a'));
    expect(_mids(q), ['b', 'c', 'a', 'd']);
    expect(i, 1);
    expect(q[i].mid, 'c');
  });

  test('已在当前歌后面的歌挪到紧跟着', () {
    final (q, i) = insertNext(queue, 0, _song('d'));
    expect(_mids(q), ['a', 'd', 'b', 'c']);
    expect(i, 0);
  });

  test('当前是最后一首时加在末尾', () {
    final (q, i) = insertNext(queue, 3, _song('x'));
    expect(_mids(q), ['a', 'b', 'c', 'd', 'x']);
    expect(i, 3);
  });
}
