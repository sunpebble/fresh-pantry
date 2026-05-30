import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/sync_status_provider.dart';
import '../../theme/app_colors.dart';

/// Lightweight banner surfacing offline / pending-sync state.
///
/// Renders nothing when online with an empty outbox; otherwise shows a thin
/// strip describing whether the app is syncing or offline and how many
/// operations remain pending.
class SyncStatusBanner extends ConsumerWidget {
  const SyncStatusBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(syncStatusProvider);
    if (!status.showBanner) return const SizedBox.shrink();

    final label = status.online
        ? '同步中 · ${status.pendingCount} 条待同步'
        : status.pendingCount > 0
            ? '离线 · ${status.pendingCount} 条待同步'
            : '离线';

    return Material(
      color: status.online ? AppColors.primary : AppColors.onSurfaceVariant,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          child: Row(
            children: [
              Icon(
                status.online ? Icons.sync : Icons.cloud_off,
                size: 16,
                color: AppColors.onPrimary,
              ),
              const SizedBox(width: 8),
              Text(
                label,
                style: const TextStyle(
                  color: AppColors.onPrimary,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
