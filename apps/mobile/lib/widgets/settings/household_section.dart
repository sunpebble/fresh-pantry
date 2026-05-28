import 'package:flutter/material.dart';

import '../../household/household_models.dart';
import '../../theme/app_theme.dart';
import '../../utils/app_dialog.dart';
import '../shared/fk_card.dart';
import '../shared/fk_pill.dart';
import '../shared/fk_section_head.dart';

class HouseholdSection extends StatelessWidget {
  const HouseholdSection({
    super.key,
    required this.householdName,
    required this.members,
    this.onInvite,
    this.onInviteEmail,
    this.isOwner = false,
    this.currentUserId = '',
    this.onRemoveMember,
    this.ownerPendingInvites = const [],
    this.onRevokeInvite,
    this.households = const [],
    this.selectedHouseholdId = '',
    this.onSwitchHousehold,
    this.onEditName,
  });

  final String householdName;
  final List<HouseholdMember> members;
  final VoidCallback? onInvite;
  final Future<void> Function(String email)? onInviteEmail;
  final bool isOwner;
  final String currentUserId;
  final Future<void> Function(String userId)? onRemoveMember;
  final List<OwnerPendingInvite> ownerPendingInvites;
  final Future<void> Function(String inviteId)? onRevokeInvite;
  final List<Household> households;
  final String selectedHouseholdId;
  final ValueChanged<String>? onSwitchHousehold;
  final Future<void> Function(String newName)? onEditName;

  @override
  Widget build(BuildContext context) {
    final inviteAction = onInviteEmail == null
        ? onInvite
        : () => _showInviteDialog(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FkSectionHead(title: '家庭共享', count: members.length),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
          child: FkCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 36,
                      height: 36,
                      decoration: const BoxDecoration(
                        color: AppColors.primarySoft,
                        shape: BoxShape.circle,
                      ),
                      alignment: Alignment.center,
                      child: const Icon(
                        Icons.home_rounded,
                        color: AppColors.primaryContainer,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(
                      child: households.length > 1 && onSwitchHousehold != null
                          ? DropdownButton<String>(
                              value: selectedHouseholdId.isNotEmpty &&
                                      households.any((h) => h.id == selectedHouseholdId)
                                  ? selectedHouseholdId
                                  : households.first.id,
                              isExpanded: true,
                              underline: const SizedBox.shrink(),
                              items: [
                                for (final h in households)
                                  DropdownMenuItem(
                                    value: h.id,
                                    child: Text(
                                      h.name,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: Theme.of(context).textTheme.titleMedium
                                          ?.copyWith(fontWeight: FontWeight.w700),
                                    ),
                                  ),
                              ],
                              onChanged: (value) {
                                if (value != null) onSwitchHousehold!(value);
                              },
                            )
                          : Text(
                              householdName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.titleMedium
                                  ?.copyWith(fontWeight: FontWeight.w700),
                            ),
                    ),
                    if (isOwner && onEditName != null)
                      IconButton(
                        icon: const Icon(Icons.edit_outlined, size: 18),
                        color: AppColors.onSurfaceVariant,
                        onPressed: () => _showEditNameDialog(context),
                        tooltip: '编辑家庭名称',
                      ),
                  ],
                ),
                const SizedBox(height: AppSpacing.md),
                if (members.isEmpty)
                  Text(
                    '登录后会显示家庭成员',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: AppColors.onSurfaceVariant,
                    ),
                  )
                else
                  for (final member in members) _buildMemberRow(context, member),
                if (isOwner && ownerPendingInvites.isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.md),
                  Text(
                    '待处理邀请',
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: AppColors.onSurfaceVariant,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  for (final invite in ownerPendingInvites)
                    _PendingInviteRow(
                      invite: invite,
                      onRevoke: onRevokeInvite != null
                          ? () => onRevokeInvite!(invite.id)
                          : null,
                    ),
                ],
                const SizedBox(height: AppSpacing.md),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: inviteAction,
                    icon: const Icon(Icons.person_add_alt_1_rounded),
                    label: const Text('邀请成员'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildMemberRow(BuildContext context, HouseholdMember member) {
    final canRemove = isOwner &&
        member.userId != currentUserId &&
        member.role != 'owner' &&
        onRemoveMember != null;

    final row = _MemberRow(member: member);

    if (!canRemove) return row;

    return Dismissible(
      key: ValueKey('member_${member.userId}'),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: AppSpacing.xl),
        color: AppColors.fkDanger,
        child: const Icon(Icons.delete_outline, color: Colors.white),
      ),
      confirmDismiss: (_) async {
        return showAppConfirmDialog(
          context,
          title: '移除成员',
          content: '确定移除 ${member.email}？',
          confirmLabel: '移除',
          isDestructive: true,
        );
      },
      onDismissed: (_) => onRemoveMember!(member.userId),
      child: row,
    );
  }

  Future<void> _showInviteDialog(BuildContext context) {
    final onSubmit = onInviteEmail;
    if (onSubmit == null) return Future<void>.value();
    return showDialog<void>(
      context: context,
      builder: (_) => _InviteMemberDialog(onSubmit: onSubmit),
    );
  }

  Future<void> _showEditNameDialog(BuildContext context) {
    final onEdit = onEditName;
    if (onEdit == null) return Future<void>.value();
    return showDialog<void>(
      context: context,
      builder: (_) => _EditNameDialog(
        currentName: householdName,
        onSubmit: onEdit,
      ),
    );
  }
}

class _MemberRow extends StatelessWidget {
  const _MemberRow({required this.member});

  final HouseholdMember member;

  @override
  Widget build(BuildContext context) {
    final label = member.role == 'owner' ? '拥有者' : '成员';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          const Icon(
            Icons.account_circle_outlined,
            color: AppColors.outline,
            size: 22,
          ),
          const SizedBox(width: AppSpacing.sm + 2),
          Expanded(
            child: Text(
              member.email,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
          FkPill(label: label, sm: true),
        ],
      ),
    );
  }
}

class _PendingInviteRow extends StatelessWidget {
  const _PendingInviteRow({required this.invite, this.onRevoke});

  final OwnerPendingInvite invite;
  final VoidCallback? onRevoke;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          const Icon(
            Icons.mail_outline,
            color: AppColors.outline,
            size: 22,
          ),
          const SizedBox(width: AppSpacing.sm + 2),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  invite.email,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                Text(
                  '待接受',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: AppColors.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          if (onRevoke != null)
            IconButton(
              icon: const Icon(Icons.close, size: 18),
              color: AppColors.fkDanger,
              onPressed: onRevoke,
              tooltip: '撤销邀请',
            ),
        ],
      ),
    );
  }
}

class _InviteMemberDialog extends StatefulWidget {
  const _InviteMemberDialog({required this.onSubmit});

  final Future<void> Function(String email) onSubmit;

  @override
  State<_InviteMemberDialog> createState() => _InviteMemberDialogState();
}

class _InviteMemberDialogState extends State<_InviteMemberDialog> {
  final _controller = TextEditingController();
  var _isSubmitting = false;
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_controller.text.trim().isEmpty) {
      setState(() => _error = '请输入成员邮箱');
      return;
    }
    setState(() {
      _isSubmitting = true;
      _error = null;
    });
    try {
      await widget.onSubmit(_controller.text);
      if (!mounted) return;
      Navigator.of(context).pop();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _isSubmitting = false;
        _error = error.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('邀请成员'),
      content: TextField(
        controller: _controller,
        enabled: !_isSubmitting,
        keyboardType: TextInputType.emailAddress,
        decoration: InputDecoration(labelText: '成员邮箱', errorText: _error),
      ),
      actions: [
        TextButton(
          onPressed: _isSubmitting ? null : () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: _isSubmitting ? null : _submit,
          child: const Text('发送邀请'),
        ),
      ],
    );
  }
}

class _EditNameDialog extends StatefulWidget {
  const _EditNameDialog({required this.currentName, required this.onSubmit});

  final String currentName;
  final Future<void> Function(String newName) onSubmit;

  @override
  State<_EditNameDialog> createState() => _EditNameDialogState();
}

class _EditNameDialogState extends State<_EditNameDialog> {
  late final _controller = TextEditingController(text: widget.currentName);
  var _isSubmitting = false;
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_controller.text.trim().isEmpty) {
      setState(() => _error = '家庭名称不能为空');
      return;
    }
    setState(() {
      _isSubmitting = true;
      _error = null;
    });
    try {
      await widget.onSubmit(_controller.text.trim());
      if (!mounted) return;
      Navigator.of(context).pop();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _isSubmitting = false;
        _error = error.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('编辑家庭名称'),
      content: TextField(
        controller: _controller,
        enabled: !_isSubmitting,
        autofocus: true,
        textInputAction: TextInputAction.done,
        onSubmitted: (_) => _submit(),
        decoration: InputDecoration(labelText: '家庭名称', errorText: _error),
      ),
      actions: [
        TextButton(
          onPressed: _isSubmitting ? null : () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: _isSubmitting ? null : _submit,
          child: const Text('保存'),
        ),
      ],
    );
  }
}
