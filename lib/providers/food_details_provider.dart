import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/food_details.dart';
import '../models/ingredient.dart';
import '../services/food_details_client.dart';
import '../storage/food_details_repo.dart';
import 'storage_service_provider.dart';

export '../services/food_details_client.dart'
    show FoodDetailsClient, OpenFoodFactsDetailsClient;
export '../storage/food_details_repo.dart'
    show
        FoodDetailsRepository,
        fallbackFoodDetailsFor,
        foodDetailsCacheKeyFor,
        foodDetailsCacheStorageKey;

final foodDetailsClientProvider = Provider<FoodDetailsClient>(
  (ref) => const OpenFoodFactsDetailsClient(),
);

final foodDetailsRepositoryProvider = Provider<FoodDetailsRepository>((ref) {
  return FoodDetailsRepository(
    storage: ref.read(storageAdapterProvider),
    client: ref.watch(foodDetailsClientProvider),
  );
});

final foodDetailsProvider = FutureProvider.autoDispose
    .family<FoodDetails, Ingredient>((ref, ingredient) {
      return ref.watch(foodDetailsRepositoryProvider).detailsFor(ingredient);
    });
