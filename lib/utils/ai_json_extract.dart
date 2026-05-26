import 'dart:convert';

List<dynamic>? extractJsonArrayWithFallbacks(String input) {
  return _extractJsonWithFallbacks<List<dynamic>>(
    input,
    fencedPattern: RegExp(r'```(?:json)?\s*(\[[\s\S]*?\])\s*```'),
    inlinePattern: RegExp(r'\[[\s\S]*\]'),
  );
}

Map<String, dynamic>? extractJsonObjectWithFallbacks(String input) {
  final value = _extractJsonWithFallbacks<Map<String, dynamic>>(
    input,
    fencedPattern: RegExp(r'```(?:json)?\s*(\{[\s\S]*?\})\s*```'),
    inlinePattern: RegExp(r'\{[\s\S]*\}'),
  );
  return value;
}

T? _extractJsonWithFallbacks<T>(
  String input, {
  required RegExp fencedPattern,
  required RegExp inlinePattern,
}) {
  final direct = _decodeAs<T>(input);
  if (direct != null) return direct;

  final fenced = fencedPattern.firstMatch(input);
  if (fenced != null) {
    final value = _decodeAs<T>(fenced.group(1)!);
    if (value != null) return value;
  }

  final inline = inlinePattern.firstMatch(input);
  if (inline != null) {
    final value = _decodeAs<T>(inline.group(0)!);
    if (value != null) return value;
  }

  return null;
}

T? _decodeAs<T>(String source) {
  try {
    final value = jsonDecode(source);
    if (value is T) return value;
  } catch (_) {
    return null;
  }
  return null;
}
