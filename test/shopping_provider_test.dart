import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fresh_pantry/data/food_categories.dart';
import 'package:fresh_pantry/models/shopping_item.dart';
import 'package:fresh_pantry/providers/shopping_provider.dart';
import 'package:fresh_pantry/providers/storage_service_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<ProviderContainer> _container() async {
  SharedPreferences.setMockInitialValues({'shopping_items': '[]'});
  final prefs = await SharedPreferences.getInstance();
  return ProviderContainer(
    overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
  );
}

void main() {
  test('add trims item name and detail before saving state', () async {
    final container = await _container();
    addTearDown(container.dispose);

    final added = await container
        .read(shoppingProvider.notifier)
        .add(
          const ShoppingItem(
            id: 'milk',
            name: '  牛奶  ',
            detail: '  1 盒  ',
            category: FoodCategories.dairyAndEggs,
          ),
        );

    expect(added, isTrue);
    final item = container.read(shoppingProvider).single;
    expect(item.name, '牛奶');
    expect(item.detail, '1 盒');
  });
}
