import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import 'fk_shimmer.dart';
import 'fk_skeleton.dart';

/// 菜谱卡骨架 —— 形状贴合 [RecipeCard](130 高 + 左 120 方图)。
class FkRecipeSkeletonCard extends StatelessWidget {
  const FkRecipeSkeletonCard({super.key});

  @override
  Widget build(BuildContext context) {
    return FkShimmer(
      child: Container(
        height: 130,
        decoration: BoxDecoration(
          color: AppColors.surfaceContainerLowest,
          borderRadius: BorderRadius.circular(AppRadius.xl),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const FkSkeletonBox(width: 120, height: 130),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.md),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: const [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        FkSkeletonLine(width: 140),
                        SizedBox(height: AppSpacing.sm),
                        FkSkeletonLine(width: 90),
                      ],
                    ),
                    FkSkeletonLine(width: double.infinity),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
