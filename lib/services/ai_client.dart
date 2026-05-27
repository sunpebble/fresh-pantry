import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/ai_settings.dart';
import '../utils/ai_base_url.dart';

sealed class AiException implements Exception {
  const AiException(this.message);
  final String message;

  @override
  String toString() => '$runtimeType: $message';
}

class AiNotConfiguredException extends AiException {
  const AiNotConfiguredException() : super('AI 服务未配置');
}

class AiNetworkException extends AiException {
  const AiNetworkException(super.message);
}

class AiAuthException extends AiException {
  const AiAuthException(super.message);
}

class AiParseException extends AiException {
  const AiParseException(super.message);
}

class AiCancelledException extends AiException {
  const AiCancelledException() : super('已取消');
}

class AiContent {
  const AiContent.text(this.text) : imageDataUrl = null, type = 'text';
  const AiContent.imageDataUrl(this.imageDataUrl)
    : text = null,
      type = 'image_url';

  final String type;
  final String? text;
  final String? imageDataUrl;

  Map<String, dynamic> toJson() => switch (type) {
    'text' => {'type': 'text', 'text': text},
    'image_url' => {
      'type': 'image_url',
      'image_url': {'url': imageDataUrl},
    },
    _ => throw StateError('unsupported content type: $type'),
  };
}

class AiMessage {
  AiMessage._({required this.role, required this.content});

  final String role;
  final List<AiContent> content;

  factory AiMessage.text(String role, String text) =>
      AiMessage._(role: role, content: [AiContent.text(text)]);

  factory AiMessage.userWithImage(String text, String dataUrl) => AiMessage._(
    role: 'user',
    content: [AiContent.text(text), AiContent.imageDataUrl(dataUrl)],
  );

  Map<String, dynamic> toJson() {
    if (content.length == 1 && content.first.type == 'text') {
      return {'role': role, 'content': content.first.text};
    }
    return {'role': role, 'content': content.map((c) => c.toJson()).toList()};
  }
}

class AiClient {
  static Future<String> chat({
    required AiSettings settings,
    required List<AiMessage> messages,
    Map<String, dynamic>? responseFormat,
    http.Client? client,
  }) async {
    if (!settings.isConfigured) {
      throw const AiNotConfiguredException();
    }

    final uri = Uri.parse(
      _join(normalizeAiBaseUrl(settings.baseUrl), '/chat/completions'),
    );
    final ownClient = client == null;
    final c = client ?? http.Client();
    try {
      final body = <String, dynamic>{
        'model': settings.model,
        'messages': messages.map((m) => m.toJson()).toList(),
        'temperature': 0.2,
        'response_format': ?responseFormat,
      };

      late http.Response res;
      try {
        res = await c
            .post(
              uri,
              headers: {
                'authorization': 'Bearer ${settings.apiKey}',
                'content-type': 'application/json; charset=utf-8',
              },
              body: jsonEncode(body),
            )
            .timeout(settings.timeout);
      } on TimeoutException {
        throw const AiNetworkException('请求超时');
      } on http.ClientException catch (e) {
        throw AiNetworkException('网络错误：${e.message}');
      }

      if (res.statusCode == 401 || res.statusCode == 403) {
        throw AiAuthException('认证失败 (${res.statusCode})');
      }
      if (res.statusCode == 429) {
        throw const AiNetworkException('服务繁忙 (429)');
      }
      if (res.statusCode >= 500) {
        throw AiNetworkException('服务错误 (${res.statusCode})');
      }
      if (res.statusCode == 404) {
        throw AiNetworkException(
          '接口不存在 (404)。Base URL 应填写到 /v1，例如 https://example.com/v1，'
          '不要包含 /chat/completions',
        );
      }
      if (res.statusCode != 200) {
        final detail = res.body.trim();
        final suffix = detail.isEmpty
            ? ''
            : '：${detail.length > 120 ? '${detail.substring(0, 120)}…' : detail}';
        throw AiNetworkException('意外状态 (${res.statusCode})$suffix');
      }

      try {
        final json =
            jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
        final choices = json['choices'] as List<dynamic>?;
        if (choices == null || choices.isEmpty) {
          throw const AiParseException('响应中无 choices');
        }
        final msg =
            (choices.first as Map<String, dynamic>)['message']
                as Map<String, dynamic>?;
        final content = msg?['content'];
        if (content is! String) {
          throw const AiParseException('响应中无 content');
        }
        return content;
      } on AiException {
        rethrow;
      } catch (e) {
        throw AiParseException('解析响应失败: $e');
      }
    } finally {
      if (ownClient) c.close();
    }
  }

  static String _join(String base, String path) {
    final b = base.endsWith('/') ? base.substring(0, base.length - 1) : base;
    final p = path.startsWith('/') ? path : '/$path';
    return '$b$p';
  }
}
