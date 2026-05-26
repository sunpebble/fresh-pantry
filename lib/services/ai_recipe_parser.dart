import '../models/draft_field.dart';
import '../models/recipe_draft.dart';
import '../utils/ai_json_extract.dart';
import '../utils/clipboard_text.dart';
import 'ai_client.dart';
import 'recipe_page_fetcher.dart';

typedef AiChatFn = Future<String> Function(List<AiMessage> messages);

class AiRecipeParser {
  static Future<RecipeDraft> fromUrl(
    String url, {
    required AiChatFn chatFn,
    RecipePageFetcherFn? pageContentFetcher,
  }) async {
    final normalizedUrl = ensureRecipeUrl(url);
    final fetch = pageContentFetcher ?? RecipePageFetcher.fetchText;
    final pageText = await fetch(normalizedUrl);

    final messages = [
      AiMessage.text(
        'system',
        '你是食谱抽取助手。用户会提供食谱网页的正文内容，请从中抽取结构化食谱。'
            '不要声称无法访问网页；只根据提供的内容工作。'
            '只返回 JSON，不要前后文。如果内容不足以抽取，返回 {"error":"..."}。'
            'JSON 字段：name, category, cookingMinutes (int 分钟), difficulty (int 1-5), '
            'description, imageUrl (可空；如果网页内容包含“封面图片”，优先使用该 URL), '
            'ingredients ([{name, amount}]), steps (string array)。',
      ),
      AiMessage.text('user', '来源 URL：$normalizedUrl\n\n网页内容：\n$pageText'),
    ];

    final raw = await chatFn(messages);
    final json = extractJsonObjectWithFallbacks(raw);
    if (json == null) {
      throw const AiParseException('AI 返回不是合法 JSON');
    }
    if (json.containsKey('error')) {
      throw AiParseException('AI 报告：${json['error']}');
    }

    try {
      return RecipeDraft(
        sourceUrl: normalizedUrl,
        name: DraftField.ai(_requireString(json, 'name')),
        category: DraftField.ai(_requireString(json, 'category')),
        cookingMinutes: DraftField.ai(_requireInt(json, 'cookingMinutes')),
        difficulty: DraftField.ai(_requireInt(json, 'difficulty')),
        description: DraftField.ai((json['description'] as String?) ?? ''),
        imageUrl: DraftField<String?>(
          value: json['imageUrl'] as String?,
          source: DraftSource.ai,
        ),
        ingredients:
            ((json['ingredients'] as List<dynamic>?) ?? const [])
                .whereType<Map<String, dynamic>>()
                .map(
                  (e) => RecipeIngredientDraft(
                    name: DraftField.ai(_requireString(e, 'name')),
                    amount: DraftField.ai(_requireString(e, 'amount')),
                  ),
                )
                .toList(),
        steps:
            ((json['steps'] as List<dynamic>?) ?? const [])
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
}
