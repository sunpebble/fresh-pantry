import 'package:flutter_test/flutter_test.dart';
import 'package:fresh_pantry/utils/json_object_list.dart';

void main() {
  group('decodeJsonObjectList', () {
    test('returns list of maps for valid JSON array', () {
      final result = decodeJsonObjectList('[{"a":1},{"b":2}]');
      expect(result, [
        {'a': 1},
        {'b': 2},
      ]);
    });

    test('returns empty list for empty JSON array', () {
      expect(decodeJsonObjectList('[]'), isEmpty);
    });

    test('filters out non-object elements from mixed array', () {
      final result = decodeJsonObjectList('[{"a":1},"string",42,null,{"b":2}]');
      expect(result, [
        {'a': 1},
        {'b': 2},
      ]);
    });

    test('returns empty list when all elements are non-objects', () {
      expect(decodeJsonObjectList('[1,"a",null,true]'), isEmpty);
    });

    test('throws FormatException for non-list JSON object', () {
      expect(
        () => decodeJsonObjectList('{"a":1}'),
        throwsA(isA<FormatException>()),
      );
    });

    test('throws FormatException for JSON string', () {
      expect(
        () => decodeJsonObjectList('"hello"'),
        throwsA(isA<FormatException>()),
      );
    });

    test('throws FormatException for JSON number', () {
      expect(
        () => decodeJsonObjectList('42'),
        throwsA(isA<FormatException>()),
      );
    });
  });
}
