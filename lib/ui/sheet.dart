import 'package:flutter/material.dart';

/// 底部弹窗：一张浮起来的圆角卡片，左右和底部留空，背景压暗。
/// 电脑上窗口很宽，卡片最宽 480 居中。底色是实心的，不用毛玻璃，长列表也不掉帧。
/// 走根导航器：每个标签页有自己的 Navigator，不然只会盖住内容区、在页面中间弹出来。
Future<T?> showKanadeSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  double? heightFactor,
  EdgeInsets padding = const EdgeInsets.fromLTRB(10, 0, 10, 10),
}) {
  return showModalBottomSheet<T>(
    context: context,
    useRootNavigator: true,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    elevation: 0,
    barrierColor: Colors.black.withValues(alpha: 0.6),
    constraints: const BoxConstraints(maxWidth: 480),
    builder: (sheet) => _SheetFrame(
      heightFactor: heightFactor,
      padding: padding,
      child: builder(sheet),
    ),
  );
}

/// 卡片底色和里面分组的底色，亮色模式下是白卡片 + 浅灰分组。
(Color, Color) sheetColors(ColorScheme scheme) =>
    scheme.brightness == Brightness.dark
    ? (scheme.surfaceContainer, scheme.surfaceContainerHigh)
    : (scheme.surface, scheme.surfaceContainer);

class _SheetFrame extends StatelessWidget {
  const _SheetFrame({
    required this.child,
    required this.padding,
    this.heightFactor,
  });

  final Widget child;
  final EdgeInsets padding;

  /// 给定时卡片固定这么高（占可用高度的比例），否则跟着内容走，最高 85%。
  final double? heightFactor;

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final scheme = Theme.of(context).colorScheme;
    final (bg, _) = sheetColors(scheme);
    // 有输入框时键盘弹起，卡片要贴着键盘上沿
    final bottom = media.padding.bottom + media.viewInsets.bottom;
    final available = media.size.height - media.padding.top - bottom - 16;
    final content = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const _Handle(),
        if (heightFactor != null)
          Expanded(child: child)
        else
          Flexible(child: child),
      ],
    );
    return Padding(
      padding: EdgeInsets.fromLTRB(8, 0, 8, 8 + bottom),
      child: Material(
        color: bg,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
          side: BorderSide(color: scheme.outlineVariant, width: 0.5),
        ),
        child: Padding(
          padding: padding,
          child: heightFactor != null
              ? SizedBox(height: available * heightFactor!, child: content)
              : ConstrainedBox(
                  constraints: BoxConstraints(maxHeight: available * 0.85),
                  child: content,
                ),
        ),
      ),
    );
  }
}

class _Handle extends StatelessWidget {
  const _Handle();

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 8, bottom: 12),
    child: Container(
      width: 32,
      height: 4,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.outline,
        borderRadius: BorderRadius.circular(2),
      ),
    ),
  );
}

/// 弹窗顶部：封面 + 标题 + 副标题，没有封面时只有一行标题。
class SheetHeader extends StatelessWidget {
  const SheetHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.leading,
  });

  final String title;
  final String? subtitle;
  final Widget? leading;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(6, 0, 6, 12),
      child: Row(
        children: [
          if (leading != null) ...[leading!, const SizedBox(width: 12)],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: scheme.onSurface,
                  ),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    subtitle!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 一排大方块，放最常用的几个操作。
class SheetQuickActions extends StatelessWidget {
  const SheetQuickActions({super.key, required this.children});

  final List<SheetQuickAction> children;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Row(
      children: [
        for (var i = 0; i < children.length; i++) ...[
          if (i > 0) const SizedBox(width: 8),
          Expanded(child: children[i]),
        ],
      ],
    ),
  );
}

class SheetQuickAction extends StatelessWidget {
  const SheetQuickAction({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
    this.iconColor,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color? iconColor;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (_, group) = sheetColors(scheme);
    return Material(
      color: group,
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 4),
          child: Column(
            children: [
              Icon(icon, size: 24, color: iconColor ?? scheme.onSurface),
              const SizedBox(height: 6),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: scheme.onSurface,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 圆角分组，行与行之间一条细线。给了 [controller] 就能在里面滚动（外面要包 Flexible）。
class SheetGroup extends StatelessWidget {
  const SheetGroup({super.key, required this.children, this.controller});

  final List<Widget> children;
  final ScrollController? controller;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (_, group) = sheetColors(scheme);
    return Material(
      color: group,
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: ListView.separated(
        controller: controller,
        shrinkWrap: true,
        padding: EdgeInsets.zero,
        physics: controller == null
            ? const NeverScrollableScrollPhysics()
            : null,
        itemCount: children.length,
        itemBuilder: (_, i) => children[i],
        separatorBuilder: (_, _) => Divider(
          height: 0.5,
          thickness: 0.5,
          indent: 14,
          color: scheme.outlineVariant,
        ),
      ),
    );
  }
}

/// 分组里的一行。[chevron] 表示点了会跳到别的页面；[destructive] 整行标红。
class SheetRow extends StatelessWidget {
  const SheetRow({
    super.key,
    required this.title,
    this.subtitle,
    this.leading,
    this.onTap,
    this.trailing,
    this.chevron = false,
    this.destructive = false,
  });

  final String title;
  final String? subtitle;
  final Widget? leading;
  final VoidCallback? onTap;

  /// 行尾的控件，比如开关。
  final Widget? trailing;
  final bool chevron;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = destructive ? scheme.error : scheme.onSurface;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            if (leading != null) ...[
              IconTheme.merge(
                data: IconThemeData(
                  size: 22,
                  color: destructive ? scheme.error : scheme.onSurfaceVariant,
                ),
                child: leading!,
              ),
              const SizedBox(width: 14),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: color,
                    ),
                  ),
                  if (subtitle != null)
                    Text(
                      subtitle!,
                      style: TextStyle(
                        fontSize: 12,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                ],
              ),
            ),
            ?trailing,
            if (chevron)
              Icon(
                Icons.chevron_right_rounded,
                size: 20,
                color: scheme.outline,
              ),
          ],
        ),
      ),
    );
  }
}
