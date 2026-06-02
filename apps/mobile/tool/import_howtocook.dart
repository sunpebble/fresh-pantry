// tool/import_howtocook.dart
//
// 用法: dart run tool/import_howtocook.dart <HowToCook clone 路径> [输出路径]
// 先 clone 一份上游:
//   git clone --depth 1 https://github.com/Anduin2017/HowToCook /tmp/HowToCook
// 数据来源: https://github.com/Anduin2017/HowToCook (Unlicense)
// 仅在 macOS/Linux 上运行（路径分隔符按 / 处理）。
// 注意：默认输出路径是相对路径，请在 apps/mobile/ 目录下运行本脚本。
import 'dart:convert';
import 'dart:io';

import 'howtocook_parser.dart';

void main(List<String> args) {
  if (args.isEmpty) {
    stderr.writeln(
      'Usage: dart run tool/import_howtocook.dart <HowToCook-clone-path> [out.json]',
    );
    exit(64);
  }
  final repoRoot = args[0];
  final outPath = args.length > 1 ? args[1] : 'assets/recipes/howtocook.json';

  final dishesDir = Directory('$repoRoot/dishes');
  if (!dishesDir.existsSync()) {
    stderr.writeln('dishes/ not found under "$repoRoot"');
    exit(66);
  }

  final mdFiles =
      dishesDir
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.md'))
          .toList()
        ..sort((a, b) => a.path.compareTo(b.path));

  final recipes = <Map<String, dynamic>>[];
  var ok = 0;
  var skippedNotRecipe = 0; // 解析器返回 null（无标题/无操作段）
  var skippedEmpty = 0; // 无食材或无步骤
  var noDifficulty = 0; // 观察项：解析成功但难度未标注（difficulty==0）
  for (final file in mdFiles) {
    final rel = file.path
        .substring(dishesDir.path.length + 1)
        .replaceAll('\\', '/');
    // Skip the upstream template under dishes/template/ (it has a title and an
    // 操作 section, so it would otherwise pass the recipe filter).
    if (rel.startsWith('template/')) {
      skippedNotRecipe++;
      continue;
    }
    final String content;
    try {
      content = file.readAsStringSync();
    } on Exception catch (e) {
      // 个别上游文件可能是非 UTF-8（如 GBK）；跳过并记录，别让整次导入中断。
      stderr.writeln('Skip (read error) $rel: $e');
      skippedNotRecipe++;
      continue;
    }
    final recipe = parseHowToCookMarkdown(content, relativePath: rel);
    if (recipe == null) {
      skippedNotRecipe++;
      continue;
    }
    if (recipe.ingredients.isEmpty || recipe.steps.isEmpty) {
      skippedEmpty++;
      continue;
    }
    if (recipe.difficulty == 0) noDifficulty++;
    recipes.add(recipe.toJson());
    ok++;
  }

  File(outPath)
    ..createSync(recursive: true)
    ..writeAsStringSync(const JsonEncoder.withIndent('  ').convert(recipes));
  stdout.writeln(
    'Imported $ok recipes '
    '(skipped: $skippedNotRecipe non-recipe, $skippedEmpty empty; '
    '$noDifficulty have no difficulty label) → $outPath',
  );
}
