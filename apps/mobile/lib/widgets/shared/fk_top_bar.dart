import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../theme/app_theme.dart';
import 'fk_icon_button.dart';

/// 设计稿 `ui.jsx::FKTopBar` — 大标题 + 可选副标题 + back / actions。
///
/// 顶部 padding 内置 18px(与 status bar 之间 SafeArea 由调用方负责)。提供
/// `dense` 给 detail 等需要矮一些的页面。`onBack` 不为空时自动在左侧渲染圆形
/// back 按钮;若 `leading` 传入会覆盖。
class FkTopBar extends StatelessWidget {
  final String title;
  final String? subtitle;
  final VoidCallback? onBack;
  final Widget? leading;
  final List<Widget> actions;
  final bool dense;
  final Color? backgroundColor;

  const FkTopBar({
    super.key,
    required this.title,
    this.subtitle,
    this.onBack,
    this.leading,
    this.actions = const [],
    this.dense = false,
    this.backgroundColor,
  });

  @override
  Widget build(BuildContext context) {
    final Widget? left =
        leading ??
        (onBack != null
            ? FkIconButton(
                onTap: onBack,
                child: const Icon(Icons.arrow_back_ios_new_rounded, size: 18),
              )
            : null);

    return Container(
      color: backgroundColor,
      padding: EdgeInsets.fromLTRB(
        18,
        dense ? AppSpacing.sm : 14,
        18,
        dense ? AppSpacing.sm : 14,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (left != null) ...[
            Padding(
              padding: EdgeInsets.only(top: dense ? 0 : AppSpacing.xs),
              child: left,
            ),
            const SizedBox(width: 10),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: dense ? 18 : 22,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.3,
                    color: AppColors.onSurface,
                    height: 1.2,
                  ),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    subtitle!,
                    style: GoogleFonts.manrope(
                      fontSize: 13,
                      color: AppColors.onSurfaceVariant,
                      height: 1.3,
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (actions.isNotEmpty) ...[
            const SizedBox(width: AppSpacing.sm),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (var i = 0; i < actions.length; i++) ...[
                  if (i > 0) const SizedBox(width: AppSpacing.sm),
                  actions[i],
                ],
              ],
            ),
          ],
        ],
      ),
    );
  }
}
