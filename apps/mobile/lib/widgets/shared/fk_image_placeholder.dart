import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../theme/app_theme.dart';
import 'fk_shimmer.dart';

/// 设计稿 `ui.jsx::FKImgPlaceholder` — 135° 斜纹 + 居中小字 label。
///
/// 用 `CustomPainter` 实现 8px / 8px 重复斜带,避免引入图片资源。
class FkImagePlaceholder extends StatelessWidget {
  final double? width;
  final double height;
  final String? label;
  final Color tint;
  final double borderRadius;

  const FkImagePlaceholder({
    super.key,
    this.width,
    this.height = 120,
    this.label,
    this.tint = AppColors.surfaceContainer,
    this.borderRadius = AppRadius.chip,
  });

  @override
  Widget build(BuildContext context) {
    return FkShimmer(
      child: ClipRRect(
        borderRadius: BorderRadius.circular(borderRadius),
        child: SizedBox(
          width: width,
          height: height,
          child: Stack(
            fit: StackFit.expand,
            children: [
              CustomPaint(painter: _StripePainter(tint)),
              if (label != null)
                Center(
                  child: Text(
                    label!,
                    style: GoogleFonts.jetBrainsMono(
                      fontSize: 10,
                      color: AppColors.outline,
                      letterSpacing: 0.4,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StripePainter extends CustomPainter {
  final Color tint;
  _StripePainter(this.tint);

  @override
  void paint(Canvas canvas, Size size) {
    final base = Paint()..color = tint;
    canvas.drawRect(Offset.zero & size, base);
    final stripe = Paint()..color = Colors.black.withValues(alpha: 0.02);
    canvas.save();
    canvas.rotate(45 * 3.1415926 / 180);
    final w = size.width + size.height;
    for (double x = -size.height; x < w; x += 16) {
      canvas.drawRect(Rect.fromLTWH(x, -size.height, 8, w * 2), stripe);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_StripePainter o) => o.tint != tint;
}
