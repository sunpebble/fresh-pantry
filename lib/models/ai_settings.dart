import 'package:flutter/foundation.dart';

@immutable
class AiSettings {
  const AiSettings({
    required this.baseUrl,
    required this.apiKey,
    required this.model,
    this.timeout = const Duration(seconds: 60),
  });

  final String baseUrl;
  final String apiKey;
  final String model;
  final Duration timeout;

  bool get isConfigured =>
      baseUrl.isNotEmpty && apiKey.isNotEmpty && model.isNotEmpty;

  AiSettings copyWith({
    String? baseUrl,
    String? apiKey,
    String? model,
    Duration? timeout,
  }) =>
      AiSettings(
        baseUrl: baseUrl ?? this.baseUrl,
        apiKey: apiKey ?? this.apiKey,
        model: model ?? this.model,
        timeout: timeout ?? this.timeout,
      );

  Map<String, dynamic> toJson() => {
        'baseUrl': baseUrl,
        'apiKey': apiKey,
        'model': model,
        'timeoutSeconds': timeout.inSeconds,
      };

  factory AiSettings.fromJson(Map<String, dynamic> json) => AiSettings(
        baseUrl: (json['baseUrl'] as String?) ?? '',
        apiKey: (json['apiKey'] as String?) ?? '',
        model: (json['model'] as String?) ?? '',
        timeout: Duration(seconds: (json['timeoutSeconds'] as int?) ?? 60),
      );

  static const empty = AiSettings(baseUrl: '', apiKey: '', model: '');

  @override
  bool operator ==(Object other) =>
      other is AiSettings &&
      other.baseUrl == baseUrl &&
      other.apiKey == apiKey &&
      other.model == model &&
      other.timeout == timeout;

  @override
  int get hashCode => Object.hash(baseUrl, apiKey, model, timeout);
}
