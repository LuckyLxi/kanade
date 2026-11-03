import 'dart:async';

import 'package:flutter/foundation.dart';

import '../src/rust/api/music.dart' as api;
import '../src/rust/api/types.dart';

enum QrLoginState {
  loading,
  loadFailed,
  waiting,
  scanned,
  expired,
  refused,
  failed,
}

/// 一次弹窗内的二维码登录会话，不持有页面或平台资源。
class QrLoginController extends ChangeNotifier {
  QrLoginController(this.kind, {required this.onSuccess});

  final LoginKind kind;
  final void Function(UserInfo) onSuccess;
  QrCode? qr;
  QrLoginState state = QrLoginState.loading;
  Object? error;
  bool get expired => switch (state) {
    QrLoginState.expired || QrLoginState.refused || QrLoginState.failed => true,
    _ => false,
  };

  Timer? _timer;
  bool _polling = false;
  bool _disposed = false;
  int _generation = 0;

  bool _stale(int generation) => _disposed || generation != _generation;

  Future<void> refresh() async {
    final generation = ++_generation;
    _timer?.cancel();
    qr = null;
    state = QrLoginState.loading;
    notifyListeners();
    try {
      final code = await api.createLoginQr(kind: kind);
      if (_stale(generation)) return;
      qr = code;
      state = QrLoginState.waiting;
      notifyListeners();
      _timer = Timer.periodic(const Duration(seconds: 2), (_) => _poll());
    } catch (e) {
      if (_stale(generation)) return;
      state = QrLoginState.loadFailed;
      error = e;
      notifyListeners();
    }
  }

  Future<void> _poll() async {
    final code = qr;
    if (code == null || _polling) return;
    final generation = _generation;
    _polling = true;
    UserInfo? authenticated;
    try {
      final status = await api.pollLoginQr(kind: kind, qrsig: code.qrsig);
      if (_stale(generation)) return;
      switch (status) {
        case QrStatus_Waiting():
          return;
        case QrStatus_Scanned():
          state = QrLoginState.scanned;
        case QrStatus_Expired():
          state = QrLoginState.expired;
        case QrStatus_Refused():
          state = QrLoginState.refused;
        case QrStatus_Success(:final user):
          _timer?.cancel();
          ++_generation;
          authenticated = user;
      }
      if (authenticated == null) {
        if (expired) _timer?.cancel();
        notifyListeners();
      }
    } catch (e) {
      if (_stale(generation)) return;
      _timer?.cancel();
      state = QrLoginState.failed;
      error = e;
      notifyListeners();
    } finally {
      _polling = false;
    }
    if (authenticated != null) onSuccess(authenticated);
  }

  /// 保留展示图片，后续轮询改用手机 QQ 的跳转票据。
  Future<QrCode?> prepareQqAppLogin() async {
    final old = qr;
    if (old == null) return null;
    final generation = ++_generation;
    final ticket = await api.createQqAppLogin();
    if (_stale(generation)) return null;
    // 申请票据期间发起的旧二维码轮询也不能再更新状态。
    ++_generation;
    qr = QrCode(image: old.image, qrsig: ticket.qrsig, url: ticket.url);
    notifyListeners();
    return ticket;
  }

  @override
  void dispose() {
    _disposed = true;
    ++_generation;
    _timer?.cancel();
    super.dispose();
  }
}
