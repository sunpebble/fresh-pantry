import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../data/food_categories.dart';
import '../data/food_knowledge.dart';
import '../models/food_details.dart';
import '../models/storage_area.dart';

/// Result returned from Open Food Facts name search.
class FoodSearchResult {
  final String productName;
  final String? imageUrl;

  const FoodSearchResult({
    required this.productName,
    this.imageUrl,
  });
}

/// Service for querying product info from Open Food Facts API.
class OpenFoodFactsService {
  static const _searchUrl = 'https://world.openfoodfacts.org/cgi/search.pl';
  static const _searchALiciousUrl = 'https://search.openfoodfacts.org/search';
  static const _productUrl = 'https://world.openfoodfacts.org/api/v2/product';
  static const _detailsFields =
      'product_name,generic_name,categories_tags,categories,'
      'image_front_small_url,image_front_url,image_small_url,image_url,'
      'image_thumb_url,completeness';
  static const _timeout = Duration(seconds: 8);
  static const _retryCount = 1;
  static const _retryDelay = Duration(milliseconds: 500);
  static const _maxSearchResults = 1;
  static const _maxDetailSearchResults = 8;
  static const _headers = <String, String>{
    'User-Agent': 'FreshPantry/1.0 (Flutter)',
  };

  /// Category keyword mapping: OFF categories_tags substring → app category.
  static const _categoryMapping = <String, String>{
    // 乳品蛋类
    'dairy': '乳品蛋类',
    'milk': '乳品蛋类',
    'cheese': '乳品蛋类',
    'yogurt': '乳品蛋类',
    'butter': '乳品蛋类',
    'cream': '乳品蛋类',
    'egg': '乳品蛋类',
    'lait': '乳品蛋类',
    'fromage': '乳品蛋类',
    // 果蔬生鲜
    'fruit': '果蔬生鲜',
    'vegetable': '果蔬生鲜',
    'legume': '果蔬生鲜',
    'salad': '果蔬生鲜',
    'produce': '果蔬生鲜',
    'fresh': '果蔬生鲜',
    // 肉类海鲜
    'meat': '肉类海鲜',
    'beef': '肉类海鲜',
    'pork': '肉类海鲜',
    'chicken': '肉类海鲜',
    'poultry': '肉类海鲜',
    'fish': '肉类海鲜',
    'seafood': '肉类海鲜',
    'shrimp': '肉类海鲜',
    'viande': '肉类海鲜',
    'poisson': '肉类海鲜',
    // 香料草本
    'spice': '香料草本',
    'herb': '香料草本',
    'seasoning': '香料草本',
    'pepper': '香料草本',
    'salt': '香料草本',
    'condiment': FoodCategories.herbsAndSpices,
    'sauce': FoodCategories.herbsAndSpices,
    'épice': '香料草本',
    // Broad shelf-stable catchall.
    'cereal': FoodCategories.other,
    'pasta': FoodCategories.other,
    'rice': FoodCategories.other,
    'bread': FoodCategories.other,
    'flour': FoodCategories.other,
    'oil': FoodCategories.other,
    'sugar': FoodCategories.other,
    'snack': FoodCategories.other,
    'beverage': FoodCategories.other,
    'drink': FoodCategories.other,
    'canned': FoodCategories.other,
    'conserve': FoodCategories.other,
    'biscuit': FoodCategories.other,
    'chocolate': FoodCategories.other,
    'coffee': FoodCategories.other,
    'tea': FoodCategories.other,
    'juice': FoodCategories.other,
    'water': FoodCategories.other,
    'noodle': FoodCategories.other,
    'grain': FoodCategories.other,
  };

  /// Search for a product by name. Returns the best match as a [FoodSearchResult]
  /// or `null` if nothing relevant is found.
  static Future<FoodSearchResult?> searchByName(String name) async {
    try {
      final uri = Uri.parse(
        '$_searchUrl'
        '?search_terms=${Uri.encodeComponent(name)}'
        '&search_simple=1&action=process&json=1&page_size=$_maxSearchResults'
        '&fields=product_name,image_front_small_url',
      );
      final response = await _fetch(uri);

      if (response.statusCode != 200) return null;

      final json = _asMap(jsonDecode(response.body));
      if (json == null) return null;

      final products = _asList(json['products']);
      if (products == null || products.isEmpty) return null;

      final first = products.first;
      final product = _asMap(first);
      if (product == null) return null;

      final productName = _asString(product['product_name']);
      if (productName == null || productName.trim().isEmpty) return null;

      final imageUrl = _asString(product['image_front_small_url']);

      return FoodSearchResult(
        productName: productName.trim(),
        imageUrl: imageUrl,
      );
    } on TimeoutException catch (e, stack) {
      debugPrint('OpenFoodFacts searchByName timeout: $e\n$stack');
      return null;
    } on http.ClientException catch (e, stack) {
      debugPrint('OpenFoodFacts searchByName HTTP error: $e\n$stack');
      return null;
    } on FormatException catch (e, stack) {
      debugPrint('OpenFoodFacts searchByName format error: $e\n$stack');
      return null;
    } catch (e, stack) {
      debugPrint('OpenFoodFacts searchByName unexpected error: $e\n$stack');
      return null;
    }
  }

  /// Lookup basic food details by barcode first, then by name.
  static Future<FoodDetails?> lookupDetails({
    required String name,
    String? barcode,
    http.Client? client,
    DateTime? fetchedAt,
  }) async {
    try {
      final trimmedBarcode = barcode?.trim();
      final lookupTime = fetchedAt ?? DateTime.now();
      if (trimmedBarcode != null && trimmedBarcode.isNotEmpty) {
        return _lookupDetailsByBarcode(
          barcode: trimmedBarcode,
          fallbackName: name,
          client: client,
          fetchedAt: lookupTime,
        );
      }

      for (final searchTerm in _searchTermsFor(name)) {
        final details = await _lookupDetailsByName(
          searchTerm: searchTerm,
          fallbackName: name,
          client: client,
          fetchedAt: lookupTime,
        );
        if (details != null) return details;
      }

      return null;
    } on TimeoutException catch (e, stack) {
      debugPrint('OpenFoodFacts lookupDetails timeout: $e\n$stack');
      return null;
    } on http.ClientException catch (e, stack) {
      debugPrint('OpenFoodFacts lookupDetails HTTP error: $e\n$stack');
      return null;
    } on FormatException catch (e, stack) {
      debugPrint('OpenFoodFacts lookupDetails format error: $e\n$stack');
      return null;
    } catch (e, stack) {
      debugPrint('OpenFoodFacts lookupDetails unexpected error: $e\n$stack');
      return null;
    }
  }

  static Future<FoodDetails?> _lookupDetailsByBarcode({
    required String barcode,
    required String fallbackName,
    required http.Client? client,
    required DateTime fetchedAt,
  }) async {
    final uri = Uri.parse(
      '$_productUrl/${Uri.encodeComponent(barcode)}?fields=$_detailsFields',
    );
    final response = await _fetch(uri, client: client);
    if (response.statusCode != 200) return null;

    final json = _asMap(jsonDecode(response.body));
    final product = json == null ? null : _asMap(json['product']);
    if (product == null) return null;

    return _productToFoodDetails(
      product,
      fallbackName: fallbackName,
      fetchedAt: fetchedAt,
      preferFallbackDisplayName: false,
    );
  }

  static Future<FoodDetails?> _lookupDetailsByName({
    required String searchTerm,
    required String fallbackName,
    required http.Client? client,
    required DateTime fetchedAt,
  }) async {
    final legacyUri = Uri.parse(
      '$_searchUrl'
      '?search_terms=${Uri.encodeComponent(searchTerm)}'
      '&search_simple=1&action=process&json=1'
      '&page_size=$_maxDetailSearchResults'
      '&fields=$_detailsFields',
    );
    final legacyResponse = await _fetch(legacyUri, client: client);
    if (legacyResponse.statusCode == 200) {
      final json = _asMap(jsonDecode(legacyResponse.body));
      final product =
          json == null ? null : _bestProduct(json['products'], fallbackName);
      if (product != null) {
        return _productToFoodDetails(
          product,
          fallbackName: fallbackName,
          fetchedAt: fetchedAt,
          preferFallbackDisplayName: true,
        );
      }
    }

    final searchALiciousUri = Uri.parse(
      '$_searchALiciousUrl'
      '?q=${Uri.encodeComponent(searchTerm)}'
      '&page_size=$_maxDetailSearchResults&fields=$_detailsFields',
    );
    final response = await _fetch(searchALiciousUri, client: client);
    if (response.statusCode != 200) return null;

    final json = _asMap(jsonDecode(response.body));
    final product =
        json == null ? null : _bestProduct(json['hits'], fallbackName);
    if (product == null) return null;

    return _productToFoodDetails(
      product,
      fallbackName: fallbackName,
      fetchedAt: fetchedAt,
      preferFallbackDisplayName: true,
    );
  }

  /// Match OFF categories_tags against keyword map. Returns the first matched
  /// app category or `null`.
  static String? _resolveCategory(List<dynamic>? tags) {
    if (tags == null || tags.isEmpty) return null;

    for (final tag in tags) {
      final lower = tag.toString().toLowerCase();
      for (final entry in _categoryMapping.entries) {
        if (lower.contains(entry.key)) {
          return entry.value;
        }
      }
    }
    return null;
  }

  /// Perform an HTTP GET with retry logic.
  static Future<http.Response> _fetch(Uri uri, {http.Client? client}) async {
    final httpClient = client ?? http.Client();
    try {
      for (var attempt = 0; attempt <= _retryCount; attempt++) {
        try {
          final response = await httpClient
              .get(uri, headers: _headers)
              .timeout(_timeout);
          return response;
        } on TimeoutException {
          if (attempt == _retryCount) rethrow;
        } on http.ClientException {
          if (attempt == _retryCount) rethrow;
        }
        await Future<void>.delayed(_retryDelay);
      }
      throw StateError('Unreachable');
    } finally {
      if (client == null) httpClient.close();
    }
  }

  static Map<String, dynamic>? _bestProduct(
    dynamic productsValue,
    String fallbackName,
  ) {
    final products = _asList(productsValue);
    if (products == null || products.isEmpty) return null;

    Map<String, dynamic>? best;
    var bestScore = double.negativeInfinity;
    for (final value in products) {
      final product = _asMap(value);
      if (product == null) continue;

      final score = _productQualityScore(product, fallbackName);
      if (score > bestScore) {
        best = product;
        bestScore = score;
      }
    }
    return best;
  }

  static double _productQualityScore(
    Map<String, dynamic> product,
    String fallbackName,
  ) {
    var score = 0.0;
    final query = fallbackName.trim().toLowerCase();

    if (_imageUrlForProduct(product) != null) {
      score += 80;
    }

    final completeness = product['completeness'];
    if (completeness is num) {
      final normalizedCompleteness = completeness.clamp(0, 1).toDouble();
      score += normalizedCompleteness * 30;
      if (normalizedCompleteness < 0.25) {
        score -= 100;
      }
    }

    final productName = _asString(product['product_name']);
    if (productName != null && productName.trim().isNotEmpty) {
      final normalizedName = productName.trim().toLowerCase();
      score += 10;
      if (query.isNotEmpty) {
        if (normalizedName == query) {
          score += 70;
        } else if (normalizedName.contains(query)) {
          score += 50;
        }

        final extraLength = normalizedName.length - query.length;
        if (extraLength > 0) {
          score -= extraLength * 5;
        }
      }
    }

    final genericName = _asString(product['generic_name']);
    if (genericName != null && genericName.trim().isNotEmpty) {
      score += 3;
    }

    return score;
  }

  static FoodDetails? _productToFoodDetails(
    Map<String, dynamic> product, {
    required String fallbackName,
    required DateTime fetchedAt,
    required bool preferFallbackDisplayName,
  }) {
    final displayName = _firstNonEmpty(
      preferFallbackDisplayName
          ? [fallbackName, product['product_name'], product['generic_name']]
          : [product['product_name'], product['generic_name'], fallbackName],
    );
    if (displayName == null || displayName.trim().isEmpty) return null;

    final categoriesTags = _asList(product['categories_tags']);
    final category =
        _resolveCategory(categoriesTags) ??
        FoodKnowledge.categoryFor(fallbackName);
    final defaults =
        FoodKnowledge.lookup(fallbackName) ?? FoodKnowledge.lookup(displayName);

    return FoodDetails(
      displayName: displayName.trim(),
      description: _descriptionForProduct(product, category),
      imageUrl: _imageUrlForProduct(product),
      category: FoodCategories.dropdownValue(category),
      storage: defaults?.storage ?? _storageForCategory(category),
      shelfLifeDays: defaults?.shelfLifeDays,
      source: 'Open Food Facts',
      fetchedAt: fetchedAt,
    );
  }

  static String _descriptionForProduct(
    Map<String, dynamic> product,
    String category,
  ) {
    final genericName = _firstNonEmpty([product['generic_name']]);
    if (genericName != null && genericName.trim().isNotEmpty) {
      return genericName.trim();
    }

    return 'Open Food Facts 记录的$category食品。';
  }

  static IconType _storageForCategory(String category) {
    return switch (FoodCategories.dropdownValue(category)) {
      FoodCategories.dairyAndEggs => IconType.fridge,
      FoodCategories.freshProduce => IconType.fridge,
      FoodCategories.meatAndSeafood => IconType.fridge,
      _ => IconType.pantry,
    };
  }

  static String? _firstNonEmpty(List<dynamic> values) {
    for (final value in values) {
      final text = _asString(value)?.trim();
      if (text != null && text.isNotEmpty) return text;
    }
    return null;
  }

  static String? _imageUrlForProduct(Map<String, dynamic> product) {
    return _firstNonEmpty([
      product['image_front_small_url'],
      product['image_small_url'],
      product['image_front_url'],
      product['image_url'],
      product['image_thumb_url'],
    ]);
  }

  static List<String> _searchTermsFor(String name) {
    final terms = <String>[];
    final trimmedName = name.trim();
    if (trimmedName.isNotEmpty) {
      terms.add(trimmedName);
    }

    final englishName = FoodKnowledge.englishName(name);
    final trimmedEnglishName = englishName?.trim();
    if (trimmedEnglishName != null &&
        trimmedEnglishName.isNotEmpty &&
        trimmedEnglishName.toLowerCase() != trimmedName.toLowerCase()) {
      terms.add(trimmedEnglishName);
    }

    return terms;
  }

  /// Safely cast [value] to [Map<String, dynamic>].
  static Map<String, dynamic>? _asMap(dynamic value) {
    if (value is Map<String, dynamic>) return value;
    return null;
  }

  /// Safely cast [value] to [List<dynamic>].
  static List<dynamic>? _asList(dynamic value) {
    if (value is List<dynamic>) return value;
    return null;
  }

  /// Safely cast [value] to [String].
  static String? _asString(dynamic value) {
    if (value is String) return value;
    return null;
  }
}
