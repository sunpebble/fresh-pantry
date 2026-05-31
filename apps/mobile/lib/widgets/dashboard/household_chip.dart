import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../household/household_models.dart';
import '../../theme/app_theme.dart';
import '../../household/household_session_controller.dart';
import '../../screens/household_screen.dart';
import '../../utils/page_transitions.dart';

class HouseholdChip extends ConsumerWidget {
  const HouseholdChip({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(householdSessionControllerProvider);
    Household? selected;
    for (final h in session.households) {
      if (h.id == session.selectedHouseholdId) {
        selected = h;
        break;
      }
    }
    final label = selected?.name ?? '本地数据';
    final hasInvite = session.pendingInvitePreviews.isNotEmpty;

    return InkWell(
      borderRadius: BorderRadius.circular(AppRadius.pill),
      onTap: () => Navigator.of(
        context,
      ).push(fkRoute<void>(builder: (_) => const HouseholdScreen())),
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: 6,
        ),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.18),
          borderRadius: BorderRadius.circular(AppRadius.pill),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.home_rounded, size: 16, color: Colors.white),
            const SizedBox(width: 6),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 120),
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
              ),
            ),
            const Icon(
              Icons.expand_more_rounded,
              size: 16,
              color: Colors.white,
            ),
            if (hasInvite) ...[
              const SizedBox(width: 6),
              Container(
                key: const ValueKey('household_chip_badge'),
                width: 8,
                height: 8,
                decoration: const BoxDecoration(
                  color: AppColors.fkAlert,
                  shape: BoxShape.circle,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
