# UI / 交互 / 动效打磨 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 统一 Fresh Pantry 移动端的动效词汇、补齐交互/动画/UI 细节、收口 token 漂移，使整体风格统一且更有「克制·高级」感，全程不引入新依赖、不改色板。

**Architecture:** 四阶段分层叠加。阶段 1 在 `theme/` + `widgets/shared/` + `utils/` 建立可复用动效原语（motion token、按压/触感包装器、页面转场），下沉到共享组件后全局生效；阶段 2-4 消费这些原语做列表入场、骨架屏、Hero 连续、状态反馈、token 扫荡。所有动效原语在构建时读取 `MediaQuery.disableAnimationsOf(context)`，系统「减弱动态效果」开启时降级为静态终态——既是无障碍，也让 widget 测试不被无限动画卡死 `pumpAndSettle`。

**Tech Stack:** Flutter (Material3) · Riverpod · `flutter_test` · 仅用 SDK 动画原语（`AnimatedScale` / `TweenAnimationBuilder` / `PageRouteBuilder` / `Hero` / `ShaderMask` / `AnimationController`）。

**关键约束（每个 commit 前必读）:**
- `flutter test` **串行**运行：`cd apps/mobile && flutter test -j 1 <path>`。
- `AppShell` 相关测试需 `syncBannerTestOverrides`（见现有 `app_shell_test.dart` 用法）。
- **仅格式化改动过的文件**：`dart format apps/mobile/lib/<改动文件>`，勿全量 format（仓库未启用 tall-style）。
- 保留工作区既有 WIP（`dashboard_screen` / `shopping_list_screen` / `top_app_bar` 及其测试）不动。
- 分支：`feat/ui-polish-pass`（已建）。spec：`docs/superpowers/specs/2026-05-31-ui-polish-design.md`。

---

## 文件结构总览

**阶段 1（地基）**
- Create `apps/mobile/lib/theme/app_motion.dart` — 时长/曲线/参数 token。
- Modify `apps/mobile/lib/theme/app_theme.dart` — `export 'app_motion.dart';`。
- Create `apps/mobile/lib/widgets/shared/fk_pressable.dart` — `FkAnimatedPressable` + `HapticKind`。
- Create `apps/mobile/lib/utils/page_transitions.dart` — `fkRoute<T>()`。
- Modify 共享原语接入按压：`fk_card.dart` / `fk_icon_button.dart` / `fk_pill.dart` / `pill_chip.dart` / `recipe_card.dart` / `inventory/ingredient_card.dart` / `dashboard/quick_action_card.dart` / `common/bottom_nav_bar.dart`。
- Modify 路由扫荡：所有 `MaterialPageRoute` 调用点改 `fkRoute`。
- Modify 时长迁移：6 处零散 `Animated*`。
- Create tests：`fk_pressable_test.dart` / `page_transitions_test.dart`。

**阶段 2（列表入场 + 加载态）**
- Create `apps/mobile/lib/widgets/shared/fk_entrance.dart`。
- Create `apps/mobile/lib/widgets/shared/fk_shimmer.dart`。
- Create `apps/mobile/lib/widgets/shared/fk_skeleton.dart`。
- Modify 入场接入 + spinner→skeleton 替换（首页/库存/菜谱/清单/Review/搜索）。
- Create tests：`fk_entrance_test.dart` / `fk_shimmer_test.dart` / `fk_skeleton_test.dart`。

**阶段 3（Hero 连续 + 状态反馈）**
- Modify `recipe_card.dart` ↔ `recipe_detail_screen.dart`、`ingredient_card.dart` ↔ `ingredient_detail_screen.dart` 加 `Hero`。
- Modify 勾选/进度条/步骤/同步横幅状态动画。
- Create tests：Hero 往返 + 状态切换。

**阶段 4（token 扫荡）**
- Create `apps/mobile/lib/theme/app_shadows.dart`。
- Modify `app_theme.dart` export；按需扩 `app_sizes.dart`。
- Modify 扫荡 fontSize / spacing / radius / color / shadow / pill 口径 / auth 输入框 / Review snackbar。

---

# 阶段 1 · 地基

> 产出后即可独立合并：全 App 获得统一按压反馈 + 触感 + 页面转场，且所有 motion 数值集中可调。

## Task 1.1: 动效 token `app_motion.dart`

**Files:**
- Create: `apps/mobile/lib/theme/app_motion.dart`
- Modify: `apps/mobile/lib/theme/app_theme.dart`
- Test: `apps/mobile/test/theme/app_motion_test.dart`

- [ ] **Step 1: 写 token 文件**

Create `apps/mobile/lib/theme/app_motion.dart`:

```dart
import 'package:flutter/animation.dart';

/// 动效时长 token。集中所有动画时长,杜绝散落的魔法数字。
/// 基调:克制·高级 —— 快而不急,平稳收尾。
class AppDuration {
  AppDuration._();

  static const Duration fast = Duration(milliseconds: 120); // 按压 / 微反馈
  static const Duration normal = Duration(milliseconds: 180); // 折叠 / 状态切换
  static const Duration slow = Duration(milliseconds: 250); // 入场 / cross-fade
  static const Duration page = Duration(milliseconds: 240); // 页面转场
  static const Duration shimmer = Duration(milliseconds: 1400); // 微光循环
}

/// 动效曲线 token。统一缓动,避免逐处自定义。
class AppMotionCurves {
  AppMotionCurves._();

  static const Curve standard = Curves.easeOutCubic; // 默认:平稳减速
  static const Curve decelerate = Curves.easeOut; // 轻量淡入
  static const Curve emphasized = Cubic(0.2, 0, 0, 1); // 页面转场:强调减速
}

/// 动效参数 token（位移幅度、交错节奏、按压缩放）。
class AppMotion {
  AppMotion._();

  static const double pressScale = 0.97; // 按压缩放终值
  static const double entranceOffset = 8; // 入场上移像素
  static const Duration staggerStep = Duration(milliseconds: 50); // 列表交错步长
  static const int staggerMaxItems = 8; // 交错封顶,避免后段延迟过长
}
```

- [ ] **Step 2: 在 app_theme 暴露**

Modify `apps/mobile/lib/theme/app_theme.dart`，在现有 export 区块（第 7-11 行附近）追加一行：

```dart
export 'app_motion.dart';
```

- [ ] **Step 3: 写测试**

Create `apps/mobile/test/theme/app_motion_test.dart`:

```dart
import 'package:flutter/animation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fresh_pantry/theme/app_motion.dart';

void main() {
  test('durations follow the restrained-premium ladder', () {
    expect(AppDuration.fast.inMilliseconds, 120);
    expect(AppDuration.normal.inMilliseconds, 180);
    expect(AppDuration.slow.inMilliseconds, 250);
    expect(AppDuration.page.inMilliseconds, 240);
    expect(AppDuration.shimmer.inMilliseconds, 1400);
  });

  test('curves and motion params are defined', () {
    expect(AppMotionCurves.standard, Curves.easeOutCubic);
    expect(AppMotion.pressScale, 0.97);
    expect(AppMotion.entranceOffset, 8);
    expect(AppMotion.staggerStep.inMilliseconds, 50);
  });
}
```

- [ ] **Step 4: 跑测试**

Run: `cd apps/mobile && flutter test -j 1 test/theme/app_motion_test.dart`
Expected: PASS（2 tests）。

- [ ] **Step 5: 格式化 + commit**

```bash
dart format apps/mobile/lib/theme/app_motion.dart apps/mobile/lib/theme/app_theme.dart apps/mobile/test/theme/app_motion_test.dart
git add apps/mobile/lib/theme/app_motion.dart apps/mobile/lib/theme/app_theme.dart apps/mobile/test/theme/app_motion_test.dart
git commit -m "feat(motion): add app_motion timing/curve/param tokens"
```

---

## Task 1.2: 按压/触感包装器 `FkAnimatedPressable`

**Files:**
- Create: `apps/mobile/lib/widgets/shared/fk_pressable.dart`
- Test: `apps/mobile/test/widgets/shared/fk_pressable_test.dart`

- [ ] **Step 1: 写失败测试**

Create `apps/mobile/test/widgets/shared/fk_pressable_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fresh_pantry/widgets/shared/fk_pressable.dart';

void main() {
  testWidgets('invokes onTap', (tester) async {
    var tapped = false;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: FkAnimatedPressable(
          onTap: () => tapped = true,
          child: const SizedBox(width: 100, height: 100),
        ),
      ),
    ));
    await tester.tap(find.byType(FkAnimatedPressable));
    await tester.pumpAndSettle();
    expect(tapped, isTrue);
  });

  testWidgets('scales down on tap-down then restores', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Center(
          child: FkAnimatedPressable(
            onTap: () {},
            child: const SizedBox(width: 100, height: 100),
          ),
        ),
      ),
    ));

    AnimatedScale scaleOf() =>
        tester.widget<AnimatedScale>(find.byType(AnimatedScale));
    expect(scaleOf().scale, 1.0);

    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(FkAnimatedPressable)),
    );
    await tester.pump();
    expect(scaleOf().scale, lessThan(1.0));

    await gesture.up();
    await tester.pumpAndSettle();
    expect(scaleOf().scale, 1.0);
  });

  testWidgets('reduce-motion disables the scale animation', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: MediaQuery(
        data: const MediaQueryData(disableAnimations: true),
        child: Scaffold(
          body: Center(
            child: FkAnimatedPressable(
              onTap: () {},
              child: const SizedBox(width: 100, height: 100),
            ),
          ),
        ),
      ),
    ));
    // reduce-motion 下不渲染 AnimatedScale,仅保留点击。
    expect(find.byType(AnimatedScale), findsNothing);
  });

  testWidgets('emits a haptic on tap-down without throwing', (tester) async {
    final calls = <MethodCall>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        calls.add(call);
        return null;
      },
    );
    addTearDown(() => tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null));

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: FkAnimatedPressable(
          onTap: () {},
          child: const SizedBox(width: 100, height: 100),
        ),
      ),
    ));
    await tester.tap(find.byType(FkAnimatedPressable));
    await tester.pumpAndSettle();
    expect(calls.any((c) => c.method == 'HapticFeedback.vibrate'), isTrue);
  });
}
```

- [ ] **Step 2: 跑测试确认失败**

Run: `cd apps/mobile && flutter test -j 1 test/widgets/shared/fk_pressable_test.dart`
Expected: FAIL（`fk_pressable.dart` 不存在 / `FkAnimatedPressable` 未定义）。

- [ ] **Step 3: 写实现**

Create `apps/mobile/lib/widgets/shared/fk_pressable.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../theme/app_theme.dart';

/// 触感强度。统一三档,屏幕只挑语义不挑 API。
enum HapticKind { selection, light, none }

/// 通用按压包装器 —— 按下缩放 + 触感,松手回弹。
///
/// 设计基调「克制·高级」:缩放仅 0.97,时长 [AppDuration.fast]。
/// 尊重系统「减弱动态效果」:[MediaQuery.disableAnimationsOf] 为真时跳过缩放,
/// 仅保留点击与触感(也避免无限/隐式动画卡住 widget 测试的 pumpAndSettle)。
class FkAnimatedPressable extends StatefulWidget {
  const FkAnimatedPressable({
    super.key,
    required this.child,
    this.onTap,
    this.onLongPress,
    this.pressedScale = AppMotion.pressScale,
    this.haptic = HapticKind.selection,
    this.behavior = HitTestBehavior.opaque,
  });

  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final double pressedScale;
  final HapticKind haptic;
  final HitTestBehavior behavior;

  @override
  State<FkAnimatedPressable> createState() => _FkAnimatedPressableState();
}

class _FkAnimatedPressableState extends State<FkAnimatedPressable> {
  bool _pressed = false;

  void _fireHaptic() {
    switch (widget.haptic) {
      case HapticKind.selection:
        HapticFeedback.selectionClick();
      case HapticKind.light:
        HapticFeedback.lightImpact();
      case HapticKind.none:
        break;
    }
  }

  void _setPressed(bool value) {
    if (_pressed == value) return;
    setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onTap != null || widget.onLongPress != null;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);

    final gesture = GestureDetector(
      behavior: widget.behavior,
      onTap: widget.onTap == null
          ? null
          : () {
              _fireHaptic();
              widget.onTap!();
            },
      onLongPress: widget.onLongPress,
      onTapDown: enabled && !reduceMotion ? (_) => _setPressed(true) : null,
      onTapUp: enabled && !reduceMotion ? (_) => _setPressed(false) : null,
      onTapCancel: enabled && !reduceMotion ? () => _setPressed(false) : null,
      child: widget.child,
    );

    if (reduceMotion) return gesture;

    return AnimatedScale(
      scale: _pressed ? widget.pressedScale : 1.0,
      duration: AppDuration.fast,
      curve: AppMotionCurves.standard,
      child: gesture,
    );
  }
}
```

- [ ] **Step 4: 跑测试确认通过**

Run: `cd apps/mobile && flutter test -j 1 test/widgets/shared/fk_pressable_test.dart`
Expected: PASS（4 tests）。

- [ ] **Step 5: 格式化 + commit**

```bash
dart format apps/mobile/lib/widgets/shared/fk_pressable.dart apps/mobile/test/widgets/shared/fk_pressable_test.dart
git add apps/mobile/lib/widgets/shared/fk_pressable.dart apps/mobile/test/widgets/shared/fk_pressable_test.dart
git commit -m "feat(motion): add FkAnimatedPressable press+haptic wrapper"
```

---

## Task 1.3: 页面转场 `fkRoute`

**Files:**
- Create: `apps/mobile/lib/utils/page_transitions.dart`
- Test: `apps/mobile/test/utils/page_transitions_test.dart`

- [ ] **Step 1: 写失败测试**

Create `apps/mobile/test/utils/page_transitions_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fresh_pantry/theme/app_motion.dart';
import 'package:fresh_pantry/utils/page_transitions.dart';

void main() {
  testWidgets('fkRoute pushes and reveals the destination', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () => Navigator.of(context).push(
                fkRoute<void>(builder: (_) => const _DestPage()),
              ),
              child: const Text('go'),
            ),
          ),
        ),
      ),
    ));

    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();
    expect(find.text('destination'), findsOneWidget);
  });

  test('fkRoute uses the page duration token', () {
    final route = fkRoute<void>(builder: (_) => const SizedBox());
    expect(route.transitionDuration, AppDuration.page);
  });
}

class _DestPage extends StatelessWidget {
  const _DestPage();
  @override
  Widget build(BuildContext context) =>
      const Scaffold(body: Center(child: Text('destination')));
}
```

- [ ] **Step 2: 跑测试确认失败**

Run: `cd apps/mobile && flutter test -j 1 test/utils/page_transitions_test.dart`
Expected: FAIL（`page_transitions.dart` 不存在）。

- [ ] **Step 3: 写实现**

Create `apps/mobile/lib/utils/page_transitions.dart`:

```dart
import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// FK 统一页面转场 —— 进入页上移淡入,退出页轻微淡出。
///
/// 替代裸 [MaterialPageRoute],让全 App 导航有一致的「设计过的」转场。
/// reduce-motion 由 Flutter 框架在路由层自动处理(返回无位移)。
Route<T> fkRoute<T>({
  required WidgetBuilder builder,
  RouteSettings? settings,
  bool fullscreenDialog = false,
}) {
  return PageRouteBuilder<T>(
    settings: settings,
    fullscreenDialog: fullscreenDialog,
    transitionDuration: AppDuration.page,
    reverseTransitionDuration: AppDuration.normal,
    pageBuilder: (context, animation, secondaryAnimation) => builder(context),
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      final curved = CurvedAnimation(
        parent: animation,
        curve: AppMotionCurves.emphasized,
        reverseCurve: AppMotionCurves.standard,
      );
      return FadeTransition(
        opacity: curved,
        child: SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0, 0.04),
            end: Offset.zero,
          ).animate(curved),
          child: child,
        ),
      );
    },
  );
}
```

- [ ] **Step 4: 跑测试确认通过**

Run: `cd apps/mobile && flutter test -j 1 test/utils/page_transitions_test.dart`
Expected: PASS（2 tests）。

- [ ] **Step 5: 格式化 + commit**

```bash
dart format apps/mobile/lib/utils/page_transitions.dart apps/mobile/test/utils/page_transitions_test.dart
git add apps/mobile/lib/utils/page_transitions.dart apps/mobile/test/utils/page_transitions_test.dart
git commit -m "feat(motion): add fkRoute slide-up+fade page transition"
```

---

## Task 1.4: 共享原语接入按压反馈

把 `FkAnimatedPressable` 嵌进有点击行为的共享组件，按压反馈一处定义全局生效。**做法统一**：把原来的 `GestureDetector(onTap: x, behavior: opaque, child: c)` 替换为 `FkAnimatedPressable(onTap: x, child: c)`（`FkAnimatedPressable` 内部已有 `GestureDetector` + opaque）。

> **关键依赖**：`RecipeCard` 通过 `FkCard(onTap: onTap)` 处理点击（recipe_card.dart:50-52），改完 Step 1 的 `FkCard` 后它**自动**获得按压反馈，本任务**不单独改** recipe_card。同理任何用 `FkCard(onTap:)` 的卡片都自动生效。

**Files:**
- Modify: `apps/mobile/lib/widgets/shared/fk_card.dart:43-48`（GestureDetector → FkAnimatedPressable）
- Modify: `apps/mobile/lib/widgets/shared/fk_icon_button.dart:58-75`（外层 GestureDetector）
- Modify: `apps/mobile/lib/widgets/shared/pill_chip.dart:95-96`（onTap 分支 GestureDetector）
- Modify: `apps/mobile/lib/widgets/inventory/ingredient_card.dart:169-174`（onTap 分支 GestureDetector）
- Modify: `apps/mobile/lib/widgets/dashboard/quick_action_card.dart:31-32`（GestureDetector）
- Test: `apps/mobile/test/widgets/shared/fk_pressable_integration_test.dart`

- [ ] **Step 1: fk_card.dart**

Modify `apps/mobile/lib/widgets/shared/fk_card.dart`，把第 43-48 行：

```dart
    if (onTap == null) return inner;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: inner,
    );
```

替换为：

```dart
    if (onTap == null) return inner;
    return FkAnimatedPressable(onTap: onTap, child: inner);
```

并在文件顶部 import 区加 `import 'fk_pressable.dart';`。

- [ ] **Step 2: fk_icon_button.dart**

Modify `apps/mobile/lib/widgets/shared/fk_icon_button.dart`：第 58-60 行的 `return GestureDetector(onTap: onTap, behavior: HitTestBehavior.opaque, child: Container(...))` 把外层 `GestureDetector` 换成 `FkAnimatedPressable(onTap: onTap, child: Container(...))`。import 加 `import 'fk_pressable.dart';`。

- [ ] **Step 3: pill_chip.dart**

Modify `apps/mobile/lib/widgets/shared/pill_chip.dart`：第 95-96 行 `if (onTap == null) return body; return GestureDetector(onTap: onTap, child: body);` → `return FkAnimatedPressable(onTap: onTap, child: body);`。import 加 `import 'fk_pressable.dart';`。

- [ ] **Step 4: ingredient_card.dart**

Modify `apps/mobile/lib/widgets/inventory/ingredient_card.dart`：第 169-174 行 `if (onTap == null) return card; return GestureDetector(onTap: onTap, behavior: HitTestBehavior.opaque, child: card);` → `return FkAnimatedPressable(onTap: onTap, child: card);`。import 加 `import '../shared/fk_pressable.dart';`。（内部 `onBuyAgain` 的 GestureDetector 第 143-145 行也可顺手换成 `FkAnimatedPressable`。）

- [ ] **Step 5: quick_action_card.dart**

Modify `apps/mobile/lib/widgets/dashboard/quick_action_card.dart`：第 31-32 行 `GestureDetector(onTap: onTap, child: Container(...))` → `FkAnimatedPressable(onTap: onTap, child: Container(...))`。import 加 `import '../shared/fk_pressable.dart';`。

> recipe_card 不在此列：它走 `FkCard(onTap:)`，Step 1 改完即自动生效。

- [ ] **Step 6: 写集成测试（验证仍可点击）**

Create `apps/mobile/test/widgets/shared/fk_pressable_integration_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fresh_pantry/widgets/shared/fk_card.dart';
import 'package:fresh_pantry/widgets/shared/fk_pressable.dart';

void main() {
  testWidgets('FkCard with onTap routes through FkAnimatedPressable',
      (tester) async {
    var taps = 0;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: FkCard(
          onTap: () => taps++,
          child: const Text('card'),
        ),
      ),
    ));
    expect(find.byType(FkAnimatedPressable), findsOneWidget);
    await tester.tap(find.text('card'));
    await tester.pumpAndSettle();
    expect(taps, 1);
  });

  testWidgets('FkCard without onTap stays plain', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: FkCard(child: Text('card'))),
    ));
    expect(find.byType(FkAnimatedPressable), findsNothing);
  });
}
```

- [ ] **Step 7: 跑测试 + 受影响的现有测试**

```bash
cd apps/mobile && flutter test -j 1 \
  test/widgets/shared/fk_pressable_integration_test.dart \
  test/widgets/ test/screens/
```
Expected: 全部 PASS（含原 RecipeCard / IngredientCard / dashboard 等 widget 测试，点击行为不变）。若某测试用 `find.byType(GestureDetector)` 定位卡片，改为 `find.byType(FkAnimatedPressable)` 或 `find.byType(FkCard)`。

- [ ] **Step 8: 格式化 + commit**

```bash
dart format apps/mobile/lib/widgets/shared/fk_card.dart apps/mobile/lib/widgets/shared/fk_icon_button.dart apps/mobile/lib/widgets/shared/pill_chip.dart apps/mobile/lib/widgets/inventory/ingredient_card.dart apps/mobile/lib/widgets/dashboard/quick_action_card.dart apps/mobile/test/widgets/shared/fk_pressable_integration_test.dart
git add -A
git commit -m "feat(motion): wire FkAnimatedPressable into shared FK primitives"
```

---

## Task 1.5: 底部导航按压反馈

`FkPill` 当前无 `onTap`（纯展示），跳过。底部导航的 `_TabButton` / `_PrimaryFab` 是高频点击点，单独接入并加触感。

**Files:**
- Modify: `apps/mobile/lib/widgets/common/bottom_nav_bar.dart:80-163`
- Test: `apps/mobile/test/widgets/common/bottom_nav_bar_test.dart`（若不存在则新建）

- [ ] **Step 1: _TabButton 接入**

Modify `apps/mobile/lib/widgets/common/bottom_nav_bar.dart`，`_TabButton.build` 内（第 99 行）`GestureDetector(onTap: onTap, behavior: HitTestBehavior.opaque, child: Padding(...))` → `FkAnimatedPressable(onTap: onTap, haptic: HapticKind.selection, child: Padding(...))`。保留外层 `Semantics`。

- [ ] **Step 2: _PrimaryFab 接入**

同文件 `_PrimaryFab.build`（第 134 行）`GestureDetector(onTap: onTap, behavior: HitTestBehavior.opaque, child: Container(...))` → `FkAnimatedPressable(onTap: onTap, haptic: HapticKind.light, child: Container(...))`。

- [ ] **Step 3: import**

文件顶部加 `import '../shared/fk_pressable.dart';`。

- [ ] **Step 4: 写/补测试**

Create（若不存在）`apps/mobile/test/widgets/common/bottom_nav_bar_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fresh_pantry/providers/navigation_provider.dart';
import 'package:fresh_pantry/widgets/common/bottom_nav_bar.dart';
import 'package:fresh_pantry/widgets/shared/fk_pressable.dart';

void main() {
  testWidgets('tapping a tab updates navigationProvider', (tester) async {
    await tester.pumpWidget(const ProviderScope(
      child: MaterialApp(home: Scaffold(bottomNavigationBar: BottomNavBar())),
    ));
    expect(find.byType(FkAnimatedPressable), findsWidgets);

    await tester.tap(find.text('食材'));
    await tester.pumpAndSettle();

    final container = ProviderScope.containerOf(
      tester.element(find.byType(BottomNavBar)),
    );
    expect(container.read(navigationProvider), FkTab.fridge);
  });
}
```

- [ ] **Step 5: 跑测试**

Run: `cd apps/mobile && flutter test -j 1 test/widgets/common/bottom_nav_bar_test.dart`
Expected: PASS。

- [ ] **Step 6: 格式化 + commit**

```bash
dart format apps/mobile/lib/widgets/common/bottom_nav_bar.dart apps/mobile/test/widgets/common/bottom_nav_bar_test.dart
git add -A
git commit -m "feat(motion): add press+haptic to bottom nav tabs and FAB"
```

---

## Task 1.6: 路由转场扫荡（MaterialPageRoute → fkRoute）

**Files:**
- Modify: 所有含 `MaterialPageRoute` 的业务文件（保留 `app.dart` 的 `onGenerateRoute` 用 `MaterialPageRoute` 不动——那是 deep-link 入口，非页内导航）。
- Test: 复用现有导航测试。

- [ ] **Step 1: 定位全部调用点**

Run: `cd apps/mobile && grep -rn "MaterialPageRoute" lib/ | grep -v "lib/app.dart"`
记录每个文件:行。预期含 `ingredient_detail_screen` / `recipe_detail_screen` / `recipes_screen` / `dashboard_screen` / `add_ingredient_screen` / `settings_screen` / `custom_recipe_form_screen` / `low_stock_screen` / `expiring_screen` / `inventory_screen` / `household_screen` / `shopping_list_screen` / `my_recipes_screen` 等。

- [ ] **Step 2: 逐文件替换**

对每个调用点，把
```dart
Navigator.of(context).push(MaterialPageRoute(builder: (_) => const FooScreen()))
```
改为
```dart
Navigator.of(context).push(fkRoute<void>(builder: (_) => const FooScreen()))
```
（保留原泛型/`fullscreenDialog` 语义；若原 `push<Result>` 带返回值，用 `fkRoute<Result>`）。每个文件顶部加 `import '../utils/page_transitions.dart';`（按相对深度调整）。

- [ ] **Step 3: 确认无遗漏**

Run: `cd apps/mobile && grep -rn "MaterialPageRoute" lib/ | grep -v "lib/app.dart"`
Expected: 无输出（仅 `app.dart` 保留）。

- [ ] **Step 4: analyze + 全量 widget 测试**

```bash
cd apps/mobile && flutter analyze && flutter test -j 1 test/
```
Expected: analyze 0 issue；测试全 PASS（导航类测试用 `pumpAndSettle` 仍能找到目标页）。

- [ ] **Step 5: 格式化改动文件 + commit**

```bash
# 用 git diff --name-only 收集改动的 lib 文件后 dart format
cd apps/mobile && dart format $(git diff --name-only --diff-filter=d -- '*.dart')
git add -A
git commit -m "feat(motion): route all in-app pushes through fkRoute"
```

---

## Task 1.7: 零散 Animated* 时长迁移到 token

把现有 6 处硬编码动画时长换成 `AppDuration`，曲线换成 `AppMotionCurves`。

**Files:**
- Modify: `apps/mobile/lib/screens/low_stock_screen.dart`（checkbox `AnimatedContainer` 150ms → `AppDuration.normal`）
- Modify: `apps/mobile/lib/widgets/common/swipe_reveal_delete_action.dart`（snap 动画时长）
- Modify: `apps/mobile/lib/widgets/common/category_chips.dart`（选中 120ms → `AppDuration.fast`）
- Modify: `apps/mobile/lib/widgets/shopping/shopping_item_tile.dart`（勾选 `AnimatedOpacity` 200ms → `AppDuration.slow`）
- Modify: `apps/mobile/lib/widgets/recipe_form/ai_collapsible_banner.dart`（折叠 `AnimatedRotation/Size`）
- Modify: `apps/mobile/lib/screens/add_ingredient_screen.dart`（对应 `Animated*`）

- [ ] **Step 1: 逐处替换**

对每个文件，将 `Duration(milliseconds: NNN)` 形参换成最接近的 `AppDuration.*`（120→fast, 150/180→normal, 200/250→slow），将内联 `Curves.*` 换成 `AppMotionCurves.standard`（折叠类）或保持原 `easeOutCubic`（等价 standard）。每个文件确保已 import `app_theme.dart`（多数已有）。

映射建议：
- `low_stock_screen.dart` checkbox `AnimatedContainer`: `duration: AppDuration.normal`。
- `category_chips.dart`: `duration: AppDuration.fast`。
- `shopping_item_tile.dart`: `duration: AppDuration.slow`。
- `swipe_reveal_delete_action.dart` / `ai_collapsible_banner.dart` / `add_ingredient_screen.dart`: 就近映射，曲线统一 `AppMotionCurves.standard`。

- [ ] **Step 2: 确认无残留魔法时长**

Run: `cd apps/mobile && grep -rn "Duration(milliseconds:" lib/widgets/common/category_chips.dart lib/widgets/shopping/shopping_item_tile.dart lib/screens/low_stock_screen.dart`
Expected: 这些动画点不再出现裸毫秒（除非语义非动画，如 debounce）。

- [ ] **Step 3: 测试**

```bash
cd apps/mobile && flutter test -j 1 test/screens/low_stock_screen_test.dart test/widgets/ && flutter analyze
```
Expected: PASS + analyze clean。

- [ ] **Step 4: 格式化 + commit**

```bash
cd apps/mobile && dart format $(git diff --name-only --diff-filter=d -- '*.dart')
git add -A
git commit -m "refactor(motion): migrate ad-hoc animation durations to AppDuration"
```

---

## 阶段 1 收尾验证

- [ ] Run: `cd apps/mobile && flutter analyze`（0 issue）
- [ ] Run: `cd apps/mobile && flutter test -j 1 test/`（全 PASS）
- [ ] 人工冒烟（可选）：`flutter run`，点击底栏 tab（有触感+缩放）、进入任一详情页（上移淡入转场）。

---

# 阶段 2 · 列表入场 + 加载态

> 依赖阶段 1 的 `app_motion.dart`。产出后即可独立合并。

## Task 2.1: 入场动画 `FkEntrance`

**Files:**
- Create: `apps/mobile/lib/widgets/shared/fk_entrance.dart`
- Test: `apps/mobile/test/widgets/shared/fk_entrance_test.dart`

- [ ] **Step 1: 写失败测试**

Create `apps/mobile/test/widgets/shared/fk_entrance_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fresh_pantry/widgets/shared/fk_entrance.dart';

void main() {
  testWidgets('fades and settles to full opacity', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: FkEntrance(index: 0, child: Text('item')),
      ),
    ));
    // 起始未完全可见
    await tester.pump();
    final opacityStart = tester
        .widget<Opacity>(find.byType(Opacity))
        .opacity;
    expect(opacityStart, lessThan(1.0));

    await tester.pumpAndSettle();
    final opacityEnd =
        tester.widget<Opacity>(find.byType(Opacity)).opacity;
    expect(opacityEnd, 1.0);
    expect(find.text('item'), findsOneWidget);
  });

  testWidgets('reduce-motion renders final state immediately', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(disableAnimations: true),
        child: Scaffold(body: FkEntrance(index: 3, child: Text('item'))),
      ),
    ));
    await tester.pump();
    expect(find.text('item'), findsOneWidget);
    // 不应有待结算的动画
    expect(tester.binding.hasScheduledFrame, isFalse);
  });
}
```

- [ ] **Step 2: 跑测试确认失败**

Run: `cd apps/mobile && flutter test -j 1 test/widgets/shared/fk_entrance_test.dart`
Expected: FAIL（未定义）。

- [ ] **Step 3: 写实现**

Create `apps/mobile/lib/widgets/shared/fk_entrance.dart`:

```dart
import 'dart:async';

import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';

/// 列表/网格元素入场 —— 淡入 + 上移,按 [index] 交错。
///
/// 一次性:每个实例只播一次,不随滚动重放。reduce-motion 时直接渲染终态。
/// 交错延迟 = min(index, [AppMotion.staggerMaxItems]) × [AppMotion.staggerStep]。
class FkEntrance extends StatefulWidget {
  const FkEntrance({
    super.key,
    required this.child,
    this.index = 0,
    this.duration,
  });

  final Widget child;
  final int index;
  final Duration? duration;

  @override
  State<FkEntrance> createState() => _FkEntranceState();
}

class _FkEntranceState extends State<FkEntrance> {
  double _t = 0; // 0 = 入场前, 1 = 完成
  Timer? _timer;
  bool _scheduled = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_scheduled) return;
    _scheduled = true;
    if (MediaQuery.disableAnimationsOf(context)) {
      _t = 1;
      return;
    }
    final steps = widget.index.clamp(0, AppMotion.staggerMaxItems);
    final delay = AppMotion.staggerStep * steps;
    _timer = Timer(delay, () {
      if (mounted) setState(() => _t = 1);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.disableAnimationsOf(context)) return widget.child;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: _t),
      duration: widget.duration ?? AppDuration.slow,
      curve: AppMotionCurves.standard,
      builder: (context, value, child) => Opacity(
        opacity: value,
        child: Transform.translate(
          offset: Offset(0, AppMotion.entranceOffset * (1 - value)),
          child: child,
        ),
      ),
      child: widget.child,
    );
  }
}
```

- [ ] **Step 4: 跑测试确认通过**

Run: `cd apps/mobile && flutter test -j 1 test/widgets/shared/fk_entrance_test.dart`
Expected: PASS（2 tests）。

- [ ] **Step 5: 格式化 + commit**

```bash
dart format apps/mobile/lib/widgets/shared/fk_entrance.dart apps/mobile/test/widgets/shared/fk_entrance_test.dart
git add -A
git commit -m "feat(motion): add FkEntrance staggered fade-up primitive"
```

---

## Task 2.2: Shimmer + Skeleton 原语

**Files:**
- Create: `apps/mobile/lib/widgets/shared/fk_shimmer.dart`
- Create: `apps/mobile/lib/widgets/shared/fk_skeleton.dart`
- Test: `apps/mobile/test/widgets/shared/fk_shimmer_test.dart`

- [ ] **Step 1: 写失败测试**

Create `apps/mobile/test/widgets/shared/fk_shimmer_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fresh_pantry/widgets/shared/fk_shimmer.dart';
import 'package:fresh_pantry/widgets/shared/fk_skeleton.dart';

void main() {
  testWidgets('shimmer renders child and animates without crashing',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: FkShimmer(
          child: FkSkeletonBox(width: 100, height: 20),
        ),
      ),
    ));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(FkSkeletonBox), findsOneWidget);
    // 主动停止动画,避免遗留计时器
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('reduce-motion shows static skeleton (settles)', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(disableAnimations: true),
        child: Scaffold(body: FkShimmer(child: FkSkeletonLine(width: 80))),
      ),
    ));
    await tester.pumpAndSettle(); // reduce-motion 下无限循环被禁用,可结算
    expect(find.byType(FkSkeletonLine), findsOneWidget);
  });
}
```

- [ ] **Step 2: 跑测试确认失败**

Run: `cd apps/mobile && flutter test -j 1 test/widgets/shared/fk_shimmer_test.dart`
Expected: FAIL（未定义）。

- [ ] **Step 3: 写 skeleton 积木**

Create `apps/mobile/lib/widgets/shared/fk_skeleton.dart`:

```dart
import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';

/// 骨架占位块 —— 配合 [FkShimmer] 使用。
class FkSkeletonBox extends StatelessWidget {
  const FkSkeletonBox({
    super.key,
    this.width,
    this.height = 16,
    this.radius = AppRadius.sm,
  });

  final double? width;
  final double height;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(radius),
      ),
    );
  }
}

/// 单行文本骨架(高度贴近正文行高)。
class FkSkeletonLine extends StatelessWidget {
  const FkSkeletonLine({super.key, this.width, this.height = 12});

  final double? width;
  final double height;

  @override
  Widget build(BuildContext context) =>
      FkSkeletonBox(width: width, height: height, radius: AppRadius.xs);
}
```

- [ ] **Step 4: 写 shimmer**

Create `apps/mobile/lib/widgets/shared/fk_shimmer.dart`:

```dart
import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';

/// 微光扫掠 —— 给骨架 [child] 叠一层左右移动的高光渐变。
///
/// reduce-motion 时不循环,仅渲染静态骨架(也让 pumpAndSettle 能结算)。
class FkShimmer extends StatefulWidget {
  const FkShimmer({super.key, required this.child});

  final Widget child;

  @override
  State<FkShimmer> createState() => _FkShimmerState();
}

class _FkShimmerState extends State<FkShimmer>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: AppDuration.shimmer,
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.disableAnimationsOf(context)) {
      _controller.stop();
      return widget.child;
    }
    if (!_controller.isAnimating) _controller.repeat();

    return AnimatedBuilder(
      animation: _controller,
      child: widget.child,
      builder: (context, child) {
        final t = _controller.value; // 0..1
        return ShaderMask(
          blendMode: BlendMode.srcATop,
          shaderCallback: (bounds) {
            final dx = bounds.width * (t * 2 - 1); // -w..+w
            return LinearGradient(
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
              colors: [
                AppColors.surfaceContainerHigh,
                AppColors.surfaceBright.withValues(alpha: 0.6),
                AppColors.surfaceContainerHigh,
              ],
              stops: const [0.35, 0.5, 0.65],
              transform: _SlideGradient(dx / bounds.width),
            ).createShader(bounds);
          },
          child: child,
        );
      },
    );
  }
}

/// 把渐变沿 X 平移 [fraction]（-1..1）个宽度。
class _SlideGradient extends GradientTransform {
  const _SlideGradient(this.fraction);
  final double fraction;

  @override
  Matrix4? transform(Rect bounds, {TextDirection? textDirection}) =>
      Matrix4.translationValues(bounds.width * fraction, 0, 0);
}
```

- [ ] **Step 5: 跑测试确认通过**

Run: `cd apps/mobile && flutter test -j 1 test/widgets/shared/fk_shimmer_test.dart`
Expected: PASS（2 tests）。

- [ ] **Step 6: 格式化 + commit**

```bash
dart format apps/mobile/lib/widgets/shared/fk_shimmer.dart apps/mobile/lib/widgets/shared/fk_skeleton.dart apps/mobile/test/widgets/shared/fk_shimmer_test.dart
git add -A
git commit -m "feat(motion): add FkShimmer + FkSkeleton loading primitives"
```

---

## Task 2.3: 骨架卡组件 + 替换裸 spinner（首页推荐菜谱）

**Files:**
- Create: `apps/mobile/lib/widgets/shared/recipe_skeleton_card.dart`
- Modify: `apps/mobile/lib/screens/dashboard_screen.dart`（推荐菜谱 `CircularProgressIndicator` → 骨架）
- Test: `apps/mobile/test/widgets/shared/recipe_skeleton_card_test.dart`

- [ ] **Step 1: 写骨架卡 + 测试**

Create `apps/mobile/lib/widgets/shared/recipe_skeleton_card.dart`:

```dart
import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import 'fk_shimmer.dart';
import 'fk_skeleton.dart';

/// RecipeCard 形状的骨架占位(图 + 标题 + 两行描述 + meta)。
class RecipeSkeletonCard extends StatelessWidget {
  const RecipeSkeletonCard({super.key});

  @override
  Widget build(BuildContext context) {
    return FkShimmer(
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.surfaceContainerLowest,
          borderRadius: BorderRadius.circular(AppRadius.xl),
          boxShadow: const [
            BoxShadow(
              color: AppColors.shadowSoft,
              blurRadius: 12,
              offset: Offset(0, 4),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(
              width: 110,
              height: 96,
              child: FkSkeletonBox(radius: 0, height: 96),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.md),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: const [
                    FkSkeletonLine(width: 140, height: 16),
                    SizedBox(height: AppSpacing.sm),
                    FkSkeletonLine(width: double.infinity),
                    SizedBox(height: AppSpacing.xs),
                    FkSkeletonLine(width: 180),
                    SizedBox(height: AppSpacing.sm),
                    FkSkeletonLine(width: 90),
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
```

Create `apps/mobile/test/widgets/shared/recipe_skeleton_card_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fresh_pantry/widgets/shared/recipe_skeleton_card.dart';

void main() {
  testWidgets('renders without overflow under reduce-motion', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(disableAnimations: true),
        child: Scaffold(
          body: Padding(
            padding: EdgeInsets.all(16),
            child: RecipeSkeletonCard(),
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.byType(RecipeSkeletonCard), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
```

- [ ] **Step 2: 跑骨架卡测试**

Run: `cd apps/mobile && flutter test -j 1 test/widgets/shared/recipe_skeleton_card_test.dart`
Expected: PASS。

- [ ] **Step 3: 替换 dashboard 推荐菜谱 spinner**

Modify `apps/mobile/lib/screens/dashboard_screen.dart`：定位推荐菜谱 section 的 loading 分支（`recipesFetchProvider` / `AsyncValue` 的 `loading:` 或 `CircularProgressIndicator`，约第 266-272 行），把 spinner 换成 1-2 张 `RecipeSkeletonCard`（与正常卡同宽、同间距）。import 加 `import '../widgets/shared/recipe_skeleton_card.dart';`。

示例（按现有结构套用）：
```dart
loading: () => const Column(
  children: [
    RecipeSkeletonCard(),
    SizedBox(height: AppSpacing.md),
    RecipeSkeletonCard(),
  ],
),
```

- [ ] **Step 4: dashboard 测试（reduce-motion override）**

Run: `cd apps/mobile && flutter test -j 1 test/screens/dashboard_screen_test.dart`
Expected: PASS。若该测试 pump loading 态，确保 wrap 在 `MediaQuery(disableAnimations: true)` 或用 `tester.pump(duration)` 不依赖 `pumpAndSettle` 结算 shimmer。

- [ ] **Step 5: 格式化 + commit**

```bash
dart format apps/mobile/lib/widgets/shared/recipe_skeleton_card.dart apps/mobile/lib/screens/dashboard_screen.dart apps/mobile/test/widgets/shared/recipe_skeleton_card_test.dart
git add -A
git commit -m "feat(motion): skeleton card for dashboard recipe loading"
```

---

## Task 2.4: 其余加载态 spinner → skeleton

**Files:**
- Modify: `apps/mobile/lib/screens/recipes_screen.dart`（列表 loading）
- Modify: `apps/mobile/lib/screens/recipe_detail_screen.dart`（步骤/食材 loading）
- Modify: `apps/mobile/lib/widgets/shared/fk_image_placeholder.dart`（图片占位用 shimmer）
- Modify: `apps/mobile/lib/widgets/shared/ai_busy_overlay.dart`（保留 spinner 但底层加 shimmer 提示，或不动——见下）
- Test: 复用各屏现有测试

- [ ] **Step 1: recipes_screen 列表骨架**

Modify `apps/mobile/lib/screens/recipes_screen.dart`：loading 分支渲染 3-4 张 `RecipeSkeletonCard`（替换原 spinner / `_RecipeSkeletonCard` 若已有占位则套 `FkShimmer`）。

- [ ] **Step 2: recipe_detail 步骤骨架**

Modify `apps/mobile/lib/screens/recipe_detail_screen.dart`：详情加载分支用 `FkShimmer` + `FkSkeletonLine` 拼几行步骤占位，替换 spinner。

- [ ] **Step 3: fk_image_placeholder shimmer**

Modify `apps/mobile/lib/widgets/shared/fk_image_placeholder.dart`：把静态占位底色包一层 `FkShimmer`（reduce-motion 下自动静态）。

- [ ] **Step 4: ai_busy_overlay 评估**

查看 `ai_busy_overlay.dart`：AI 处理是不确定时长的全屏遮罩，spinner 语义恰当，**保持 spinner**，仅确认其颜色用 `AppColors.primary`。不强行换 skeleton（YAGNI）。

- [ ] **Step 5: analyze + 测试**

```bash
cd apps/mobile && flutter analyze && flutter test -j 1 test/screens/recipes_screen_test.dart test/screens/recipe_detail_screen_test.dart test/widgets/
```
Expected: PASS。loading 态测试避免 `pumpAndSettle` 卡 shimmer（用 reduce-motion override 或定时 pump）。

- [ ] **Step 6: 格式化 + commit**

```bash
cd apps/mobile && dart format $(git diff --name-only --diff-filter=d -- '*.dart')
git add -A
git commit -m "feat(motion): roll skeleton/shimmer across recipe + image loaders"
```

---

## Task 2.5: 列表入场接入（有界列表）

把 `FkEntrance` 包到首屏/有界列表的元素上。**仅限不随滚动重建的有界场景**，避免长列表抖动。

**Files:**
- Modify: `apps/mobile/lib/screens/dashboard_screen.dart`（分类网格 / 临期轮播 / 迷你数据行）
- Modify: `apps/mobile/lib/screens/shopping_list_screen.dart`（分组）
- Modify: `apps/mobile/lib/screens/intake_review_screen.dart` / `deduction_review_screen.dart`（提案行）
- Modify: `apps/mobile/lib/widgets/common/search_overlay.dart`（结果项）
- Test: 复用现有屏测试 + 新增 1 个 entrance smoke

- [ ] **Step 1: 通用接入方式**

对每个有界列表的 `itemBuilder` / `children.map`，把元素包成：
```dart
FkEntrance(index: i, child: <原元素>)
```
其中 `i` 为该元素在当前批次的序号。

- [ ] **Step 2: dashboard 三处**

`_CategoryGrid` 网格项、临期轮播项、迷你数据行各包 `FkEntrance(index: ...)`。import 加 `import '../widgets/shared/fk_entrance.dart';`。

- [ ] **Step 3: shopping / review / search**

各列表项同法包裹（注意 Review 行有勾选交互，`FkEntrance` 只管入场不拦截点击）。

- [ ] **Step 4: analyze + 测试**

```bash
cd apps/mobile && flutter analyze && flutter test -j 1 test/screens/ test/widgets/common/
```
Expected: PASS。屏测试若用 `pumpAndSettle`，`FkEntrance` 是有限动画可正常结算。

- [ ] **Step 5: 格式化 + commit**

```bash
cd apps/mobile && dart format $(git diff --name-only --diff-filter=d -- '*.dart')
git add -A
git commit -m "feat(motion): staggered entrance on bounded lists"
```

---

## 阶段 2 收尾验证

- [ ] `cd apps/mobile && flutter analyze`（0 issue）
- [ ] `cd apps/mobile && flutter test -j 1 test/`（全 PASS）
- [ ] 冒烟（可选）：进入菜谱列表看骨架→内容；首页打开看分类网格交错入场。

---

# 阶段 3 · Hero 连续 + 状态反馈

> 依赖阶段 1（`fkRoute` 配合 Hero）。产出后即可独立合并。

## Task 3.1: 菜谱卡 → 详情 Hero 图片连续

**Files:**
- Modify: `apps/mobile/lib/widgets/recipe_card.dart`（封面图包 `Hero`）
- Modify: `apps/mobile/lib/screens/recipe_detail_screen.dart`（头图包同 tag `Hero`）
- Test: `apps/mobile/test/widgets/recipe_hero_test.dart`

- [ ] **Step 1: 写失败测试**

Create `apps/mobile/test/widgets/recipe_hero_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fresh_pantry/models/recipe.dart';
import 'package:fresh_pantry/widgets/recipe_card.dart';

void main() {
  testWidgets('recipe card cover image is wrapped in a Hero', (tester) async {
    // Recipe 真实必填字段(见 lib/models/recipe.dart:100-135):
    // id / name / category / difficulty(int) / cookingMinutes(int) /
    // description / ingredients / steps / tags / remoteVersion;imageUrl 可空。
    const recipe = Recipe(
      id: 'r1',
      name: '番茄炒蛋',
      category: '家常',
      difficulty: 1,
      cookingMinutes: 10,
      description: '家常菜',
      ingredients: [],
      steps: [],
      tags: [],
      imageUrl: 'https://example.com/x.jpg',
      remoteVersion: 0,
    );
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: RecipeCard(recipe: recipe)),
    ));
    final hero = tester.widget<Hero>(find.byType(Hero));
    expect(hero.tag, 'recipe-image-r1');
  });
}
```

> 注：`Recipe` 构造若有调整以 `lib/models/recipe.dart` 为准；可参考现有测试里的 Recipe fixture。`const` 取决于构造器是否 const，若非 const 去掉关键字。

- [ ] **Step 2: 跑测试确认失败**

Run: `cd apps/mobile && flutter test -j 1 test/widgets/recipe_hero_test.dart`
Expected: FAIL（无 Hero）。

- [ ] **Step 3: recipe_card 加 Hero**

Modify `apps/mobile/lib/widgets/recipe_card.dart`：封面图在 `_Cover` 组件内（第 186-204 行的 `ClipRRect` + `RecipeImage`）。`_Cover` 当前只接 `recipe` + `useExpiring`，需把封面图区域包进 `Hero`。把 `_Cover.build`（第 181 行起）的 `ClipRRect(... child: RecipeImage(imageSource: recipe.imageUrl, ...))` 包成：

```dart
Hero(
  tag: 'recipe-image-${recipe.id}',
  child: ClipRRect(
    borderRadius: const BorderRadius.only(
      topLeft: Radius.circular(AppRadius.xl),
      bottomLeft: Radius.circular(AppRadius.xl),
    ),
    child: RecipeImage(
      imageSource: recipe.imageUrl,
      fit: BoxFit.cover,
      fallback: Container(
        color: AppColors.primarySoft,
        alignment: Alignment.center,
        child: const Icon(Icons.restaurant_rounded,
            size: 32, color: AppColors.primary),
      ),
    ),
  ),
)
```

注意：`RecipeImage` 参数是 `imageSource:`（非 `imageUrl:`）且 `fallback:` 必填——保持现有调用不变，仅外层加 `Hero`。`Recipe.id` 字段已存在（recipe.dart:100）。

- [ ] **Step 4: recipe_detail 加同 tag Hero**

Modify `apps/mobile/lib/screens/recipe_detail_screen.dart`：头图在 `_HeroSection`（第 302-303 行 `RecipeImage(imageSource: recipe.imageUrl, ...)`）。用 `Hero(tag: 'recipe-image-${recipe.id}', child: <该 RecipeImage 或其 Clip 容器>)` 包裹。`recipe.id` 在该屏为 `widget.recipe.id`，与卡片一致。

- [ ] **Step 5: 跑测试 + 导航冒烟测试**

Run: `cd apps/mobile && flutter test -j 1 test/widgets/recipe_hero_test.dart test/screens/recipe_detail_screen_test.dart`
Expected: PASS。

- [ ] **Step 6: 格式化 + commit**

```bash
dart format apps/mobile/lib/widgets/recipe_card.dart apps/mobile/lib/screens/recipe_detail_screen.dart apps/mobile/test/widgets/recipe_hero_test.dart
git add -A
git commit -m "feat(motion): hero image continuity for recipe card to detail"
```

---

## Task 3.2: 食材卡 → 详情 Hero（带 tag 唯一性保护）

**Files:**
- Modify: `apps/mobile/lib/widgets/inventory/ingredient_card.dart`
- Modify: `apps/mobile/lib/screens/ingredient_detail_screen.dart`
- Test: `apps/mobile/test/widgets/ingredient_hero_test.dart`

- [ ] **Step 1: 选定唯一 tag 来源**

食材 `Ingredient.id` 本地可能为空（见项目 identity 不变量）。改用稳定且单屏唯一的 key：`'ingredient-image-${ingredient.name}-${ingredient.storageArea.name}'`（必要时再拼 batch）。**若同屏可能重复**（理论上身份唯一，但防御性），用一个 `Set` 跟踪已用 tag，重复则回退不加 Hero。简化做法：仅在库存网格这种身份唯一场景启用，tag 用上面的复合键。

- [ ] **Step 2: ingredient_card 加 Hero**

Modify `apps/mobile/lib/widgets/inventory/ingredient_card.dart`：把卡片内的 `CategoryIcon` / 图标区包成
```dart
Hero(
  tag: 'ingredient-image-${ingredient.name}-${ingredient.storageArea.name}',
  child: <原图标 widget>,
)
```

- [ ] **Step 3: ingredient_detail 加同 tag Hero**

Modify `apps/mobile/lib/screens/ingredient_detail_screen.dart`：详情头部图标用同 tag `Hero` 包裹。

- [ ] **Step 4: 写测试**

Create `apps/mobile/test/widgets/ingredient_hero_test.dart`，断言 `IngredientCard` 含 `Hero` 且 tag 以 `ingredient-image-` 开头（构造 `Ingredient` 按真实签名）。

- [ ] **Step 5: 测试**

Run: `cd apps/mobile && flutter test -j 1 test/widgets/ingredient_hero_test.dart test/screens/`（含 inventory/ingredient_detail 相关）
Expected: PASS（无重复 tag 异常）。

- [ ] **Step 6: 格式化 + commit**

```bash
dart format apps/mobile/lib/widgets/inventory/ingredient_card.dart apps/mobile/lib/screens/ingredient_detail_screen.dart apps/mobile/test/widgets/ingredient_hero_test.dart
git add -A
git commit -m "feat(motion): hero image continuity for ingredient card to detail"
```

---

## Task 3.3: 勾选状态反馈（缩放回弹 + 触感）

把清单/低库存/Review/库存多选的勾选圈用一个共享的勾选动画组件统一。

**Files:**
- Create: `apps/mobile/lib/widgets/shared/fk_check_circle.dart`
- Modify: `apps/mobile/lib/screens/low_stock_screen.dart`（`_CheckCircle` → `FkCheckCircle`）
- Modify: `apps/mobile/lib/widgets/shopping/shopping_item_tile.dart`（勾选圈）
- Test: `apps/mobile/test/widgets/shared/fk_check_circle_test.dart`

- [ ] **Step 1: 写失败测试**

Create `apps/mobile/test/widgets/shared/fk_check_circle_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fresh_pantry/widgets/shared/fk_check_circle.dart';

void main() {
  testWidgets('toggles and reports tap', (tester) async {
    var checked = false;
    await tester.pumpWidget(MaterialApp(
      home: StatefulBuilder(
        builder: (context, setState) => Scaffold(
          body: Center(
            child: FkCheckCircle(
              checked: checked,
              onTap: () => setState(() => checked = !checked),
            ),
          ),
        ),
      ),
    ));
    expect(find.byIcon(Icons.check_rounded), findsNothing);
    await tester.tap(find.byType(FkCheckCircle));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.check_rounded), findsOneWidget);
  });
}
```

- [ ] **Step 2: 跑测试确认失败**

Run: `cd apps/mobile && flutter test -j 1 test/widgets/shared/fk_check_circle_test.dart`
Expected: FAIL。

- [ ] **Step 3: 写 FkCheckCircle**

Create `apps/mobile/lib/widgets/shared/fk_check_circle.dart`:

```dart
import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import 'fk_pressable.dart';

/// 统一勾选圈 —— 选中填充 + 勾,按压缩放,带选择触感。
class FkCheckCircle extends StatelessWidget {
  const FkCheckCircle({
    super.key,
    required this.checked,
    required this.onTap,
    this.size = 28,
  });

  final bool checked;
  final VoidCallback onTap;
  final double size;

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    return FkAnimatedPressable(
      onTap: onTap,
      haptic: HapticKind.selection,
      child: AnimatedContainer(
        duration: reduceMotion ? Duration.zero : AppDuration.normal,
        curve: AppMotionCurves.standard,
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: checked ? AppColors.primary : Colors.transparent,
          shape: BoxShape.circle,
          border: Border.all(
            color: checked ? AppColors.primary : AppColors.outline,
            width: 2,
          ),
        ),
        alignment: Alignment.center,
        child: checked
            ? Icon(Icons.check_rounded,
                size: size * 0.6, color: AppColors.onPrimary)
            : null,
      ),
    );
  }
}
```

- [ ] **Step 4: 跑测试确认通过**

Run: `cd apps/mobile && flutter test -j 1 test/widgets/shared/fk_check_circle_test.dart`
Expected: PASS。

- [ ] **Step 5: 接入 low_stock + shopping_item_tile**

Modify `low_stock_screen.dart`：把内部 `_CheckCircle`（约 267-291 行）替换为 `FkCheckCircle(checked: ..., onTap: ...)`，删除旧私有组件。
Modify `shopping_item_tile.dart`：勾选圈替换为 `FkCheckCircle`，保留原 `AnimatedOpacity` 文本删除线效果（不冲突）。
两文件 import 加 `fk_check_circle.dart`。

- [ ] **Step 6: 测试**

Run: `cd apps/mobile && flutter test -j 1 test/screens/low_stock_screen_test.dart test/screens/shopping_list_screen_test.dart test/widgets/`
Expected: PASS（含工作区 WIP 的 shopping 测试）。

- [ ] **Step 7: 格式化 + commit**

```bash
cd apps/mobile && dart format $(git diff --name-only --diff-filter=d -- '*.dart') test/widgets/shared/fk_check_circle_test.dart
git add -A
git commit -m "feat(motion): unified FkCheckCircle with scale+haptic feedback"
```

---

## Task 3.4: 卡片进度条挂载填充 + 步骤完成过渡

> 注：`freshness_meter.dart`（`FreshnessMeter` / `GradientFreshnessMeter`）只用于 add_ingredient 表单（add_ingredient_screen.dart:917），**不**用于列表卡片。卡片的新鲜度条是 `ingredient_card.dart:124-139` 与 `recipe_card.dart:128-144` 的内联 `FractionallySizedBox`。挂载填充动画落在这两处内联条。

**Files:**
- Modify: `apps/mobile/lib/widgets/inventory/ingredient_card.dart:124-139`（0→目标填充）
- Modify: `apps/mobile/lib/widgets/recipe_card.dart:128-144`（匹配进度条 0→目标填充）
- Modify: `apps/mobile/lib/screens/recipe_detail_screen.dart`（步骤完成淡出 + 删除线）
- Modify: `apps/mobile/lib/widgets/common/sync_status_banner.dart`（滑入）
- Test: `apps/mobile/test/widgets/inventory/ingredient_card_fill_test.dart`

- [ ] **Step 1: ingredient_card / recipe_card 进度条挂载动画**

两处都是 `FractionallySizedBox(widthFactor: <ratio>, ...)`。把 `widthFactor` 用 `TweenAnimationBuilder<double>` 驱动 0→目标，reduce-motion 时直接用终值：

```dart
final reduceMotion = MediaQuery.disableAnimationsOf(context);
// ...进度条:
TweenAnimationBuilder<double>(
  tween: Tween(begin: 0, end: progress.clamp(0.05, 1.0)),
  duration: reduceMotion ? Duration.zero : AppDuration.slow,
  curve: AppMotionCurves.standard,
  builder: (context, w, _) => FractionallySizedBox(
    alignment: Alignment.centerLeft,
    widthFactor: w,
    child: Container(
      decoration: BoxDecoration(
        color: progressColor,
        borderRadius: BorderRadius.circular(AppRadius.xs),
      ),
    ),
  ),
)
```
（`recipe_card` 用其 `ratio`，注意 ingredient_card 的 `build` 是无 `BuildContext` 直取问题——它本就有 `build(BuildContext context)`，可直接用 `context`。）

- [ ] **Step 2: 写填充测试**

Create `apps/mobile/test/widgets/inventory/ingredient_card_fill_test.dart`：pump `IngredientCard`（构造真实 `Ingredient`，参考现有 ingredient_card 测试 fixture），`pumpAndSettle` 后断言含 `FractionallySizedBox` 且 `widthFactor > 0`；reduce-motion override 下首帧即为终值。

- [ ] **Step 3: 步骤完成过渡**

Modify `apps/mobile/lib/screens/recipe_detail_screen.dart`（约 724-791 行步骤行）：完成态文本用 `AnimatedDefaultTextStyle(duration: AppDuration.normal, ...)` 切换颜色 `onSurface → onSurfaceVariant` 并加 `decoration: TextStyle(decoration: TextDecoration.lineThrough)`，替代瞬切。完成切换时 `HapticFeedback.selectionClick()`。

- [ ] **Step 4: sync banner 滑入**

Modify `apps/mobile/lib/widgets/common/sync_status_banner.dart`：横幅出现用 `AnimatedSize` 或 `SlideTransition` 从顶部滑入（约 16-53 行）。**保留** `syncBannerTestOverrides` 兼容（测试里横幅常被 override 掉，确保动画不破坏该路径）。

- [ ] **Step 5: 测试**

Run: `cd apps/mobile && flutter test -j 1 test/widgets/inventory/ingredient_card_fill_test.dart test/screens/recipe_detail_screen_test.dart test/widgets/common/`
Expected: PASS。

- [ ] **Step 6: 格式化 + commit**

```bash
cd apps/mobile && dart format $(git diff --name-only --diff-filter=d -- '*.dart') test/widgets/inventory/ingredient_card_fill_test.dart
git add -A
git commit -m "feat(motion): animated card progress fill, step completion, sync banner slide"
```

---

## 阶段 3 收尾验证

- [ ] `cd apps/mobile && flutter analyze`（0 issue）
- [ ] `cd apps/mobile && flutter test -j 1 test/`（全 PASS）
- [ ] 冒烟（可选）：菜谱卡点进详情看图片飞入；勾选清单项看回弹+触感；进库存看新鲜度条填充。

---

# 阶段 4 · token 遵循扫荡（风格统一）

> 不依赖前序阶段的运行时行为，但放最后做，避免与前面改动冲突。机械性强、收益在「统一」。

## Task 4.1: 新增 `AppShadows`

**Files:**
- Create: `apps/mobile/lib/theme/app_shadows.dart`
- Modify: `apps/mobile/lib/theme/app_theme.dart`（export）
- Test: `apps/mobile/test/theme/app_shadows_test.dart`

- [ ] **Step 1: 收集现有内联 BoxShadow**

Run: `cd apps/mobile && grep -rn "BoxShadow(" lib/ | grep -v "theme/"`
记录各处 blur/offset/color，归并成 5 档。

- [ ] **Step 2: 写 token**

Create `apps/mobile/lib/theme/app_shadows.dart`:

```dart
import 'package:flutter/material.dart';

import 'app_colors.dart';

/// 阴影 token —— 收编所有内联 BoxShadow,统一 App 的高度语言。
class AppShadows {
  AppShadows._();

  /// 极轻(icon button / 小元素)。
  static const List<BoxShadow> subtle = [
    BoxShadow(color: AppColors.subtleShadow, blurRadius: 8, offset: Offset(0, 2)),
  ];

  /// 软(默认卡片,两层)。
  static const List<BoxShadow> soft = [
    BoxShadow(color: AppColors.shadowSoft, blurRadius: 2, offset: Offset(0, 1)),
    BoxShadow(color: AppColors.shadowSoft, blurRadius: 16, offset: Offset(0, 4)),
  ];

  /// 卡片(列表卡,单层略强)。
  static const List<BoxShadow> card = [
    BoxShadow(color: AppColors.shadowSoft, blurRadius: 12, offset: Offset(0, 4)),
  ];

  /// 暖投影(FAB / 强调)。
  static const List<BoxShadow> fab = [
    BoxShadow(color: AppColors.shadowWarm, blurRadius: 18, offset: Offset(0, 6)),
  ];
}
```

- [ ] **Step 3: export + 测试**

Modify `app_theme.dart` 加 `export 'app_shadows.dart';`。
Create `apps/mobile/test/theme/app_shadows_test.dart`：断言各档非空、`card` 单层、`soft` 两层。

- [ ] **Step 4: 替换内联 BoxShadow**

把 `fk_card.dart` 的 `_kDefaultShadow` 改为引用 `AppShadows.soft`；`fk_icon_button.dart:38-44` 的 `Color(0x0F000000)` 阴影 → `AppShadows.subtle`；`recipe_card.dart:31-37` → `AppShadows.card`；`recipe_skeleton_card.dart` 同步 → `AppShadows.card`；`bottom_nav_bar.dart` FAB 阴影 → `AppShadows.fab`；`dashboard_screen.dart` / `stat_card.dart` 内联阴影 → 对应档。

- [ ] **Step 5: 测试 + analyze**

Run: `cd apps/mobile && flutter test -j 1 test/theme/app_shadows_test.dart test/widgets/ && flutter analyze`
Expected: PASS。视觉等价。

- [ ] **Step 6: 格式化 + commit**

```bash
cd apps/mobile && dart format $(git diff --name-only --diff-filter=d -- '*.dart') test/theme/app_shadows_test.dart
git add -A
git commit -m "refactor(theme): add AppShadows and adopt across components"
```

---

## Task 4.2: 圆角扫荡（BorderRadius.circular → AppRadius）

**Files:**
- Modify: 含硬编码 `BorderRadius.circular(<数字>)` 的文件
- Test: 复用现有测试

- [ ] **Step 1: 定位**

Run: `cd apps/mobile && grep -rn "BorderRadius.circular(" lib/ | grep -E "circular\([0-9]" | grep -v "AppRadius"`

- [ ] **Step 2: 映射替换**

`2→AppRadius.xs` · `8→sm` · `12→md` · `14→chip` · `16→lg` · `20→xl` · `24→xxl` · `28→hero` · `999→pill`。`bottom_nav_bar.dart` 的两处 `Radius.circular(24)` → `Radius.circular(AppRadius.xxl)`。非标准值（如 18, 22）就近取最接近 token 并在该行加注释说明原值。

- [ ] **Step 3: 确认 + 测试**

Run: `cd apps/mobile && grep -rn "circular([0-9]" lib/ | grep -v AppRadius`（预期仅剩刻意保留项）
Run: `cd apps/mobile && flutter analyze && flutter test -j 1 test/`
Expected: PASS。

- [ ] **Step 4: 格式化 + commit**

```bash
cd apps/mobile && dart format $(git diff --name-only --diff-filter=d -- '*.dart')
git add -A
git commit -m "refactor(theme): sweep hardcoded radii to AppRadius"
```

---

## Task 4.3: 颜色扫荡（裸 hex / Colors.* → AppColors）

**Files:**
- Modify: `apps/mobile/lib/utils/fk_toast.dart`（绿 `0xFF5CC9A7`）
- Modify: `apps/mobile/lib/widgets/dashboard/household_chip.dart`（红 `0xFFE5484D`）
- Modify: `apps/mobile/lib/screens/dashboard_screen.dart`（绿 `0xFF1F8A70` / `0xFF2A6F5A`、琥珀 `0xFFF4A300`、`Colors.white` 簇）
- Modify: `apps/mobile/lib/theme/app_colors.dart`（补语义色）
- Test: 复用现有测试

- [ ] **Step 1: 在 AppColors 补缺失语义色**

Modify `app_colors.dart`，新增（命名贴语义，值取现有 hex）：
```dart
// 成功/积极(toast 完成态)
static const success = Color(0xFF5CC9A7);
// 危险强调(household 离线/移除)
static const dangerStrong = Color(0xFFE5484D);
// Dashboard 强调绿 / 暖琥珀(状态点缀)
static const accentGreen = Color(0xFF1F8A70);
static const accentGreenDeep = Color(0xFF2A6F5A);
static const accentAmber = Color(0xFFF4A300);
```

- [ ] **Step 2: 替换各处裸值**

`fk_toast.dart` 绿 → `AppColors.success`；`household_chip.dart` 红 → `AppColors.dangerStrong`；`dashboard_screen.dart` 绿/琥珀 → 对应 accent；`Colors.white` 在 hero 蓝底上下文 → `AppColors.onPrimary` 或 `Colors.white.withValues(...)` 保留（白本身合理，但统一成 `AppColors.surfaceBright`/`onPrimary` 语义，逐处判断）。

- [ ] **Step 3: 确认 + 测试**

Run: `cd apps/mobile && grep -rn "Color(0xFF" lib/ | grep -v "theme/app_colors.dart"`（预期大幅减少，剩余为 theme 内部）
Run: `cd apps/mobile && flutter analyze && flutter test -j 1 test/`
Expected: PASS。

- [ ] **Step 4: 格式化 + commit**

```bash
cd apps/mobile && dart format $(git diff --name-only --diff-filter=d -- '*.dart')
git add -A
git commit -m "refactor(theme): move ad-hoc color literals into AppColors semantics"
```

---

## Task 4.4: 字号扫荡（内联 fontSize → AppFontSize / textTheme）

> 量最大（~197 处）。分批做，每批一个 commit，避免巨型 diff。

**Files:**
- Modify: `ingredient_detail_screen.dart` / `dashboard_screen.dart` / `recipe_detail_screen.dart` / `settings_screen.dart` / `shopping_list_screen.dart` 等高密度文件
- Test: 复用现有测试

- [ ] **Step 1: 定位高密度文件**

Run: `cd apps/mobile && grep -rc "fontSize:" lib/ | sort -t: -k2 -rn | head -20`

- [ ] **Step 2: 分批替换（每文件或每 2-3 文件一批）**

把 `fontSize: 11/12/14/16/20/24/28/32` 映射到 `AppFontSize.xs/sm/md/lg/xl/xxl/xxxl/huge`。能整体套 `Theme.of(context).textTheme.<style>` 的优先用 textTheme（带正确字重/字体）。**仅当**无法套 textTheme（inline `TextStyle` 且字重特殊）才用 `AppFontSize.*`。非阶梯值（如 13, 22, 56）保留或映射到最近，特殊大数字用 `AppTypography.heroStat/heroSubStat/sectionTitleLg`。

- [ ] **Step 3: 每批测试 + commit**

每批后：`cd apps/mobile && flutter analyze && flutter test -j 1 test/<相关>`，然后 `dart format` 改动文件并 commit，message 如 `refactor(theme): fontSize sweep (ingredient_detail + recipe_detail)`。

- [ ] **Step 4: 收尾确认**

Run: `cd apps/mobile && grep -rn "fontSize: [0-9]" lib/ | grep -v "AppFontSize" | wc -l`
预期接近 0（剩余为刻意非阶梯值，已加注释）。

---

## Task 4.5: 间距扫荡（硬编码 EdgeInsets/SizedBox → AppSpacing）

**Files:**
- Modify: `settings_screen.dart` / `custom_recipe_form_screen.dart` / `shopping_list_screen.dart` / `dashboard_screen.dart` 等
- Test: 复用现有测试

- [ ] **Step 1: 定位**

Run: `cd apps/mobile && grep -rnE "EdgeInsets|SizedBox\((width|height)?:" lib/ | grep -E "[0-9]{1,2}" | grep -v AppSpacing | wc -l`

- [ ] **Step 2: 分批替换**

`4→xs · 8→sm · 12→md · 16→lg · 20→xl · 24→xxl · 28→xxxl · 32→huge`。非网格值（10/14/18）就近取 token 并按视觉校验；确属设计意图的保留并注释。`EdgeInsets.fromLTRB(18, ...)` 常见 → `AppSpacing.xl`（20）或 `lg`（16），按上下文选最接近且视觉无回归者。

- [ ] **Step 3: 每批测试 + commit**

每批后 `flutter analyze && flutter test -j 1 test/<相关>`，`dart format`，commit `refactor(theme): spacing sweep (<files>)`。

- [ ] **Step 4: 收尾确认**

Run: `cd apps/mobile && flutter analyze && flutter test -j 1 test/`
Expected: 全 PASS，视觉等价。

---

## Task 4.6: 收口残余不一致

**Files:**
- Modify: `apps/mobile/lib/widgets/shared/fk_pill.dart` + `pill_chip.dart`（统一 padding 口径）
- Modify: `apps/mobile/lib/screens/auth_gate_screen.dart`（输入框 filled）
- Modify: `apps/mobile/lib/screens/intake_review_screen.dart` + `deduction_review_screen.dart`（用 app_snackbar）
- Test: 复用现有测试

- [ ] **Step 1: 统一 pill padding**

让 `FkPill` 的 `padding` 改用 `EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: AppSpacing.xs)`（与 `PillChip` 口径靠拢，消除 `+2`/`-1` 魔法微调），视觉校验无明显变化后定稿。

- [ ] **Step 2: auth 输入框 filled**

Modify `auth_gate_screen.dart`：给各 `TextField` 的 `InputDecoration` 加 `filled: true, fillColor: AppColors.surfaceContainer`（或直接依赖全局 `inputDecorationTheme`，移除局部覆盖），消除下划线边框，与 FK filled 风格一致。

- [ ] **Step 3: Review 改用 app_snackbar**

Modify 两个 review 屏：把裸 `ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)))` 换成 `app_snackbar.dart` 的工具函数：
```dart
import '../utils/app_snackbar.dart';
// ...
showAppSnackBar(context, '消息文案');
```
签名：`showAppSnackBar(BuildContext context, String message, {Color? backgroundColor, Duration duration, String? actionLabel, VoidCallback? onAction, ...})`。原 SnackBar 若带 action，用 `actionLabel` + `onAction` 成对传入。

- [ ] **Step 4: 测试 + analyze**

Run: `cd apps/mobile && flutter analyze && flutter test -j 1 test/`
Expected: 全 PASS。

- [ ] **Step 5: 格式化 + commit**

```bash
cd apps/mobile && dart format $(git diff --name-only --diff-filter=d -- '*.dart')
git add -A
git commit -m "refactor(ui): unify pill padding, auth fields filled, review snackbars"
```

---

## 阶段 4 收尾验证

- [ ] `cd apps/mobile && flutter analyze`（0 issue）
- [ ] `cd apps/mobile && flutter test -j 1 test/`（全 PASS）
- [ ] `cd apps/mobile && grep -rn "Color(0xFF" lib/ | grep -v theme/`、`grep -rn "circular([0-9]" lib/ | grep -v AppRadius`、`grep -rn "fontSize: [0-9]" lib/ | grep -v AppFontSize`：均接近 0（剩余有注释）。

---

# 全计划收尾

- [ ] 全量 `cd apps/mobile && flutter analyze`（0 issue）
- [ ] 全量 `cd apps/mobile && flutter test -j 1 test/`（全 PASS）
- [ ] `git log --oneline` 复核每阶段 commit 清晰、原子。
- [ ] 工作区 WIP（dashboard/shopping/top_app_bar）仍未提交、未被本工作破坏。
- [ ] 用 `superpowers:requesting-code-review` 自审 diff（重点：无吞错、无静默 fallback、动效均 honor reduce-motion、无视觉回归）。
- [ ] 决定整合方式（`superpowers:finishing-a-development-branch`）。

---

# 风险与缓解

| 风险 | 缓解 |
|---|---|
| shimmer 无限动画卡死 `pumpAndSettle` | 所有原语 honor `disableAnimationsOf`；loading 态测试用 reduce-motion override 或定时 `pump` |
| Hero 重复 tag 崩溃 | tag 用稳定唯一键；同屏潜在重复回退无 Hero |
| token 扫荡引入视觉回归 | 每批 commit 小、可回退；映射就近且对非标准值加注释；测试全过 |
| 改动碰到工作区 WIP 文件 | dashboard/shopping/top_app_bar 已知，叠加不删 WIP；commit 前 `git status` 确认 WIP 仍在 |
| `flutter test` 并发不稳 | 一律 `-j 1` 串行 |
| 测试用 `find.byType(GestureDetector)` 失效 | 改为 `find.byType(FkAnimatedPressable)` / 具体组件类型 |
