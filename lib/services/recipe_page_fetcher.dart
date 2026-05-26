import 'dart:convert';

import 'package:http/http.dart' as http;

import '../utils/clipboard_text.dart';
import 'ai_client.dart';

typedef RecipePageFetcherFn = Future<String> Function(String url);

const _mobileSafariUserAgent =
    'Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) '
    'AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1';

class RecipePageFetcher {
  const RecipePageFetcher._();

  static Future<String> fetchText(
    String url, {
    http.Client? client,
    Duration humanCheckRetryDelay = const Duration(milliseconds: 500),
  }) async {
    final normalizedUrl = ensureRecipeUrl(url);
    final uri = Uri.parse(normalizedUrl);
    final ownClient = client == null;
    final c = client ?? http.Client();
    try {
      for (var attempt = 0; attempt < 2; attempt += 1) {
        final response = await c
            .get(
              uri,
              headers: const {
                'User-Agent': _mobileSafariUserAgent,
                'Accept': 'text/html,application/xhtml+xml',
                'Accept-Language': 'zh-CN,zh;q=0.9',
              },
            )
            .timeout(const Duration(seconds: 20));

        if (response.statusCode != 200) {
          throw AiNetworkException('网页抓取失败 (${response.statusCode})');
        }

        final html = utf8.decode(response.bodyBytes, allowMalformed: true);
        if (_looksLikeCaptchaPage(html, response.request?.url ?? uri)) {
          if (attempt == 0) {
            await Future<void>.delayed(humanCheckRetryDelay);
            continue;
          }
          throw const AiNetworkException('目标网站需要人机验证，暂时无法自动抓取');
        }

        final text = extractRecipePageText(html);
        if (text.trim().isEmpty) {
          throw const AiParseException('网页中没有可解析的食谱内容');
        }
        return text;
      }
      throw StateError('Unreachable');
    } on AiException {
      rethrow;
    } on http.ClientException catch (e) {
      throw AiNetworkException('网页抓取失败：${e.message}');
    } finally {
      if (ownClient) c.close();
    }
  }
}

bool _looksLikeCaptchaPage(String html, Uri finalUri) {
  final lower = html.toLowerCase();
  return finalUri.path.contains('humancheck') ||
      lower.contains('humancheck_captcha') ||
      lower.contains('auth/humancheck');
}

String extractRecipePageText(String html) {
  final parts = <String>[];

  final titleMatch = RegExp(
    r'<title[^>]*>([^<]+)',
    caseSensitive: false,
  ).firstMatch(html);
  final title = _decodeHtmlEntities(titleMatch?.group(1)?.trim());
  if (title != null && title.isNotEmpty) {
    parts.add('标题: $title');
  }

  final descriptionMatch = RegExp(
    r'''name=["']description["']\s+content=["']([^"']*)["']''',
    caseSensitive: false,
  ).firstMatch(html);
  final description = _decodeHtmlEntities(descriptionMatch?.group(1)?.trim());
  if (description != null && description.isNotEmpty) {
    parts.add('摘要: $description');
  }

  final coverImageUrl = _extractCoverImageUrl(html);
  if (coverImageUrl != null && coverImageUrl.isNotEmpty) {
    parts.add('封面图片: $coverImageUrl');
  }

  var body = html;
  body = body.replaceAll(
    RegExp(r'<script[\s\S]*?</script>', caseSensitive: false),
    ' ',
  );
  body = body.replaceAll(
    RegExp(r'<style[\s\S]*?</style>', caseSensitive: false),
    ' ',
  );
  body = body.replaceAll(RegExp(r'<[^>]+>'), ' ');
  body = body.replaceAll(RegExp(r'\s+'), ' ').trim();
  if (body.length > 80_000) {
    body = body.substring(0, 80_000);
  }
  if (body.isNotEmpty) {
    parts.add('正文: $body');
  }

  return parts.join('\n\n');
}

String? _extractCoverImageUrl(String html) {
  for (final tag in RegExp(
    r'<meta\b[^>]*>',
    caseSensitive: false,
  ).allMatches(html).map((match) => match.group(0)!)) {
    final key =
        _htmlAttribute(tag, 'property') ??
        _htmlAttribute(tag, 'name') ??
        _htmlAttribute(tag, 'itemprop');
    final normalizedKey = key?.toLowerCase();
    if (normalizedKey == 'og:image' ||
        normalizedKey == 'twitter:image' ||
        normalizedKey == 'image') {
      final content = _decodeHtmlEntities(_htmlAttribute(tag, 'content'));
      if (_isHttpUrl(content)) return content;
    }
  }

  for (final match in RegExp(
    r'''<script\b[^>]*type=["']application/ld\+json["'][^>]*>([\s\S]*?)</script>''',
    caseSensitive: false,
  ).allMatches(html)) {
    final rawJson = _decodeHtmlEntities(match.group(1)?.trim());
    if (rawJson == null || rawJson.isEmpty) continue;
    try {
      final imageUrl = _imageUrlFromStructuredData(jsonDecode(rawJson));
      if (_isHttpUrl(imageUrl)) return imageUrl;
    } catch (_) {
      continue;
    }
  }

  return null;
}

String? _htmlAttribute(String tag, String name) {
  final match = RegExp(
    '$name\\s*=\\s*([\\\'"])(.*?)\\1',
    caseSensitive: false,
  ).firstMatch(tag);
  return match?.group(2);
}

String? _imageUrlFromStructuredData(
  dynamic value, {
  bool imageContext = false,
}) {
  if (value is String) {
    return imageContext ? value : null;
  }
  if (value is List) {
    for (final item in value) {
      final imageUrl = _imageUrlFromStructuredData(
        item,
        imageContext: imageContext,
      );
      if (_isHttpUrl(imageUrl)) return imageUrl;
    }
    return null;
  }
  if (value is Map<String, dynamic>) {
    final directImage = _imageUrlFromStructuredData(
      value['image'],
      imageContext: true,
    );
    if (_isHttpUrl(directImage)) return directImage;

    final type = value['@type'];
    final isImageObject =
        imageContext ||
        type == 'ImageObject' ||
        (type is List && type.contains('ImageObject'));
    if (isImageObject) {
      for (final key in const ['url', 'contentUrl', 'thumbnailUrl']) {
        final imageUrl = _imageUrlFromStructuredData(
          value[key],
          imageContext: true,
        );
        if (_isHttpUrl(imageUrl)) return imageUrl;
      }
    }

    for (final entry in value.entries) {
      if (entry.key == 'author' || entry.key == 'aggregateRating') continue;
      final imageUrl = _imageUrlFromStructuredData(entry.value);
      if (_isHttpUrl(imageUrl)) return imageUrl;
    }
  }
  return null;
}

bool _isHttpUrl(String? value) {
  if (value == null || value.isEmpty) return false;
  final uri = Uri.tryParse(value);
  return uri != null &&
      (uri.scheme == 'http' || uri.scheme == 'https') &&
      uri.host.isNotEmpty;
}

String? _decodeHtmlEntities(String? value) {
  if (value == null || value.isEmpty) return value;
  return value
      .replaceAll('&amp;', '&')
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&quot;', '"')
      .replaceAll('&#39;', "'")
      .replaceAll('&nbsp;', ' ');
}
