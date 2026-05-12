# FreshKeeper UI 重构实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 把现有 fresh_pantry (深森林绿 Material 3) 整体替换为 FreshKeeper 设计稿(矢车菊蓝 `#5B7FD4` + 暖奶油底 + 卡通线性 SVG 食材图标 + 5-tab 底栏)定义的"生活化"视觉系统,覆盖全部 11 个屏幕。

**Architecture:** 自底向上替换 — 先重写 design token (colors / radius / typography / theme),再建 SVG 图标库与 FK 共享组件层,然后逐屏幕重做 UI,**保持 providers / models / services 业务逻辑不变**。把现有 4-tab 扩为 5-tab(把"菜谱"提升为 primary 入口、把"设置"作为"我的"tab),与设计稿对齐。

**Tech Stack:** Flutter 3.7+ · Riverpod 3 · Google Fonts (Plus Jakarta Sans + Manrope, fallback PingFang SC) · CustomPaint 绘制 9 个食材分类 + 5 个存储区 SVG (不引入 flutter_svg)。

**Reference assets** in `/tmp/design_pkg/1/project/`:
- `data.jsx` — FK_COLORS / FK_CATEGORIES / FK_ZONES / FK_STATUS_LABEL
- `ui.jsx` — CatIcon / ZoneIcon (SVG paths) + FKCard / FKPill / FKTopBar / FKTabBar / FKSectionHead / FKStatusBadge / FKToast
- `screens-1.jsx` — Home (Dashboard) + AddScreen
- `screens-2.jsx` — Ingredients list + Detail + Expiring + LowStock
- `screens-3.jsx` — Shopping + Recipes + RecipeDetail + Settings

**Out of scope:** 后台 / 数据模型 / AI 集成逻辑均不动。Add 屏幕的"扫码"/"拍照"模式只做视觉,不接入 camera。

**Non-negotiables (locked from chat 2):**
- Primary: `#5B7FD4` (cornflower blue), primaryDark `#3F60B5`, primaryLight `#8AA3E0`, primarySoft `#E5ECFA`
- Warn (临期 / 黄油黄): `#FFC857`, warnSoft `#FFF3D6`
- Danger (过期 / 不足 / 珊瑚红): `#E76F51`, dangerSoft `#FBE0D7`
- Background: warm cream `#FBF8F3`, bgAlt `#F0EBE3`, card `#FFFFFF`
- Ink: `#2D2438` (deep plum-ink), text `#4F4358`, muted `#9B92A5`, hair `rgba(45,36,56,0.08)`
- 主按钮投影色: 暖灰棕 `rgba(60,45,30,0.16)` — 不要紫调
- 圆角 hero block 28px, 卡片 20px, 中卡 14-16px, pill 999

---

## Phase 1: 设计 token 重写

### Task 1.1: 替换 `lib/theme/app_colors.dart`

**Files:**
- Modify: `lib/theme/app_colors.dart`

旧 token 大量映射到 Material 3 `ColorScheme` 字段(primary / primaryContainer / surface / tertiary / secondary 等)。**保留原命名让 ColorScheme 不动**,但把 RGB 值替换成 FK 调色,并新增 FK 专属 token (`category*` / `status*` / `shadowWarm` 等)。

- [ ] **Step 1: 替换原色板,保留所有现有字段名,但 RGB 改为 FK 调色**

```dart
import 'package:flutter/material.dart';

class AppColors {
  // ─── FK Primary (cornflower blue) ───
  static const primary = Color(0xFF5B7FD4);
  static const primaryContainer = Color(0xFF3F60B5);
  static const onPrimary = Color(0xFFFFFFFF);
  static const onPrimaryContainer = Color(0xFFE5ECFA);
  static const primaryFixed = Color(0xFFE5ECFA);
  static const primaryLight = Color(0xFF8AA3E0);
  static const primarySoft = Color(0xFFE5ECFA);

  // ─── Warn (butter yellow, 临期) ───
  static const secondary = Color(0xFFFFC857);
  static const secondaryContainer = Color(0xFFFFF3D6);
  static const onSecondary = Color(0xFF2D2438);
  static const onSecondaryContainer = Color(0xFF9B7A2A);
  static const secondaryFixed = Color(0xFFFFF3D6);

  // ─── Danger (coral, 过期 / 不足) — 保留 tertiary 名字便于映射,语义改为 danger ───
  static const tertiary = Color(0xFFE76F51);
  static const tertiaryContainer = Color(0xFFFBE0D7);
  static const onTertiary = Color(0xFFFFFFFF);
  static const onTertiaryContainer = Color(0xFFB5523A);
  static const tertiaryFixedDim = Color(0xFFFFC857); // alias to warn for legacy callers

  // Aliases — 用 fk 前缀的语义命名以便迁移期间双轨
  static const fkWarn = secondary;
  static const fkWarnSoft = secondaryContainer;
  static const fkDanger = tertiary;
  static const fkDangerSoft = tertiaryContainer;

  // Error
  static const error = Color(0xFFE76F51);
  static const errorContainer = Color(0xFFFBE0D7);
  static const onError = Color(0xFFFFFFFF);
  static const onErrorContainer = Color(0xFFB5523A);

  // Surface hierarchy (warm cream)
  static const surface = Color(0xFFFBF8F3);
  static const surfaceDim = Color(0xFFE8E3DA);
  static const surfaceBright = Color(0xFFFFFFFF);
  static const surfaceContainerLowest = Color(0xFFFFFFFF);
  static const surfaceContainerLow = Color(0xFFF6F2EB);
  static const surfaceContainer = Color(0xFFF0EBE3);
  static const surfaceContainerHigh = Color(0xFFE9E2D6);
  static const surfaceContainerHighest = Color(0xFFE3DCCB);

  // On-surface — deep plum-ink
  static const onSurface = Color(0xFF2D2438);
  static const onSurfaceVariant = Color(0xFF4F4358);
  static const outline = Color(0xFF9B92A5);
  static const outlineVariant = Color(0xFFC7C1CE);
  static const hair = Color(0x142D2438); // rgba(45,36,56,0.08)

  // Semantic
  static const urgentAttentionBackground = Color(0xFFFBE0D7);
  static const onTertiaryFixedDim = Color(0xFF9B7A2A);

  // Inverse
  static const inverseSurface = Color(0xFF2D2438);
  static const inverseOnSurface = Color(0xFFF6F2EB);
  static const inversePrimary = Color(0xFF8AA3E0);

  // AI accents — sit in primary family
  static const aiAccent = primary;
  static const aiAccentMuted = outline;
  static const aiGradientStart = primary;
  static const aiGradientEnd = primaryContainer;

  // Overlays / shadows
  static const onImageScrim = Color(0x33000000);
  static const onImageBorderStrong = Color(0xB3FFFFFF);
  static const onImageBorderSoft = Color(0x99FFFFFF);
  static const modalBarrier = Color(0x47000000);
  static const subtleShadow = Color(0x0F000000);

  // FK 专属:暖灰棕投影 — 替代旧 primary 紫色光晕
  static const shadowWarm = Color(0x293C2D1E); // rgba(60,45,30,0.16)
  static const shadowSoft = Color(0x0A263A34); // 软阴影
}
```

- [ ] **Step 2: 新增 `lib/theme/fk_category_palette.dart`** — 9 个食材分类的 (tint / ink) 配对

```dart
import 'package:flutter/material.dart';

/// FreshKeeper 食材分类语义色板。
/// 每个分类提供 `tint` (avatar 背景 / 软底) 与 `ink` (描边 / 文字 / icon)。
class FkCategoryPalette {
  FkCategoryPalette._();

  static const veg   = (tint: Color(0xFFE8F3E1), ink: Color(0xFF4F7A3A));
  static const fruit = (tint: Color(0xFFFBE0D7), ink: Color(0xFFB5523A));
  static const meat  = (tint: Color(0xFFFDD6CE), ink: Color(0xFFA8442C));
  static const sea   = (tint: Color(0xFFD6EBF2), ink: Color(0xFF3F7691));
  static const dairy = (tint: Color(0xFFE5ECFA), ink: Color(0xFF3F60B5));
  static const drink = (tint: Color(0xFFE2EAF5), ink: Color(0xFF4A5E91));
  static const sauce = (tint: Color(0xFFF0EBE3), ink: Color(0xFF7A6748));
  static const grain = (tint: Color(0xFFFFF3D6), ink: Color(0xFF9B7A2A));
  static const snack = (tint: Color(0xFFFBE3CE), ink: Color(0xFFA85F2C));
}
```

- [ ] **Step 3: 跑 `flutter analyze` 验证**

Run: `flutter analyze`
Expected: 0 errors (warnings about unused constants are acceptable mid-migration).

- [ ] **Step 4: Commit**

```bash
git add lib/theme/app_colors.dart lib/theme/fk_category_palette.dart
git commit -m "refactor(theme): replace color palette with FreshKeeper cornflower blue system"
```

### Task 1.2: 扩 `lib/theme/app_radius.dart`

**Files:**
- Modify: `lib/theme/app_radius.dart`

新增 hero / chip / card-lg 三个 token。原有保留(被广泛引用)。

- [ ] **Step 1: Edit**

```dart
class AppRadius {
  AppRadius._();
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 20;       // 卡片(FK 主卡)
  static const double xxl = 24;
  static const double hero = 28;     // FK Hero block 底圆角
  static const double chip = 14;     // FK search / chip 矩形
  static const double pill = 999;
}
```

- [ ] **Step 2: Commit**

### Task 1.3: 重写 `lib/theme/app_theme.dart`

**Files:**
- Modify: `lib/theme/app_theme.dart`

把 `cardTheme` 的 border 去掉(FK 设计是阴影区分,不要描边);`chipTheme` 默认背景改为 `bgAlt`;`inputDecorationTheme` 圆角 14;`filledButtonTheme` 加暖灰棕 shadow;`appBarTheme.systemOverlayStyle` 沿用 `kAppSystemOverlayStyle` 不变。

- [ ] **Step 1: Replace `cardTheme` block**

```dart
cardTheme: CardThemeData(
  elevation: 0,
  shape: RoundedRectangleBorder(
    borderRadius: BorderRadius.circular(AppRadius.xl),
  ),
  color: AppColors.surfaceContainerLowest,
  shadowColor: AppColors.shadowSoft,
  margin: EdgeInsets.zero,
),
```

- [ ] **Step 2: Replace `chipTheme`**

```dart
chipTheme: ChipThemeData(
  shape: const StadiumBorder(),
  backgroundColor: AppColors.surfaceContainer,
  selectedColor: AppColors.primary,
  labelStyle: AppTypography.textTheme.labelLarge,
  showCheckmark: false,
  side: BorderSide.none,
),
```

- [ ] **Step 3: Replace `inputDecorationTheme` (圆角 14)**

```dart
inputDecorationTheme: InputDecorationTheme(
  filled: true,
  fillColor: AppColors.surfaceContainer,
  border: OutlineInputBorder(
    borderRadius: BorderRadius.circular(AppRadius.chip),
    borderSide: BorderSide.none,
  ),
  enabledBorder: OutlineInputBorder(
    borderRadius: BorderRadius.circular(AppRadius.chip),
    borderSide: BorderSide.none,
  ),
  focusedBorder: OutlineInputBorder(
    borderRadius: BorderRadius.circular(AppRadius.chip),
    borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
  ),
  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
),
```

- [ ] **Step 4: Commit**

### Task 1.4: 扩 `lib/theme/app_typography.dart`

**Files:**
- Modify: `lib/theme/app_typography.dart`

新增 `heroStat` (大数字 56) 和 `heroLabel`,服务于 Dashboard / Detail / Shopping 进度卡的"大数字"展示。

- [ ] **Step 1: Append**

```dart
static TextStyle get heroStat => GoogleFonts.plusJakartaSans(
      fontSize: 56,
      fontWeight: FontWeight.w800,
      letterSpacing: -1,
      height: 1,
    );

static TextStyle get heroSubStat => GoogleFonts.plusJakartaSans(
      fontSize: 28,
      fontWeight: FontWeight.w800,
      letterSpacing: -0.4,
    );

static TextStyle get sectionTitleLg =>
    GoogleFonts.plusJakartaSans(fontSize: 22, fontWeight: FontWeight.w700, letterSpacing: -0.3);
```

- [ ] **Step 2: `flutter analyze` + commit**

---

## Phase 2: SVG 卡通图标系统

### Task 2.1: 9 个食材分类 CustomPainter — `lib/widgets/shared/cat_icon.dart`

把 `ui.jsx` 里 `CatIcon` 的 SVG path 翻译成 Flutter `Path` 调用,用 36×36 viewBox 等比缩放。strokeWidth 1.8 / linecap round / linejoin round。

**Files:**
- Create: `lib/widgets/shared/cat_icon.dart`

- [ ] **Step 1: 写 CatIcon widget** (全部 9 个分类,共一个文件)

接口:`CatIcon(category: 'veg', size: 28, color: AppColors.onSurface)`。`category` 接 9 种 id 之一 (`veg / fruit / meat / sea / dairy / drink / sauce / grain / snack`)。

每个分类一个 `_paint*` 函数,从设计稿 SVG path 翻译。对每个 SVG 子 `<path>`/`<circle>` 都翻一遍。circle 用 `canvas.drawCircle`,path 用 `Path()` + `moveTo / lineTo / cubicTo / quadraticBezierTo`。viewBox 36×36 → 缩放 = size/36。

代码骨架:

```dart
import 'package:flutter/material.dart';

class CatIcon extends StatelessWidget {
  final String category;
  final double size;
  final Color color;
  final double strokeWidth;

  const CatIcon({
    super.key,
    required this.category,
    this.size = 28,
    this.color = const Color(0xFF2D2438),
    this.strokeWidth = 1.8,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(painter: _CatIconPainter(category, color, strokeWidth)),
    );
  }
}

class _CatIconPainter extends CustomPainter {
  final String category;
  final Color color;
  final double strokeWidth;
  _CatIconPainter(this.category, this.color, this.strokeWidth);

  @override
  void paint(Canvas canvas, Size size) {
    final scale = size.width / 36;
    canvas.scale(scale);
    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final fill = Paint()..color = color;
    switch (category) {
      case 'fruit': _fruit(canvas, stroke, fill); break;
      case 'meat':  _meat(canvas, stroke, fill); break;
      case 'sea':   _sea(canvas, stroke, fill); break;
      case 'dairy': _dairy(canvas, stroke); break;
      case 'drink': _drink(canvas, stroke); break;
      case 'sauce': _sauce(canvas, stroke, fill); break;
      case 'grain': _grain(canvas, stroke); break;
      case 'snack': _snack(canvas, stroke, fill); break;
      case 'veg':
      default:      _veg(canvas, stroke); break;
    }
  }

  void _veg(Canvas canvas, Paint stroke) {
    // path d="M18 7c-6 0-10 4-10 10 0 5 4 9 10 9s10-4 10-9C28 11 24 7 18 7z"
    final p = Path()
      ..moveTo(18, 7)
      ..relativeCubicTo(-6, 0, -10, 4, -10, 10)
      ..relativeCubicTo(0, 5, 4, 9, 10, 9)
      ..relativeCubicTo(6, 0, 10, -4, 10, -9)
      ..cubicTo(28, 11, 24, 7, 18, 7)
      ..close();
    canvas.drawPath(p, stroke);
    // ... (将 ui.jsx 里 veg 段剩余 path 一一翻译)
  }
  // ... 其余 8 个 _fruit / _meat / _sea / _dairy / _drink / _sauce / _grain / _snack 同样翻译
  @override
  bool shouldRepaint(_CatIconPainter o) =>
      o.category != category || o.color != color || o.strokeWidth != strokeWidth;
}
```

> **翻译规则:** SVG path `M x y` = `moveTo`,`m dx dy` = `relativeMoveTo`,`L x y` = `lineTo`,`l dx dy` = `relativeLineTo`,`C x1 y1 x2 y2 x y` = `cubicTo`,`c dx1 dy1 dx2 dy2 dx dy` = `relativeCubicTo`,`Z` = `close`。`<circle cx cy r/>` = `canvas.drawCircle(Offset(cx, cy), r, fill)`.

- [ ] **Step 2: Widget test — 渲染 9 个分类不抛异常**

```dart
testWidgets('CatIcon renders all 9 categories without throwing', (tester) async {
  for (final cat in ['veg','fruit','meat','sea','dairy','drink','sauce','grain','snack']) {
    await tester.pumpWidget(MaterialApp(home: CatIcon(category: cat)));
    expect(find.byType(CatIcon), findsOneWidget);
  }
});
```

- [ ] **Step 3: 跑 test + commit**

### Task 2.2: 5 个存储区 CustomPainter — `lib/widgets/shared/zone_icon.dart`

同样翻译 `ui.jsx` 的 ZoneIcon (5 个 zone: fridge / freezer / door / box / pantry)。viewBox 24×24,strokeWidth 1.7。

- [ ] **Step 1: 写 ZoneIcon widget,5 个 paint 函数**
- [ ] **Step 2: Widget test + commit**

### Task 2.3: 替换 `lib/widgets/shared/category_icon.dart`

**Files:**
- Modify: `lib/widgets/shared/category_icon.dart`

`CategoryIconAvatar` 沿用接口(`category` 字段是 `FoodCategories` enum 字符串如 `'fresh_produce'`),但内部:
- 把 enum → FK cat id 映射:`fresh_produce` → `veg`,`dairy_and_eggs` → `dairy`,`meat_and_seafood` → `meat`/`sea`,`herbs_and_spices` → `sauce`,默认 → `grain`。
- 用 `FkCategoryPalette` 决定 tint / ink。
- 内部渲染换成 `CatIcon`。

- [ ] **Step 1: 写映射 + Avatar 重构**

```dart
String _fkCatIdFor(String? category) {
  return switch (FoodCategories.dropdownValue(category)) {
    FoodCategories.dairyAndEggs   => 'dairy',
    FoodCategories.freshProduce   => 'veg',
    FoodCategories.meatAndSeafood => 'meat',
    FoodCategories.herbsAndSpices => 'sauce',
    _ => 'grain',
  };
}

({Color tint, Color ink}) _fkPaletteFor(String fkCat) => switch (fkCat) {
  'veg' => FkCategoryPalette.veg, 'fruit' => FkCategoryPalette.fruit,
  'meat' => FkCategoryPalette.meat, 'sea' => FkCategoryPalette.sea,
  'dairy' => FkCategoryPalette.dairy, 'drink' => FkCategoryPalette.drink,
  'sauce' => FkCategoryPalette.sauce, 'grain' => FkCategoryPalette.grain,
  'snack' => FkCategoryPalette.snack,
  _ => FkCategoryPalette.grain,
};
```

`categoryIconFor` 旧函数(返回 IconData)保留以避免大面积调用方爆炸;但新代码用 `CategoryIconAvatar` 自己渲染 `CatIcon`。

- [ ] **Step 2: `flutter analyze` + commit**

---

## Phase 3: FK 核心共享组件库

### Task 3.1: `lib/widgets/shared/fk_card.dart`

圆角 20、`#FFFFFF` 背景、两层软阴影 (`0 1px 2px rgba(38,58,52,0.04), 0 4px 16px rgba(38,58,52,0.04)`)。支持自定义 padding / onTap / decoration 覆盖。

- [ ] **Step 1: 写组件**

```dart
class FkCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  final Color? backgroundColor;
  final double borderRadius;
  final Gradient? gradient;

  const FkCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.onTap,
    this.backgroundColor,
    this.borderRadius = 20,
    this.gradient,
  });

  @override
  Widget build(BuildContext context) {
    final inner = Container(
      padding: padding,
      decoration: BoxDecoration(
        color: gradient == null ? (backgroundColor ?? AppColors.surfaceContainerLowest) : null,
        gradient: gradient,
        borderRadius: BorderRadius.circular(borderRadius),
        boxShadow: const [
          BoxShadow(color: Color(0x0A263A34), blurRadius: 2, offset: Offset(0, 1)),
          BoxShadow(color: Color(0x0A263A34), blurRadius: 16, offset: Offset(0, 4)),
        ],
      ),
      child: child,
    );
    if (onTap == null) return inner;
    return GestureDetector(onTap: onTap, behavior: HitTestBehavior.opaque, child: inner);
  }
}
```

- [ ] **Step 2: Commit**

### Task 3.2: `lib/widgets/shared/fk_pill.dart`

现有 `pill_chip.dart` 已经接近 FK 设计,但 default bg 是 `surfaceContainerLow`(较冷)。FK 默认是 `bgAlt` (`#F0EBE3`)。
**保留** `PillChip` 接口和文件(避免破坏所有 caller),但 default bg 改为 `AppColors.surfaceContainer`(已映射到 `#F0EBE3` 经过 Phase 1 token);新增 `FkPill.status({status})` 静态构造支持 4 种 status (fresh / soon / urgent / expired / low) 直接渲染对应配色。

- [ ] **Step 1: 在 `pill_chip.dart` 内追加 `FkStatusPalette` enum 与静态命名构造**

```dart
enum FkStatus { fresh, soon, urgent, expired, low }

class FkStatusStyle {
  final Color bg; final Color fg; final String label;
  const FkStatusStyle(this.bg, this.fg, this.label);
}

const Map<FkStatus, FkStatusStyle> kFkStatusStyles = {
  FkStatus.fresh:   FkStatusStyle(AppColors.primarySoft, AppColors.primaryContainer, '新鲜'),
  FkStatus.soon:    FkStatusStyle(AppColors.fkWarnSoft, AppColors.onSecondaryContainer, '即将过期'),
  FkStatus.urgent:  FkStatusStyle(AppColors.fkDangerSoft, AppColors.onTertiaryContainer, '快过期'),
  FkStatus.expired: FkStatusStyle(AppColors.fkDanger, Colors.white, '已过期'),
  FkStatus.low:     FkStatusStyle(AppColors.fkDangerSoft, AppColors.onTertiaryContainer, '库存不足'),
};
```

- [ ] **Step 2: Commit**

### Task 3.3: `lib/widgets/shared/fk_icon_button.dart`

圆形 36 (default) / 28 (sm) / 52 (primary FAB) icon button。可选 `primary` (主色填充 + 暖灰投影)。

- [ ] **Step 1: 写组件 + commit**

### Task 3.4: `lib/widgets/shared/fk_top_bar.dart`

大标题 (22 / 700 / -0.3) + 副标题 (13 / muted),左 back / 右 actions。`sticky` 与 `dense` 选项。

- [ ] **Step 1: 写组件**

```dart
class FkTopBar extends StatelessWidget {
  final String title;
  final String? subtitle;
  final VoidCallback? onBack;
  final Widget? leading;          // 覆盖 onBack 默认渲染
  final List<Widget> actions;
  final bool dense;
  final Color? backgroundColor;

  const FkTopBar({
    super.key,
    required this.title,
    this.subtitle,
    this.onBack,
    this.leading,
    this.actions = const [],
    this.dense = false,
    this.backgroundColor,
  });
  // build: padding 18px horizontal, top inset by SafeArea, gap 10
}
```

- [ ] **Step 2: Commit**

### Task 3.5: `lib/widgets/shared/fk_section_head.dart`

Section title (16 / 700 / -0.2) + 可选 count (muted 13) + 右侧 action label (primary 13 / 600) + chevron。

- [ ] **Step 1: 写组件 + commit**

### Task 3.6: `lib/widgets/shared/fk_image_placeholder.dart`

斜纹 placeholder:`repeating-linear-gradient(135deg, tint 0 8px, rgba(0,0,0,0.02) 8px 16px)`。Flutter 用 `CustomPainter` 画 8px / 8px 重复斜条带。

- [ ] **Step 1: 写组件 + commit**

### Task 3.7: `lib/widgets/shared/fk_status_badge.dart`

读 `FkStatus` enum 渲染对应配色 + label。

- [ ] **Step 1: 写组件 + commit**

### Task 3.8: `lib/widgets/shared/fk_hero_header.dart`

通用 hero block:linear gradient (primary → primaryDark),`borderBottomLeftRadius / borderBottomRightRadius = 28`,左右 padding 20,顶部 padding 54(留 status bar),底部 padding 80。可选两枚装饰圆斑(白色 7% / 9% alpha)。`child` slot 放具体内容(stat / mini grid 等)。

- [ ] **Step 1: 写组件**

```dart
class FkHeroHeader extends StatelessWidget {
  final Widget child;
  final List<Color> gradient;
  final double bottomRadius;
  // build: ClipRRect with bottom radii, Stack of deco circles + child
}
```

- [ ] **Step 2: Commit**

### Task 3.9: 添加全局 Toast helper

替换 / 新增 `lib/utils/fk_toast.dart`:`fkToast(context, msg)` 显示 1.8s 暗墨色底 + 白字 + check icon 的浮 pill。可以 wrap 现有 `app_snackbar.dart` 输出。

- [ ] **Step 1: 写 helper + commit**

---

## Phase 4: 5-tab Bottom Nav + 路由

### Task 4.1: 改 `navigation_provider.dart` 为 5-index

**Files:**
- Modify: `lib/providers/navigation_provider.dart`

把所有调用方搜出来(`ref.navigateToTab(N)`)并把 index 映射改为:
- 0 = 首页 (Dashboard)
- 1 = 食材 (Inventory)
- 2 = 添加 (Add) — 中间 primary FAB
- 3 = 菜谱 (Recipes)
- 4 = 购物 (Shopping)
- 5 = 我的 (Settings) — 新加

> 5 个 tab,profile 用独立 push 还是第 5 tab?**第 5 tab**:`tabs = [Home, Fridge, Add(primary), Recipes, Shopping]`,profile 通过 Dashboard 右上角铃铛入口 push 进入(`SettingsScreen`)。这样匹配设计稿 `FKTabBar`(5 项,中间 add 突出),settings 走 chat 中"我的"路由。

- [ ] **Step 1: 把 index 改为 5(Add 在中间索引 2)**

Old `_screens` indices: 0=Dashboard, 1=Inventory, 2=Add, 3=Shopping → New: 0=Dashboard, 1=Inventory, 2=Add, 3=Recipes, 4=Shopping。

`grep -rn "navigateToTab(" lib/` 找出全部 call site,把:
- `navigateToTab(3)`(旧 Shopping)→ `navigateToTab(4)`
- 其他不变

- [ ] **Step 2: 改 `lib/app.dart` _screens 列表**

```dart
static const _screens = [
  DashboardScreen(),
  InventoryScreen(),
  AddIngredientScreen(),
  MyRecipesScreen(),
  ShoppingListScreen(),
];
```

- [ ] **Step 3: 改 `lib/widgets/common/bottom_nav_bar.dart`**

5 tabs,中间(index 2)用 primary 圆形 FAB (52×52,bg = primary,icon = plus,白色,`shadowWarm`)。左右各 2 个 icon + 文字 (home/fridge/recipes/shopping)。

```dart
static const _items = [
  _NavItem(_FkNavIcon.home,     '首页'),
  _NavItem(_FkNavIcon.fridge,   '食材'),
  _NavItem(_FkNavIcon.add,      ''),      // primary FAB,no label
  _NavItem(_FkNavIcon.recipes,  '菜谱'),
  _NavItem(_FkNavIcon.shopping, '清单'),
];
```

Icon 用自定义 `FkNavIcon` (CustomPaint) 或 Material Icons (Icons.home_outlined / Icons.kitchen_outlined / Icons.add / Icons.menu_book_outlined / Icons.shopping_cart_outlined) — 第二种更简单。

- [ ] **Step 4: Commit**

---

## Phase 5: Dashboard 重做

### Task 5.1: 重写 `lib/screens/dashboard_screen.dart`

完全替换文件正文。复用现有 providers(`statCountsProvider` / `expiringItemsProvider` / `recentAdditionsProvider` / `recommendedRecipesProvider` / `uncheckedCountProvider`)。

新结构(对照 `screens-1.jsx::HomeScreen`):

1. `FkHeroHeader` (primary gradient,大数字 = `stats.total`,3-grid mini stats: 快过期 / 即将过期 / 库存不足)
2. Quick Add 浮卡(`Transform.translate(-36)` 实现 hero overlap):3 个按钮 — 扫码 / 拍照 / 手动 → 都跳 add tab
3. "该用了" 横滚 `ListView.builder(scrollDirection: horizontal)` 渲染 `ExpiringCard`
4. "库存不足" 卡片块(若有低库存项)+ "查看全部 N 项 · 一键加购" CTA → push 新 `LowStockScreen`
5. "食材分类" 4-col `GridView`
6. "今日推荐" `FkCard` 包 recipe placeholder + 名 / 时间 / 已有食材 pill / 标签 pill → 点击 push `RecipeDetailScreen`

- [ ] **Step 1: 写新 DashboardScreen**
- [ ] **Step 2: `flutter analyze`**
- [ ] **Step 3: 跑现有 widget tests**(可能需要更新 test 内对老元素的 finder)
- [ ] **Step 4: Commit**

### Task 5.2: `ExpiringCard` widget — `lib/widgets/dashboard/fk_expiring_card.dart`

宽 132、白底、圆角 18、顶部 3px 色条(根据 status)、CatIcon avatar (56×56 with tint bg)、名称、qty + zone、底部小 pill (剩余天数文案)。

- [ ] **Step 1: 写组件 + commit**

### Task 5.3: `LowStockRow` — `lib/widgets/dashboard/fk_low_stock_row.dart`

横向 row:CatIcon avatar 36×36 → 名称 + "剩 N,建议补 N" → 右侧 "加购" pill 按钮 (primarySoft bg)。点击 → `addToShopping(item)` + toast。

- [ ] **Step 1: 写组件 + commit**

---

## Phase 6: Inventory + Detail 重做

### Task 6.1: 重写 `inventory_screen.dart`

对照 `screens-2.jsx::IngredientsScreen`:
- `FkTopBar`(标题 "我的食材",副标题 "共 N 件 · M 类",右侧 sort + add primary 圆按钮)
- 搜索行(`AppColors.surfaceContainer` 14px 圆角)
- 分类 chip 横滚 (全部 / 9 个分类带 CatIcon + count) — active 用 `AppColors.primary` 填充
- 状态 tag chip 横滚 (全部 / 快过期 / 即将过期 / 库存不足 / 冷藏 / 冷冻) — active 用 `AppColors.onSurface` 填充
- 排序行 (保质期 / 添加时间 / 剩余数量) — 文本按钮
- 2-col grid `IngredientCard`

- [ ] **Step 1: 写新 screen + Commit**

### Task 6.2: `lib/widgets/inventory/ingredient_card.dart` 重写

参考 `screens-2.jsx::IngredientCard`。白底圆角 18、CatIcon avatar、status pill(右上)、名称、qty + ZoneIcon + zone 名、底部进度条 (4px,色随 status,宽度按状态)。

- [ ] **Step 1: 重写 + commit**

### Task 6.3: 重写 `ingredient_detail_screen.dart`

对照 `screens-2.jsx::DetailScreen`。Hero block 用 cat.tint 背景,scattered ghost CatIcon (4 处不同 size / rotation / opacity)、白色 ghost 圆斑 (2 个 blur 圆)、subtle dot grid。中央白色软玻璃 avatar (92×92, rgba(255,255,255,0.7) bg)。

主体 split card (`FkCard` p=0,左数量 + step buttons,右剩余天数 + 到期日)。info list (5 行 detail)。actions 2-col (加入清单 / 标记已用完)。可做菜谱横滚。

- [ ] **Step 1: 写 ScatteredCatBackground widget(CustomPaint or Stack of Positioned)**
- [ ] **Step 2: 写新 DetailScreen + commit**

---

## Phase 7: Recipes + Recipe Detail 重做

### Task 7.1: 重写 `my_recipes_screen.dart`

升为 tab (index 3),不再是 push 进入。
- `FkTopBar` 标题"智能菜谱",副标题"基于你的冰箱推荐",右侧 search icon button
- 3-tab segmented (用临期 / 现有食材 / 探索),用 active 下划线 (`AppColors.primary` 2.5px)
- 时间筛选 chip 横滚 (不限 / 15 分钟内 / 30 分钟内)
- "用临期" tab 顶部黄色 banner(`fkWarnSoft` bg + flame icon + 文案 "优先使用 N 件临期食材")
- 菜谱列表:每张卡用 horizontal layout (左 120px placeholder img with 可选 "临期" 角标)

- [ ] **Step 1: 写新 screen + commit**

### Task 7.2: 重写 `widgets/recipe_card.dart`

`FkCard` (p=0),`Row`:左 120×120 placeholder,右内容(名称 / 时间 + 难度 / 食材匹配进度条 / 标签)。进度条颜色按 ratio (满 = primary, ≥0.7 = primaryLight, 否则 warn)。

- [ ] **Step 1: 重写 + commit**

### Task 7.3: 重写 `recipe_detail_screen.dart`

参考 `screens-3.jsx::RecipeDetailScreen`。Hero placeholder 260px + back / 收藏(heart) 浮于其上(白色软玻璃 icon button)。标题 (24 / 800)、时间 + 难度、标签 row、营养卡 (`bgAlt`)、食材清单(已有 / 缺少高亮 - 缺的用 dangerSoft bg + dashed border check)、一键加购缺少的 CTA、步骤卡 (圆角 step number)、底部 "开始烹饪" primary 按钮(shadowWarm)。

- [ ] **Step 1: 写新 detail + commit**

---

## Phase 8: Shopping 重做

### Task 8.1: 重写 `shopping_list_screen.dart`

对照 `screens-3.jsx::ShoppingScreen`:
- `FkTopBar` 标题 + 副标题 + 右侧 add icon
- 大渐变进度卡:gradient (primary → primaryDark), 白字 "本次采购进度",大数字 `done`,`/ total 项`,右侧 percent,底部 6px 白色进度条
- 优先级 chip 行 (全部 / 待购买 / 必买 / 常备 / 可选)
- 按品类分组的 group card:头部 CatIcon + 分类名 + count,body 圆按钮 check + 名称 (打勾时 line-through + opacity 0.45) + qty + priority + source + delete icon
- 清空已完成 dashed button

- [ ] **Step 1: 写新 screen + commit**

### Task 8.2: 改 `widgets/shopping/shopping_item_tile.dart`

只动视觉(check 圆按钮、line-through、source 标签),保留所有现有接口。

- [ ] **Step 1: 改 + commit**

---

## Phase 9: Settings 屏(我的)

### Task 9.1: 新建 `lib/screens/settings_screen.dart`

对照 `screens-3.jsx::SettingsScreen`。Profile 卡片(渐变 avatar + 用户名 + 统计文案 + chevron),3-stat grid (食材 / 采购 / 收藏菜谱),临期提醒 toggle 4 行,饮食偏好 chip 7 项,更多 group (冰箱布局 / 阈值 / 导出 / 关于)。

> 用户当前没有真实 profile model — 用 mock(从 mock_data.dart 拉 / 或直接硬编码 "小米")。

- [ ] **Step 1: 写新 screen + commit**

### Task 9.2: Dashboard 右上角铃铛入口 push 进入 settings

(Dashboard task 5.1 已经预留了 icon button,这里只是把 `onTap` 接到 `SettingsScreen` push)

- [ ] **Step 1: 接路由 + commit**

---

## Phase 10: Add Ingredient 重做

### Task 10.1: 重写 `add_ingredient_screen.dart`

对照 `screens-1.jsx::AddScreen`。3-mode 切换(扫码 / 拍照 / 手动)— mode 切换只切换上方展示(scan: 220×220 角标方框 + 文案;photo: img placeholder + 文案;manual: 不显示)。
表单 5 行 (`FormRow`):名称(input)/分类(chip 横滚 with CatIcon)/数量(step buttons + 单位)/存放位置(chip with ZoneIcon)/保质期(数字 input + "天后")。底部 primary submit (shadowWarm)。

**注意**:现有 `add_ingredient_screen.dart` 是 1182 行,包含 AI draft / 各种 picker 等复杂逻辑。**不要简单覆盖**。策略:
- 保留所有 providers / state / form validation 逻辑
- 把可视部分(layout + decoration)用 FK 组件包装
- mode switcher 只在文件顶部加一个 stateful header,不改下面的 ai_draft 流程

- [ ] **Step 1: 重写 visuals,保留 logic + commit**

---

## Phase 11: 临期 / 库存不足分组页

### Task 11.1: 新建 `lib/screens/expiring_screen.dart`

对照 `screens-2.jsx::ExpiringScreen`。`FkTopBar` + 提醒设置链接 card + 3 个分组 (今天到期 / 3 天内 / 7 天内),每组顶 dot + label + count,body group `FkCard(p=0)` 包多个 `ExpiringRow` (CatIcon + 名称 + qty/zone + status pill + 3 个 mini action button)。

- [ ] **Step 1: 写新 screen + commit**

### Task 11.2: 新建 `lib/screens/low_stock_screen.dart`

对照 `screens-2.jsx::LowStockScreen`。按 cat 分组,每组 header CatIcon + 名称 + count。`LowRow` 是 checkbox 圆按钮 + 名称 + qty / threshold + "+N unit 建议补货" 右侧标。底部 sticky CTA "一键加入购物清单 (N)"。

- [ ] **Step 1: 写新 screen + commit**

### Task 11.3: Dashboard 链接 push 进入这两个屏幕

- [ ] **Step 1: 接路由 + commit**

---

## Phase 12: 现有项目独有屏幕沿用新风味

### Task 12.1: `custom_recipe_form_screen.dart` — 用 FK token + 组件包装

只换 visual 层(背景色 / 卡片样式 / chip / button shadow),不改逻辑。

- [ ] **Step 1: Edit + commit**

### Task 12.2: `recipe_draft_review_screen.dart` + `ingredient_draft_review_screen.dart`

- [ ] **Step 1: Edit + commit**

### Task 12.3: `ai_settings_screen.dart`

- [ ] **Step 1: Edit + commit**

---

## Phase 13: 集成验证

### Task 13.1: `flutter analyze` 0 error

- [ ] **Step 1**: `flutter analyze`,预期 0 error。

### Task 13.2: Widget tests 全绿

旧 widget tests 大量使用 `Icons.priority_high` / `'紧急关注'` / `AlertCard` finder,这些在重构后不再存在。**策略**:
- 先跑 `flutter test`,记录失败 case
- 失败 case 分两类:(a) 文案 / icon finder 失效 → 改 finder;(b) 业务逻辑断言 → 应该仍然通过

- [ ] **Step 1: `flutter test`**
- [ ] **Step 2: 改失效 finder 直到全绿 + commit**

### Task 13.3: 手动 dev 走查

```bash
flutter run -d ios
```

Smoke checklist:
- 5-tab 切换正常
- 中间 Add primary FAB 跳 Add 屏
- Dashboard hero stat 数字 = inventory total
- Dashboard 该用了 / 库存不足 / 分类 4-grid / 今日推荐 都渲染
- Inventory 搜索 + 双层 chip + 排序 + 2-col grid
- Detail hero (cat.tint + scattered icons) 渲染
- Shopping 进度卡渐变 + 分组列表
- Recipes 3-tab + 时间筛选
- RecipeDetail hero + 营养卡 + 食材匹配 + 缺少高亮
- Settings tab(经铃铛入口)profile + 3-stat + toggles 渲染

- [ ] **Step 1: 走查 + 截图保存到 `docs/superpowers/screenshots/`**
- [ ] **Step 2: Final commit + push**

---

## Self-Review

**Spec coverage:**
- ✅ FK_COLORS → AppColors (Phase 1)
- ✅ FK_CATEGORIES tint/ink → FkCategoryPalette (Phase 1)
- ✅ CatIcon SVG → Phase 2.1
- ✅ ZoneIcon SVG → Phase 2.2
- ✅ FK 组件(Card/Pill/IconBtn/TopBar/SectionHead/StatusBadge/HeroHeader/ImagePlaceholder/Toast)→ Phase 3
- ✅ 5-tab nav → Phase 4
- ✅ 10 个设计稿屏幕 → Phase 5-11 (Home / Add / Inventory / Detail / Expiring / LowStock / Recipes / RecipeDetail / Shopping / Settings)
- ✅ 现有 4 个独有屏幕 → Phase 12

**Placeholder scan:** SVG path 翻译详细规则已给,组件骨架代码已具体。

**Type consistency:** `FkStatus` enum / `FkCategoryPalette` / `CatIcon` / `ZoneIcon` 接口在 Phase 2-3 定义,后续 Phase 5+ 使用同名。

**Risk register:**
- SVG path 翻译手工容易出错 → Phase 2.1 / 2.2 各加一个 visual test (golden) 比对设计稿截图
- 5-tab 索引迁移(旧 3 → 新 4)→ 用 `grep -rn "navigateToTab"` 列举所有 caller,逐个迁移
- `add_ingredient_screen.dart` 1182 行复杂 logic → 不重写,只换视觉

