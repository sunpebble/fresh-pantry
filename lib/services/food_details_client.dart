import '../models/food_details.dart';
import '../models/ingredient.dart';
import 'open_food_facts_service.dart';

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
