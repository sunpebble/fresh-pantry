import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/navigation_provider.dart';
import '../../theme/app_theme.dart';
import '../shared/fk_nav_icon.dart';
import '../shared/fk_pressable.dart';

class _NavItem {
  final String icon;
  final String label;
  const _NavItem(this.icon, this.label);
}

/// 设计稿 `ui.jsx::FKTabBar` — 5 tab,中间 add 是 52×52 primary FAB,左右各
/// 两个普通 tab(icon + label)。底栏底白半透明 + 模糊。
class BottomNavBar extends ConsumerWidget {
  const BottomNavBar({super.key});

  static const _items = [
    _NavItem('home', '首页'),
    _NavItem('fridge', '食材'),
    _NavItem('add', ''),
    _NavItem('recipes', '菜谱'),
    _NavItem('shopping', '清单'),
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
        filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
        child: Container(
          decoration: BoxDecoration(
            color: AppColors.surface.withValues(alpha: 0.92),
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(24),
              topRight: Radius.circular(24),
            ),
            border: const Border(
              top: BorderSide(color: AppColors.hair, width: 0.5),
            ),
          ),
          child: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  for (final (index, item) in _items.indexed)
                    index == FkTab.add
                        ? _PrimaryFab(
                            icon: item.icon,
                            onTap: () => ref.navigateToTab(index),
                          )
                        : _TabButton(
                            icon: item.icon,
                            label: item.label,
                            active: index == currentIndex,
                            onTap: () => ref.navigateToTab(index),
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

class _TabButton extends StatelessWidget {
  final String icon;
  final String label;
  final bool active;
  final VoidCallback onTap;
  const _TabButton({
    required this.icon,
    required this.label,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = active ? AppColors.primary : AppColors.outline;
    return Semantics(
      selected: active,
      button: true,
      label: label,
      child: FkAnimatedPressable(
        onTap: onTap,
        haptic: HapticKind.selection,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              FkNavIcon(icon: icon, size: 22, color: color),
              const SizedBox(height: 3),
              Text(
                label,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: color,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PrimaryFab extends StatelessWidget {
  final String icon;
  final VoidCallback onTap;
  const _PrimaryFab({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: '添加食材',
      child: FkAnimatedPressable(
        onTap: onTap,
        haptic: HapticKind.light,
        child: Container(
          width: AppSize.profileAvatar - AppSpacing.xs,
          height: AppSize.profileAvatar - AppSpacing.xs,
          margin: const EdgeInsets.only(bottom: 4),
          decoration: const BoxDecoration(
            color: AppColors.primary,
            shape: BoxShape.circle,
            boxShadow: AppShadows.strong,
          ),
          alignment: Alignment.center,
          child: FkNavIcon(
            icon: icon,
            size: AppSize.iconMd + 6,
            color: AppColors.onPrimary,
            strokeWidth: 2,
          ),
        ),
      ),
    );
  }
}
