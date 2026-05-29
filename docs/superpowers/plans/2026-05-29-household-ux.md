# 家庭管理 UX 重组 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 把家庭管理从「设置」深处提为一级入口(首页家庭 chip + 独立家庭页),并补上成员自行退出与进入 app 后接受邀请。

**Architecture:** 后端能力(含 `leave_household` RPC + 自删 RLS)已就绪,本计划主要是前端重组 + 一个 `leaveHousehold` 贯通方法。新增 `HouseholdScreen` 承载现有 `HouseholdSection`(扩展两节:收到的邀请、退出家庭),首页 hero 加 `HouseholdChip` 入口,设置只留跳转行。

**Tech Stack:** Flutter / Riverpod (StateNotifier) / Supabase RPC。测试用 `flutter_test` + `flutter_riverpod` 的 `ProviderScope` override,沿用现有 `HouseholdGatewayStub` / `FakeHouseholdGateway` 范式。

**工作目录:** `apps/mobile`。所有 `flutter` 命令在 `apps/mobile` 下执行。分支:`feat/household-ux`(spec 已提交于此)。

---

## 关键既有事实(实现前必读)

- 后端已有 `leave_household(target_household_id uuid)` RPC(`supabase/migrations/20260529090000_harden_household_security.sql`):成员可退出,唯一 owner 被阻止。**无需新迁移。**
- `remove_household_member` RPC 明确 `Cannot remove yourself` —— 退出**不能**复用 `removeMember`,必须用 `leave_household`。
- 控制器 `acceptInviteById(inviteId)` 已实现「接受→重载→切到新家庭→从 `pendingInvitePreviews` 移除」。摩擦点 4 只差 UI。
- `dissolveHousehold`(`lib/household/household_session_controller.dart:631`)是 `leaveHousehold` 的范本;两者都用私有 `_selectedHouseholdIdAfterRemoval`(:774)回退选中家庭。
- `HouseholdGateway`(抽象)实现者:`SupabaseHouseholdGateway`(`household_session_controller.dart`)、`test/helpers/household_gateway_stub.dart`、`test/household_session_controller_test.dart`、`test/household_bootstrap_test.dart`、`test/invite_acceptance_test.dart`、`test/auth_gate_screen_test.dart`。
- `RemotePantryRepository`(抽象)实现者:`SupabaseRemotePantryRepository`(`lib/sync/remote_pantry_repository.dart`)、`test/household_bootstrap_test.dart`、`test/realtime_sync_test.dart`。
- `SupabaseHouseholdGateway` 把成员操作委托给 `_remoteRepository`(如 `removeMember` → `_remoteRepository.removeMember`)。

## File Structure

| 文件 | 责任 | 动作 |
|------|------|------|
| `lib/sync/remote_pantry_repository.dart` | 远端 RPC 网关 | 改:接口 + Supabase 实现加 `leaveHousehold` |
| `lib/household/household_session_controller.dart` | 家庭会话状态机 + 网关 | 改:`HouseholdGateway` 接口 + `SupabaseHouseholdGateway` 委托 + 新增 `leaveHousehold` controller 方法 |
| `lib/widgets/household/household_section.dart` | 家庭管理 UI 区块 | 移动(从 `settings/`)+ 扩展「收到的邀请」「退出家庭」 |
| `lib/screens/household_screen.dart` | 独立家庭页,组合 section + 接线控制器 | 新建 |
| `lib/widgets/dashboard/household_chip.dart` | 首页 hero 的家庭入口 chip(名字 + 红点) | 新建 |
| `lib/screens/dashboard_screen.dart` | 首页 hero | 改:`_HeroSection` 顶部 Row 加 `HouseholdChip` |
| `lib/screens/settings_screen.dart` | 设置页 | 改:内联 section → 跳转行;移走接线 |
| 各测试 fake / 测试文件 | — | 同步新增方法 + 新测试 |

---

## Task 1: `leaveHousehold` 贯通方法(接口 + Supabase 实现 + 全部 fake)

**Files:**
- Modify: `lib/sync/remote_pantry_repository.dart`(接口 ~:28 dissolveHousehold 附近;Supabase 实现 ~:228 removeMember 附近)
- Modify: `lib/household/household_session_controller.dart`(`HouseholdGateway` 接口 :56 dissolveHousehold 后;`SupabaseHouseholdGateway` :195 removeMember 后)
- Modify: `test/helpers/household_gateway_stub.dart`、`test/household_session_controller_test.dart`、`test/household_bootstrap_test.dart`、`test/invite_acceptance_test.dart`、`test/auth_gate_screen_test.dart`、`test/realtime_sync_test.dart`(各 fake)

- [ ] **Step 1: `RemotePantryRepository` 接口加方法**

在 `lib/sync/remote_pantry_repository.dart` 抽象类里 `dissolveHousehold` 声明之后加:

```dart
  Future<void> leaveHousehold(String householdId);
```

- [ ] **Step 2: `SupabaseRemotePantryRepository` 实现(RPC)**

在 `SupabaseRemotePantryRepository` 里 `removeMember` 实现之后加(镜像其校验):

```dart
  @override
  Future<void> leaveHousehold(String householdId) async {
    final trimmedHouseholdId = householdId.trim();
    if (!isUuid(trimmedHouseholdId)) {
      throw ArgumentError.value(
        householdId,
        'householdId',
        'Invalid household id',
      );
    }
    if (_client.auth.currentUser == null) {
      throw StateError('Cannot leave a household without a signed-in user.');
    }
    await _client.rpc(
      'leave_household',
      params: {'target_household_id': trimmedHouseholdId},
    );
  }
```

- [ ] **Step 3: `HouseholdGateway` 接口加方法**

在 `lib/household/household_session_controller.dart` 的 `abstract class HouseholdGateway` 里 `dissolveHousehold` 之后加:

```dart
  Future<void> leaveHousehold(String householdId);
```

- [ ] **Step 4: `SupabaseHouseholdGateway` 委托实现**

在 `SupabaseHouseholdGateway` 里 `removeMember` 之后加:

```dart
  @override
  Future<void> leaveHousehold(String householdId) {
    return _remoteRepository.leaveHousehold(householdId);
  }
```

- [ ] **Step 5: 补全所有 fake(否则不编译)**

`test/helpers/household_gateway_stub.dart`(在 `dissolveHousehold` 后加;退出 = 移除当前用户在该家庭的成员行):

```dart
  var leftHouseholdId = '';

  @override
  Future<void> leaveHousehold(String householdId) async {
    leftHouseholdId = householdId;
    households.removeWhere((household) => household.id == householdId);
    members.removeWhere(
      (member) =>
          member.householdId == householdId && member.userId == currentUserId,
    );
  }
```

`test/household_session_controller_test.dart` 的 `FakeHouseholdGateway`(在 `dissolveHousehold` 后加):

```dart
  var leftHouseholdId = '';
  Object? leaveHouseholdError;

  @override
  Future<void> leaveHousehold(String householdId) async {
    if (leaveHouseholdError != null) throw leaveHouseholdError!;
    leftHouseholdId = householdId;
    households.removeWhere((household) => household.id == householdId);
    members.removeWhere(
      (member) =>
          member.householdId == householdId && member.userId == currentUserId,
    );
  }
```

`test/household_bootstrap_test.dart`、`test/invite_acceptance_test.dart`、`test/auth_gate_screen_test.dart` 里每个 `implements HouseholdGateway` 的 fake,加最简实现:

```dart
  @override
  Future<void> leaveHousehold(String householdId) async {}
```

`test/household_bootstrap_test.dart`、`test/realtime_sync_test.dart` 里每个 `implements RemotePantryRepository` 的 fake,加:

```dart
  @override
  Future<void> leaveHousehold(String householdId) async {}
```

> 提示:若某 fake 用 `noSuchMethod` 或已有「未实现即抛」的兜底,则按其既有风格处理。逐个文件搜 `dissolveHousehold` 定位插入点。

- [ ] **Step 6: 编译 + 现有测试通过**

Run: `flutter analyze`
Expected: `No issues found!`

Run: `flutter test`
Expected: 全部通过(数量不少于改动前)。

- [ ] **Step 7: Commit**

```bash
git add apps/mobile/lib/sync/remote_pantry_repository.dart apps/mobile/lib/household/household_session_controller.dart apps/mobile/test
git commit -m "feat(household): add leaveHousehold gateway plumbing"
```

---

## Task 2: 控制器 `leaveHousehold`(TDD)

**Files:**
- Modify: `lib/household/household_session_controller.dart`(`HouseholdSessionController`,`dissolveHousehold` :631–674 之后)
- Test: `test/household_session_controller_test.dart`

- [ ] **Step 1: 写失败测试**

在 `test/household_session_controller_test.dart` 末尾(`main()` 内)加。沿用文件里已有的 `FakeHouseholdGateway` 与控制器构造方式(参考同文件中 `dissolveHousehold` 的测试写法):

```dart
  test('leaveHousehold re-selects another household after leaving', () async {
    final gateway = FakeHouseholdGateway()
      ..isAuthenticated = true
      ..households.addAll(const [
        Household(id: 'h1', name: '我家', ownerId: 'owner_2', defaultStorageArea: 'fridge'),
        Household(id: 'h2', name: '李家', ownerId: 'owner_2', defaultStorageArea: 'fridge'),
      ])
      ..members.addAll(const [
        HouseholdMember(householdId: 'h2', userId: 'owner_1', role: 'member', email: 'me@ex.com'),
      ]);
    final controller = HouseholdSessionController(gateway);
    addTearDown(controller.dispose);
    await controller.switchHousehold('h1');

    final ok = await controller.leaveHousehold('h1');

    expect(ok, isTrue);
    expect(gateway.leftHouseholdId, 'h1');
    expect(controller.state.households.map((h) => h.id), ['h2']);
    expect(controller.state.selectedHouseholdId, 'h2');
    expect(controller.state.error, isNull);
  });

  test('leaveHousehold surfaces error and keeps selection on failure', () async {
    final gateway = FakeHouseholdGateway()
      ..isAuthenticated = true
      ..households.addAll(const [
        Household(id: 'h1', name: '我家', ownerId: 'owner_2', defaultStorageArea: 'fridge'),
      ])
      ..leaveHouseholdError = StateError('sole owner');
    final controller = HouseholdSessionController(gateway);
    addTearDown(controller.dispose);
    await controller.switchHousehold('h1');

    final ok = await controller.leaveHousehold('h1');

    expect(ok, isFalse);
    expect(controller.state.error, isNotNull);
    expect(controller.state.selectedHouseholdId, 'h1');
  });
```

- [ ] **Step 2: 跑测试确认失败**

Run: `flutter test test/household_session_controller_test.dart -p vm --name leaveHousehold`
Expected: FAIL —— `leaveHousehold` 方法不存在 / 未定义。

- [ ] **Step 3: 实现 `leaveHousehold`**

在 `HouseholdSessionController` 里 `dissolveHousehold` 之后加(镜像 `dissolveHousehold`,改用 `leaveHousehold` 网关调用):

```dart
  Future<bool> leaveHousehold(String householdId) async {
    final trimmedHouseholdId = householdId.trim();
    if (trimmedHouseholdId.isEmpty) {
      state = state.copyWith(error: '家庭不存在');
      return false;
    }

    state = state.copyWith(isSubmitting: true, error: null);
    try {
      await _gateway.leaveHousehold(trimmedHouseholdId);
      final households = await _gateway.loadHouseholds();
      final isAuthenticated = _gateway.isAuthenticated;
      final selectedId = _selectedHouseholdIdAfterRemoval(
        households,
        removedHouseholdId: trimmedHouseholdId,
      );
      final members = isAuthenticated
          ? await _loadMembersForSelectedHousehold(households, selectedId)
          : const <HouseholdMember>[];
      if (!mounted) return false;
      state = state.copyWith(
        isSubmitting: false,
        isAuthenticated: isAuthenticated,
        error: null,
        households: List.unmodifiable(households),
        householdMembers: List.unmodifiable(members),
        selectedHouseholdId: selectedId,
        currentUserId: _gateway.currentUserId ?? '',
        ownerPendingInvites: const [],
      );
      if (isAuthenticated) {
        await refreshPendingInvites();
      }
      return true;
    } catch (error) {
      if (mounted) {
        state = state.copyWith(isSubmitting: false, error: error.toString());
      }
      return false;
    }
  }
```

- [ ] **Step 4: 跑测试确认通过**

Run: `flutter test test/household_session_controller_test.dart`
Expected: PASS(含新增两条 + 原有)。

- [ ] **Step 5: Commit**

```bash
git add apps/mobile/lib/household/household_session_controller.dart apps/mobile/test/household_session_controller_test.dart
git commit -m "feat(household): add leaveHousehold controller flow"
```

---

## Task 3: 把 `household_section.dart` 移到 `lib/widgets/household/`

**Files:**
- Move: `lib/widgets/settings/household_section.dart` → `lib/widgets/household/household_section.dart`
- Modify: `lib/screens/settings_screen.dart`(import 路径)、`test/household_section_test.dart`(import 路径)

- [ ] **Step 1: 移动文件并修相对 import**

```bash
mkdir -p apps/mobile/lib/widgets/household
git mv apps/mobile/lib/widgets/settings/household_section.dart apps/mobile/lib/widgets/household/household_section.dart
```

文件内相对 import 上移一层:把 `../../household/...`、`../../theme/...`、`../shared/...` 路径按新位置修正(新位置 `lib/widgets/household/` 与原 `lib/widgets/settings/` 同深度,相对路径**不变**)。确认无需改动。

- [ ] **Step 2: 修引用方 import**

`lib/screens/settings_screen.dart`:把 `import '../widgets/settings/household_section.dart';` 改为 `import '../widgets/household/household_section.dart';`。
`test/household_section_test.dart`:把 `package:fresh_pantry/widgets/settings/household_section.dart` 改为 `package:fresh_pantry/widgets/household/household_section.dart`。

- [ ] **Step 3: 编译 + 测试**

Run: `flutter analyze`
Expected: `No issues found!`

Run: `flutter test test/household_section_test.dart`
Expected: PASS(纯搬家,行为不变)。

- [ ] **Step 4: Commit**

```bash
git add apps/mobile/lib apps/mobile/test/household_section_test.dart
git commit -m "refactor(household): relocate household_section out of settings"
```

---

## Task 4: HouseholdSection 加「退出家庭」(成员)

**Files:**
- Modify: `lib/widgets/household/household_section.dart`
- Test: `test/household_section_test.dart`

- [ ] **Step 1: 写失败 widget 测试**

在 `test/household_section_test.dart` 加(沿用该文件已有的 `pumpWidget(MaterialApp(home: Scaffold(body: HouseholdSection(...))))` 包裹范式):

```dart
  testWidgets('member sees 退出家庭, owner does not', (tester) async {
    var left = false;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: HouseholdSection(
          householdName: '我家',
          members: const [
            HouseholdMember(householdId: 'h1', userId: 'u2', role: 'member', email: 'me@ex.com'),
          ],
          isOwner: false,
          currentUserId: 'u2',
          onLeaveHousehold: () async => left = true,
        ),
      ),
    ));

    expect(find.text('退出家庭'), findsOneWidget);
    expect(find.text('解散家庭'), findsNothing);

    await tester.tap(find.text('退出家庭'));
    await tester.pumpAndSettle();
    // 确认弹窗后再触发(确认按钮文案见实现)。
    await tester.tap(find.text('退出'));
    await tester.pumpAndSettle();
    expect(left, isTrue);
  });
```

- [ ] **Step 2: 跑测试确认失败**

Run: `flutter test test/household_section_test.dart --name "退出家庭"`
Expected: FAIL —— `onLeaveHousehold` 命名参数不存在。

- [ ] **Step 3: 实现**

在 `HouseholdSection` 构造参数加 `this.onLeaveHousehold`(类型 `Future<void> Function()?`)与字段。在 `build` 的危险区:owner 显示现有「解散家庭」;非 owner 且 `onLeaveHousehold != null` 时显示「退出家庭」按钮(破坏性,带确认弹窗):

```dart
    final canLeave = !isOwner && onLeaveHousehold != null;
    // ...危险区:
    if (canLeave) ...[
      const SizedBox(height: AppSpacing.md),
      const Divider(height: 1),
      const SizedBox(height: AppSpacing.sm),
      TextButton.icon(
        style: TextButton.styleFrom(
          foregroundColor: AppColors.fkDanger,
          alignment: Alignment.centerLeft,
        ),
        onPressed: () => _confirmLeave(context),
        icon: const Icon(Icons.logout_rounded),
        label: const Text('退出家庭'),
      ),
    ],
```

```dart
  Future<void> _confirmLeave(BuildContext context) async {
    final ok = await showAppConfirmDialog(
      context,
      title: '退出家庭',
      content: '退出后将不再看到该家庭的共享数据。确定退出？',
      confirmLabel: '退出',
      isDestructive: true,
    );
    if (ok == true) await onLeaveHousehold?.call();
  }
```

> `showAppConfirmDialog` 已在本文件用于移除成员,直接复用。

- [ ] **Step 4: 跑测试确认通过**

Run: `flutter test test/household_section_test.dart`
Expected: PASS。

- [ ] **Step 5: Commit**

```bash
git add apps/mobile/lib/widgets/household/household_section.dart apps/mobile/test/household_section_test.dart
git commit -m "feat(household): add member leave-household action"
```

---

## Task 5: HouseholdSection 加「收到的邀请」区

**Files:**
- Modify: `lib/widgets/household/household_section.dart`
- Test: `test/household_section_test.dart`

- [ ] **Step 1: 写失败 widget 测试**

```dart
  testWidgets('incoming invites render and accept fires', (tester) async {
    var acceptedId = '';
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: HouseholdSection(
          householdName: '我家',
          members: const [],
          incomingInvites: const [
            HouseholdInvitePreview(
              inviteId: 'inv1',
              householdId: 'h9',
              householdName: '李家',
              ownerEmail: 'owner@ex.com',
              invitedEmail: 'me@ex.com',
              memberCount: 3,
              inventoryCount: 12,
              shoppingCount: 0,
              customRecipeCount: 0,
            ),
          ],
          onAcceptInvite: (id) async => acceptedId = id,
        ),
      ),
    ));

    expect(find.text('收到的邀请'), findsOneWidget);
    expect(find.text('李家'), findsOneWidget);
    await tester.tap(find.text('接受'));
    await tester.pumpAndSettle();
    expect(acceptedId, 'inv1');
  });
```

- [ ] **Step 2: 跑测试确认失败**

Run: `flutter test test/household_section_test.dart --name "incoming invites"`
Expected: FAIL —— `incomingInvites` / `onAcceptInvite` 不存在。

- [ ] **Step 3: 实现**

构造参数加 `this.incomingInvites = const <HouseholdInvitePreview>[]` 与 `this.onAcceptInvite`(`Future<void> Function(String inviteId)?`)及字段。在 `build` 里(家庭头之后、成员之前)插入一节,仅当 `incomingInvites.isNotEmpty && onAcceptInvite != null`:

```dart
        if (incomingInvites.isNotEmpty && onAcceptInvite != null) ...[
          const SizedBox(height: AppSpacing.md),
          Text('收到的邀请',
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: AppColors.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                  )),
          const SizedBox(height: AppSpacing.sm),
          for (final invite in incomingInvites)
            _IncomingInviteRow(
              invite: invite,
              onAccept: () => onAcceptInvite!(invite.inviteId),
            ),
        ],
```

新增私有部件(放文件末,仿 `_PendingInviteRow`):

```dart
class _IncomingInviteRow extends StatelessWidget {
  const _IncomingInviteRow({required this.invite, required this.onAccept});

  final HouseholdInvitePreview invite;
  final Future<void> Function() onAccept;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          const Icon(Icons.mail_outline, color: AppColors.outline, size: 22),
          const SizedBox(width: AppSpacing.sm + 2),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(invite.householdName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodyMedium),
                Text('来自 ${invite.ownerEmail} · ${invite.inventoryCount} 项库存 · ${invite.memberCount} 名成员',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: AppColors.onSurfaceVariant,
                        )),
              ],
            ),
          ),
          FilledButton(onPressed: onAccept, child: const Text('接受')),
        ],
      ),
    );
  }
}
```

确认文件已 import `HouseholdInvitePreview`(来自 `../../household/household_models.dart`,已有)。

- [ ] **Step 4: 跑测试确认通过**

Run: `flutter test test/household_section_test.dart`
Expected: PASS。

- [ ] **Step 5: Commit**

```bash
git add apps/mobile/lib/widgets/household/household_section.dart apps/mobile/test/household_section_test.dart
git commit -m "feat(household): show incoming invites with in-app accept"
```

---

## Task 6: 新建 `HouseholdScreen`(接线控制器)

**Files:**
- Create: `lib/screens/household_screen.dart`
- Test: `test/household_screen_test.dart`
- 参考(把接线逻辑从此处迁出):`lib/screens/settings_screen.dart:45–250`(`_onEditName/_onInviteLink/_onInviteEmail/_onRemoveMember/_onRevokeInvite/_onDissolveHousehold/_onSwitchHousehold/_ensureOwnerPendingInvitesLoaded` 等)

- [ ] **Step 1: 写失败 widget 测试**

新建 `test/household_screen_test.dart`。用 `HouseholdGatewayStub` 构造控制器并 override,种一个家庭让页面渲染(参考 `test/auth_gate_screen_test.dart` 的 override 范式):

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fresh_pantry/household/household_models.dart';
import 'package:fresh_pantry/household/household_session_controller.dart';
import 'package:fresh_pantry/screens/household_screen.dart';
import 'helpers/household_gateway_stub.dart';

void main() {
  testWidgets('HouseholdScreen renders current household and members', (tester) async {
    final stub = HouseholdGatewayStub(
      isAuthenticated: true,
      households: const [
        Household(id: 'h1', name: '我家', ownerId: 'owner_1', defaultStorageArea: 'fridge'),
      ],
      members: const [
        HouseholdMember(householdId: 'h1', userId: 'owner_1', role: 'owner', email: 'me@ex.com'),
      ],
    );
    final controller = HouseholdSessionController(stub);
    addTearDown(controller.dispose);
    await controller.refreshHouseholds();
    await controller.switchHousehold('h1');

    await tester.pumpWidget(ProviderScope(
      overrides: [householdSessionControllerProvider.overrideWith((ref) => controller)],
      child: const MaterialApp(home: HouseholdScreen()),
    ));
    await tester.pumpAndSettle();

    expect(find.text('我家'), findsOneWidget);
    expect(find.text('me@ex.com'), findsOneWidget);
  });
}
```

- [ ] **Step 2: 跑测试确认失败**

Run: `flutter test test/household_screen_test.dart`
Expected: FAIL —— `household_screen.dart` 不存在。

- [ ] **Step 3: 实现 `HouseholdScreen`**

`ConsumerWidget`:`FkTopBar(title: '家庭', onBack: ...)` + 滚动体内放 `HouseholdSection`,把回调接到 `householdSessionControllerProvider.notifier`。把 settings 里那套 `_on*` handler 逻辑搬到这里(改名/邀请链接/邮箱邀请/移除成员/撤销/解散/切换/`_ensureOwnerPendingInvitesLoaded`),并接上本计划新增的:

```dart
          onLeaveHousehold: household == null
              ? null
              : () async {
                  final ok = await ref
                      .read(householdSessionControllerProvider.notifier)
                      .leaveHousehold(household.id);
                  if (ok && context.mounted) Navigator.of(context).maybePop();
                },
          incomingInvites: session.pendingInvitePreviews,
          onAcceptInvite: (inviteId) => ref
              .read(householdSessionControllerProvider.notifier)
              .acceptInviteById(inviteId),
```

`isOwner = selected.ownerId == session.currentUserId`;`household` = `session.households` 中 `selectedHouseholdId` 对应项(可能为 null = 本地态,显示创建/登录 CTA,复用 settings 现有空态文案)。

> 迁移而非复制:settings 里的同名 handler 在 Task 9 删除,避免两份。

- [ ] **Step 4: 跑测试确认通过**

Run: `flutter test test/household_screen_test.dart`
Expected: PASS。

- [ ] **Step 5: Commit**

```bash
git add apps/mobile/lib/screens/household_screen.dart apps/mobile/test/household_screen_test.dart
git commit -m "feat(household): add dedicated household screen"
```

---

## Task 7: 新建 `HouseholdChip`

**Files:**
- Create: `lib/widgets/dashboard/household_chip.dart`
- Modify: `test/helpers/household_gateway_stub.dart`(加可选 `pendingInvites` 入参,供红点测试)
- Test: `test/household_chip_test.dart`

- [ ] **Step 1: 给 stub 加 `pendingInvites` 入参**

`HouseholdGatewayStub`:构造参数加 `List<HouseholdInvitePreview> pendingInvites = const []`,存字段,并让 `loadPendingInvites` 返回它(替换现在的 `const []`)。

- [ ] **Step 2: 写失败 widget 测试**

新建 `test/household_chip_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fresh_pantry/household/household_models.dart';
import 'package:fresh_pantry/household/household_session_controller.dart';
import 'package:fresh_pantry/widgets/dashboard/household_chip.dart';
import 'helpers/household_gateway_stub.dart';

Future<HouseholdSessionController> _seeded(tester, {List<HouseholdInvitePreview> invites = const []}) async {
  final stub = HouseholdGatewayStub(
    isAuthenticated: true,
    households: const [
      Household(id: 'h1', name: '我家', ownerId: 'owner_1', defaultStorageArea: 'fridge'),
    ],
    pendingInvites: invites,
  );
  final controller = HouseholdSessionController(stub);
  addTearDown(controller.dispose);
  await controller.refreshHouseholds();
  await controller.switchHousehold('h1');
  await controller.refreshPendingInvites();
  return controller;
}

void main() {
  testWidgets('chip shows current household name', (tester) async {
    final controller = await _seeded(tester);
    await tester.pumpWidget(ProviderScope(
      overrides: [householdSessionControllerProvider.overrideWith((ref) => controller)],
      child: const MaterialApp(home: Scaffold(body: HouseholdChip())),
    ));
    await tester.pumpAndSettle();
    expect(find.text('我家'), findsOneWidget);
    expect(find.byKey(const ValueKey('household_chip_badge')), findsNothing);
  });

  testWidgets('chip shows badge when there is an incoming invite', (tester) async {
    final controller = await _seeded(tester, invites: const [
      HouseholdInvitePreview(
        inviteId: 'inv1', householdId: 'h9', householdName: '李家',
        ownerEmail: 'o@ex.com', invitedEmail: 'me@ex.com',
        memberCount: 1, inventoryCount: 0, shoppingCount: 0, customRecipeCount: 0,
      ),
    ]);
    await tester.pumpWidget(ProviderScope(
      overrides: [householdSessionControllerProvider.overrideWith((ref) => controller)],
      child: const MaterialApp(home: Scaffold(body: HouseholdChip())),
    ));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('household_chip_badge')), findsOneWidget);
  });
}
```

- [ ] **Step 3: 跑测试确认失败**

Run: `flutter test test/household_chip_test.dart`
Expected: FAIL —— `household_chip.dart` 不存在。

- [ ] **Step 4: 实现 `HouseholdChip`**

`ConsumerWidget`,适配深色 hero(半透明白底药丸)。点按 push `HouseholdScreen`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../household/household_session_controller.dart';
import '../../screens/household_screen.dart';

class HouseholdChip extends ConsumerWidget {
  const HouseholdChip({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(householdSessionControllerProvider);
    final selected = session.households
        .where((h) => h.id == session.selectedHouseholdId)
        .cast<Household?>()
        .firstWhere((_) => true, orElse: () => null);
    final label = selected?.name ?? '本地数据';
    final hasInvite = session.pendingInvitePreviews.isNotEmpty;

    return InkWell(
      borderRadius: BorderRadius.circular(999),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const HouseholdScreen()),
      ),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.18),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.home_rounded, size: 16, color: Colors.white),
            const SizedBox(width: 6),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 120),
              child: Text(label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      color: Colors.white, fontWeight: FontWeight.w600, fontSize: 13)),
            ),
            const Icon(Icons.expand_more_rounded, size: 16, color: Colors.white),
            if (hasInvite) ...[
              const SizedBox(width: 6),
              Container(
                key: const ValueKey('household_chip_badge'),
                width: 8, height: 8,
                decoration: const BoxDecoration(color: Color(0xFFE5484D), shape: BoxShape.circle),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
```

> `Household` 类型来自 `household_session_controller.dart` 的导出链(`household_models.dart`)。若分析器提示未导入 `Household`,加 `import '../../household/household_models.dart';`。

- [ ] **Step 5: 跑测试确认通过**

Run: `flutter test test/household_chip_test.dart`
Expected: PASS。

- [ ] **Step 6: Commit**

```bash
git add apps/mobile/lib/widgets/dashboard/household_chip.dart apps/mobile/test/household_chip_test.dart apps/mobile/test/helpers/household_gateway_stub.dart
git commit -m "feat(household): add home household chip with invite badge"
```

---

## Task 8: 把 `HouseholdChip` 接入首页 hero

**Files:**
- Modify: `lib/screens/dashboard_screen.dart`(`_HeroSection.build` 顶部 Row,:384–418)
- Modify: `test/dashboard_screen_test.dart`(+ 任何渲染 `DashboardScreen`/`_DashboardHero` 的测试)以 override `householdSessionControllerProvider`

- [ ] **Step 1: 在 hero 顶部 Row 插入 chip**

在 `_HeroSection.build` 的顶部 `Row`(greeting `Expanded` 与设置 `FkIconButton` 之间)插入:

```dart
              const SizedBox(width: 8),
              const HouseholdChip(),
              const SizedBox(width: 8),
```

并在文件顶部加 `import '../widgets/dashboard/household_chip.dart';`。

- [ ] **Step 2: 修被波及的 dashboard 测试**

`DashboardScreen` 现在会构建 `HouseholdChip`,它读 `householdSessionControllerProvider`(默认会经 `householdGatewayProvider` → `supabaseClientProvider` 抛错)。在所有渲染 dashboard 的测试的 `ProviderScope.overrides` 里加 override(沿用 Task 7 的 seeded controller 写法或一个空 stub):

```dart
        householdSessionControllerProvider.overrideWith((ref) {
          final c = HouseholdSessionController(HouseholdGatewayStub(isAuthenticated: true));
          return c;
        }),
```

(import `helpers/household_gateway_stub.dart` 与 `household_session_controller.dart`。)

- [ ] **Step 3: 编译 + 测试**

Run: `flutter analyze`
Expected: `No issues found!`

Run: `flutter test test/dashboard_screen_test.dart test/dashboard_widget_test.dart test/dashboard_greeting_test.dart`
Expected: PASS(全部 dashboard 相关测试)。

- [ ] **Step 4: Commit**

```bash
git add apps/mobile/lib/screens/dashboard_screen.dart apps/mobile/test
git commit -m "feat(household): surface household chip in home hero"
```

---

## Task 9: 设置页改为跳转行,移走接线

**Files:**
- Modify: `lib/screens/settings_screen.dart`
- Modify: `test/top_app_bar_settings_test.dart` / 任何断言设置内联家庭 UI 的测试

- [ ] **Step 1: 内联 `HouseholdSection` → 跳转行**

把 `settings_screen.dart` 里整段 `HouseholdSection(...)`(:413–442)替换为一行入口(放在原家庭区位置),点按 push `HouseholdScreen`:

```dart
            FkCard(
              child: ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.home_rounded, color: AppColors.primaryContainer),
                title: const Text('家庭共享'),
                subtitle: Text(
                  householdSession.households.isEmpty
                      ? '未加入家庭'
                      : '${household?.name ?? ''} · ${householdSession.householdMembers.length} 名成员',
                ),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const HouseholdScreen()),
                ),
              ),
            ),
```

加 `import 'household_screen.dart';`。删除已迁移到 `HouseholdScreen` 的 `_on*` handler 与 `_ensureOwnerPendingInvitesLoaded`(及 `household_section.dart` 的 import,若不再使用)。保留备份/导入逻辑里仍需要的 `householdSession` 读取。

> 用 `flutter analyze` 找出删除 handler 后变成「未使用」的私有方法/字段/import,一并清掉。

- [ ] **Step 2: 修被波及的设置测试**

若 `test/top_app_bar_settings_test.dart` 或其它测试断言设置页里直接出现成员/邀请按钮,改为断言出现「家庭共享」入口行;家庭管理本身的断言迁到 `test/household_screen_test.dart`。

- [ ] **Step 3: 编译 + 测试**

Run: `flutter analyze`
Expected: `No issues found!`

Run: `flutter test test/top_app_bar_settings_test.dart test/household_screen_test.dart`
Expected: PASS。

- [ ] **Step 4: Commit**

```bash
git add apps/mobile/lib/screens/settings_screen.dart apps/mobile/test
git commit -m "refactor(household): replace inline settings section with entry row"
```

---

## Task 10: 全量验证

- [ ] **Step 1: 静态分析**

Run: `flutter analyze`
Expected: `No issues found!`

- [ ] **Step 2: 全量测试**

Run: `flutter test`
Expected: 全部通过,且新增测试涵盖:`leaveHousehold` 控制器回退、退出按钮可见性、收到的邀请接受、家庭页渲染、chip 名称/红点、dashboard 接入。

- [ ] **Step 3: 真机/模拟器冒烟(可选,推荐)**

按 `README.md` 用 `flutter run --dart-define=...` 启动,手动走查:首页 chip → 家庭页 → 切换/接受邀请/退出。

---

## Self-Review 结果

- **Spec 覆盖**:摩擦点 1(chip+设置行 Task 7/8/9)、2(切换在家庭页,复用现有 `switchHousehold`,Task 6)、3(退出 Task 1/2/4/6)、4(收到的邀请 Task 5/6 + chip 红点 Task 7)。非目标(透明度/所有权转移/拒绝 API)未触及。✓
- **占位扫描**:无 TBD;每个改代码的步骤都给了完整代码或精确插入点。fake 列表已逐文件枚举。
- **类型一致**:`leaveHousehold(String)` 贯穿 RemotePantryRepository / HouseholdGateway / 两个 Supabase 实现 / controller;`onLeaveHousehold`(`Future<void> Function()?`)、`onAcceptInvite`(`Future<void> Function(String)?`)、`incomingInvites`(`List<HouseholdInvitePreview>`)在 Task 4/5/6 一致;`ValueKey('household_chip_badge')` 在 Task 7 定义并断言。
- **风险**:Task 8 会波及现有 dashboard 测试(provider 未 override 即抛),已在 Task 8 Step 2 处理。`HouseholdScreen` 接线从 settings 迁移而非复制(Task 6 注 + Task 9 删除),避免两份事实源。
