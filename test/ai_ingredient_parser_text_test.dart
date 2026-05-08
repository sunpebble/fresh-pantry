// test/ai_ingredient_parser_text_test.dart
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:fresh_pantry/models/storage_area.dart';
import 'package:fresh_pantry/services/ai_ingredient_parser.dart';

String _f(String name) => File('test/fixtures/ai_responses/$name').readAsStringSync();

void main() {
  test('fromText returns single ingredient', () async {
    final list = await AiIngredientParser.fromText(
      '番茄 3 个',
      chatFn: (_) async => _f('ingredient_text_simple.json'),
    );
    expect(list.single.name.value, '番茄');
    expect(list.single.quantity.value, '3');
    expect(list.single.storage.value, IconType.fridge);
    expect(list.single.shelfLifeDays.value, 7);
  });

  test('fromText returns multiple ingredients', () async {
    final list = await AiIngredientParser.fromText(
      '番茄 3 个 鸡蛋 6 颗 面条 1 把',
      chatFn: (_) async => _f('ingredient_text_complex.json'),
    );
    expect(list.length, 3);
    expect(list.last.storage.value, IconType.pantry);
  });

  test('fromText with empty input throws ArgumentError', () async {
    expect(
      () => AiIngredientParser.fromText('', chatFn: (_) async => '[]'),
      throwsArgumentError,
    );
  });
}
