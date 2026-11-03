import 'package:flutter/widgets.dart';

/// 外壳发布的浮层布局信息，供提示读取。
class OverlayLayoutState {
  static final instance = OverlayLayoutState();

  final chrome = ValueNotifier(EdgeInsets.zero);
  final playerVisible = ValueNotifier(false);
}
