import 'dart:convert';

import '../models/draft_field.dart';
import '../models/recipe_draft.dart';
import 'ai_client.dart';

typedef AiChatFn = Future<String> Function(List<AiMessage> messages);

class AiRecipeParser {
  static Future<RecipeDraft> fromUrl(
    String url, {
    required AiChatFn chatFn,
  }) async {
    final messages = [
      AiMessage.text(
        'system',
        '你是食谱抽取助手。访问用户提供的 URL（你具备访问网页的能力），从中抽取结构化食谱。'
            '只返回 JSON，不要前后文。如果无法访问，返回 {"error":"..."}。'
            'JSON 字段：name, category, cookingMinutes (int 分钟), difficulty (int 1-5), '
            'description, imageUrl (可空), ingredients ([{name, amount}]), steps (string array)。',
      ),
      AiMessage.text('user', '请抽取这个食谱：$url'),
    ];

    final raw = await chatFn(messages);
    final json = _extractJsonObject(raw);
    if (json == null) {
      throw const AiParseException('AI 返回不是合法 JSON');
    }
    if (json.containsKey('error')) {
      throw AiParseException('AI 报告：${json['error']}');
    }

    try {
      return RecipeDraft(
        sourceUrl: url,
        name: DraftField.ai(_requireString(json, 'name')),
        category: DraftField.ai(_requireString(json, 'category')),
        cookingMinutes: DraftField.ai(_requireInt(json, 'cookingMinutes')),
        difficulty: DraftField.ai(_requireInt(json, 'difficulty')),
        description: DraftField.ai((json['description'] as String?) ?? ''),
        imageUrl: DraftField<String?>(value: json['imageUrl'] as String?, source: DraftSource.ai),
        ingredients: ((json['ingredients'] as List<dynamic>?) ?? const [])
            .whereType<Map<String, dynamic>>()
            .map((e) => RecipeIngredientDraft(
                  name: DraftField.ai(_requireString(e, 'name')),
                  amount: DraftField.ai(_requireString(e, 'amount')),
                ))
            .toList(),
        steps: ((json['steps'] as List<dynamic>?) ?? const [])
            .whereType<String>()
            .map(DraftField<String>.ai)
            .toList(),
      );
    } on AiParseException {
      rethrow;
    } catch (e) {
      throw AiParseException('字段缺失或类型不符: $e');
    }
  }

  static String _requireString(Map<String, dynamic> m, String key) {
    final v = m[key];
    if (v is! String || v.isEmpty) {
      throw AiParseException('字段 $key 缺失或非字符串');
    }
    return v;
  }

  static int _requireInt(Map<String, dynamic> m, String key) {
    final v = m[key];
    if (v is int) return v;
    if (v is num) return v.round();
    throw AiParseException('字段 $key 缺失或非整数');
  }

  static Map<String, dynamic>? _extractJsonObject(String input) {
    try {
      final v = jsonDecode(input);
      if (v is Map<String, dynamic>) return v;
    } catch (_) {}

    final fenceMatch = RegExp(r'```(?:json)?\s*(\{[\s\S]*?\})\s*```').firstMatch(input);
    if (fenceMatch != null) {
      try {
        final v = jsonDecode(fenceMatch.group(1)!);
        if (v is Map<String, dynamic>) return v;
      } catch (_) {}
    }

    final braceMatch = RegExp(r'\{[\s\S]*\}').firstMatch(input);
    if (braceMatch != null) {
      try {
        final v = jsonDecode(braceMatch.group(0)!);
        if (v is Map<String, dynamic>) return v;
      } catch (_) {}
    }
    return null;
  }
}
