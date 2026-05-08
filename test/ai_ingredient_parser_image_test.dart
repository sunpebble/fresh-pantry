import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:fresh_pantry/services/ai_client.dart';
import 'package:fresh_pantry/services/ai_ingredient_parser.dart';

String _f(String name) => File('test/fixtures/ai_responses/$name').readAsStringSync();

void main() {
  test('fromImage encodes data URL and parses 3 items', () async {
    var capturedBody = '';
    final list = await AiIngredientParser.fromImage(
      Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xE0]),
      chatFn: (messages) async {
        capturedBody = messages.last.toJson().toString();
        return _f('ingredient_image_fridge.json');
      },
    );
    expect(list.length, 3);
    expect(capturedBody, contains('image_url'));
    expect(capturedBody, contains('data:image/jpeg;base64,'));
  });

  test('fromImage with empty bytes throws ArgumentError', () async {
    expect(
      () => AiIngredientParser.fromImage(Uint8List(0), chatFn: (_) async => '[]'),
      throwsArgumentError,
    );
  });

  test('fromImage rethrows AiException from chatFn', () async {
    expect(
      () => AiIngredientParser.fromImage(
        Uint8List.fromList([0xFF]),
        chatFn: (_) async => throw const AiAuthException('401'),
      ),
      throwsA(isA<AiAuthException>()),
    );
  });
}
