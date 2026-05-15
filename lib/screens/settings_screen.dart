import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../providers/inventory_provider.dart';
import '../providers/shopping_provider.dart';
import '../providers/storage_service_provider.dart';
import '../services/backup_service.dart';
import '../theme/app_theme.dart';
import '../utils/fk_toast.dart';
import '../widgets/shared/fk_card.dart';
import '../widgets/shared/fk_pill.dart';
import '../widgets/shared/fk_section_head.dart';
import '../widgets/shared/fk_top_bar.dart';
import 'ai_settings_screen.dart';
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
  // Local-only toggle states; persistence is out of scope for this redesign.
  bool _remindD1 = true;
  bool _remindD3 = true;
  bool _remindD7 = false;
  bool _remindDaily = true;

  final Set<String> _selectedPrefs = {'高蛋白', '低脂', '素食'};

  Future<void> _onExportTap() async {
    final prefs = ref.read(sharedPreferencesProvider);
    final envelope = BackupService.exportToMap(prefs);
    final json = BackupService.encodeToJson(envelope);
    await Clipboard.setData(ClipboardData(text: json));
    if (!mounted) return;
    final bytes = json.length;
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

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('确认导入?'),
        content: const Text('将覆盖当前的所有食材、购物清单、菜谱与 AI 设置。此操作不可撤销。'),
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

    final prefs = ref.read(sharedPreferencesProvider);
    await BackupService.importFromMap(prefs, decoded);
    if (!mounted) return;
    _showSimpleDialog('导入完成', '请重启 App 以加载新数据。');
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

  @override
  Widget build(BuildContext context) {
    final inventory = ref.watch(inventoryProvider);
    final shopping = ref.watch(shoppingProvider);

    return Scaffold(
      backgroundColor: AppColors.surface,
      body: SafeArea(
        bottom: false,
        child: ListView(
          padding: const EdgeInsets.only(bottom: 40),
          children: [
            FkTopBar(
              title: '我的',
              subtitle: '设置 · 提醒 · 偏好',
              onBack: () => Navigator.of(context).maybePop(),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18),
              child: _ProfileCard(
                onTap: () {},
              ),
            ),
            const SizedBox(height: 14),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18),
              child: _StatRow(
                items: [
                  ('食材', '${inventory.length}', AppColors.primary),
                  ('采购', '${shopping.length}', AppColors.fkWarn),
                  ('收藏菜谱', '12', AppColors.fkDanger),
                ],
              ),
            ),
            const FkSectionHead(title: '临期提醒'),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18),
              child: FkCard(
                padding: EdgeInsets.zero,
                child: Column(
                  children: [
                    _ToggleRow(
                      label: '提前 1 天提醒',
                      sub: '高优先级 · 推送 + 角标',
                      value: _remindD1,
                      onChanged: (v) => setState(() => _remindD1 = v),
                    ),
                    _ToggleRow(
                      label: '提前 3 天提醒',
                      sub: '标准 · 仅推送',
                      value: _remindD3,
                      onChanged: (v) => setState(() => _remindD3 = v),
                    ),
                    _ToggleRow(
                      label: '提前 7 天提醒',
                      sub: '轻量 · 仅角标',
                      value: _remindD7,
                      onChanged: (v) => setState(() => _remindD7 = v),
                    ),
                    _ToggleRow(
                      label: '每日 9:00 汇总',
                      sub: '包含临期 + 库存不足',
                      value: _remindDaily,
                      onChanged: (v) => setState(() => _remindDaily = v),
                      isLast: true,
                    ),
                  ],
                ),
              ),
            ),
            const FkSectionHead(title: '数据备份'),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18),
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
            const SizedBox(height: 18),
            const FkSectionHead(title: '饮食偏好'),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18),
              child: FkCard(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '根据偏好为你推荐菜谱',
                      style: GoogleFonts.manrope(
                        fontSize: 12,
                        color: AppColors.onSurfaceVariant,
                      ),
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
                            selected: _selectedPrefs.contains(tag),
                            onTap: () => setState(() {
                              if (_selectedPrefs.contains(tag)) {
                                _selectedPrefs.remove(tag);
                              } else {
                                _selectedPrefs.add(tag);
                              }
                            }),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const FkSectionHead(title: '更多'),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18),
              child: FkCard(
                padding: EdgeInsets.zero,
                child: Column(
                  children: [
                    _LinkRow(
                      label: '我的食谱',
                      sub: '添加和管理私房菜单',
                      icon: Icons.menu_book_rounded,
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const MyRecipesScreen(),
                        ),
                      ),
                    ),
                    _LinkRow(
                      label: 'AI 助手',
                      sub: '配置模型与连接',
                      icon: Icons.auto_awesome_outlined,
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(
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
          ],
        ),
      ),
    );
  }
}

class _ProfileCard extends StatelessWidget {
  final VoidCallback onTap;
  const _ProfileCard({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return FkCard(
      padding: const EdgeInsets.all(16),
      onTap: onTap,
      child: Row(
        children: [
          Container(
            width: 56,
            height: 56,
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
              '米',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 24,
                fontWeight: FontWeight.w700,
                color: Colors.white,
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '小米的厨房',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: AppColors.onSurface,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '管理冰箱 90 天 · 减少浪费 23 件',
                  style: GoogleFonts.manrope(
                    fontSize: 12,
                    color: AppColors.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const Icon(
            Icons.chevron_right_rounded,
            size: 18,
            color: AppColors.outline,
          ),
        ],
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
          if (i > 0) const SizedBox(width: 10),
          Expanded(
            child: FkCard(
              padding: const EdgeInsets.all(14),
              child: Column(
                children: [
                  Text(
                    items[i].$2,
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      color: items[i].$3,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    items[i].$1,
                    style: GoogleFonts.manrope(
                      fontSize: 11,
                      color: AppColors.onSurfaceVariant,
                    ),
                  ),
                ],
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
                  style: GoogleFonts.manrope(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppColors.onSurface,
                  ),
                ),
                if (sub != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    sub!,
                    style: GoogleFonts.manrope(
                      fontSize: 11,
                      color: AppColors.onSurfaceVariant,
                    ),
                  ),
                ],
              ],
            ),
          ),
          Switch.adaptive(
            value: value,
            onChanged: onChanged,
            activeThumbColor: AppColors.primary,
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
      backgroundColor: selected ? AppColors.primary : AppColors.surfaceContainer,
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
    required this.label,
    this.sub,
    required this.icon,
    required this.onTap,
    this.isLast = false,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
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
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: AppColors.primarySoft,
                borderRadius: BorderRadius.circular(8),
              ),
              alignment: Alignment.center,
              child: Icon(icon, size: 18, color: AppColors.primary),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: GoogleFonts.manrope(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: AppColors.onSurface,
                    ),
                  ),
                  if (sub != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      sub!,
                      style: GoogleFonts.manrope(
                        fontSize: 11,
                        color: AppColors.onSurfaceVariant,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const Icon(
              Icons.chevron_right_rounded,
              size: 16,
              color: AppColors.outline,
            ),
          ],
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
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            if (icon != null) ...[
              Icon(icon, size: 20, color: color),
              const SizedBox(width: 12),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: GoogleFonts.manrope(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: color,
                    ),
                  ),
                  if (sub != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      sub!,
                      style: GoogleFonts.manrope(
                        fontSize: 11,
                        color: AppColors.onSurfaceVariant,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const Icon(
              Icons.chevron_right,
              size: 20,
              color: AppColors.outline,
            ),
          ],
        ),
      ),
    );
  }
}
