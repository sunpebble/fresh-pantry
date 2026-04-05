# Recipe Recommendation Feature Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace mock recipe data with 60 HowToCook-based Chinese recipes, upgrade the recommendation algorithm to prioritize expiring ingredients, and enhance the UI to show expiry-aware recommendations.

**Architecture:** Local JSON asset loaded via `RecipeService` → `FutureProvider` → scoring algorithm with expiry bonus → existing Dashboard bottom sheet with two sections (expiring-first, general). No new screens or tabs.

**Tech Stack:** Flutter, Riverpod (hand-written providers), JSON asset loading via `rootBundle`

---

### Task 1: Upgrade Recipe model + add RecipeIngredient and ScoredRecipe

**Files:**
- Modify: `lib/models/recipe.dart`

- [ ] **Step 1: Rewrite `lib/models/recipe.dart` with new model classes**

Replace the entire file content with:

```dart
class RecipeIngredient {
  final String name;
  final String amount;

  const RecipeIngredient({required this.name, required this.amount});

  factory RecipeIngredient.fromJson(Map<String, dynamic> json) {
    return RecipeIngredient(
      name: json['name'] as String,
      amount: json['amount'] as String,
    );
  }
}

class Recipe {
  final String id;
  final String name;
  final String category;
  final int difficulty;
  final int cookingMinutes;
  final String description;
  final List<RecipeIngredient> ingredients;
  final List<String> steps;
  final List<String> tags;

  const Recipe({
    required this.id,
    required this.name,
    required this.category,
    required this.difficulty,
    required this.cookingMinutes,
    required this.description,
    required this.ingredients,
    required this.steps,
    this.tags = const [],
  });

  factory Recipe.fromJson(Map<String, dynamic> json) {
    return Recipe(
      id: json['id'] as String,
      name: json['name'] as String,
      category: json['category'] as String? ?? '',
      difficulty: json['difficulty'] as int? ?? 0,
      cookingMinutes: json['cookingMinutes'] as int,
      description: json['description'] as String,
      ingredients: (json['ingredients'] as List<dynamic>)
          .map((e) => RecipeIngredient.fromJson(e as Map<String, dynamic>))
          .toList(),
      steps: (json['steps'] as List<dynamic>).cast<String>(),
      tags: (json['tags'] as List<dynamic>?)?.cast<String>() ?? const [],
    );
  }
}

class ScoredRecipe {
  final Recipe recipe;
  final double score;
  final int matchedCount;
  final int expiringMatchedCount;

  const ScoredRecipe({
    required this.recipe,
    required this.score,
    required this.matchedCount,
    required this.expiringMatchedCount,
  });
}
```

- [ ] **Step 2: Run analysis to verify no syntax errors**

Run: `cd /Users/shikun/Developer/opensource/fresh_pantry && flutter analyze lib/models/recipe.dart`

Expected: Errors in files that still reference `Recipe` with old constructor (this is expected — we fix them in subsequent tasks).

- [ ] **Step 3: Commit**

```bash
git add lib/models/recipe.dart
git commit -m "feat: upgrade Recipe model with RecipeIngredient and ScoredRecipe"
```

---

### Task 2: Create recipes.json asset data

**Files:**
- Create: `assets/data/recipes.json`
- Modify: `pubspec.yaml`

- [ ] **Step 1: Create the `assets/data/` directory and `recipes.json` file**

Create `assets/data/recipes.json` containing approximately 60 Chinese recipes in this exact JSON schema. Each recipe must follow this structure:

```json
{
  "id": "pinyin-kebab-id",
  "name": "中文菜名",
  "category": "素菜|荤菜|水产|早餐|主食|汤与粥|甜品|饮料|酱料|半成品加工",
  "difficulty": 1-5,
  "cookingMinutes": number,
  "description": "一句话简介",
  "ingredients": [
    { "name": "标准化食材名", "amount": "精确用量" }
  ],
  "steps": ["步骤1", "步骤2"],
  "tags": ["标签1", "标签2"]
}
```

Include these specific recipes (at minimum), organized by category:

**素菜 (~10道)**:
西红柿炒鸡蛋、酸辣土豆丝、地三鲜、拍黄瓜、炒青菜、干煸四季豆、蒜蓉西兰花、虎皮青椒、醋溜白菜、家常豆腐

**荤菜 (~15道)**:
红烧肉、宫保鸡丁、回锅肉、糖醋排骨、鱼香肉丝、红烧鸡翅、青椒肉丝、木须肉、可乐鸡翅、蚂蚁上树、辣椒炒肉、京酱肉丝、黑椒牛柳、蒜苔炒肉、水煮肉片

**水产 (~5道)**:
红烧鱼、清蒸鲈鱼、水煮鱼、糖醋鱼、蒜蓉粉丝蒸虾

**早餐 (~5道)**:
茶叶蛋、煎饺、葱花蛋饼、牛奶燕麦、吐司果酱

**主食 (~8道)**:
蛋炒饭、西红柿鸡蛋面、炒面、饺子、葱油拌面、扬州炒饭、酸辣粉、番茄意面

**汤与粥 (~6道)**:
西红柿鸡蛋汤、皮蛋瘦肉粥、紫菜蛋花汤、玉米排骨汤、冬瓜排骨汤、小米粥

**甜品 (~4道)**:
双皮奶、红糖姜茶、绿豆沙、酒酿圆子

**饮料 (~3道)**:
奶茶、酸梅汤、蜂蜜柠檬水

**酱料 (~2道)**:
油泼辣子、葱油

**半成品 (~2道)**:
速冻水饺、方便面升级版

食材名使用标准化名称：如"鸡蛋"而非"蛋"，"西红柿"而非"番茄"，"生抽"而非"酱油"。用量使用精确计量（如"200g"、"3个"、"15ml"），不用"适量"、"少许"。

- [ ] **Step 2: Add assets declaration to `pubspec.yaml`**

In `pubspec.yaml`, after line 64 (`uses-material-design: true`), add:

```yaml

  assets:
    - assets/data/
```

- [ ] **Step 3: Verify asset is loadable**

Run: `cd /Users/shikun/Developer/opensource/fresh_pantry && flutter analyze`

Expected: PASS (no new errors from asset declaration)

- [ ] **Step 4: Commit**

```bash
git add assets/data/recipes.json pubspec.yaml
git commit -m "feat: add 60 HowToCook-based Chinese recipe data as JSON asset"
```

---

### Task 3: Create RecipeService

**Files:**
- Create: `lib/services/recipe_service.dart`

- [ ] **Step 1: Create `lib/services/recipe_service.dart`**

```dart
import 'dart:convert';
import 'package:flutter/services.dart';
import '../models/recipe.dart';

class RecipeService {
  List<Recipe>? _cache;

  Future<List<Recipe>> loadRecipes([AssetBundle? bundle]) async {
    if (_cache != null) return _cache!;
    final assetBundle = bundle ?? rootBundle;
    final jsonStr = await assetBundle.loadString('assets/data/recipes.json');
    final List<dynamic> jsonList = json.decode(jsonStr) as List<dynamic>;
    _cache = jsonList
        .map((e) => Recipe.fromJson(e as Map<String, dynamic>))
        .toList();
    return _cache!;
  }
}
```

- [ ] **Step 2: Run analysis**

Run: `cd /Users/shikun/Developer/opensource/fresh_pantry && flutter analyze lib/services/recipe_service.dart`

Expected: No errors

- [ ] **Step 3: Commit**

```bash
git add lib/services/recipe_service.dart
git commit -m "feat: add RecipeService for loading recipes from JSON asset"
```

---

### Task 4: Rewrite recipe_provider.dart with new algorithm

**Files:**
- Modify: `lib/providers/recipe_provider.dart`

- [ ] **Step 1: Rewrite `lib/providers/recipe_provider.dart`**

Replace the entire file with:

```dart
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/recipe.dart';
import '../models/ingredient.dart';
import '../services/recipe_service.dart';
import 'inventory_provider.dart';

/// Singleton RecipeService instance
final recipeServiceProvider = Provider<RecipeService>((ref) {
  return RecipeService();
});

/// All available recipes loaded from JSON asset
final recipesProvider = FutureProvider<List<Recipe>>((ref) async {
  final service = ref.read(recipeServiceProvider);
  return service.loadRecipes();
});

/// Checks if an inventory item name matches a recipe ingredient name.
/// Uses exact match first, then substring match with a minimum length of 2.
bool _ingredientMatches(String inventoryName, String recipeName) {
  if (inventoryName == recipeName) return true;
  if (inventoryName.length >= 2 && recipeName.length >= 2) {
    return inventoryName.contains(recipeName) ||
        recipeName.contains(inventoryName);
  }
  return false;
}

/// Recipes scored and sorted by inventory match + expiry bonus
final recommendedRecipesProvider = Provider<AsyncValue<List<ScoredRecipe>>>((ref) {
  final recipesAsync = ref.watch(recipesProvider);
  final inventory = ref.watch(inventoryProvider);

  return recipesAsync.when(
    loading: () => const AsyncValue.loading(),
    error: (e, st) => AsyncValue.error(e, st),
    data: (recipes) {
      final scored = recipes.map((recipe) {
        int matchedCount = 0;
        int expiringMatchedCount = 0;

        for (final recipeIng in recipe.ingredients) {
          for (final invItem in inventory) {
            if (_ingredientMatches(invItem.name, recipeIng.name)) {
              matchedCount++;
              if (invItem.state == FreshnessState.expiringSoon ||
                  invItem.state == FreshnessState.expired) {
                expiringMatchedCount++;
              }
              break; // Found a match for this ingredient, move to next
            }
          }
        }

        final totalCount = recipe.ingredients.length;
        final baseScore = totalCount > 0 ? matchedCount / totalCount : 0.0;
        final expiryBonus = expiringMatchedCount * 0.15;
        final score = baseScore + expiryBonus;

        return ScoredRecipe(
          recipe: recipe,
          score: score,
          matchedCount: matchedCount,
          expiringMatchedCount: expiringMatchedCount,
        );
      }).toList();

      scored.sort((a, b) => b.score.compareTo(a.score));
      return AsyncValue.data(scored);
    },
  );
});

/// Legacy helper — count of matching inventory items for a recipe.
/// Used by RecipeDetailScreen.
int matchedIngredientCount(List<Ingredient> inventory, Recipe recipe) {
  int count = 0;
  for (final recipeIng in recipe.ingredients) {
    for (final invItem in inventory) {
      if (_ingredientMatches(invItem.name, recipeIng.name)) {
        count++;
        break;
      }
    }
  }
  return count;
}

/// Check if a specific recipe ingredient is available in inventory,
/// and whether it is expiring.
({bool available, bool expiring}) ingredientStatus(
  List<Ingredient> inventory,
  String ingredientName,
) {
  for (final invItem in inventory) {
    if (_ingredientMatches(invItem.name, ingredientName)) {
      final isExpiring = invItem.state == FreshnessState.expiringSoon ||
          invItem.state == FreshnessState.expired;
      return (available: true, expiring: isExpiring);
    }
  }
  return (available: false, expiring: false);
}
```

- [ ] **Step 2: Run analysis**

Run: `cd /Users/shikun/Developer/opensource/fresh_pantry && flutter analyze lib/providers/recipe_provider.dart`

Expected: No errors in this file (other files may still have errors due to API changes — fixed in subsequent tasks)

- [ ] **Step 3: Commit**

```bash
git add lib/providers/recipe_provider.dart
git commit -m "feat: rewrite recipe provider with expiry-aware scoring algorithm"
```

---

### Task 5: Remove mock recipes from mock_data.dart

**Files:**
- Modify: `lib/data/mock_data.dart`

- [ ] **Step 1: Remove the `recipes` constant from `MockData`**

In `lib/data/mock_data.dart`, delete lines 153–208 (the entire `static const recipes = [...]` block including all three Recipe entries and the closing `];`).

- [ ] **Step 2: Remove the Recipe import if present**

Check if `mock_data.dart` imports `recipe.dart`. If so, remove the import line since `recipes` no longer references `Recipe`.

- [ ] **Step 3: Run analysis**

Run: `cd /Users/shikun/Developer/opensource/fresh_pantry && flutter analyze lib/data/mock_data.dart`

Expected: No errors

- [ ] **Step 4: Commit**

```bash
git add lib/data/mock_data.dart
git commit -m "refactor: remove mock recipe data (replaced by JSON asset)"
```

---

### Task 6: Update Dashboard screen for async recipes + expiry sections

**Files:**
- Modify: `lib/screens/dashboard_screen.dart`

- [ ] **Step 1: Update imports**

At the top of `lib/screens/dashboard_screen.dart`, the imports stay the same. No new imports needed — `recipe_provider.dart` and `recipe_card.dart` are already imported.

- [ ] **Step 2: Update `build()` method to use async recommendedRecipesProvider**

In the `build()` method, line 28 currently reads:
```dart
final recommendedRecipes = ref.watch(recommendedRecipesProvider);
```

Replace it with:
```dart
final recommendedRecipesAsync = ref.watch(recommendedRecipesProvider);
final scoredRecipes = recommendedRecipesAsync.valueOrNull ?? [];
```

- [ ] **Step 3: Update CuratorsTipCard section (lines 232–248)**

Replace the existing CuratorsTipCard block (lines 232–248) with:

```dart
          // ── Curator's Tip ──
          if (scoredRecipes.isNotEmpty)
            GestureDetector(
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) =>
                        RecipeDetailScreen(recipe: scoredRecipes.first.recipe),
                  ),
                );
              },
              child: CuratorsTipCard(
                tip:
                    '根据您的库存，推荐制作「${scoredRecipes.first.recipe.name}」——匹配 ${scoredRecipes.first.matchedCount}/${scoredRecipes.first.recipe.ingredients.length} 种食材${scoredRecipes.first.expiringMatchedCount > 0 ? '，可消耗 ${scoredRecipes.first.expiringMatchedCount} 种临期食材' : ''}',
              ),
            ),
```

- [ ] **Step 4: Update `_showRecipeSheet` method (lines 265–351)**

Replace the entire `_showRecipeSheet` method with:

```dart
  void _showRecipeSheet(BuildContext context, WidgetRef ref) {
    final recommendedAsync = ref.read(recommendedRecipesProvider);
    final scoredList = recommendedAsync.valueOrNull ?? [];

    // Split into expiry-priority and general lists
    final expiryRecipes = scoredList
        .where((s) => s.expiringMatchedCount > 0)
        .take(3)
        .toList();
    final allRecipes = scoredList;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        return DraggableScrollableSheet(
          initialChildSize: 0.6,
          minChildSize: 0.4,
          maxChildSize: 0.85,
          expand: false,
          builder: (context, scrollController) {
            return Padding(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Handle bar
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: AppColors.outline,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    '食谱推荐',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.3,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '根据您的库存食材智能推荐',
                    style: GoogleFonts.manrope(
                      fontSize: 14,
                      color: AppColors.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 20),
                  Expanded(
                    child: allRecipes.isEmpty
                        ? Center(
                            child: Text(
                              '添加库存食材后，将为你推荐可做的菜谱',
                              style: GoogleFonts.manrope(
                                fontSize: 14,
                                color: AppColors.onSurfaceVariant,
                              ),
                            ),
                          )
                        : ListView(
                            controller: scrollController,
                            children: [
                              // Expiry section
                              if (expiryRecipes.isNotEmpty) ...[
                                Row(
                                  children: [
                                    Icon(Icons.warning_amber_rounded,
                                        size: 18, color: Colors.orange[700]),
                                    const SizedBox(width: 6),
                                    Text(
                                      '消耗临期食材',
                                      style: GoogleFonts.plusJakartaSans(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w700,
                                        color: Colors.orange[700],
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 10),
                                ...expiryRecipes.map((scored) => RecipeCard(
                                      recipe: scored.recipe,
                                      matchedCount: scored.matchedCount,
                                      expiringMatchedCount:
                                          scored.expiringMatchedCount,
                                      onTap: () {
                                        Navigator.pop(context);
                                        Navigator.push(
                                          context,
                                          MaterialPageRoute(
                                            builder: (_) => RecipeDetailScreen(
                                                recipe: scored.recipe),
                                          ),
                                        );
                                      },
                                    )),
                                const SizedBox(height: 16),
                              ],
                              // General section
                              Text(
                                '推荐菜谱',
                                style: GoogleFonts.plusJakartaSans(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 10),
                              ...allRecipes.map((scored) => RecipeCard(
                                    recipe: scored.recipe,
                                    matchedCount: scored.matchedCount,
                                    expiringMatchedCount:
                                        scored.expiringMatchedCount,
                                    onTap: () {
                                      Navigator.pop(context);
                                      Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (_) => RecipeDetailScreen(
                                              recipe: scored.recipe),
                                        ),
                                      );
                                    },
                                  )),
                            ],
                          ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
```

- [ ] **Step 5: Run analysis**

Run: `cd /Users/shikun/Developer/opensource/fresh_pantry && flutter analyze lib/screens/dashboard_screen.dart`

Expected: May show errors in `RecipeCard` due to new `expiringMatchedCount` parameter — fixed in Task 7.

- [ ] **Step 6: Commit**

```bash
git add lib/screens/dashboard_screen.dart
git commit -m "feat: update dashboard with async recipes and expiry-priority sections"
```

---

### Task 7: Update RecipeCard widget with difficulty, category, and expiry badge

**Files:**
- Modify: `lib/widgets/recipe_card.dart`

- [ ] **Step 1: Rewrite `lib/widgets/recipe_card.dart`**

Replace the entire file with:

```dart
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../models/recipe.dart';
import '../theme/app_theme.dart';

class RecipeCard extends StatelessWidget {
  final Recipe recipe;
  final int matchedCount;
  final int expiringMatchedCount;
  final VoidCallback? onTap;

  const RecipeCard({
    super.key,
    required this.recipe,
    required this.matchedCount,
    this.expiringMatchedCount = 0,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: AppColors.surfaceContainerLowest,
          borderRadius: BorderRadius.circular(16),
        ),
        clipBehavior: Clip.antiAlias,
        child: Row(
          children: [
            // Category icon placeholder (no images available)
            Container(
              width: 80,
              height: 96,
              decoration: BoxDecoration(
                color: AppColors.surfaceContainerLow,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(16),
                  bottomLeft: Radius.circular(16),
                ),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(_iconForCategory(recipe.category),
                      size: 28, color: AppColors.primary),
                  const SizedBox(height: 4),
                  Text(
                    recipe.category,
                    style: GoogleFonts.manrope(
                      fontSize: 10,
                      color: AppColors.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            // Info
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Title row
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            recipe.name,
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: AppColors.onSurface,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (expiringMatchedCount > 0)
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.orange[50],
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              '消耗临期',
                              style: GoogleFonts.manrope(
                                fontSize: 9,
                                fontWeight: FontWeight.w700,
                                color: Colors.orange[700],
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      recipe.description,
                      style: GoogleFonts.manrope(
                        fontSize: 12,
                        color: AppColors.onSurfaceVariant,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 6),
                    // Meta row: difficulty + time + match count
                    Row(
                      children: [
                        // Difficulty stars
                        Text(
                          '★' * recipe.difficulty +
                              '☆' * (5 - recipe.difficulty),
                          style: TextStyle(
                              fontSize: 10, color: Colors.orange[400]),
                        ),
                        const SizedBox(width: 8),
                        Icon(Icons.timer_outlined,
                            size: 12, color: AppColors.onSurfaceVariant),
                        const SizedBox(width: 2),
                        Text(
                          '${recipe.cookingMinutes}分钟',
                          style: GoogleFonts.manrope(
                            fontSize: 11,
                            color: AppColors.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Icon(Icons.checklist,
                            size: 12, color: AppColors.primary),
                        const SizedBox(width: 2),
                        Text(
                          '$matchedCount/${recipe.ingredients.length}已备',
                          style: GoogleFonts.manrope(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: AppColors.primary,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const Padding(
              padding: EdgeInsets.only(right: 10),
              child: Icon(Icons.chevron_right,
                  color: AppColors.outline, size: 20),
            ),
          ],
        ),
      ),
    );
  }

  IconData _iconForCategory(String category) {
    return switch (category) {
      '素菜' => Icons.eco,
      '荤菜' => Icons.restaurant,
      '水产' => Icons.set_meal,
      '早餐' => Icons.free_breakfast,
      '主食' => Icons.rice_bowl,
      '汤与粥' => Icons.soup_kitchen,
      '甜品' => Icons.cake,
      '饮料' => Icons.local_cafe,
      '酱料' => Icons.water_drop,
      '半成品加工' => Icons.microwave,
      _ => Icons.restaurant_outlined,
    };
  }
}
```

- [ ] **Step 2: Run analysis**

Run: `cd /Users/shikun/Developer/opensource/fresh_pantry && flutter analyze lib/widgets/recipe_card.dart`

Expected: No errors

- [ ] **Step 3: Commit**

```bash
git add lib/widgets/recipe_card.dart
git commit -m "feat: enhance RecipeCard with difficulty stars, category icon, and expiry badge"
```

---

### Task 8: Update RecipeDetailScreen for new model

**Files:**
- Modify: `lib/screens/recipe_detail_screen.dart`

- [ ] **Step 1: Rewrite `lib/screens/recipe_detail_screen.dart`**

Replace the entire file with:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../models/recipe.dart';
import '../providers/inventory_provider.dart';
import '../providers/recipe_provider.dart';
import '../theme/app_theme.dart';

class RecipeDetailScreen extends ConsumerWidget {
  final Recipe recipe;

  const RecipeDetailScreen({super.key, required this.recipe});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final inventory = ref.watch(inventoryProvider);
    final matched = matchedIngredientCount(inventory, recipe);

    return Scaffold(
      backgroundColor: AppColors.surface,
      body: CustomScrollView(
        slivers: [
          // ── Gradient header (no image) ──
          SliverAppBar(
            expandedHeight: 160,
            pinned: true,
            backgroundColor: AppColors.primary,
            foregroundColor: Colors.white,
            flexibleSpace: FlexibleSpaceBar(
              background: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      AppColors.primary,
                      AppColors.primary.withValues(alpha: 0.7),
                    ],
                  ),
                ),
                child: Center(
                  child: Icon(
                    _iconForCategory(recipe.category),
                    size: 56,
                    color: Colors.white.withValues(alpha: 0.5),
                  ),
                ),
              ),
            ),
          ),

          SliverPadding(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 40),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                // ── Title ──
                Text(
                  recipe.name,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 26,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.5,
                    color: AppColors.onSurface,
                  ),
                ),
                const SizedBox(height: 8),
                // ── Difficulty + Category ──
                Row(
                  children: [
                    Text(
                      '★' * recipe.difficulty +
                          '☆' * (5 - recipe.difficulty),
                      style: TextStyle(
                          fontSize: 14, color: Colors.orange[400]),
                    ),
                    const SizedBox(width: 10),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: AppColors.surfaceContainerLow,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        recipe.category,
                        style: GoogleFonts.manrope(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: AppColors.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  recipe.description,
                  style: GoogleFonts.manrope(
                    fontSize: 15,
                    color: AppColors.onSurfaceVariant,
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 16),

                // ── Meta chips ──
                Row(
                  children: [
                    _buildChip(
                      Icons.timer_outlined,
                      '${recipe.cookingMinutes}分钟',
                    ),
                    const SizedBox(width: 10),
                    _buildChip(
                      Icons.checklist,
                      '$matched/${recipe.ingredients.length} 食材已备',
                    ),
                  ],
                ),
                const SizedBox(height: 32),

                // ── Ingredients ──
                Text(
                  '所需食材',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 12),
                ...recipe.ingredients.map((ing) {
                  final status = ingredientStatus(inventory, ing.name);
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      children: [
                        Icon(
                          status.available
                              ? Icons.check_circle
                              : Icons.circle_outlined,
                          size: 20,
                          color: status.available
                              ? (status.expiring
                                  ? Colors.orange
                                  : AppColors.primary)
                              : AppColors.onSurfaceVariant,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            '${ing.name}  ${ing.amount}',
                            style: GoogleFonts.manrope(
                              fontSize: 15,
                              color: status.available
                                  ? AppColors.onSurface
                                  : AppColors.onSurfaceVariant,
                              decoration: status.available
                                  ? null
                                  : TextDecoration.lineThrough,
                            ),
                          ),
                        ),
                        if (status.available && status.expiring)
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.orange[50],
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              '临期',
                              style: GoogleFonts.manrope(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: Colors.orange[700],
                              ),
                            ),
                          )
                        else if (status.available)
                          Text(
                            '库存中',
                            style: GoogleFonts.manrope(
                              fontSize: 12,
                              color: AppColors.primary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                      ],
                    ),
                  );
                }),
                const SizedBox(height: 32),

                // ── Steps ──
                Text(
                  '烹饪步骤',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 12),
                ...recipe.steps.asMap().entries.map((entry) {
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: 28,
                          height: 28,
                          decoration: BoxDecoration(
                            color: AppColors.primaryContainer,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          alignment: Alignment.center,
                          child: Text(
                            '${entry.key + 1}',
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: AppColors.primary,
                            ),
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Text(
                            entry.value,
                            style: GoogleFonts.manrope(
                              fontSize: 15,
                              color: AppColors.onSurface,
                              height: 1.5,
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                }),
              ]),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildChip(IconData icon, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: AppColors.primary),
          const SizedBox(width: 6),
          Text(
            label,
            style: GoogleFonts.manrope(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: AppColors.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  IconData _iconForCategory(String category) {
    return switch (category) {
      '素菜' => Icons.eco,
      '荤菜' => Icons.restaurant,
      '水产' => Icons.set_meal,
      '早餐' => Icons.free_breakfast,
      '主食' => Icons.rice_bowl,
      '汤与粥' => Icons.soup_kitchen,
      '甜品' => Icons.cake,
      '饮料' => Icons.local_cafe,
      '酱料' => Icons.water_drop,
      '半成品加工' => Icons.microwave,
      _ => Icons.restaurant_outlined,
    };
  }
}
```

- [ ] **Step 2: Run analysis**

Run: `cd /Users/shikun/Developer/opensource/fresh_pantry && flutter analyze lib/screens/recipe_detail_screen.dart`

Expected: No errors

- [ ] **Step 3: Commit**

```bash
git add lib/screens/recipe_detail_screen.dart
git commit -m "feat: update RecipeDetailScreen with difficulty, category, and expiry indicators"
```

---

### Task 9: Final verification

**Files:** None (verification only)

- [ ] **Step 1: Run full flutter analyze**

Run: `cd /Users/shikun/Developer/opensource/fresh_pantry && flutter analyze`

Expected: No new errors (only pre-existing warnings in `batch_entry_screen.dart` are acceptable)

- [ ] **Step 2: Verify JSON asset loads correctly**

Check that `assets/data/recipes.json` is valid JSON by running:

```bash
cd /Users/shikun/Developer/opensource/fresh_pantry && dart run -e "import 'dart:io'; import 'dart:convert'; void main() { final f = File('assets/data/recipes.json'); final j = json.decode(f.readAsStringSync()) as List; print('Loaded \${j.length} recipes'); }"
```

Expected: `Loaded 60 recipes` (approximate count)

- [ ] **Step 3: Commit any remaining fixes**

```bash
git add -A
git commit -m "fix: resolve any remaining analysis issues"
```
