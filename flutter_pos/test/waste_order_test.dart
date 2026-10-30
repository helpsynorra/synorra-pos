import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:synorra_pos/models/menu_item.dart';
import 'package:synorra_pos/models/inventory_item.dart';
import 'package:synorra_pos/models/login_activity.dart';
import 'package:synorra_pos/models/order.dart';
import 'package:synorra_pos/models/order_item.dart';
import 'package:synorra_pos/models/staff_user.dart';
import 'package:synorra_pos/services/local_storage_service.dart';
import 'package:synorra_pos/services/supabase_service.dart';
import 'package:synorra_pos/services/sync_service.dart';
import 'package:synorra_pos/state/pos_controller.dart';

class _MockSupabaseService extends SupabaseService {
  Order? lastPushedOrder;
  List<Map<String, dynamic>>? lastDeductions;

  @override
  bool get isPosApiTokenExpired => false;

  @override
  bool get hasPosApiToken => true;

  @override
  Future<Map<String, dynamic>> pushOrderAtomic(
    Order order,
    List<Map<String, dynamic>> deductions, {
    String? managerUsername,
    String? managerPassword,
  }) async {
    lastPushedOrder = order;
    lastDeductions = deductions;
    return {
      'ok': true,
      'ticketNo': null,
    };
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Waste Order Handling', () {
    test('Order model recognizes waste order and serializes wasteReason', () {
      final order = Order(
        id: 'waste-12345',
        createdAt: '2026-10-25T00:00:00Z',
        baristaName: 'Barista',
        items: [],
        subtotal: 0,
        total: 0,
        paymentMethod: 'waste',
        ticketNo: '',
        paid: 0,
        wasteReason: 'Wrong Preparation',
        excludedWasteInventoryItemIds: const ['milk-id'],
      );

      expect(order.isWaste, isTrue);
      expect(order.ticketNo, isEmpty);
      expect(order.wasteReason, 'Wrong Preparation');

      final json = order.toJson();
      expect(json['wasteReason'], 'Wrong Preparation');
      expect(json['paymentMethod'], 'waste');
      expect(json['excludedWasteInventoryItemIds'], ['milk-id']);

      final reconstructed = Order.fromJson(json);
      expect(reconstructed.isWaste, isTrue);
      expect(reconstructed.wasteReason, 'Wrong Preparation');
      expect(reconstructed.excludedWasteInventoryItemIds, ['milk-id']);
    });

    test(
        'waste deductions omit excluded inventory items but keep included ones',
        () async {
      SharedPreferences.setMockInitialValues({});
      final storage = LocalStorageService();
      await storage.init();
      await storage.saveInventory([
        InventoryItem(id: 'milk-id', name: 'Milk', unit: 'ml', stock: 1000),
        InventoryItem(
            id: 'beans-id', name: 'Coffee Beans', unit: 'g', stock: 1000),
      ]);
      await storage.saveMenu([
        const MenuItem(
          id: 'drink-1',
          name: 'Americano',
          price: 100,
          category: 'Drinks',
          image: '',
          available: true,
          inventoryMode: 'stock_and_recipe',
        ),
      ]);
      await storage.saveRecipesData({
        'recipeCostings': [
          {
            'menuItems': ['Americano'],
            'ingredients': [
              {
                'inventoryItemId': 'milk-id',
                'name': 'Milk',
                'amount': 100,
                'unit': 'ml',
              },
              {
                'inventoryItemId': 'beans-id',
                'name': 'Coffee Beans',
                'amount': 18,
                'unit': 'g',
              },
            ],
          },
        ],
      });

      final sync = SyncService(
          supabaseService: _MockSupabaseService(), localStorage: storage);
      final wasteOrder = Order(
        id: 'waste-exclusion-test',
        createdAt: DateTime.now().toIso8601String(),
        baristaName: 'Cashier',
        items: [
          OrderItem(
            productId: 'drink-1',
            name: 'Americano',
            price: 100,
          ),
        ],
        subtotal: 0,
        total: 0,
        paymentMethod: 'waste',
        paid: 0,
        wasteReason: 'Spilled',
        excludedWasteInventoryItemIds: const ['milk-id'],
      );

      final deductions = sync.buildDeductionsForOrder(wasteOrder);

      expect(deductions, hasLength(1));
      expect(deductions.single['inventoryItemId'], 'beans-id');
      expect(deductions.single['amount'], 18);
    });

    test('recordWasteOrder requires non-empty reason and sets empty ticketNo',
        () async {
      SharedPreferences.setMockInitialValues({});
      final storage = LocalStorageService();
      await storage.init();
      final supabase = _MockSupabaseService();
      final sync =
          SyncService(supabaseService: supabase, localStorage: storage);
      final controller = PosController(
        localStorage: storage,
        supabaseService: supabase,
        syncService: sync,
      );
      final previousSale = Order(
        id: 'ord-before-waste',
        createdAt: '2026-10-24T10:00:00Z',
        baristaName: 'Sam Cashier',
        items: const [],
        subtotal: 0,
        total: 0,
        paymentMethod: 'cash',
        ticketNo: '#001',
        paid: 0,
      );
      controller.lastCompletedOrder = previousSale;
      const cashier = StaffUser(
        id: 'pos-cashier-1',
        username: 'sam',
        password: '',
        name: 'Sam Cashier',
        role: 'pos_cashier',
        title: 'Cashier',
      );
      controller.staffUsers.add(cashier);
      controller.shiftLogs.add(
        LoginActivity(
          id: 'shift-login-1',
          userId: cashier.id,
          username: cashier.username,
          name: cashier.name,
          role: cashier.role,
          type: 'login',
          at: DateTime.now().toIso8601String(),
        ),
      );

      const coffeeItem = MenuItem(
        id: 'drink-1',
        name: 'Americano',
        price: 100,
        category: 'Drinks',
        image: '',
        available: true,
      );
      controller.addToCart(coffeeItem);

      // Attempting to record waste with empty reason must fail
      final emptyResult = await controller.recordWasteOrder(reason: '   ');
      expect(emptyResult['ok'], isFalse);
      expect(emptyResult['error'], contains('reason'));

      // Recording waste with a valid reason succeeds
      final successResult =
          await controller.recordWasteOrder(reason: 'Spilled');
      expect(successResult['ok'], isTrue);

      final recordedOrder = successResult['order'] as Order;
      expect(recordedOrder.isWaste, isTrue);
      expect(recordedOrder.wasteReason, 'Spilled');
      expect(recordedOrder.ticketNo, isEmpty);
      expect(recordedOrder.total, 0);
      expect(recordedOrder.baristaName, cashier.name);
      expect(recordedOrder.baristaUserId, cashier.id);
      expect(controller.lastCompletedOrder, same(previousSale));

      // Pushed order to backend has empty ticketNo and wasteReason
      expect(supabase.lastPushedOrder?.ticketNo, isEmpty);
      expect(supabase.lastPushedOrder?.wasteReason, 'Spilled');
    });

    test(
        'nextTicketNoForOrders fills waste-created gaps before issuing new tickets',
        () {
      final now = DateTime(2026, 10, 25, 11, 38);
      final orders = [
        Order(
          id: 'ord-1',
          createdAt: '2026-10-25T11:36:00+08:00',
          baristaName: 'Cashier',
          items: [],
          subtotal: 0,
          total: 0,
          paymentMethod: 'cash',
          ticketNo: '#001',
          paid: 0,
        ),
        Order(
          id: 'waste-1',
          createdAt: '2026-10-25T11:37:00+08:00',
          baristaName: 'Cashier',
          items: [],
          subtotal: 0,
          total: 0,
          paymentMethod: 'waste',
          ticketNo: '#002',
          paid: 0,
          wasteReason: 'Spilled',
        ),
        Order(
          id: 'ord-2',
          createdAt: '2026-10-25T11:37:00+08:00',
          baristaName: 'Cashier',
          items: [],
          subtotal: 0,
          total: 0,
          paymentMethod: 'cash',
          ticketNo: '#003',
          paid: 0,
        ),
        Order(
          id: 'ord-3',
          createdAt: '2026-10-25T11:38:00+08:00',
          baristaName: 'Cashier',
          items: [],
          subtotal: 0,
          total: 0,
          paymentMethod: 'cash',
          ticketNo: '#004',
          paid: 0,
          voided: true,
        ),
      ];

      expect(nextTicketNoForOrders(orders, now), '#002');
    });
  });
}
