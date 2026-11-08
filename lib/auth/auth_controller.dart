import 'package:flutter/foundation.dart';

import '../src/rust/api/music.dart' as api;
import '../src/rust/api/types.dart';

/// 登录状态。登录态本身由 Rust 层持久化在 SQLite 里。
class AuthController extends ChangeNotifier {
  AuthController() : user = api.currentUser();

  UserInfo? user;

  bool get loggedIn => user != null;

  void reloadSession() {
    user = api.currentUser();
    notifyListeners();
  }

  void onLoggedIn(UserInfo u) {
    user = u;
    api.clearCache();
    notifyListeners();
  }

  Future<UserInfo> loginWithCookie(String cookie) async {
    final u = await api.loginWithCookie(cookie: cookie);
    onLoggedIn(u);
    return u;
  }

  Future<void> logout() async {
    await api.logout();
    await api.clearCache();
    user = null;
    notifyListeners();
  }
}
