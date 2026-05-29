import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../household/household_session_controller.dart';
import '../theme/app_theme.dart';
import '../utils/app_dialog.dart';
import '../utils/app_snackbar.dart';
import '../utils/fk_toast.dart';
import '../widgets/household/household_section.dart';
import '../widgets/shared/fk_top_bar.dart';
import '../widgets/settings/invite_result_sheet.dart';

/// Dedicated screen for household management.
///
/// Hosts [HouseholdSection] and wires all its callbacks to
/// [householdSessionControllerProvider]. Mirrors the household wiring
/// from [SettingsScreen].
class HouseholdScreen extends ConsumerStatefulWidget {
  const HouseholdScreen({super.key});

  @override
  ConsumerState<HouseholdScreen> createState() => _HouseholdScreenState();
}

class _HouseholdScreenState extends ConsumerState<HouseholdScreen> {
  String? _ownerInviteRefreshHouseholdId;

  // ── helpers ──────────────────────────────────────────────────────────────

  void _ensureOwnerPendingInvitesLoaded(String householdId, bool isOwner) {
    if (!isOwner) {
      _ownerInviteRefreshHouseholdId = null;
      return;
    }
    if (_ownerInviteRefreshHouseholdId == householdId) return;
    _ownerInviteRefreshHouseholdId = householdId;
    Future.microtask(() {
      if (!mounted) return;
      ref
          .read(householdSessionControllerProvider.notifier)
          .refreshOwnerPendingInvites(householdId);
    });
  }

  Future<T> _withLoading<T>(String message, Future<T> Function() run) async {
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        content: Row(
          children: [
            const SizedBox(
              width: AppSize.iconMd,
              height: AppSize.iconMd,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(child: Text(message)),
          ],
        ),
      ),
    );
    try {
      return await run();
    } finally {
      if (mounted) {
        Navigator.of(context, rootNavigator: true).pop();
      }
    }
  }

  // ── callbacks ─────────────────────────────────────────────────────────────

  Future<void> _onEditName(String householdId, String newName) async {
    await ref
        .read(householdSessionControllerProvider.notifier)
        .updateHouseholdName(householdId, newName);
  }

  Future<void> _onInviteLink(String householdId) async {
    final String inviteUrl;
    try {
      inviteUrl = await ref
          .read(householdSessionControllerProvider.notifier)
          .createInvite(householdId);
    } catch (_) {
      if (!mounted) return;
      final error = ref.read(householdSessionControllerProvider).error;
      showAppSnackBar(
        context,
        error ?? '创建邀请失败，请重试',
        backgroundColor: AppColors.error,
      );
      return;
    }
    if (!mounted) return;
    await InviteResultSheet.show(context, inviteUrl: inviteUrl);
    await ref
        .read(householdSessionControllerProvider.notifier)
        .refreshOwnerPendingInvites(householdId);
  }

  Future<void> _onInviteEmail(String householdId, String email) async {
    final inviteUrl = await ref
        .read(householdSessionControllerProvider.notifier)
        .createInvite(householdId, email: email);
    if (!mounted) return;
    await InviteResultSheet.show(
      context,
      inviteUrl: inviteUrl,
      invitedEmail: email.trim(),
    );
    await ref
        .read(householdSessionControllerProvider.notifier)
        .refreshOwnerPendingInvites(householdId);
  }

  Future<void> _onRemoveMember(String householdId, String userId) async {
    await ref
        .read(householdSessionControllerProvider.notifier)
        .removeMember(householdId, userId);
    if (!mounted) return;
    final error = ref.read(householdSessionControllerProvider).error;
    if (error != null) {
      showAppSnackBar(context, error, backgroundColor: AppColors.error);
    }
  }

  Future<void> _onRevokeInvite(String householdId, String inviteId) async {
    final confirmed = await showAppConfirmDialog(
      context,
      title: '撤销邀请',
      content: '确定撤销该邀请？',
      confirmLabel: '撤销',
      isDestructive: true,
    );
    if (!confirmed || !mounted) return;
    await ref
        .read(householdSessionControllerProvider.notifier)
        .revokeInvite(householdId, inviteId);
    if (!mounted) return;
    final error = ref.read(householdSessionControllerProvider).error;
    if (error != null) {
      showAppSnackBar(context, error, backgroundColor: AppColors.error);
    }
  }

  Future<void> _onDissolveHousehold(String householdId, String name) async {
    final confirmed = await showAppConfirmDialog(
      context,
      title: '解散家庭',
      content: '确定解散「$name」？这会删除家庭、成员、邀请以及所有共享食材、采购和菜谱数据，无法撤销。',
      confirmLabel: '解散',
      isDestructive: true,
    );
    if (!confirmed || !mounted) return;
    _ownerInviteRefreshHouseholdId = null;
    final dissolved = await _withLoading(
      '正在解散家庭...',
      () => ref
          .read(householdSessionControllerProvider.notifier)
          .dissolveHousehold(householdId),
    );
    if (!mounted) return;

    final session = ref.read(householdSessionControllerProvider);
    if (!dissolved) {
      showAppSnackBar(
        context,
        session.error ?? '解散家庭失败，请重试',
        backgroundColor: AppColors.error,
      );
      return;
    }

    fkToast(context, '已解散「$name」');
    if (session.households.isEmpty && Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    }
  }

  void _onSwitchHousehold(String householdId) {
    _ownerInviteRefreshHouseholdId = null;
    ref
        .read(householdSessionControllerProvider.notifier)
        .switchHousehold(householdId);
  }

  // ── build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(householdSessionControllerProvider);
    final household = session.households.isEmpty
        ? null
        : session.households.firstWhere(
            (h) => h.id == session.selectedHouseholdId,
            orElse: () => session.households.first,
          );
    final isOwner =
        household != null && household.ownerId == session.currentUserId;

    if (household != null) {
      _ensureOwnerPendingInvitesLoaded(household.id, isOwner);
    }

    return Scaffold(
      backgroundColor: AppColors.surface,
      body: SafeArea(
        bottom: false,
        child: ListView(
          padding: const EdgeInsets.only(bottom: AppSpacing.huge),
          children: [
            FkTopBar(
              title: '家庭',
              onBack: () => Navigator.of(context).maybePop(),
            ),
            HouseholdSection(
              householdName: household?.name ?? '未加入家庭',
              members: household == null ? const [] : session.householdMembers,
              onInviteLink: household == null || !isOwner
                  ? null
                  : () => _onInviteLink(household.id),
              onInviteEmail: household == null || !isOwner
                  ? null
                  : (email) => _onInviteEmail(household.id, email),
              isOwner: isOwner,
              currentUserId: session.currentUserId,
              onRemoveMember: household == null
                  ? null
                  : (userId) => _onRemoveMember(household.id, userId),
              ownerPendingInvites: session.ownerPendingInvites,
              onRevokeInvite: household == null
                  ? null
                  : (inviteId) => _onRevokeInvite(household.id, inviteId),
              onDissolveHousehold: household == null || !isOwner
                  ? null
                  : () => _onDissolveHousehold(household.id, household.name),
              households: session.households,
              selectedHouseholdId: session.selectedHouseholdId,
              onSwitchHousehold: (id) => _onSwitchHousehold(id),
              onEditName: household == null
                  ? null
                  : (newName) => _onEditName(household.id, newName),
              onLeaveHousehold: household == null
                  ? null
                  : () async {
                      final ok = await ref
                          .read(householdSessionControllerProvider.notifier)
                          .leaveHousehold(household.id);
                      if (ok && context.mounted) {
                        Navigator.of(context).maybePop();
                      }
                    },
              incomingInvites: session.pendingInvitePreviews,
              onAcceptInvite: (inviteId) => ref
                  .read(householdSessionControllerProvider.notifier)
                  .acceptInviteById(inviteId),
            ),
          ],
        ),
      ),
    );
  }
}
