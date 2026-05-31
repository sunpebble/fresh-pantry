# Fresh Pantry — UI / 交互 / 动效打磨设计

**日期**: 2026-05-31
**分支**: `feat/ui-polish-pass`
**目标**: 在不改动既有视觉风格（暖奶油 + 矢车菊蓝 FK 设计语言）的前提下，统一 App 的动效词汇、补齐交互/动画细节、收口 token 漂移，使整体风格统一、更有「高级感」。
**基调**: 克制·高级（restrained premium）。
**范围**: 全面升级，分 4 阶段，每阶段可独立合并与 review。

---

## 1. 背景与现状

由全仓 UI 审计（7 路并行审计 + 综合）得出的事实基线：

- **动效近乎为零**：全 `lib/` 仅 8 个文件有零散隐式动画（checkbox 填充、分类 chip 选中、滑动删除回弹、清单勾选淡出、折叠箭头），时长各写各的（120/150/180/200ms），**无统一 motion token**。
- **导航无设计感**：31 处路由全部使用裸 `MaterialPageRoute`（平台默认转场）。
- **加载态简陋**：异步状态一律 `CircularProgressIndicator`。
- **触感缺席**：全仓 **0 处 `HapticFeedback`**。
- **关键缺失**：无 `FadeTransition/SlideTransition/ScaleTransition`、无 `PageRouteBuilder`、无真正的 `Hero`（现有 "Hero" 命名只是静态渐变头）、无 shimmer/skeleton、无列表入场。
- **token 漂移**：~197 处内联 `fontSize`、95+ 处硬编码间距、24 处硬编码圆角、若干裸色值（dashboard 绿/琥珀、`fk_toast` 绿、`household_chip` 红）、内联 `BoxShadow`、两套口径不一的 pill 组件。

设计系统基础已成熟，**保留不动**：tokens 在 `theme/`（`app_colors` / `app_typography` / `app_spacing` / `app_radius` / `app_sizes`）；共享组件在 `widgets/shared/`（`fk_card` / `fk_pill` / `fk_icon_button` / `fk_hero_header` 等）；字体 Plus Jakarta Sans + Manrope；Material3、无描边、软暖阴影、StadiumBorder 按钮。

> 注：本工作基于工作区当前的「导航入口收敛」WIP（dashboard hero 去掉设置/通知按钮、清单顶部去掉 add 聚焦按钮、top bar 改推 `SettingsScreen`），在其之上叠加。

---

## 2. 贯穿设计原则

1. **统一动效词汇**：所有时长、曲线、位移、交错步长走 `app_motion.dart` token，禁止再出现散落的魔法数字。
2. **尊重「减弱动态效果」**（核心）：所有动效原语在构建时读取 `MediaQuery.disableAnimationsOf(context)`。开启系统 Reduce Motion 时，动效降级为瞬时/静态终态。
   - 这是无障碍正确性，**同时**让 widget 测试不会被无限循环动画（shimmer / 脉冲）卡死 `pumpAndSettle`。
3. **原语下沉、屏幕消费**：动效封装进 `theme/`（token）与 `widgets/shared/` + `utils/`（可复用 widget），屏幕只调用，不各自造轮子。每个原语可独立理解、独立测试。
4. **克制基调**：曲线 `easeOutCubic / easeOut`；位移幅度小（入场 8px、按压 0.97）；不使用回弹/弹簧；触感用最轻档（`selectionClick` / `lightImpact`）。
5. **不扩大范围**：不引入新依赖（全部 Flutter SDK 原语）；不改色板；不做深色模式；不做无关重构。

---

## 3. 动效 Token（`theme/app_motion.dart`，新增）

```text
AppDuration   fast 120ms · normal 180ms · slow 250ms · page 240ms · shimmer 1400ms
AppMotionCurves   standard = easeOutCubic · decelerate = easeOut · emphasized = Cubic(0.2, 0, 0, 1)
AppMotion     pressScale 0.97 · entranceOffset 8.0px · staggerStep 50ms · staggerMaxItems ~8（封顶，避免长延迟）
```

经 `app_theme.dart` 统一 `export`，与其它 token 同入口。

---

## 4. 阶段 1 · 地基（最先合并，后续阶段都依赖）

### 4.1 产物

| 产物 | 位置 | 说明 |
|---|---|---|
| `AppDuration / AppMotionCurves / AppMotion` | `theme/app_motion.dart` | §3 的 token |
| `FkAnimatedPressable` | `widgets/shared/fk_pressable.dart` | 按压缩放 + 触感包装器 |
| `fkRoute<T>()` | `utils/page_transitions.dart` | 统一页面转场 |

### 4.2 `FkAnimatedPressable` API

```text
FkAnimatedPressable({
  required Widget child,
  VoidCallback? onTap,
  VoidCallback? onLongPress,
  double pressedScale = AppMotion.pressScale,   // 0.97
  HapticKind haptic = HapticKind.selection,     // selection | light | none
  HitTestBehavior behavior = opaque,
})
```

- 实现：`GestureDetector` + `AnimatedScale`（`onTapDown` → 缩小，`onTapUp/onTapCancel` → 复原，时长 `fast`，曲线 `standard`）。无 `AnimationController`，无生命周期泄漏风险。
- reduce-motion：开启时跳过缩放，仅保留点击与触感。
- 触感：`onTapDown` 触发对应 `HapticFeedback`。

### 4.3 `fkRoute` 行为

- `PageRouteBuilder`，`transitionDuration = AppDuration.page`，曲线 `emphasized`。
- incoming：上移淡入（`SlideTransition` 从 +8% 高度 → 0 叠 `FadeTransition`）；outgoing：轻微淡出。
- 提供可选 `fullscreenDialog`/`opaque` 参数透传；保留 `RouteSettings`。
- 全量替换 31 处 `MaterialPageRoute`（高频优先：`ingredient_detail` / `recipe_detail` / `recipes` / `dashboard` / `add_ingredient` / `settings` / `custom_recipe_form`）。

### 4.4 接入点（按压反馈一处定义、全局生效）

- 共享原语内置：`FkCard`（仅当 `onTap != null`）、`FkPill`（可点时）、`FkIconButton`、`PillChip`、`QuickActionCard`。
- 高频组件：`RecipeCard`、`IngredientCard`、底部导航 `_TabButton` / `_PrimaryFab`、顶栏图标。
- 现有 6 处零散 `Animated*` 时长迁移到 token：`low_stock_screen` / `swipe_reveal_delete_action` / `category_chips` / `shopping_item_tile` / `ai_collapsible_banner` / `add_ingredient_screen`。

### 4.5 验证

- 新增 `fk_pressable` widget 测试（按压缩放、reduce-motion 降级、触感不抛错）。
- 新增 `page_transitions` 测试（push 后目标页可见、settle 正常）。
- 既有路由相关测试保持通过。

---

## 5. 阶段 2 · 列表入场 + 加载态

### 5.1 产物

| 产物 | 位置 | 说明 |
|---|---|---|
| `FkEntrance` | `widgets/shared/fk_entrance.dart` | 入场淡入 + 上移，带 `index` 交错 |
| `FkShimmer` | `widgets/shared/fk_shimmer.dart` | ShaderMask 微光扫掠 |
| `FkSkeletonBox` / `FkSkeletonLine` | `widgets/shared/fk_skeleton.dart` | 骨架积木 |

### 5.2 `FkEntrance` 设计

```text
FkEntrance({ required Widget child, int index = 0, Duration? duration })
```

- 实现：`StatefulWidget`，`initState` 调度 `Future.delayed(index × staggerStep)`（封顶 `staggerMaxItems`）后置 `_visible = true`，驱动 `TweenAnimationBuilder`（opacity 0→1 + translateY 8→0，时长 `slow`，曲线 `standard`）。`mounted` 守卫。
- **一次性**：每个 element 实例只播一次，**不随滚动重放**。
- 范围刻意限定在「有界 / 首屏」列表，避免长列表滚动抖动：首页分类网格 / 临期轮播 / 迷你数据、设置数据卡行、清单分组、Review 提案行、搜索结果、各空状态；库存网格与菜谱列表仅首屏挂载播放。
- reduce-motion：直接渲染终态。

### 5.3 Shimmer / Skeleton 设计

- `FkShimmer`：`AnimationController`（`shimmer` 时长循环）+ `ShaderMask` 高光渐变扫掠，底色用 `surfaceContainer` 系。reduce-motion：静态底色不循环。
- `FkSkeleton*`：圆角/尺寸走 token 的占位块；组出 `RecipeCard` / `IngredientCard` 形状的骨架卡。
- 替换裸 spinner：首页推荐菜谱（`dashboard_screen`）、菜谱列表（`recipes_screen`）、菜谱详情步骤（`recipe_detail_screen`）、食材解析（`add_ingredient_screen`）、表单异步（`custom_recipe_form_screen`）；`fk_image_placeholder` / `ai_busy_overlay` 改用 shimmer。

### 5.4 验证

- `FkEntrance` / `FkShimmer` widget 测试（含 reduce-motion 降级与不卡 settle）。
- 替换 spinner 的屏幕：测试改用固定 `pump(duration)` 或 reduce-motion override，确认加载→内容切换正常。

---

## 6. 阶段 3 · Hero 连续 + 状态变化反馈

### 6.1 Hero 图片连续

- `RecipeCard` 封面图 ↔ `RecipeDetailScreen` 头图，`Hero(tag: 'recipe-image-<id>')`。
- `IngredientCard` 图标/图 ↔ `IngredientDetailScreen`。
- 配合 §4 `fkRoute`：背景滑动、图片飞入。
- **tag 唯一性保护**：仅当 id 稳定且单屏唯一时启用；同屏潜在重复（如同名占位）回退无 tag，避免 Hero 重复 tag 崩溃。

### 6.2 状态变化反馈（克制）

| 反馈 | 位置 | 手法 |
|---|---|---|
| 勾选缩放回弹 + 轻触感 | 清单 / 低库存 / Review / 库存多选 | 短缩放 + `HapticFeedback.selection` |
| 新鲜度色彩/徽章 cross-fade | `ingredient_card` / `expiring_screen` | `AnimatedContainer` / `AnimatedDefaultTextStyle` |
| 进度条挂载填充 0→目标 | `ingredient_card` 新鲜度条 | `TweenAnimationBuilder` widthFactor |
| 步骤完成淡出 + 删除线 | `recipe_detail_screen` | `AnimatedDefaultTextStyle` 颜色 + strikethrough |
| 同步横幅滑入 | `sync_status_banner` | `SlideTransition` / `AnimatedSize` 入场 |

### 6.3 验证

- Hero 往返导航 widget 测试（含同屏重复 id 回退路径）。
- 勾选/进度/步骤状态变化测试（值正确切换、reduce-motion 下仍为终态）。

---

## 7. 阶段 4 · token 遵循扫荡（风格统一）

### 7.1 补齐缺失 token

- `AppShadows`（新增，`theme/`）：`subtle / soft / warm / card / fab`，收编所有内联 `BoxShadow`（`fk_card` 默认、`fk_icon_button`、`dashboard`、`stat_card`）。
- 按需扩 `AppSize`（现有 `iconSm/iconMd/settingsIconBox/profileAvatar` 之外补常用尺寸）。
- 可选 `AppLetterSpacing`（~20 处裸字距）。

### 7.2 扫荡

| 类别 | 数量级 | 目标 |
|---|---|---|
| 内联 `fontSize` | ~197 | `AppFontSize` / `textTheme` |
| 硬编码间距 | 95+ | `AppSpacing`（worst：settings / custom_recipe_form / shopping_list / dashboard） |
| 硬编码圆角 | 24 | `AppRadius`（2→xs · 999→pill · 12→md · 14→chip） |
| 裸色值 | 若干 | `AppColors` 语义色（含 dashboard 的 `Colors.white` 簇 + 透明度阶） |
| 内联 `BoxShadow` | 若干 | `AppShadows` |

### 7.3 收口不一致

- 合并 `FkPill` / `PillChip` 内边距口径（共享 padding token，消除两套 pill）。
- `auth_gate` 输入框改 FK `filled` 风格（消除下划线边框）。
- Review 屏改用 `app_snackbar` 工具（停用裸 `SnackBar`）。
- 统一分隔线 token（替代散落的 `BorderSide(width: 0.5)`）。

### 7.4 验证

- 全量 `flutter analyze` 0 warning。
- 视觉等价：扫荡后渲染应与扫荡前一致（token 值对齐原魔法数；不一致处以设计意图为准并记录）。
- 全量 widget 测试通过。

---

## 8. 跨阶段非回归约束

- `flutter test` **串行**运行（`-j 1`）。
- `AppShell` 相关测试需 `syncBannerTestOverrides`。
- **仅格式化改动过的文件**（仓库未启用 tall-style，勿全量 format）。
- 保留工作区既有 WIP（导航入口收敛）不动。
- 每阶段顺序验证：相关 widget 测试 → `flutter analyze` → 必要时构建冒烟。

---

## 9. 构建顺序

阶段 1（地基）→ 阶段 2（列表/加载）→ 阶段 3（Hero/状态）→ 阶段 4（token 扫荡）。每阶段一个可合并单元，依赖上一阶段的原语。

---

## 10. 非目标（YAGNI）

- 不做深色模式 / 多主题。
- 不引入 `flutter_animate` / `shimmer` / `lottie` 等第三方动效包。
- 不改色板与品牌色。
- 不做布局/信息架构重构（除阶段 4 收口必需的小幅整理）。
- 不动业务逻辑、provider、sync、存储。
