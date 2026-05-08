import 'dart:convert';
import 'dart:typed_data';

import '../data/food_categories.dart';
import '../models/draft_field.dart';
import '../models/ingredient_draft.dart';
import '../models/storage_area.dart';
import 'ai_client.dart';
import 'ai_recipe_parser.dart';

const _maxTextLength = 5000;

class AiIngredientParser {
  static Future<List<IngredientDraft>> fromText(
    String text, {
    required AiChatFn chatFn,
  }) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) {
      throw ArgumentError('文本不能为空');
    }
    final input = trimmed.length > _maxTextLength
        ? trimmed.substring(0, _maxTextLength)
        : trimmed;

    final messages = [
      AiMessage.text(
        'system',
        '你是食材清单解析助手。把用户输入的食材文本拆为多条结构化条目。'
            '只返回 JSON 数组，每条 {name, quantity, unit, category, storage (fridge/pantry), shelfLifeDays}。'
            '估算合理的数量、单位、分类、存储、保质期。',
      ),
      AiMessage.text('user', input),
    ];
    final raw = await chatFn(messages);
    return _parseList(raw);
  }

  static Future<List<IngredientDraft>> fromImage(
    Uint8List imageBytes, {
    required AiChatFn chatFn,
  }) async {
    if (imageBytes.isEmpty) {
      throw ArgumentError('图片为空');
    }
    final dataUrl = 'data:image/jpeg;base64,${base64Encode(imageBytes)}';
    final messages = [
      AiMessage.text(
        'system',
        '你是食材识别助手。识别图中所有可入库的食材，返回 JSON 数组：'
            '{name, quantity, unit, category, storage (fridge/pantry), shelfLifeDays}。',
      ),
      AiMessage.userWithImage('请识别图中食材', dataUrl),
    ];
    final raw = await chatFn(messages);
    return _parseList(raw);
  }

  static List<IngredientDraft> _parseList(String raw) {
    final list = _extractJsonArray(raw);
    if (list == null) {
      throw const AiParseException('AI 返回不是合法 JSON 数组');
    }
    final items = <IngredientDraft>[];
    var idCounter = 0;
    for (final entry in list.whereType<Map<String, dynamic>>()) {
      try {
        final name = (entry['name'] as String?)?.trim();
        if (name == null || name.isEmpty) continue;
        items.add(IngredientDraft(
          id: 'ai_${DateTime.now().millisecondsSinceEpoch}_${idCounter++}',
          name: DraftField.ai(name),
          quantity: DraftField.ai((entry['quantity'] ?? '1').toString()),
          unit: DraftField.ai((entry['unit'] as String?) ?? '个'),
          category: DraftField.ai((entry['category'] as String?) ?? FoodCategories.other),
          storage: DraftField.ai(_parseStorage(entry['storage'] as String?)),
          shelfLifeDays: DraftField.ai(_parseInt(entry['shelfLifeDays'])),
        ));
      } catch (_) {
        // Skip malformed entries — keep partial results.
      }
    }
    return items;
  }

  static List<dynamic>? _extractJsonArray(String input) {
    try {
      final v = jsonDecode(input);
      if (v is List) return v;
    } catch (_) {}
    final fence = RegExp(r'```(?:json)?\s*(\[[\s\S]*?\])\s*```').firstMatch(input);
    if (fence != null) {
      try {
        final v = jsonDecode(fence.group(1)!);
        if (v is List) return v;
      } catch (_) {}
    }
    final bracket = RegExp(r'\[[\s\S]*\]').firstMatch(input);
    if (bracket != null) {
      try {
        final v = jsonDecode(bracket.group(0)!);
        if (v is List) return v;
      } catch (_) {}
    }
    return null;
  }

  // IconType only has {fridge, pantry}. Map raw input following storage_area.dart convention.
  static IconType? _parseStorage(String? raw) {
    switch (raw) {
      case 'pantry':
        return IconType.pantry;
      case 'fridge':
      case 'freezer': // legacy/AI may say freezer; treat as fridge per IconType.from convention
        return IconType.fridge;
      default:
        return null;
    }
  }

  static int? _parseInt(dynamic v) {
    if (v is int) return v;
    if (v is num) return v.round();
    if (v is String) return int.tryParse(v);
    return null;
  }
}
