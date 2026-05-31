import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../theme/app_theme.dart';

/// 设计稿 `ui.jsx::FKSectionHead` — section 标题 + 可选 count + 右侧 action 或
/// 自定义 widget。
class FkSectionHead extends StatelessWidget {
  final String title;
  final int? count;
  final String? actionLabel;
  final VoidCallback? onAction;
  final Widget? trailing;
  final EdgeInsetsGeometry padding;

  const FkSectionHead({
    super.key,
    required this.title,
    this.count,
    this.actionLabel,
    this.onAction,
    this.trailing,
    this.padding = const EdgeInsets.fromLTRB(18, 18, 18, 10),
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: padding,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          Text(
            title,
            style: GoogleFonts.plusJakartaSans(
              fontSize: AppFontSize.lg,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.2,
              color: AppColors.onSurface,
            ),
          ),
          if (count != null) ...[
            const SizedBox(width: AppSpacing.sm),
            Text(
              '$count',
              style: GoogleFonts.manrope(
                fontSize: 13,
                color: AppColors.onSurfaceVariant,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
          const Spacer(),
          if (trailing != null)
            trailing!
          else if (actionLabel != null)
            GestureDetector(
              onTap: onAction,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    actionLabel!,
                    style: GoogleFonts.manrope(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AppColors.primary,
                    ),
                  ),
                  const Icon(
                    Icons.chevron_right_rounded,
                    size: 16,
                    color: AppColors.primary,
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
