import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:fresh_pantry/data/food_categories.dart';
import 'package:fresh_pantry/models/storage_area.dart';
import 'package:fresh_pantry/services/open_food_facts_service.dart';
import 'package:http/http.dart' as http;

void main() {
  test('lookupDetails maps Open Food Facts fields into food details', () async {
    final client = _FakeHttpClient(
      http.Response('''
        {
          "products": [
            {
              "product_name": "Organic Whole Milk",
              "generic_name": "Whole milk from organic farming",
              "categories_tags": ["en:dairies", "en:milks"],
              "image_front_small_url": "https://example.com/milk-small.jpg"
            }
          ]
        }
        ''', 200),
    );

    final details = await OpenFoodFactsService.lookupDetails(
      name: '牛奶',
      client: client,
    );

    expect(details, isNotNull);
    expect(details!.displayName, '牛奶');
    expect(details.description, 'Whole milk from organic farming');
    expect(details.imageUrl, 'https://example.com/milk-small.jpg');
    expect(details.category, FoodCategories.dairyAndEggs);
    expect(details.storage, IconType.fridge);
    expect(details.shelfLifeDays, 7);
    expect(details.source, 'Open Food Facts');
  });

  test('lookupDetails returns null for empty search results', () async {
    final client = _FakeHttpClient(http.Response('{"products":[]}', 200));

    final details = await OpenFoodFactsService.lookupDetails(
      name: '未知食材',
      client: client,
    );

    expect(details, isNull);
  });

  test('lookupDetails searches Chinese names directly first', () async {
    final client = _FakeHttpClient([
      _jsonResponse('''
        {
          "products": [
            {
              "product_name": "中文牛奶",
              "generic_name": "全脂牛奶",
              "categories_tags": ["en:milks"],
              "image_front_small_url": "https://example.com/chinese-milk.jpg"
            }
          ]
        }
        '''),
    ]);

    final details = await OpenFoodFactsService.lookupDetails(
      name: '牛奶',
      client: client,
    );

    expect(details?.displayName, '牛奶');
    expect(client.requests, hasLength(1));
    expect(client.requests.single.url.path, '/cgi/search.pl');
    expect(client.requests.single.url.queryParameters['search_terms'], '牛奶');
  });

  test(
    'lookupDetails falls back to English when Chinese search is empty',
    () async {
      final client = _FakeHttpClient([
        http.Response('{"products":[]}', 200),
        http.Response('{"hits":[]}', 200),
        _jsonResponse('''
        {
          "products": [
            {
              "product_name": "Whole Milk",
              "categories_tags": ["en:milks"]
            }
          ]
        }
        '''),
      ]);

      final details = await OpenFoodFactsService.lookupDetails(
        name: '牛奶',
        client: client,
      );

      expect(details?.displayName, '牛奶');
      expect(client.requests, hasLength(3));
      expect(client.requests.first.url.queryParameters['search_terms'], '牛奶');
      expect(client.requests.last.url.queryParameters['search_terms'], 'milk');
    },
  );

  test(
    'lookupDetails uses Search-a-licious when legacy search is unavailable',
    () async {
      final client = _FakeHttpClient([
        http.Response('Service unavailable', 503),
        _jsonResponse('''
        {
          "hits": [
            {
              "product_name": "牛奶",
              "image_front_small_url": "https://example.com/search-milk.jpg"
            }
          ]
        }
        '''),
      ]);

      final details = await OpenFoodFactsService.lookupDetails(
        name: '牛奶',
        client: client,
      );

      expect(details?.displayName, '牛奶');
      expect(details?.imageUrl, 'https://example.com/search-milk.jpg');
      expect(client.requests, hasLength(2));
      expect(client.requests.first.url.path, '/cgi/search.pl');
      expect(client.requests.last.url.host, 'search.openfoodfacts.org');
      expect(client.requests.last.url.path, '/search');
      expect(client.requests.last.url.queryParameters['q'], '牛奶');
    },
  );

  test(
    'lookupDetails prefers a complete Search-a-licious hit with an image',
    () async {
      final client = _FakeHttpClient([
        http.Response('Service unavailable', 503),
        _jsonResponse('''
        {
          "hits": [
            {
              "product_name": "牛奶",
              "completeness": 0.16,
              "image_front_small_url": "https://example.com/placeholder.jpg"
            },
            {
              "product_name": "伊利纯牛奶",
              "completeness": 0.78,
              "categories_tags": ["en:milks"],
              "image_front_small_url": "https://example.com/real-milk.jpg"
            }
          ]
        }
        '''),
      ]);

      final details = await OpenFoodFactsService.lookupDetails(
        name: '牛奶',
        client: client,
      );

      expect(details?.displayName, '牛奶');
      expect(details?.imageUrl, 'https://example.com/real-milk.jpg');
    },
  );

  test('lookupDetails returns null when the network call times out', () async {
    final client = _ThrowingHttpClient(TimeoutException('search timed out'));

    final details = await OpenFoodFactsService.lookupDetails(
      name: '牛奶',
      client: client,
    );

    expect(details, isNull);
    expect(client.requests, isNotEmpty);
  });

  test('lookupDetails returns null on malformed JSON responses', () async {
    final client = _FakeHttpClient(
      http.Response('this is { not valid json', 200),
    );

    final details = await OpenFoodFactsService.lookupDetails(
      name: '牛奶',
      client: client,
    );

    expect(details, isNull);
  });

  test(
    'lookupDetails does not expose package quantity in descriptions',
    () async {
      final client = _FakeHttpClient([
        _jsonResponse('''
        {
          "products": [
            {
              "product_name": "牛奶",
              "brands": "Brand",
              "quantity": "240 ml",
              "categories_tags": ["en:milks"],
              "image_front_small_url": "https://example.com/milk.jpg"
            }
          ]
        }
        '''),
      ]);

      final details = await OpenFoodFactsService.lookupDetails(
        name: '牛奶',
        client: client,
      );

      expect(details?.description, isNot(contains('240 ml')));
      expect(details?.description, 'Open Food Facts 记录的乳品蛋类食品。');
    },
  );
}

http.Response _jsonResponse(String body) {
  return http.Response.bytes(
    utf8.encode(body),
    200,
    headers: const {'content-type': 'application/json; charset=utf-8'},
  );
}

class _FakeHttpClient extends http.BaseClient {
  _FakeHttpClient(Object responses)
    : responses =
          responses is List<http.Response>
              ? responses
              : <http.Response>[responses as http.Response];

  final List<http.Response> responses;
  final List<http.BaseRequest> requests = [];

  http.BaseRequest? get lastRequest => requests.isEmpty ? null : requests.last;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    requests.add(request);
    final index = requests.length - 1;
    final response =
        index < responses.length ? responses[index] : responses.last;
    return http.StreamedResponse(
      Stream.value(response.bodyBytes),
      response.statusCode,
      headers: response.headers,
      request: request,
      reasonPhrase: response.reasonPhrase,
    );
  }
}

class _ThrowingHttpClient extends http.BaseClient {
  _ThrowingHttpClient(this.error);

  final Object error;
  final List<http.BaseRequest> requests = [];

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    requests.add(request);
    throw error;
  }
}
