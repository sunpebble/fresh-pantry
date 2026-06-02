import 'package:fresh_pantry/models/recipe.dart';

/// HowToCook `dishes/<dir>/` 目录名 → 中文类别。
const Map<String, String> howtocookCategoryByDir = {
  'aquatic': '水产',
  'breakfast': '早餐',
  'condiment': '酱料',
  'dessert': '甜品',
  'drink': '饮品',
  'meat_dish': '荤菜',
  'semi-finished': '半成品',
  'soup': '汤羹',
  'staple': '主食',
  'vegetable_dish': '素菜',
};

const Map<int, int> _minutesByDifficulty = {1: 15, 2: 25, 3: 40, 4: 60, 5: 90};
const int _defaultMinutes = 30;

final RegExp _bullet = RegExp(r'^\s*[*-]\s+(.*)$');
final RegExp _ordered = RegExp(r'^\s*\d+\.\s+(.*)$');

/// 解析单篇 HowToCook 菜谱 markdown 为 [Recipe]。
/// [relativePath] 是相对 `dishes/` 的路径，例如 `meat_dish/可乐鸡翅.md`。
/// 当文档不是菜谱（无 `# ` 标题、或无 `## 操作` 段）时返回 null。
Recipe? parseHowToCookMarkdown(
  String markdown, {
  required String relativePath,
}) {
  final lines = markdown.split('\n');

  final title = _firstTitle(lines);
  if (title == null) return null;
  final name = title.endsWith('的做法')
      ? title.substring(0, title.length - 3)
      : title;

  final sections = _splitSections(lines);
  final operation = sections['操作'];
  if (operation == null) return null;

  final difficulty = _parseDifficulty(lines);
  final ingredients = _parseIngredients(sections['必备原料和工具'] ?? const []);
  final steps = _parseSteps(operation);
  final description = _parseDescription(lines);
  final category = howtocookCategoryByDir[_firstSegment(relativePath)] ?? '其他';
  final cookingMinutes = _minutesByDifficulty[difficulty] ?? _defaultMinutes;
  final id = 'howtocook:${relativePath.replaceAll(RegExp(r'\.md$'), '')}';

  return Recipe(
    id: id,
    name: name,
    category: category,
    difficulty: difficulty,
    cookingMinutes: cookingMinutes,
    description: description,
    ingredients: ingredients,
    steps: steps,
    tags: [category],
  );
}

String? _firstTitle(List<String> lines) {
  for (final line in lines) {
    final t = line.trim();
    if (t.startsWith('# ')) return t.substring(2).trim();
  }
  return null;
}

String _firstSegment(String relativePath) {
  final normalized = relativePath.replaceAll('\\', '/');
  final idx = normalized.indexOf('/');
  return idx == -1 ? '' : normalized.substring(0, idx);
}

/// 切成 `## ` 段：标题（去掉 `## `）→ 段内行。
Map<String, List<String>> _splitSections(List<String> lines) {
  final sections = <String, List<String>>{};
  String? current;
  for (final line in lines) {
    final t = line.trim();
    if (t.startsWith('## ')) {
      current = t.substring(3).trim();
      sections[current] = <String>[];
    } else if (current != null) {
      sections[current]!.add(line);
    }
  }
  return sections;
}

int _parseDifficulty(List<String> lines) {
  for (final line in lines) {
    if (line.contains('预估烹饪难度')) {
      return '★'.allMatches(line).length.clamp(0, 5);
    }
  }
  return 0;
}

/// 食材名来自「必备原料和工具」段（纯食材名，统一、可靠）。amount 留空。
List<RecipeIngredient> _parseIngredients(List<String> body) {
  final result = <RecipeIngredient>[];
  for (final line in body) {
    final m = _bullet.firstMatch(line);
    if (m == null) continue;
    final name = m.group(1)!.trim();
    if (name.isEmpty) continue;
    result.add(RecipeIngredient(name: name));
  }
  return result;
}

/// 仅取顶层有序项（`1. `…）作为步骤；缩进的子贴士忽略。
List<String> _parseSteps(List<String> body) {
  final result = <String>[];
  for (final line in body) {
    if (line.startsWith(' ') || line.startsWith('\t')) continue;
    final m = _ordered.firstMatch(line);
    if (m == null) continue;
    final step = m.group(1)!.trim();
    if (step.isNotEmpty) result.add(step);
  }
  return result;
}

/// 标题之后、`预估`/`## ` 之前的第一段非空文本。
String _parseDescription(List<String> lines) {
  final buffer = <String>[];
  var seenTitle = false;
  for (final line in lines) {
    final t = line.trim();
    if (!seenTitle) {
      if (t.startsWith('# ')) seenTitle = true;
      continue;
    }
    if (t.isEmpty) {
      if (buffer.isNotEmpty) break;
      continue;
    }
    if (t.startsWith('预估') || t.startsWith('#')) break;
    buffer.add(t);
  }
  return buffer.join(' ');
}
