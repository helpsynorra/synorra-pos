import 'package:flutter_test/flutter_test.dart';
import 'package:synorra_pos/models/menu_item.dart';
import 'package:synorra_pos/models/order_item.dart';
import 'package:synorra_pos/services/sync_service.dart';

void main() {
  test('does not add styles when none are configured', () {
    final item = MenuItem.fromJson({
      'id': 'plain-drink',
      'name': 'Plain Drink',
      'category': 'Coffee',
      'image': '/images/drink.jpg',
    });

    expect(item.styles, isEmpty);
  });

  test('an explicit empty style list overrides legacy image options', () {
    final item = MenuItem.fromJson({
      'id': 'plain-drink',
      'name': 'Plain Drink',
      'category': 'Coffee',
      'image': '/images/drink.jpg#styles=hot,iced',
      'styles': <String>[],
    });

    expect(item.styles, isEmpty);
  });

  test('keeps explicitly configured styles', () {
    final item = MenuItem.fromJson({
      'id': 'iced-drink',
      'name': 'Iced Drink',
      'category': 'Coffee',
      'image': '/images/drink.jpg',
      'styles': ['iced'],
    });

    expect(item.styles, ['iced']);
  });

  test('round trips the configured category type', () {
    final item = MenuItem.fromJson({
      'id': 'custom-dessert',
      'name': 'Mango Tart',
      'price': 100,
      'category': 'Tarts',
      'categoryType': 'Desserts',
      'image': '/images/tart.jpg',
    });

    expect(item.categoryType, 'Desserts');
    expect(MenuItem.fromJson(item.toJson()).categoryType, 'Desserts');
  });

  test('round trips the category type on an order item', () {
    final item = OrderItem(
      productId: 'seasonal-item',
      name: 'Seasonal Item',
      qty: 1,
      price: 50,
      category: 'Seasonal menu',
      categoryType: 'Limited Edition',
    );

    expect(OrderItem.fromJson(item.toJson()).categoryType, 'Limited Edition');
  });

  test('keeps local menu and category edits when server sync is stale', () {
    final localMenu = <MenuItem>[
      const MenuItem(
        id: 'local-item',
        name: 'Local Item',
        price: 30,
        category: 'Coffee',
        image: '/images/local.jpg',
      ),
    ];
    final remoteMenu = <MenuItem>[
      const MenuItem(
        id: 'remote-item',
        name: 'Remote Item',
        price: 40,
        category: 'Classic',
        image: '/images/remote.jpg',
      ),
    ];

    final mergedMenu = SyncService.mergeMenuPreservingLocal(localMenu, remoteMenu);
    expect(mergedMenu.map((item) => item.id), containsAll(['local-item', 'remote-item']));
    expect(mergedMenu.length, 2);

    final localCategories = ['All', 'Coffee'];
    final remoteCategories = ['All', 'Classic'];
    final mergedCategories = SyncService.mergeCategoriesPreservingLocal(
      localCategories,
      remoteCategories,
    );
    expect(mergedCategories, ['All', 'Coffee', 'Classic']);
  });
}
