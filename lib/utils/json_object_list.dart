import 'dart:convert';

List<Map<String, dynamic>> decodeJsonObjectList(String source) {
  final decoded = json.decode(source);
  if (decoded is! List<dynamic>) {
    throw const FormatException('Expected a JSON list');
  }

  return decoded.whereType<Map<String, dynamic>>().toList(growable: false);
}
