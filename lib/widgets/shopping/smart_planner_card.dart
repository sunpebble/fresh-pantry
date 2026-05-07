import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../theme/app_theme.dart';

class SmartPlannerCard extends StatelessWidget {
  final String title;
  final VoidCallback? onViewRecipe;

  const SmartPlannerCard({
    super.key,
    required this.title,
    this.onViewRecipe,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        color: AppColors.primaryContainer,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Stack(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '智能规划',
                style: GoogleFonts.manrope(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 3,
                  color: AppColors.onPrimaryContainer.withValues(alpha: 0.7),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                title,
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  color: AppColors.onPrimaryContainer,
                  height: 1.3,
                ),
              ),
              const SizedBox(height: 20),
              Semantics(
                button: onViewRecipe != null,
                label: '查看食谱',
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: onViewRecipe,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 12,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '查看食谱',
                          style: GoogleFonts.manrope(
                            fontWeight: FontWeight.w700,
                            color: AppColors.primary,
                            fontSize: 14,
                          ),
                        ),
                        const SizedBox(width: 4),
                        const Icon(
                          Icons.arrow_forward,
                          color: AppColors.primary,
                          size: 16,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
          Positioned(
            right: -8,
            bottom: -8,
            child: Icon(
              Icons.restaurant,
              size: 120,
              color: AppColors.onPrimaryContainer.withValues(alpha: 0.08),
            ),
          ),
        ],
      ),
    );
  }
}
