import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../theme/app_theme.dart';
import '../../providers/navigation_provider.dart';

class _NavItem {
  final IconData icon;
  final String label;
  const _NavItem(this.icon, this.label);
}

class BottomNavBar extends ConsumerWidget {
  const BottomNavBar({super.key});

  static const _items = [
    _NavItem(Icons.dashboard, '首页'),
    _NavItem(Icons.inventory_2, '库存'),
    _NavItem(Icons.add_circle, '添加'),
    _NavItem(Icons.shopping_cart, '购物'),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentIndex = ref.watch(navigationProvider);

    return ClipRRect(
      borderRadius: const BorderRadius.only(
        topLeft: Radius.circular(24),
        topRight: Radius.circular(24),
      ),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          decoration: BoxDecoration(
            color: AppColors.surface.withValues(alpha: 0.8),
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(24),
              topRight: Radius.circular(24),
            ),
            boxShadow: [
              BoxShadow(
                color: AppColors.onSurface.withValues(alpha: 0.06),
                blurRadius: 24,
                offset: const Offset(0, -8),
              ),
            ],
          ),
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  for (final (index, item) in _items.indexed)
                    Semantics(
                      selected: index == currentIndex,
                      button: true,
                      label: item.label,
                      child: GestureDetector(
                        onTap: () => ref.navigateToTab(index),
                        behavior: HitTestBehavior.opaque,
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          padding: EdgeInsets.symmetric(
                            horizontal: index == currentIndex ? 16 : 12,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color:
                                index == currentIndex
                                    ? AppColors.primaryContainer
                                    : Colors.transparent,
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                item.icon,
                                color:
                                    index == currentIndex
                                        ? Colors.white
                                        : AppColors.outline,
                                size: 24,
                              ),
                              const SizedBox(height: 4),
                              Text(
                                item.label.toUpperCase(),
                                style: GoogleFonts.manrope(
                                  fontSize: 9,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 0.5,
                                  color:
                                      index == currentIndex
                                          ? Colors.white
                                          : AppColors.outline,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
