import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../household/household_session_controller.dart';
import '../providers/ai_settings_provider.dart';
import '../providers/custom_recipe_provider.dart';
import '../providers/inventory_provider.dart';
import '../providers/notification_service_provider.dart';
import '../providers/reminder_settings_provider.dart';
import '../providers/shopping_provider.dart';
import '../providers/storage_service_provider.dart';
import '../services/backup_service.dart';
import '../sync/sync_providers.dart';
import '../theme/app_theme.dart';
import '../utils/fk_toast.dart';
import '../utils/page_transitions.dart';
import '../widgets/shared/fk_card.dart';
import '../widgets/shared/fk_entrance.dart';
import '../widgets/shared/fk_pill.dart';
import '../widgets/shared/fk_section_head.dart';
import '../widgets/shared/fk_top_bar.dart';
import 'ai_settings_screen.dart';
import 'household_screen.dart';
import 'my_recipes_screen.dart';

/// FreshKeeper "我的" 设置页 — 设计稿 `screens-3.jsx::SettingsScreen`。
///
/// 视觉栈:profile 卡 + 3-stat grid + 临期提醒 toggles + 饮食偏好 chip + 更多入口。
/// 这里所有 toggle 状态都暂存于本地 state(尚未接入 settings 持久化)。
class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  String _currentUserEmail(HouseholdSessionState session) {
    for (final member in session.householdMembers) {
      if (member.userId == session.currentUserId) return member.email;
    }
    return session.email;
  }

  Future<void> _onExportTap() async {
    late final String json;
    await _withLoading('正在导出数据...', () async {
      final prefs = ref.read(sharedPreferencesProvider);
      final envelope = BackupService.exportToMap(prefs);
      json = BackupService.encodeToJson(envelope);
      await Clipboard.setData(ClipboardData(text: json));
    });
    if (!mounted) return;
    final bytes = utf8.encode(json).length;
    fkToast(context, '已复制 $bytes 字节,粘贴到 Notes/邮箱保存');
  }

  Future<void> _onImportTap() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text;
    if (!mounted) return;
    if (text == null || text.trim().isEmpty) {
      _showSimpleDialog('剪贴板为空', '请先在另一台设备复制备份 JSON 后再试。');
      return;
    }

    final Map<String, dynamic> decoded;
    try {
      decoded = BackupService.decodeFromJson(text);
    } on BackupVersionException catch (e) {
      _showSimpleDialog('备份版本不兼容', e.message);
      return;
    } on FormatException catch (e) {
      _showSimpleDialog('备份不是合法 JSON', e.message);
      return;
    }

    final inHousehold = ref.read(selectedHouseholdIdProvider).trim().isNotEmpty;
    final confirmMessage = inHousehold
        ? '将覆盖当前的所有食材、购物清单、菜谱与 AI 设置。此操作不可撤销。\n\n'
              '当前已加入家庭共享，导入后云端同步可能用其他成员的数据覆盖刚导入的内容；'
              '如需完整恢复，建议先退出家庭共享再导入。'
        : '将覆盖当前的所有食材、购物清单、菜谱与 AI 设置。此操作不可撤销。';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('确认导入?'),
        content: Text(confirmMessage),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.fkDanger),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('确认覆盖'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    await _withLoading('正在导入数据...', () async {
      final prefs = ref.read(sharedPreferencesProvider);
      await BackupService.importFromMap(
        prefs,
        decoded,
        onImported: () async {
          // Reload the notifiers from the freshly written prefs so stale
          // in-memory state (and the sync engine that reads it) cannot persist
          // the pre-import data back over the restored backup.
          ref.invalidate(inventoryProvider);
          ref.invalidate(shoppingProvider);
          ref.invalidate(customRecipesProvider);
          ref.invalidate(aiSettingsProvider);
        },
      );
    });
    if (!mounted) return;
    _showSimpleDialog('导入完成', '数据已恢复。如未刷新，请重启 App。');
  }

  void _throwSentryTestException() {
    throw StateError('This is test exception');
  }

  Future<void> _onReminderToggle(
    bool newValue,
    Future<void> Function() apply,
  ) async {
    if (newValue) {
      final service = ref.read(notificationServiceProvider);
      if (!service.permissionGranted) {
        final granted = await service.requestPermission();
        if (!mounted) return;
        if (!granted) {
          await showDialog(
            context: context,
            builder: (_) => AlertDialog(
              title: const Text('未开启通知权限'),
              content: const Text('系统通知权限未开启,无法发送临期提醒。请在 系统设置 → 通知 中允许。'),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('好'),
                ),
              ],
            ),
          );
          return; // don't apply
        }
      }
    }
    await apply();
  }

  Future<void> _showSimpleDialog(String title, String body) {
    return showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('好'),
          ),
        ],
      ),
    );
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

  @override
  Widget build(BuildContext context) {
    final inventoryCount = ref.watch(
      inventoryProvider.select((items) => items.length),
    );
    final shoppingCount = ref.watch(
      shoppingProvider.select((items) => items.length),
    );
    final recipeCount = ref.watch(
      customRecipesProvider.select((items) => items.length),
    );
    final householdSession = ref.watch(householdSessionControllerProvider);
    final household = householdSession.households.isEmpty
        ? null
        : householdSession.households.firstWhere(
            (h) => h.id == householdSession.selectedHouseholdId,
            orElse: () => householdSession.households.first,
          );
    final categoryPrefs =
        household?.categoryPreferences ?? const <String, dynamic>{};
    final selectedPrefs = <String>{
      for (final entry in categoryPrefs.entries)
        if (entry.value == true) entry.key,
    };
    final reminder = ref.watch(reminderSettingsProvider);
    final reminderN = ref.read(reminderSettingsProvider.notifier);

    final anyReminderOn =
        reminder.remindD1 ||
        reminder.remindD3 ||
        reminder.remindD7 ||
        reminder.remindDaily;
    final permissionGranted = ref.watch(
      notificationServiceProvider.select(
        (service) => service.permissionGranted,
      ),
    );
    final permissionMissing = anyReminderOn && !permissionGranted;

    return Scaffold(
      backgroundColor: AppColors.surface,
      body: SafeArea(
        bottom: false,
        child: Builder(
          builder: (context) {
            final sections = <Widget>[
              FkTopBar(
                title: '我的',
                subtitle: '设置 · 提醒 · 偏好',
                onBack: () => Navigator.of(context).maybePop(),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
                child: _ProfileCard(
                  householdName: household?.name ?? '未加入家庭',
                  userEmail: _currentUserEmail(householdSession),
                ),
              ),
              const SizedBox(height: 14),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
                child: _StatRow(
                  items: [
                    ('食材', '$inventoryCount', AppColors.primary),
                    ('采购', '$shoppingCount', AppColors.fkWarn),
                    ('收藏菜谱', '$recipeCount', AppColors.fkDanger),
                  ],
                ),
              ),
              const FkSectionHead(title: '家庭共享'),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
                child: _LinkRow(
                  key: const Key('household_entry_row'),
                  label: '家庭共享',
                  sub: householdSession.households.isEmpty
                      ? '未加入家庭'
                      : '${household?.name ?? ''} · ${householdSession.householdMembers.length} 名成员',
                  icon: Icons.home_rounded,
                  onTap: () => Navigator.of(context).push(
                    fkRoute<void>(builder: (_) => const HouseholdScreen()),
                  ),
                  isLast: true,
                ),
              ),
              if (permissionMissing)
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.xl,
                  ),
                  child: Container(
                    padding: const EdgeInsets.all(AppSpacing.md),
                    decoration: BoxDecoration(
                      color: AppColors.fkWarnSoft,
                      borderRadius: BorderRadius.circular(AppRadius.md),
                    ),
                    child: Row(
                      children: const [
                        Icon(Icons.warning_amber, color: AppColors.fkWarn),
                        SizedBox(width: AppSpacing.sm + 2),
                        Expanded(
                          child: Text(
                            '系统通知权限未开启,提醒不会送达。请去 系统设置 → 通知 中允许。',
                            style: TextStyle(fontSize: 13),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              if (permissionMissing) const SizedBox(height: AppSpacing.md),
              const FkSectionHead(title: '临期提醒'),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
                child: FkCard(
                  padding: EdgeInsets.zero,
                  child: Column(
                    children: [
                      _ToggleRow(
                        label: '提前 1 天提醒',
                        sub: '高优先级 · 推送 + 角标',
                        value: reminder.remindD1,
                        onChanged: (v) => _onReminderToggle(
                          v,
                          () => reminderN.update(remindD1: v),
                        ),
                      ),
                      _ToggleRow(
                        label: '提前 3 天提醒',
                        sub: '标准 · 仅推送',
                        value: reminder.remindD3,
                        onChanged: (v) => _onReminderToggle(
                          v,
                          () => reminderN.update(remindD3: v),
                        ),
                      ),
                      _ToggleRow(
                        label: '提前 7 天提醒',
                        sub: '轻量 · 仅角标',
                        value: reminder.remindD7,
                        onChanged: (v) => _onReminderToggle(
                          v,
                          () => reminderN.update(remindD7: v),
                        ),
                      ),
                      _ToggleRow(
                        label: '每日 9:00 汇总',
                        sub: '包含临期 + 库存不足',
                        value: reminder.remindDaily,
                        onChanged: (v) => _onReminderToggle(
                          v,
                          () => reminderN.update(remindDaily: v),
                        ),
                        isLast: true,
                      ),
                    ],
                  ),
                ),
              ),
              const FkSectionHead(title: '数据备份'),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
                child: FkCard(
                  padding: EdgeInsets.zero,
                  child: Column(
                    children: [
                      _ActionRow(
                        key: const Key('backup_export_action'),
                        label: '导出到剪贴板',
                        sub: '复制全部数据为 JSON,粘贴到 Notes/邮箱保存',
                        icon: Icons.upload_outlined,
                        onTap: _onExportTap,
                      ),
                      const Divider(height: 1, color: AppColors.hair),
                      _ActionRow(
                        key: const Key('backup_import_action'),
                        label: '从剪贴板导入',
                        sub: '会覆盖当前所有数据',
                        icon: Icons.download_outlined,
                        destructive: true,
                        onTap: _onImportTap,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.xl),
              const FkSectionHead(title: '饮食偏好'),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
                child: FkCard(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '根据偏好为你推荐菜谱',
                        style: Theme.of(context).textTheme.labelMedium
                            ?.copyWith(color: AppColors.onSurfaceVariant),
                      ),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          for (final tag in const [
                            '高蛋白',
                            '低脂',
                            '素食',
                            '家常菜',
                            '快手菜',
                            '儿童餐',
                            '低碳水',
                          ])
                            _PrefChip(
                              label: tag,
                              selected: selectedPrefs.contains(tag),
                              onTap: () {
                                final newPrefs = Map<String, dynamic>.from(
                                  categoryPrefs,
                                );
                                if (selectedPrefs.contains(tag)) {
                                  newPrefs[tag] = false;
                                } else {
                                  newPrefs[tag] = true;
                                }
                                if (household != null) {
                                  ref
                                      .read(
                                        householdSessionControllerProvider
                                            .notifier,
                                      )
                                      .updateCategoryPreferences(
                                        household.id,
                                        newPrefs,
                                      );
                                }
                              },
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const FkSectionHead(title: '更多'),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
                child: FkCard(
                  padding: EdgeInsets.zero,
                  child: Column(
                    children: [
                      _LinkRow(
                        label: '我的食谱',
                        sub: '添加和管理私房菜单',
                        icon: Icons.menu_book_rounded,
                        onTap: () => Navigator.of(context).push(
                          fkRoute<void>(
                            builder: (_) => const MyRecipesScreen(),
                          ),
                        ),
                      ),
                      _LinkRow(
                        label: 'AI 助手',
                        sub: '配置模型与连接',
                        icon: Icons.auto_awesome_outlined,
                        onTap: () => Navigator.of(context).push(
                          fkRoute<void>(
                            builder: (_) => const AiSettingsScreen(),
                          ),
                        ),
                      ),
                      _LinkRow(
                        label: '冰箱布局',
                        sub: '4 个分区已设置',
                        icon: Icons.kitchen_outlined,
                        onTap: () {},
                      ),
                      _LinkRow(
                        label: '常备库存阈值',
                        sub: '已为 6 种食材设置',
                        icon: Icons.inventory_2_outlined,
                        onTap: () {},
                      ),
                      if (kDebugMode)
                        _LinkRow(
                          key: const Key('sentry_verify_action'),
                          label: '验证 Sentry',
                          sub: '创建一条测试异常',
                          icon: Icons.bug_report_outlined,
                          onTap: _throwSentryTestException,
                        ),
                      _LinkRow(
                        label: '关于 FreshKeeper',
                        icon: Icons.info_outline_rounded,
                        onTap: () {},
                        isLast: true,
                      ),
                    ],
                  ),
                ),
              ),
            ];
            return ListView.builder(
              padding: const EdgeInsets.only(bottom: AppSpacing.huge),
              itemCount: sections.length,
              itemBuilder: (context, index) => sections[index],
            );
          },
        ),
      ),
    );
  }
}

class _ProfileCard extends StatelessWidget {
  const _ProfileCard({required this.householdName, required this.userEmail});

  final String householdName;
  final String userEmail;

  @override
  Widget build(BuildContext context) {
    return FkCard(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Row(
        children: [
          _ProfileAvatar(letter: _avatarLetter(userEmail)),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  householdName,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: AppColors.onSurface,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  userEmail,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppColors.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const Icon(
            Icons.chevron_right_rounded,
            size: AppSize.iconSm,
            color: AppColors.outline,
          ),
        ],
      ),
    );
  }

  static String _avatarLetter(String email) {
    if (email.isEmpty) return '?';
    return email[0].toUpperCase();
  }
}

class _ProfileAvatar extends StatelessWidget {
  const _ProfileAvatar({required this.letter});

  final String letter;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: AppSize.profileAvatar,
      height: AppSize.profileAvatar,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.primary, AppColors.primaryLight],
        ),
        shape: BoxShape.circle,
      ),
      alignment: Alignment.center,
      child: Text(
        letter,
        style: Theme.of(context).textTheme.displaySmall?.copyWith(
          fontWeight: FontWeight.w700,
          color: Colors.white,
        ),
      ),
    );
  }
}

class _StatRow extends StatelessWidget {
  final List<(String, String, Color)> items;
  const _StatRow({required this.items});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (var i = 0; i < items.length; i++) ...[
          if (i > 0) const SizedBox(width: AppSpacing.sm + 2),
          Expanded(
            child: FkEntrance(
              index: i,
              child: FkCard(
                padding: const EdgeInsets.all(14),
                child: Column(
                  children: [
                    Text(
                      items[i].$2,
                      style: Theme.of(context).textTheme.headlineSmall
                          ?.copyWith(
                            fontWeight: FontWeight.w800,
                            color: items[i].$3,
                          ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      items[i].$1,
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: AppColors.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _ToggleRow extends StatelessWidget {
  final String label;
  final String? sub;
  final bool value;
  final ValueChanged<bool> onChanged;
  final bool isLast;

  const _ToggleRow({
    required this.label,
    this.sub,
    required this.value,
    required this.onChanged,
    this.isLast = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        border: isLast
            ? null
            : const Border(
                bottom: BorderSide(color: AppColors.hair, width: 0.5),
              ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: AppColors.onSurface,
                  ),
                ),
                if (sub != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    sub!,
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: AppColors.onSurfaceVariant,
                    ),
                  ),
                ],
              ],
            ),
          ),
          // 设计稿 `ToggleRow`:白滑块 + 开 primary / 关 #D9DDD8 轨道、无描边。
          Switch(
            value: value,
            onChanged: onChanged,
            thumbColor: const WidgetStatePropertyAll(Colors.white),
            trackColor: WidgetStateProperty.resolveWith(
              (states) => states.contains(WidgetState.selected)
                  ? AppColors.primary
                  : AppColors.switchTrackOff,
            ),
            trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
          ),
        ],
      ),
    );
  }
}

class _PrefChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _PrefChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return FkPill(
      label: label,
      onTap: onTap,
      backgroundColor: selected
          ? AppColors.primary
          : AppColors.surfaceContainer,
      foregroundColor: selected ? Colors.white : AppColors.onSurface,
    );
  }
}

class _LinkRow extends StatelessWidget {
  final String label;
  final String? sub;
  final IconData icon;
  final VoidCallback onTap;
  final bool isLast;

  const _LinkRow({
    super.key,
    required this.label,
    this.sub,
    required this.icon,
    required this.onTap,
    this.isLast = false,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            border: isLast
                ? null
                : const Border(
                    bottom: BorderSide(color: AppColors.hair, width: 0.5),
                  ),
          ),
          child: Row(
            children: [
              Container(
                width: AppSize.settingsIconBox,
                height: AppSize.settingsIconBox,
                decoration: BoxDecoration(
                  color: AppColors.primarySoft,
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                ),
                alignment: Alignment.center,
                child: Icon(
                  icon,
                  size: AppSize.iconSm,
                  color: AppColors.primary,
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: AppColors.onSurface,
                      ),
                    ),
                    if (sub != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        sub!,
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: AppColors.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const Icon(
                Icons.chevron_right_rounded,
                size: AppSize.iconSm,
                color: AppColors.outline,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A tappable settings row: leading icon (optional) + label + trailing chevron.
class _ActionRow extends StatelessWidget {
  const _ActionRow({
    super.key,
    required this.label,
    this.sub,
    required this.onTap,
    this.icon,
    this.destructive = false,
  });

  final String label;
  final String? sub;
  final VoidCallback onTap;
  final IconData? icon;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final color = destructive ? AppColors.fkDanger : AppColors.onSurface;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: 14,
        ),
        child: Row(
          children: [
            if (icon != null) ...[
              Icon(icon, size: AppSize.iconMd, color: color),
              const SizedBox(width: AppSpacing.md),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: color,
                    ),
                  ),
                  if (sub != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      sub!,
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: AppColors.onSurfaceVariant,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const Icon(
              Icons.chevron_right,
              size: AppSize.iconMd,
              color: AppColors.outline,
            ),
          ],
        ),
      ),
    );
  }
}
