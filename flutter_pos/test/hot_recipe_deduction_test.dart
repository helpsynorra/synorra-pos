import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../lib/models/inventory_item.dart';
import '../lib/models/menu_item.dart';
import '../lib/models/order.dart';
import '../lib/models/order_item.dart';
import '../lib/services/local_storage_service.dart';
import '../lib/services/supabase_service.dart';
import '../lib/services/sync_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('hot size order deducts its hot recipe and matching hot cup', () async {
    SharedPreferences.setMockInitialValues({});
    final storage = LocalStorageService();
    await storage.init();
    await storage.saveMenu([
      const MenuItem(
        id: 'iced-coffee',
        name: 'Iced Coffee',
        price: 100,
        category: 'Coffee',
        image: '',
        styles: ['hot', 'iced'],
        addons: [
          MenuAddon(id: 'size:22oz', name: '22oz', price: 120),
        ],
      ),
      const MenuItem(
        id: 'chocolate',
        name: 'Chocolate',
        price: 150,
        category: 'Coffee',
        image: '',
        styles: ['iced'],
        addons: [
          MenuAddon(
            id: 'size:16oz',
            name: '16oz',
            price: 0,
            inventoryItemId: 'legacy-16',
            usageAmount: 1,
            usageUnit: 'pcs',
          ),
        ],
      ),
    ]);
    await storage.saveInventory([
      InventoryItem(
        id: 'beans',
        name: 'Coffee Beans',
        unit: 'grams',
        stock: 1000,
        inventoryType: 'ingredient',
      ),
      InventoryItem(
        id: 'milk',
        name: 'Milk',
        unit: 'ml',
        stock: 1000,
        inventoryType: 'ingredient',
      ),
      InventoryItem(
        id: 'legacy-16',
        name: '16oz',
        unit: 'pcs',
        stock: 100,
        inventoryType: 'cup',
        cupSize: '16oz',
      ),
      InventoryItem(
        // Legacy generic cup rows can share a size with style-specific cups.
        // The hot recipe must resolve the hot cup before consulting cupRecipes.
        id: 'legacy-22',
        name: '22oz',
        unit: 'pcs',
        stock: 100,
        inventoryType: 'cup',
        cupSize: '22oz',
      ),
      InventoryItem(
        id: 'hot-22',
        name: 'Hot Cup - 22',
        unit: 'pcs',
        stock: 100,
        inventoryType: 'cup_hot',
        cupSize: '22oz',
      ),
      InventoryItem(
        id: 'iced-22',
        name: 'Iced Cup - 22',
        unit: 'pcs',
        stock: 100,
        inventoryType: 'cup_iced',
        cupSize: '22oz',
      ),
      InventoryItem(
        id: 'hot-16',
        name: 'Hot Cup - 16',
        unit: 'pcs',
        stock: 100,
        inventoryType: 'cup_hot',
        cupSize: '16oz',
      ),
    ]);
    await storage.saveRecipesData({
      'recipes': {
        'chocolate': [
          {
            'inventoryItemId': 'legacy-16',
            'name': '16oz',
            'amount': 1,
            'unit': 'pcs',
          },
        ],
      },
      'recipeCostings': [
        {
          'id': 'coffee-costing',
          'name': 'Iced Coffee',
          'menuItems': ['Iced Coffee'],
          // The legacy shared recipe intentionally differs from the hot 22oz recipe.
          'ingredients': [
            {
              'inventoryItemId': 'beans',
              'name': 'Coffee Beans',
              'amount': 3,
              'unit': 'grams',
            },
          ],
          'hotCupInventoryItemId': 'hot-16',
          'icedCupInventoryItemId': 'iced-22',
          'cupRecipes': {
            'hot-22': [
              {
                'inventoryItemId': 'beans',
                'name': 'Coffee Beans',
                'amount': 8,
                'unit': 'grams',
              },
              {
                'inventoryItemId': 'milk',
                'name': 'Milk',
                'amount': 130,
                'unit': 'ml',
              },
            ],
          },
        },
      ],
    });

    final service = SyncService(
      localStorage: storage,
      supabaseService: SupabaseService(),
    );
    final order = Order(
      id: 'test-hot-22',
      createdAt: DateTime.utc(2026, 10, 22).toIso8601String(),
      baristaName: 'Test',
      items: [
        OrderItem(
          productId: 'iced-coffee',
          name: 'Iced Coffee',
          qty: 1,
          price: 120,
          style: 'hot',
          addons: const [
            OrderAddonSelection(
              id: 'size:22oz',
              name: '22oz',
              qty: 1,
              price: 20,
            ),
          ],
        ),
      ],
      subtotal: 120,
      total: 120,
      paymentMethod: 'cash',
      paid: 120,
    );

    final deductions = service.buildDeductionsForOrder(order);
    final byId = {for (final row in deductions) row['inventoryItemId']: row};

    expect(byId.keys, containsAll(['beans', 'milk', 'hot-22']));
    expect(byId['beans']?['amount'], 8);
    expect(byId['milk']?['amount'], 130);
    expect(byId['hot-22']?['amount'], 1);
    expect(byId.keys, isNot(contains('iced-22')));
    expect(byId.keys, isNot(contains('legacy-22')));
    expect(byId.keys, isNot(contains('hot-16')));

    final unconfiguredHot16 = Order(
      id: 'test-hot-16-unconfigured',
      createdAt: DateTime.utc(2026, 10, 22).toIso8601String(),
      baristaName: 'Test',
      items: [
        OrderItem(
          productId: 'iced-coffee',
          name: 'Iced Coffee',
          qty: 1,
          price: 100,
          style: 'hot',
          addons: const [
            OrderAddonSelection(
              id: 'size:16oz',
              name: '16oz',
              qty: 1,
              price: 0,
            ),
          ],
        ),
      ],
      subtotal: 100,
      total: 100,
      paymentMethod: 'cash',
      paid: 100,
    );
    expect(service.buildDeductionsForOrder(unconfiguredHot16), isEmpty);

    final unconfiguredChocolate = OrderItem(
      productId: 'chocolate',
      name: 'Chocolate',
      qty: 1,
      price: 150,
      style: 'iced',
      addons: const [
        OrderAddonSelection(
          id: 'size:16oz',
          name: '16oz',
          qty: 1,
          price: 0,
          inventoryItemId: 'legacy-16',
          usageAmount: 1,
          usageUnit: 'pcs',
        ),
      ],
    );
    expect(service.buildDeductionsForItems([unconfiguredChocolate]), isEmpty);

    // Even if old local data contains a legacy recipe for this known menu
    // item, the current recipe setup says it is unassigned.
    await storage.saveRecipesData({
      'recipes': {
        'chocolate': [
          {
            'inventoryItemId': 'legacy-16',
            'name': '16oz',
            'amount': 1,
            'unit': 'pcs',
          },
        ],
      },
      'recipeCostings': [],
    });
    expect(service.buildDeductionsForItems([unconfiguredChocolate]), isEmpty);
  });
}
