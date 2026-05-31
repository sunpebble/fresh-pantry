import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../theme/app_theme.dart';

/// FK 浮 pill toast — 暗墨色底 + 白字 + check icon,1.8s 自动消失。
///
/// 设计稿 `ui.jsx::FKToast`。Flutter 用 SnackBar 包装(底部 110px,圆角 12)。
void fkToast(BuildContext context, String message) {
  ScaffoldMessenger.of(context)
    ..clearSnackBars()
    ..showSnackBar(
      SnackBar(
        content: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.check_rounded,
              size: 16,
              color: AppColors.fkSuccess,
            ),
            const SizedBox(width: AppSpacing.sm),
            Text(
              message,
              style: GoogleFonts.manrope(
                fontSize: 13,
                color: Colors.white,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
        backgroundColor: AppColors.onSurface.withValues(alpha: 0.95),
        behavior: SnackBarBehavior.floating,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
        ),
        duration: const Duration(milliseconds: 1800),
        margin: const EdgeInsets.only(left: 50, right: 50, bottom: 110),
      ),
    );
}
