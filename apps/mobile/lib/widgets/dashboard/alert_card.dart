import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../theme/app_theme.dart';

class AlertCard extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String name;
  final String subtitle;
  final String badge;
  final Color badgeBg;
  final Color badgeText;
  final String? storageTag;
  final VoidCallback? onConsume;
  final VoidCallback? onAddToCart;

  const AlertCard({
    super.key,
    required this.icon,
    required this.iconColor,
    required this.name,
    required this.subtitle,
    required this.badge,
    required this.badgeBg,
    required this.badgeText,
    this.storageTag,
    this.onConsume,
    this.onAddToCart,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: onConsume != null || onAddToCart != null,
      label: name,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: AppSpacing.lg,
        ),
        decoration: BoxDecoration(
          color: AppColors.surfaceContainerLowest,
          borderRadius: BorderRadius.circular(AppRadius.lg),
          boxShadow: [
            BoxShadow(
              color: AppColors.onSurface.withValues(alpha: 0.03),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          children: [
            Row(
              children: [
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    color: iconColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(AppRadius.lg),
                  ),
                  child: Icon(icon, color: iconColor, size: 26),
                ),
                const SizedBox(width: AppSpacing.lg),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(
                              fontWeight: FontWeight.w700,
                              color: AppColors.onSurface,
                            ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      Row(
                        children: [
                          Text(
                            subtitle,
                            style: GoogleFonts.manrope(
                              fontSize: AppFontSize.sm,
                              color: AppColors.onSurfaceVariant,
                            ),
                          ),
                          if (storageTag != null) ...[
                            const SizedBox(width: AppSpacing.sm),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: AppSpacing.sm,
                                vertical: AppSpacing.xs,
                              ),
                              decoration: const BoxDecoration(
                                color: AppColors.surfaceContainer,
                                borderRadius: BorderRadius.all(
                                  Radius.circular(AppRadius.xs),
                                ),
                              ),
                              child: Text(
                                storageTag!.toUpperCase(),
                                style: Theme.of(context).textTheme.labelSmall
                                    ?.copyWith(
                                      fontSize: AppFontSize.xs,
                                      fontWeight: FontWeight.w700,
                                      letterSpacing: 0.8,
                                      color: AppColors.onSurfaceVariant,
                                    ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.lg),
            _AlertActions(
              badge: badge,
              badgeBg: badgeBg,
              badgeText: badgeText,
              onConsume: onConsume,
              onAddToCart: onAddToCart,
            ),
          ],
        ),
      ),
    );
  }
}

class _AlertActions extends StatelessWidget {
  final String badge;
  final Color badgeBg;
  final Color badgeText;
  final VoidCallback? onConsume;
  final VoidCallback? onAddToCart;

  const _AlertActions({
    required this.badge,
    required this.badgeBg,
    required this.badgeText,
    required this.onConsume,
    required this.onAddToCart,
  });

  @override
  Widget build(BuildContext context) {
    final buttons = [
      if (onConsume != null)
        _ActionButton(
          icon: Icons.check_circle_outline,
          label: '已消耗',
          color: AppColors.primary,
          onTap: onConsume!,
        ),
      if (onAddToCart != null)
        _ActionButton(
          icon: Icons.add_shopping_cart,
          label: '加入清单',
          color: AppColors.secondary,
          onTap: onAddToCart!,
        ),
    ];
    final badgeWidget = _StatusBadge(
      badge: badge,
      badgeBg: badgeBg,
      badgeText: badgeText,
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 300) {
          return Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [...buttons, badgeWidget],
          );
        }

        return Row(
          children: [
            for (final (index, button) in buttons.indexed) ...[
              if (index > 0) const SizedBox(width: AppSpacing.sm),
              button,
            ],
            const Spacer(),
            badgeWidget,
          ],
        );
      },
    );
  }
}

class _StatusBadge extends StatelessWidget {
  final String badge;
  final Color badgeBg;
  final Color badgeText;

  const _StatusBadge({
    required this.badge,
    required this.badgeBg,
    required this.badgeText,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.sm,
      ),
      constraints: const BoxConstraints(minWidth: 70),
      decoration: BoxDecoration(
        color: badgeBg,
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: Text(
        badge.toUpperCase(),
        textAlign: TextAlign.center,
        style: GoogleFonts.manrope(
          fontSize: AppFontSize.xs,
          fontWeight: FontWeight.w900,
          letterSpacing: 1.2,
          color: badgeText,
        ),
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String? label;
  final Color color;
  final VoidCallback onTap;

  const _ActionButton({
    required this.icon,
    this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.lg,
            vertical: AppSpacing.sm,
          ),
          decoration: BoxDecoration(
            color: AppColors.surfaceContainerLow,
            borderRadius: BorderRadius.circular(AppRadius.pill),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: color, size: 18),
              if (label != null) ...[
                const SizedBox(width: AppSpacing.sm),
                Text(
                  label!,
                  style: GoogleFonts.manrope(
                    fontSize: AppFontSize.sm,
                    fontWeight: FontWeight.w700,
                    color: color,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
