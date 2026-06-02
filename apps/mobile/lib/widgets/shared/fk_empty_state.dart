import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../theme/app_theme.dart';

/// 统一空态:64 圆形软底图标 + 标题(PlusJakartaSans lg) + 副标题(Manrope sm)。
///
/// 收敛此前 inventory / expiring / low_stock / shopping 各自私有的近似实现。
/// 不内置入场动画 —— 需要时由调用方用 `FkEntrance` 包裹。
class FkEmptyState extends StatelessWidget {
  const FkEmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.xl,
        vertical: 60,
      ),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 64,
              height: 64,
              child: DecoratedBox(
                decoration: const BoxDecoration(
                  color: AppColors.primarySoft,
                  shape: BoxShape.circle,
                ),
                child: Center(
                  child: Icon(icon, size: 32, color: AppColors.primary),
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            Text(
              title,
              textAlign: TextAlign.center,
              style: GoogleFonts.plusJakartaSans(
                fontSize: AppFontSize.lg,
                fontWeight: FontWeight.w700,
                color: AppColors.onSurface,
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: GoogleFonts.manrope(
                fontSize: AppFontSize.sm,
                color: AppColors.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
