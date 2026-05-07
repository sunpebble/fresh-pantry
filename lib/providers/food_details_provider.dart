import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/food_categories.dart';
import '../data/food_knowledge.dart';
import '../models/food_details.dart';
import '../models/ingredient.dart';
import '../models/storage_area.dart';
import '../services/open_food_facts_service.dart';
import '../utils/normalize_cache_key.dart';
import '../utils/storage_labels.dart';
import 'storage_service_provider.dart';

const foodDetailsCacheStorageKey = 'food_details_cache';
const _localFoodDetailsSource = '本地食材知识库';
const _foodDetailsCacheVersion = 4;

abstract class FoodDetailsClient {
  Future<FoodDetails?> lookup(Ingredient ingredient);
}

class OpenFoodFactsDetailsClient implements FoodDetailsClient {
  const OpenFoodFactsDetailsClient();

  @override
  Future<FoodDetails?> lookup(Ingredient ingredient) {
    return OpenFoodFactsService.lookupDetails(
      name: ingredient.name,
      barcode: ingredient.barcode,
    );
  }
}

final foodDetailsClientProvider = Provider<FoodDetailsClient>(
  (ref) => const OpenFoodFactsDetailsClient(),
);

final foodDetailsRepositoryProvider = Provider<FoodDetailsRepository>((ref) {
  return FoodDetailsRepository(
    prefs: ref.read(sharedPreferencesProvider),
    client: ref.watch(foodDetailsClientProvider),
  );
});

final foodDetailsProvider = FutureProvider.autoDispose
    .family<FoodDetails, Ingredient>((ref, ingredient) {
      return ref.watch(foodDetailsRepositoryProvider).detailsFor(ingredient);
    });

String foodDetailsCacheKeyFor(Ingredient ingredient) {
  final barcode = ingredient.barcode?.trim();
  if (barcode != null && barcode.isNotEmpty) return 'barcode:$barcode';
  return 'name:${normalizeCacheKey(ingredient.name)}';
}

class FoodDetailsRepository {
  FoodDetailsRepository({required this.prefs, required this.client});

  final SharedPreferences prefs;
  final FoodDetailsClient client;

  Future<FoodDetails> detailsFor(Ingredient ingredient) async {
    final cache = _readCache();
    final key = foodDetailsCacheKeyFor(ingredient);
    final cachedValue = cache[key];
    final cachedDetails = _cachedDetailsFrom(cachedValue);
    if (cachedDetails != null &&
        _isCurrentCacheValue(cachedValue) &&
        !_isLocalFallback(cachedDetails)) {
      return cachedDetails;
    }

    FoodDetails? fetched;
    try {
      fetched = await client.lookup(ingredient);
    } catch (_) {
      fetched = null;
    }

    final details =
        fetched ?? cachedDetails ?? fallbackFoodDetailsFor(ingredient);
    cache[key] = details.toJson();
    await prefs.setString(foodDetailsCacheStorageKey, jsonEncode(cache));
    return details;
  }

  FoodDetails? _cachedDetailsFrom(Object? value) {
    if (value is Map<String, dynamic>) {
      return FoodDetails.fromJson(value);
    }
    if (value is Map) {
      return FoodDetails.fromJson(Map<String, dynamic>.from(value));
    }
    return null;
  }

  bool _isLocalFallback(FoodDetails details) {
    return details.source == _localFoodDetailsSource;
  }

  bool _isCurrentCacheValue(Object? value) {
    if (value is Map<String, dynamic>) {
      return value['cacheVersion'] == _foodDetailsCacheVersion;
    }
    if (value is Map) {
      return value['cacheVersion'] == _foodDetailsCacheVersion;
    }
    return false;
  }

  Map<String, dynamic> _readCache() {
    final raw = prefs.getString(foodDetailsCacheStorageKey);
    if (raw == null || raw.isEmpty) return <String, dynamic>{};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        return Map<String, dynamic>.from(decoded);
      }
    } catch (_) {
      return <String, dynamic>{};
    }
    return <String, dynamic>{};
  }
}

FoodDetails fallbackFoodDetailsFor(Ingredient ingredient, {DateTime? now}) {
  final defaults = FoodKnowledge.lookup(ingredient.name);
  final category = FoodCategories.dropdownValue(
    defaults?.category ?? ingredient.category,
  );
  final storage = defaults?.storage ?? ingredient.storage;
  final shelfLifeDays = defaults?.shelfLifeDays ?? ingredient.shelfLifeDays;
  final imageUrl = _fallbackImageUrl(ingredient);

  return FoodDetails(
    displayName: ingredient.name,
    description: _fallbackDescription(storage, shelfLifeDays),
    imageUrl: imageUrl,
    category: category,
    storage: storage,
    shelfLifeDays: shelfLifeDays,
    source: _localFoodDetailsSource,
    fetchedAt: now ?? DateTime.now(),
  );
}

String _fallbackDescription(IconType storage, int? shelfLifeDays) {
  final storageLabel = storageLabelFor(storage);
  if (shelfLifeDays != null && shelfLifeDays > 0) {
    return '建议存放在$storageLabel，约 $shelfLifeDays 天内食用。';
  }
  return '暂无联网详情，已保留本地库存中的食材信息。';
}

String? _fallbackImageUrl(Ingredient ingredient) {
  final savedImage = ingredient.imageUrl.trim();
  if (savedImage.isNotEmpty) return savedImage;

  final englishName = FoodKnowledge.englishName(ingredient.name);
  if (englishName == null || englishName.trim().isEmpty) return null;

  final slug = englishName.trim().toLowerCase().replaceAll(RegExp(r'\s+'), '_');
  return 'https://www.themealdb.com/images/ingredients/$slug.png';
}

