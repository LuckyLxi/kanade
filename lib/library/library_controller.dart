import 'dart:async';

import 'package:flutter/foundation.dart';

import '../auth/auth_controller.dart';
import '../src/rust/api/music.dart' as api;
import '../src/rust/api/types.dart';

/// 红心状态和自己的歌单。写操作只在用户点击后发出。
class LibraryController extends ChangeNotifier {
  LibraryController(this._auth) {
    _auth.addListener(_onAuthChanged);
    _onAuthChanged();
  }

  final AuthController _auth;
  Set<int> _liked = {};

  /// 正在提交的歌曲，防止连点。
  final Set<int> _pending = {};

  bool isLiked(Song s) => _liked.contains(s.id.toInt());

  bool isPending(Song s) => _pending.contains(s.id.toInt());

  void _onAuthChanged() {
    _liked = {};
    notifyListeners();
    if (_auth.loggedIn) unawaited(refreshLiked());
  }

  Future<void> refreshLiked() async {
    try {
      final ids = await api.getLikedSongIds();
      _liked = ids.map((e) => e.toInt()).toSet();
      notifyListeners();
    } catch (_) {
      // 拿不到红心列表只影响图标显示，点击时会照常提交
    }
  }

  /// 切换红心，返回新状态；失败时抛出 ApiError，状态保持不变。
  Future<bool> toggleLike(Song s) async {
    final id = s.id.toInt();
    if (_pending.contains(id)) return isLiked(s);
    final liked = !_liked.contains(id);
    _pending.add(id);
    notifyListeners();
    try {
      await api.setSongLiked(songId: s.id, liked: liked);
      liked ? _liked.add(id) : _liked.remove(id);
      return liked;
    } finally {
      _pending.remove(id);
      notifyListeners();
    }
  }

  Future<List<MyPlaylist>> myPlaylists() => api.getMyPlaylists();

  Future<void> addToPlaylist(MyPlaylist p, Song s) async {
    await api.addSongToPlaylist(dirId: p.dirId, songId: s.id);
    if (p.dirId == 201) _liked.add(s.id.toInt());
    notifyListeners();
  }

  Future<void> removeFromPlaylist(MyPlaylist p, Song s) async {
    await api.removeSongFromPlaylist(dirId: p.dirId, songId: s.id);
    if (p.dirId == 201) _liked.remove(s.id.toInt());
    notifyListeners();
  }

  /// 歌单 id（tid）属于自己时返回对应歌单，用来决定能不能删歌；没登录或不是自己的返回 null。
  Future<MyPlaylist?> ownPlaylist(String id) async {
    if (!_auth.loggedIn) return null;
    try {
      return (await api.getMyPlaylists()).where((p) => p.tid.toString() == id).firstOrNull;
    } catch (_) {
      return null;
    }
  }

  @override
  void dispose() {
    _auth.removeListener(_onAuthChanged);
    super.dispose();
  }
}
